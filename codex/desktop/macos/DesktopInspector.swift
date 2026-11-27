import AppKit
import Foundation
import SwiftUI
import WebKit

// MARK: - Abas do Painel Lateral do Agente

enum InspectorTab: String, CaseIterable, Identifiable {
    case browser = "Navegador"
    case terminal = "Terminal"
    case project = "Projeto"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .browser: return "globe"
        case .terminal: return "terminal"
        case .project: return "folder"
        }
    }
}

// MARK: - Gerenciador do Terminal Interno do Agente

struct TerminalLine: Identifiable {
    let id = UUID()
    let text: String
    let isCommand: Bool
    let isError: Bool
    let timestamp: Date
}

@MainActor
final class AgentTerminalManager: ObservableObject {
    @Published var lines: [TerminalLine] = []
    @Published var isRunning: Bool = false
    @Published var lastCommand: String? = nil
    private var process: Process?
    private var outputPipe: Pipe?

    init() {
        let welcome = "Terminal interno do agente inicializado (zsh). Digite comandos para executar no diretório de trabalho."
        lines.append(TerminalLine(text: welcome, isCommand: false, isError: false, timestamp: Date()))
    }

    func execute(command: String, workingDir: String) {
        let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty, !isRunning else { return }

        lastCommand = cmd
        lines.append(TerminalLine(text: "$ \(cmd)", isCommand: true, isError: false, timestamp: Date()))
        isRunning = true

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-l", "-c", cmd]
        let dirURL = URL(fileURLWithPath: workingDir)
        if FileManager.default.fileExists(atPath: dirURL.path) {
            proc.currentDirectoryURL = dirURL
        } else {
            proc.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        }

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        self.process = proc
        self.outputPipe = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let output = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    self?.appendOutput(output)
                }
            }
        }

        proc.terminationHandler = { [weak self] p in
            Task { @MainActor in
                guard let self else { return }
                self.outputPipe?.fileHandleForReading.readabilityHandler = nil
                self.outputPipe = nil
                self.process = nil
                self.isRunning = false
                let exitCode = p.terminationStatus
                if exitCode != 0 {
                    self.lines.append(TerminalLine(text: "[processo encerrou com código \(exitCode)]", isCommand: false, isError: true, timestamp: Date()))
                }
            }
        }

        do {
            try proc.run()
        } catch {
            lines.append(TerminalLine(text: "Falha ao iniciar processo: \(error.localizedDescription)", isCommand: false, isError: true, timestamp: Date()))
            isRunning = false
        }
    }

    private func appendOutput(_ text: String) {
        let rawLines = text.components(separatedBy: .newlines)
        for (index, line) in rawLines.enumerated() {
            if index == rawLines.count - 1 && line.isEmpty { continue }
            lines.append(TerminalLine(text: line, isCommand: false, isError: false, timestamp: Date()))
        }
        if lines.count > 1500 {
            lines.removeFirst(lines.count - 1500)
        }
    }

    func interrupt() {
        if let proc = process, proc.isRunning {
            proc.terminate()
            lines.append(TerminalLine(text: "^C [comando interrompido]", isCommand: false, isError: true, timestamp: Date()))
        }
        isRunning = false
    }

    func clear() {
        lines.removeAll()
    }
}

// MARK: - Estado e Gerenciador do Navegador Interno

@MainActor
final class AgentBrowserState: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var urlInput: String = "https://www.google.com"
    @Published var currentURL: String = "https://www.google.com"
    @Published var pageTitle: String = "Google"
    @Published var isLoading: Bool = false
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false

    let webView: WKWebView

    override init() {
        let config = WKWebViewConfiguration()
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        self.webView.navigationDelegate = self
        load(input: "https://www.google.com")
    }

    func load(input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let targetURL: URL
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            targetURL = URL(string: trimmed) ?? URL(string: "https://www.google.com")!
        } else if trimmed.contains(".") && !trimmed.contains(" ") {
            targetURL = URL(string: "https://" + trimmed) ?? URL(string: "https://www.google.com")!
        } else {
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            targetURL = URL(string: "https://www.google.com/search?q=\(encoded)") ?? URL(string: "https://www.google.com")!
        }

        self.urlInput = targetURL.absoluteString
        let request = URLRequest(url: targetURL)
        webView.load(request)
    }

    func goBack() {
        if webView.canGoBack {
            webView.goBack()
        }
    }

    func goForward() {
        if webView.canGoForward {
            webView.goForward()
        }
    }

    func reload() {
        webView.reload()
    }

    // MARK: - WKNavigationDelegate

    nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Task { @MainActor in
            self.isLoading = true
            self.canGoBack = webView.canGoBack
            self.canGoForward = webView.canGoForward
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.isLoading = false
            self.canGoBack = webView.canGoBack
            self.canGoForward = webView.canGoForward
            self.pageTitle = webView.title ?? ""
            if let address = webView.url?.absoluteString {
                self.currentURL = address
                self.urlInput = address
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.isLoading = false
        }
    }
}

// MARK: - Componente NSViewRepresentable para WKWebView

struct AgentWebViewRepresentable: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: - Mini Card Terminal

struct MiniTerminalCard: View {
    @ObservedObject var terminal: AgentTerminalManager
    let workingDir: String
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.green)
                    .frame(width: 32, height: 32)
                    .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Terminal do Agente")
                            .font(.system(size: 12, weight: .semibold))
                        Circle()
                            .fill(terminal.isRunning ? Color.orange : Color.green)
                            .frame(width: 6, height: 6)
                        Text(terminal.isRunning ? "Executando…" : "zsh")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(terminal.isRunning ? Color.orange : DesktopStyle.muted)
                    }

                    let dirName = URL(fileURLWithPath: workingDir).lastPathComponent
                    let commandPreview = terminal.lastCommand.map { "$ \($0)" } ?? "Diretório: \(dirName) · clique para abrir"
                    Text(commandPreview)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(DesktopStyle.muted)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DesktopStyle.muted)
            }
            .padding(10)
            .background(DesktopStyle.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(DesktopStyle.line))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Abrir terminal interno do agente")
    }
}

// MARK: - Visualização do Navegador Interno do Agente

struct AgentBrowserView: View {
    @ObservedObject var browser: AgentBrowserState
    @ObservedObject var terminal: AgentTerminalManager
    @ObservedObject var workspace: Workspace
    let workingDir: String
    @Binding var activeTab: InspectorTab

    var body: some View {
        VStack(spacing: 0) {
            // Barra de navegação e endereço
            HStack(spacing: 8) {
                Button { browser.goBack() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(DesktopStyle.surface, in: Circle())
                }
                .disabled(!browser.canGoBack)
                .buttonStyle(.plain)
                .accessibilityLabel("Voltar no navegador")

                Button { browser.goForward() } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(DesktopStyle.surface, in: Circle())
                }
                .disabled(!browser.canGoForward)
                .buttonStyle(.plain)
                .accessibilityLabel("Avançar no navegador")

                Button { browser.reload() } label: {
                    Image(systemName: browser.isLoading ? "xmark" : "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(DesktopStyle.surface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Recarregar página")

                // Campo de busca / endereço URL
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(DesktopStyle.muted)

                    TextField("Pesquisar na web ou digitar URL…", text: $browser.urlInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .onSubmit { browser.load(input: browser.urlInput) }

                    if browser.isLoading {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(DesktopStyle.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(DesktopStyle.line))

                Button {
                    browser.load(input: browser.urlInput)
                } label: {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 26, height: 26)
                        .background(WisdTheme.accent, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ir para URL")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(DesktopStyle.surface.opacity(0.4))

            // Atalhos rápidos de pesquisa e documentação (roláveis para qualquer largura)
            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        quickChip("Google", url: "https://www.google.com")
                        quickChip("DuckDuckGo", url: "https://duckduckgo.com")
                        quickChip("GitHub", url: "https://github.com")
                        quickChip("Localhost:3000", url: "http://localhost:3000")
                    }
                }

                // Botão para enviar URL atual ao chat
                Button {
                    let pageInfo = "Consulte esta página web: \(browser.currentURL)"
                    if workspace.prompt.isEmpty {
                        workspace.prompt = pageInfo
                    } else {
                        workspace.prompt += "\n" + pageInfo
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.left")
                            .font(.system(size: 9, weight: .bold))
                        Text("Ao Chat")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(WisdTheme.softAccentText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(WisdTheme.accent.opacity(0.16), in: Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityLabel("Enviar endereço desta página para o chat")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Divider()

            // Visualização Web ativa (WKWebView)
            AgentWebViewRepresentable(webView: browser.webView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Mini card terminal acoplado na parte inferior
            MiniTerminalCard(terminal: terminal, workingDir: workingDir) {
                activeTab = .terminal
            }
            .padding(10)
            .background(DesktopStyle.canvas)
        }
    }

    private func quickChip(_ title: String, url: String) -> some View {
        Button {
            browser.load(input: url)
        } label: {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DesktopStyle.muted)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(DesktopStyle.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(DesktopStyle.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Visualização do Terminal Interno do Agente

struct AgentTerminalView: View {
    @ObservedObject var terminal: AgentTerminalManager
    let workingDir: String
    @Binding var activeTab: InspectorTab
    @State private var inputCommand: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header do terminal
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.green)
                    Text("Terminal Interno (zsh)")
                        .font(.system(size: 12, weight: .semibold))
                }

                Spacer()

                // Botão de Interromper comando ativo
                if terminal.isRunning {
                    Button {
                        terminal.interrupt()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.fill").font(.system(size: 9))
                            Text("Interromper").font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                // Botão de Limpar tela
                Button {
                    terminal.clear()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(DesktopStyle.muted)
                        .frame(width: 24, height: 24)
                        .background(DesktopStyle.surface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Limpar histórico do terminal")

                // Botão para alternar de volta ao navegador
                Button {
                    activeTab = .browser
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "globe").font(.system(size: 11))
                        Text("Navegador").font(.system(size: 11))
                    }
                    .foregroundStyle(WisdTheme.softAccentText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(WisdTheme.accent.opacity(0.16), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(DesktopStyle.surface.opacity(0.4))

            // Sub-barra informativa de diretório
            HStack {
                Text(workingDir)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(DesktopStyle.muted)
                    .lineLimit(1)
                Spacer()
                Text("UTF-8 · zsh")
                    .font(.system(size: 10))
                    .foregroundStyle(DesktopStyle.muted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.15))

            Divider()

            // Console de saída com rolagem automática
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(terminal.lines) { line in
                            HStack(alignment: .top, spacing: 6) {
                                if line.isCommand {
                                    Text(line.text)
                                        .foregroundStyle(Color.green)
                                        .fontWeight(.semibold)
                                } else if line.isError {
                                    Text(line.text)
                                        .foregroundStyle(Color.red)
                                } else {
                                    Text(line.text)
                                        .foregroundStyle(Color(white: 0.88))
                                }
                            }
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .id(line.id)
                        }
                    }
                    .padding(12)
                }
                .background(Color(red: 0.08, green: 0.09, blue: 0.11))
                .onChange(of: terminal.lines.count) {
                    if let last = terminal.lines.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            Divider()

            // Linha de entrada de comandos
            HStack(spacing: 8) {
                Text("$")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.green)

                TextField("Digite um comando (ex: git status, ls -la, python3…)", text: $inputCommand)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit {
                        guard !inputCommand.isEmpty else { return }
                        let toRun = inputCommand
                        inputCommand = ""
                        terminal.execute(command: toRun, workingDir: workingDir)
                    }

                Button {
                    guard !inputCommand.isEmpty else { return }
                    let toRun = inputCommand
                    inputCommand = ""
                    terminal.execute(command: toRun, workingDir: workingDir)
                } label: {
                    Image(systemName: "return")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 24, height: 24)
                        .background(inputCommand.isEmpty ? Color.gray : WisdTheme.accent, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(inputCommand.isEmpty || terminal.isRunning)
                .accessibilityLabel("Executar comando no terminal")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(DesktopStyle.surface)
        }
    }
}

// MARK: - Visualização de Detalhes do Projeto

struct AgentProjectDetailsView: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var local: DesktopLocalData

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(workspace.project?.lastPathComponent ?? "Sem projeto selecionado", systemImage: "folder")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }

            if let path = workspace.project?.path {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Caminho do diretório:")
                        .font(.system(size: 11))
                        .foregroundStyle(DesktopStyle.muted)
                    Text(path)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(DesktopStyle.muted)
                        .textSelection(.enabled)
                }
                .padding(10)
                .background(DesktopStyle.surface, in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Button("Alterar projeto…", action: workspace.chooseProject)
                    .buttonStyle(.bordered)
                    .disabled(workspace.busy)

                Spacer()

                Button("Revisar alterações", systemImage: "arrow.triangle.branch", action: workspace.reviewChanges)
                    .buttonStyle(.borderedProminent)
                    .disabled(workspace.project == nil || workspace.busy || !workspace.ready)
            }

            Divider()

            Text("Projetos Cadastrados no WisdAI")
                .font(.system(size: 13, weight: .semibold))

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(local.projects) { proj in
                        Button {
                            workspace.project = URL(fileURLWithPath: proj.path)
                        } label: {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(WisdTheme.iconAccent)
                                Text(proj.name)
                                    .font(.system(size: 12, weight: .medium))
                                Spacer()
                                if let p = workspace.project, proj.matchesPath(p.path) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Color.green)
                                }
                            }
                            .padding(10)
                            .background(DesktopStyle.surface, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Painel Lateral Completo do Agente (Inspector)

struct AgentInspectorPane: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var local: DesktopLocalData
    @ObservedObject var browserState: AgentBrowserState
    @ObservedObject var terminalManager: AgentTerminalManager
    @Binding var isPresented: Bool
    @Binding var activeTab: InspectorTab
    let width: CGFloat

    private var effectiveWorkingDir: String {
        workspace.project?.path ?? FileManager.default.homeDirectoryForCurrentUser.path
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header superior do painel lateral com tabs e botão de fechar
            HStack(spacing: 10) {
                // Seletor de abas
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(InspectorTab.allCases) { tab in
                            Button {
                                activeTab = tab
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: tab.icon)
                                        .font(.system(size: 11))
                                    Text(tab.rawValue)
                                        .font(.system(size: 11, weight: activeTab == tab ? .semibold : .regular))
                                }
                                .foregroundStyle(activeTab == tab ? WisdTheme.softAccentText : DesktopStyle.muted)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(activeTab == tab ? WisdTheme.accent.opacity(0.18) : Color.clear, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer(minLength: 4)

                // Botão de fechar painel lateral
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isPresented = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesktopStyle.muted)
                        .frame(width: 24, height: 24)
                        .background(DesktopStyle.hover, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fechar painel lateral")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(DesktopStyle.surface)

            Divider()

            // Conteúdo conforme a aba ativa
            Group {
                switch activeTab {
                case .browser:
                    AgentBrowserView(
                        browser: browserState,
                        terminal: terminalManager,
                        workspace: workspace,
                        workingDir: effectiveWorkingDir,
                        activeTab: $activeTab
                    )
                case .terminal:
                    AgentTerminalView(
                        terminal: terminalManager,
                        workingDir: effectiveWorkingDir,
                        activeTab: $activeTab
                    )
                case .project:
                    AgentProjectDetailsView(
                        workspace: workspace,
                        local: local
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .clipped()
        .background(DesktopStyle.canvas)
    }
}

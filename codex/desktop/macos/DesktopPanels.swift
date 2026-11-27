import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum DesktopPage: String, Identifiable {
    case chat = "Início"
    case schedule = "Agendado"
    case library = "Espaço"
    case plugins = "Plugins"
    case sites = "Sites"
    case settings = "Configurações"
    case usage = "Uso e faturamento"
    case maps = "Mapas"
    case assistants = "GPTs"
    case images = "Imagens"
    case figma = "Figma"
    case skills = "Habilidades"

    var id: Self { self }

    var icon: String {
        switch self {
        case .chat: "house"
        case .schedule: "clock"
        case .library: "rectangle.on.rectangle"
        case .plugins: "puzzlepiece.extension"
        case .sites: "square.grid.2x2"
        case .settings: "gearshape"
        case .usage: "gauge.with.dots.needle.50percent"
        case .maps: "map"
        case .assistants: "square.stack.3d.up"
        case .images: "photo"
        case .figma: "circle.hexagongrid"
        case .skills: "cube"
        }
    }
}

struct UsageWindow: Identifiable {
    let id: String
    let used: Int
    let minutes: Int?
    let reset: Date?

    var title: String {
        switch minutes {
        case 300: "Limite a cada 5 horas"
        case 10_080: "Limite semanal"
        case let value?: "Limite a cada \(value) min"
        default: "Limite do plano"
        }
    }
}

struct ScheduledTask: Identifiable, Codable {
    var id = UUID()
    let name: String
    let prompt: String
    let folder: String
    let accountID: String
    var next: Date
    let days: Int
    var paused = false
    var lastResult: String?
    var lastThreadID: String?
}

struct LibraryEntry: Identifiable, Codable {
    var id = UUID()
    let path: String
    var favorite = false

    var url: URL { URL(fileURLWithPath: path) }
    var isFolder: Bool { (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    var isImage: Bool { UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true }
}

struct LocalSpaceFolder: Identifiable, Codable {
    var id = UUID()
    var name: String
    var members: [UUID] = []
}

@MainActor
final class DesktopLocalData: ObservableObject {
    @Published var projects = load([ProjectItem].self, key: "projectsList") { didSet { save(projects, key: "projectsList") } }
    @Published var aiAccounts = load([AIAccount].self, key: "aiAccountsList") { didSet { save(aiAccounts, key: "aiAccountsList") } }
    @Published var recentCollapsed: Bool = UserDefaults.standard.bool(forKey: "wisdcode.desktop.recentCollapsed") {
        didSet { UserDefaults.standard.set(recentCollapsed, forKey: "wisdcode.desktop.recentCollapsed") }
    }
    @Published var projectPaths = load([String].self, key: "projects") { didSet { save(projectPaths, key: "projects") } }
    @Published var pinnedProjects = load([String].self, key: "pinnedProjects") { didSet { save(pinnedProjects, key: "pinnedProjects") } }
    @Published var pinnedThreads = load([String].self, key: "pinnedThreads") { didSet { save(pinnedThreads, key: "pinnedThreads") } }
    @Published var spaces = load([LocalSpaceFolder].self, key: "spaces") { didSet { save(spaces, key: "spaces") } }
    @Published var libraryTrash = load([UUID].self, key: "libraryTrash") { didSet { save(libraryTrash, key: "libraryTrash") } }
    @Published var tasks = load([ScheduledTask].self, key: "tasks") { didSet { save(tasks, key: "tasks") } }
    @Published var library = load([LibraryEntry].self, key: "library") { didSet { save(library, key: "library") } }
    @Published var sites = load([LibraryEntry].self, key: "sites") { didSet { save(sites, key: "sites") } }
    @Published var credentialMigrationNotice: String?
    private var running = false

    init() {
        let isSmoke = ProcessInfo.processInfo.processName.contains("Smoke")
        var accounts = aiAccounts
        for i in accounts.indices {
            if let key = accounts[i].apiKeyOrToken {
                do { try AccountKeychain.save(key, accountID: accounts[i].id); accounts[i].apiKeyOrToken = nil }
                catch { credentialMigrationNotice = "Uma chave legada ainda precisa ser migrada para o Chaves do macOS. A configuração original foi preservada." }
            }
            if accounts[i].modelsUpdatedAt == nil { accounts[i].models = [] }
            if !isSmoke && !accounts[i].models.isEmpty {
                let prevModel = accounts[i].currentModel
                let filteredModels = accounts[i].models.filter { accounts[i].provider.ownsModel($0) }
                if filteredModels.count != accounts[i].models.count {
                    accounts[i].models = filteredModels
                    accounts[i].activeModelIndex = filteredModels.firstIndex(of: prevModel) ?? 0
                    accounts[i].exhaustedModelIndices = accounts[i].exhaustedModelIndices.filter { filteredModels.indices.contains($0) }
                }
            }
            if accounts[i].provider == .openai && accounts[i].sessionID == nil { accounts[i].isActive = false }
            if !isSmoke && accounts[i].provider != .openai {
                let candidateCLI = accounts[i].cliPath ?? AgentCLIAuthenticator.locateCLI(for: accounts[i].provider)
                let hasValidCLI = candidateCLI.map { FileManager.default.isExecutableFile(atPath: $0) } ?? false
                accounts[i].cliInstalled = hasValidCLI
                if hasValidCLI {
                    accounts[i].cliPath = candidateCLI
                } else {
                    accounts[i].cliPath = nil
                    let hasKey = (try? AccountKeychain.read(accountID: accounts[i].id)) != nil
                        || AccountKeychain.readAccountPassword(accountID: accounts[i].id) != nil
                        || AccountKeychain.readProviderKey(provider: accounts[i].provider) != nil
                    if !hasKey && accounts[i].modelsUpdatedAt == nil {
                        accounts[i].isActive = false
                    }
                }
            }
        }
        if !isSmoke && !accounts.contains(where: { $0.isActive && $0.supportsExecution }),
           let fallbackIdx = accounts.firstIndex(where: {
               $0.provider == .openai ? ($0.sessionID != nil) : ($0.cliInstalled && $0.supportsExecution)
           }) {
            accounts[fallbackIdx].isActive = true
        }
        aiAccounts = accounts

        // Deduplicar projetos por caminho normalizado para evitar projetos fantasmas duplicados
        var uniqueProjects: [ProjectItem] = []
        var seenPaths = Set<String>()
        for proj in projects {
            let norm = URL(fileURLWithPath: proj.path).standardized.resolvingSymlinksInPath().path
            if !seenPaths.contains(norm) {
                seenPaths.insert(norm)
                uniqueProjects.append(proj)
            }
        }
        if uniqueProjects.count != projects.count {
            projects = uniqueProjects
            save(projects, key: "projectsList")
        }

        if projects.isEmpty && !projectPaths.isEmpty {
            projects = projectPaths.map { path in
                ProjectItem(name: URL(fileURLWithPath: path).lastPathComponent, path: path, pinned: pinnedProjects.contains(path))
            }
            save(projects, key: "projectsList")
        }
    }

    func syncModels(accountID: UUID, models: [String], source: String) {
        guard let index = aiAccounts.firstIndex(where: { $0.id == accountID }) else { return }
        let previousModel = aiAccounts[index].currentModel
        let scoped = models.filter { aiAccounts[index].provider.ownsModel($0) }
        let finalModels = scoped.isEmpty ? models : scoped
        aiAccounts[index].models = finalModels
        aiAccounts[index].activeModelIndex = finalModels.firstIndex(of: previousModel) ?? 0
        aiAccounts[index].exhaustedModelIndices = []
        aiAccounts[index].modelsUpdatedAt = Date()
        aiAccounts[index].catalogSource = source
    }

    func syncSessions(_ sessions: [AccountChoice]) {
        let hasActiveNonOpenAI = aiAccounts.contains { $0.isActive && $0.provider != .openai && $0.supportsExecution }
        for choice in sessions {
            if let index = aiAccounts.firstIndex(where: { $0.provider == .openai && $0.sessionID == choice.id }) {
                if aiAccounts[index].workspaceID != choice.workspaceID {
                    aiAccounts[index].models = []; aiAccounts[index].modelsUpdatedAt = nil
                }
                aiAccounts[index].workspaceID = choice.workspaceID
                if !hasActiveNonOpenAI {
                    aiAccounts[index].isActive = choice.active
                } else {
                    aiAccounts[index].isActive = false
                }
            } else {
                var account = AIAccount(name: choice.label, provider: .openai, emailOrIdentity: choice.label, isActive: !hasActiveNonOpenAI && choice.active)
                account.sessionID = choice.id
                account.workspaceID = choice.workspaceID
                aiAccounts.append(account)
            }
        }
        // Revoked sessions must never remain executable based on cached metadata.
        for index in aiAccounts.indices where aiAccounts[index].provider == .openai {
            if let id = aiAccounts[index].sessionID, !sessions.contains(where: { $0.id == id }) {
                aiAccounts[index].sessionID = nil
                aiAccounts[index].models = []
                aiAccounts[index].isActive = false
            }
        }
    }

    func addOrUpdateProject(_ item: ProjectItem) {
        if let idx = projects.firstIndex(where: { $0.id == item.id }) {
            let oldPath = projects[idx].path
            if oldPath != item.path {
                pinnedProjects.removeAll { $0 == oldPath }
                projectPaths.removeAll { $0 == oldPath }
            }
            projects[idx] = item
        } else {
            projects.append(item)
        }
        if item.pinned && !pinnedProjects.contains(item.path) {
            pinnedProjects.append(item.path)
        } else if !item.pinned {
            pinnedProjects.removeAll { $0 == item.path }
        }
        if !projectPaths.contains(item.path) {
            projectPaths.append(item.path)
        }
    }

    func deleteProject(_ item: ProjectItem) {
        projects.removeAll { $0.id == item.id }
        pinnedProjects.removeAll { $0 == item.path }
        projectPaths.removeAll { $0 == item.path }
    }

    func togglePinProject(_ item: ProjectItem) {
        if let idx = projects.firstIndex(where: { $0.id == item.id }) {
            projects[idx].pinned.toggle()
            if projects[idx].pinned {
                if !pinnedProjects.contains(projects[idx].path) { pinnedProjects.append(projects[idx].path) }
            } else {
                pinnedProjects.removeAll { $0 == projects[idx].path }
            }
        }
    }

    func addAccount(_ account: AIAccount) {
        if let index = aiAccounts.firstIndex(where: { $0.id == account.id }) { aiAccounts[index] = account }
        else { aiAccounts.append(account) }
    }

    func deleteAccount(_ account: AIAccount) {
        aiAccounts.removeAll { $0.id == account.id }

    }

    func selectAccount(_ account: AIAccount) {
        for i in aiAccounts.indices {
            aiAccounts[i].isActive = (aiAccounts[i].id == account.id)
        }
    }

    var activeAccount: AIAccount? {
        aiAccounts.first(where: { $0.isActive && $0.supportsExecution }) ?? aiAccounts.first(where: \.supportsExecution)
    }

    func setActiveAccount(id: UUID) {
        for i in aiAccounts.indices {
            aiAccounts[i].isActive = (aiAccounts[i].id == id)
        }
    }

    func markAccountExhausted(accountID: UUID) {
        guard let index = aiAccounts.firstIndex(where: { $0.id == accountID }) else { return }
        aiAccounts[index].exhaustedModelIndices = Array(0..<aiAccounts[index].models.count)
        aiAccounts[index].isActive = false
    }

    func markModelExhausted(accountID: UUID, modelIndex: Int) {
        guard let index = aiAccounts.firstIndex(where: { $0.id == accountID }) else { return }
        if !aiAccounts[index].exhaustedModelIndices.contains(modelIndex) {
            aiAccounts[index].exhaustedModelIndices.append(modelIndex)
        }
    }

    func nextAvailableAccount(excluding currentID: UUID?) -> AIAccount? {
        if let found = aiAccounts.first(where: { $0.id != currentID && $0.hasAvailableModels }) {
            return found
        }
        return aiAccounts.first(where: { $0.id != currentID })
    }

    private static func load<T: Codable>(_ type: [T].Type, key: String) -> [T] {
        guard let data = UserDefaults.standard.data(forKey: "wisdcode.desktop." + key) else { return [] }
        return (try? JSONDecoder().decode(type, from: data)) ?? []
    }

    private func save<T: Codable>(_ value: [T], key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: "wisdcode.desktop." + key)
        }
    }

    func runDue(using workspace: Workspace) {
        let now = Date()
        guard !running, workspace.ready, !workspace.busy, !workspace.accountBusy,
              let account = workspace.accountIdentity,
              let index = tasks.firstIndex(where: { !$0.paused && $0.accountID == account && $0.next <= now }) else { return }
        let task = tasks[index]
        guard FileManager.default.fileExists(atPath: task.folder) else {
            tasks[index].paused = true
            tasks[index].lastResult = "Pasta do projeto indisponível"
            return
        }
        // Record the next attempt before dispatch so restarting cannot repeat the same occurrence.
        if task.days == 0 {
            tasks[index].paused = true
        } else if let next = Calendar.current.date(byAdding: .day, value: task.days, to: now) {
            tasks[index].next = next
        } else {
            tasks[index].paused = true
        }
        tasks[index].lastResult = "Execução iniciada"
        running = true
        workspace.runScheduled(task) { [weak self] success, threadID, failureMessage in
            guard let self else { return }
            self.running = false
            if let current = self.tasks.firstIndex(where: { $0.id == task.id }) {
                if let threadID { self.tasks[current].lastThreadID = threadID }
                if success {
                    self.tasks[current].lastResult = "Concluída"
                } else {
                    self.tasks[current].lastResult = failureMessage.map { "Falhou: \($0)" } ?? "Falhou"
                }
            }
        }
    }

    func runNow(_ id: UUID, using workspace: Workspace) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].paused = false
        tasks[index].next = Date()
        runDue(using: workspace)
    }

    func togglePaused(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].paused.toggle()
        if !tasks[index].paused && tasks[index].next <= Date() {
            tasks[index].next = Date().addingTimeInterval(60)
        }
    }

    func removeTask(_ id: UUID) {
        tasks.removeAll { $0.id == id }
    }
}

private struct ExtensionEntry: Identifiable {
    let id: String
    let name: String
    let description: String
    let installed: Bool
    let installAllowed: Bool
    let parameters: JSON
    var category = "Ferramentas"
    var logo: String?
    var logoURL: String?
    var fullDescription: String?
}

private struct ExtensionLogo: View {
    let entry: ExtensionEntry

    var body: some View {
        Group {
            if let path = entry.logo, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image).resizable().scaledToFit()
            } else if let address = entry.logoURL, let url = URL(string: address), url.scheme == "https" {
                AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { placeholder }
            } else { placeholder }
        }.padding(6).frame(width: 42, height: 42)
            .background(DesktopStyle.surface, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(DesktopStyle.line))
    }

    private var placeholder: some View {
        Text(String(entry.name.prefix(1))).font(.system(size: 22, weight: .semibold))
    }
}

struct UsageDetails: View {
    @ObservedObject var workspace: Workspace

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Limites em tempo real").font(.headline)
                Spacer()
                if let last = workspace.quotaStore.lastGlobalRefreshAt {
                    Text("Atualizado às \(last.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await workspace.refreshAllQuotasNow(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(workspace.quotaStore.isRefreshing)
            }

            if !workspace.usageWindows.isEmpty {
                ForEach(workspace.usageWindows) { window in
                    let remaining = min(100, max(0, 100 - window.used))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(window.title)
                            Spacer()
                            Text("\(remaining)% restante").monospacedDigit()
                        }
                        ProgressView(value: Double(remaining), total: 100)
                        if let reset = window.reset { Text("Renova em \(reset.formatted())").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }

            if let local = workspace.localDataRef, !local.aiAccounts.isEmpty {
                Divider()
                Text("Monitoramento em memória por conta e modelo").font(.subheadline).fontWeight(.semibold)
                ForEach(local.aiAccounts) { acc in
                    let snap = workspace.quotaStore.accountSnapshot(for: acc.id)
                    let accAvail = snap?.availability ?? (acc.hasAvailableModels ? .unknown : .exhausted)
                    let metrics = workspace.quotaStore.allMetrics(for: acc.id)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: acc.provider.iconName).foregroundStyle(.blue)
                            Text(acc.name).fontWeight(.medium)
                            Spacer()
                            Text(accAvail.label)
                                .font(.caption)
                                .foregroundStyle(accAvail == .exhausted ? .red : (accAvail == .nearLimit ? .orange : (accAvail == .available ? .green : .secondary)))
                        }
                        if let rem = snap?.remainingPercent {
                            ProgressView(value: Double(rem), total: 100)
                            HStack {
                                Text("\(rem)% restante")
                                Spacer()
                                if let reset = snap?.nextResetAt {
                                    Text("Renova às \(reset.formatted(date: .omitted, time: .shortened))")
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        } else if let tokens = snap?.totalTokensConsumed, tokens > 0 {
                            Text("\(tokens.formatted()) tokens consumidos nesta sessão")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !metrics.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(metrics.prefix(6)) { m in
                                    HStack {
                                        Text(AIProvider.modelDisplayName(for: m.modelID))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        if m.availability == .exhausted {
                                            Text(m.nextResetAt.map { "Esgotado · \($0.formatted(date: .omitted, time: .shortened))" } ?? "Esgotado")
                                                .font(.caption2)
                                                .foregroundStyle(.red)
                                        } else if let rem = m.remainingPercent {
                                            Text("\(rem)% livre")
                                                .font(.caption2)
                                                .monospacedDigit()
                                                .foregroundStyle(rem < 15 ? .orange : .green)
                                        } else if m.totalTokensConsumed > 0 {
                                            Text("\(m.totalTokensConsumed.formatted()) tok")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .padding(.leading, 16)
                        }
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
                }
            } else if workspace.usageWindows.isEmpty {
                Text("Aguardando leitura de cota das contas conectadas.").foregroundStyle(.secondary)
            }

            if let balance = workspace.creditBalance { Text("Créditos · \(balance)").foregroundStyle(.secondary) }
        }
    }
}

struct DesktopPanels: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var workspace: Workspace
    @ObservedObject var local: DesktopLocalData
    @Binding var page: DesktopPage
    @State private var query = ""
    @State private var libraryFilter = "Tudo"
    @State private var grid = true
    @State private var showSchedule = false
    @State private var showScheduleRepeatPopover = false
    @State private var scheduleName = ""
    @State private var schedulePrompt = ""
    @State private var scheduleDate = Date().addingTimeInterval(300)
    @State private var scheduleDays = 0
    @State private var onlyPaused = false
    @State private var skillTab = false
    @State private var installedOnly = false
    @State private var plugins: [ExtensionEntry] = []
    @State private var skills: [ExtensionEntry] = []
    @State private var loadingExtensions = false
    @State private var extensionRequest = UUID()
    @State private var pendingPlugin: ExtensionEntry?
    @State private var selectedExtension: ExtensionEntry?
    @State private var extensionNotice: String?
    @State private var extensionError: String?
    @State private var lifetimeTokens: Int?
    @State private var usageTab = "Visão geral"
    @State private var confirmReset = false
    @State private var resetInFlight = false
    @State private var resetAttempt = UUID()
    @State private var resetNotice: String?

    var body: some View {
        HStack(spacing: 0) {
            if [.schedule, .plugins, .figma, .skills, .settings, .usage].contains(page) {
                panelSidebar
                Divider()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch page {
                    case .schedule: schedulePanel
                    case .library, .images: libraryPanel
                    case .plugins, .figma, .skills: extensionsPanel
                    case .sites: sitesPanel
                    case .settings: settingsPanel
                    case .usage: usagePanel
                    case .chat: EmptyView()
                    case .maps, .assistants: unconnectedPanel
                    }
                }
                .frame(maxWidth: [.library, .images, .sites].contains(page) ? 1100 : 780, alignment: .leading)
                .padding(30)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesktopStyle.canvas)
        .onChange(of: page, initial: true) {
            query = ""
            if page == .images { libraryFilter = "Imagens" }
            if page == .figma { query = "Figma"; skillTab = false }
            if page == .skills { skillTab = true }
            if [.plugins, .figma, .skills].contains(page) { loadExtensions() }
            if page == .usage { refreshUsage() }
        }
        .onChange(of: workspace.ready) {
            if [.plugins, .figma, .skills].contains(page) { loadExtensions() }
            if page == .usage { refreshUsage() }
        }
        .onChange(of: workspace.accountIdentity) {
            lifetimeTokens = nil
            resetNotice = nil
            resetAttempt = UUID()
            if page == .usage { refreshUsage() }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSchedule) {
            scheduleEditor
                .presentationBackground(.clear)
        }
        .sheet(item: $selectedExtension) { entry in
            extensionDetail(entry)
                .presentationBackground(.clear)
        }
        .sheet(item: $pendingPlugin) { plugin in
            WisdModalShell(
                title: plugin.installed ? "Remover plugin?" : "Instalar plugin?",
                subtitle: plugin.name,
                statusColor: plugin.installed ? WisdTheme.danger : WisdTheme.iconAccent,
                width: 420,
                onClose: { pendingPlugin = nil },
                footer: {
                    HStack(spacing: 10) {
                        Spacer()
                        WisdSecondaryButton("Cancelar") { pendingPlugin = nil }
                        if plugin.installed {
                            Button {
                                changePlugin(plugin)
                                pendingPlugin = nil
                            } label: {
                                Text("Remover")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(WisdTheme.danger))
                            }
                            .buttonStyle(.plain)
                        } else {
                            WisdPrimaryButton("Instalar", icon: "arrow.down.circle") {
                                changePlugin(plugin)
                                pendingPlugin = nil
                            }
                        }
                    }
                }
            ) {
                Text(plugin.installed ? "O plugin \"\(plugin.name)\" será desativado e removido desta sessão." : "Deseja instalar o plugin \"\(plugin.name)\" nesta conta?")
                    .font(.system(size: 13))
                    .foregroundStyle(WisdTheme.ink(scheme))
            }
            .presentationBackground(.clear)
        }
        .sheet(isPresented: $confirmReset) {
            WisdModalShell(
                title: "Usar uma redefinição de limite?",
                subtitle: "Solicitação de crédito da conta ativa",
                statusColor: WisdTheme.warning,
                width: 430,
                onClose: { confirmReset = false },
                footer: {
                    HStack(spacing: 10) {
                        Spacer()
                        WisdSecondaryButton("Cancelar") { confirmReset = false }
                        WisdPrimaryButton("Confirmar", icon: "checkmark") {
                            confirmReset = false
                            redeemReset()
                        }
                    }
                }
            ) {
                Text("A solicitação usa um crédito de redefinição da conta ativa quando o servidor confirmar a elegibilidade.")
                    .font(.system(size: 13))
                    .foregroundStyle(WisdTheme.ink(scheme))
            }
            .presentationBackground(.clear)
        }
    }

    private var panelSidebar: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(page == .usage ? "Configurações" : [.plugins, .figma, .skills].contains(page) ? "Personalizar" : page.rawValue).font(.system(size: 19, weight: .semibold))
            switch page {
            case .schedule:
                Button("Nova tarefa", systemImage: "plus") { beginSchedule() }
                    .padding(.vertical, 6)
                Button { onlyPaused.toggle() } label: {
                    HStack { Text("Em pausa"); Image(systemName: onlyPaused ? "chevron.down" : "chevron.right").font(.caption) }
                }.foregroundStyle(DesktopStyle.muted)
            case .plugins, .figma, .skills:
                Button("Plugins", systemImage: "puzzlepiece.extension") { skillTab = false; installedOnly = false }
                    .padding(9).frame(maxWidth: .infinity, alignment: .leading)
                    .modifier(DesktopHover(selected: !skillTab && !installedOnly))
                Button("Habilidades", systemImage: "cube") { skillTab = true }
                    .padding(9).frame(maxWidth: .infinity, alignment: .leading)
                    .modifier(DesktopHover(selected: skillTab))
                Button("Instalados") { installedOnly.toggle(); skillTab = false }
                    .foregroundStyle(DesktopStyle.muted).padding(.top, 16)
                ForEach(plugins.filter(\.installed)) { entry in
                    Button { selectedExtension = entry } label: {
                        HStack(spacing: 10) {
                            ExtensionLogo(entry: entry).scaleEffect(0.6).frame(width: 26, height: 26)
                            Text(entry.name).lineLimit(1)
                        }.padding(6).frame(maxWidth: .infinity, alignment: .leading).modifier(DesktopHover())
                    }
                }
            case .settings, .usage:
                Button("Conta", systemImage: "person.crop.circle") { page = .settings }
                Button("Uso e faturamento", systemImage: "gauge.with.dots.needle.50percent") { page = .usage }
                Button("Plugins", systemImage: "puzzlepiece.extension") { page = .plugins }
            default:
                EmptyView()
            }
            Spacer()
        }
        .buttonStyle(.plain)
        .padding(15)
        .frame(width: 288, alignment: .leading)
        .background(DesktopStyle.canvas)
    }

    private func heading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 25, weight: .semibold))
            Text(subtitle).foregroundStyle(.secondary)
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(DesktopStyle.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(DesktopStyle.line))
    }

    private func beginSchedule(_ title: String = "", prompt: String = "") {
        scheduleName = title
        schedulePrompt = prompt
        scheduleDate = Date().addingTimeInterval(60)
        scheduleDays = 0
        showSchedule = true
    }

    private func scheduleCadence(_ days: Int) -> String {
        switch days {
        case 1: return "Diária"
        case 7: return "Semanal"
        default: return "Uma vez"
        }
    }

    private var schedulePanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 12) {
                Text("🕒").font(.system(size: 42)).padding(.bottom, 4)
                Text("Agendar uma tarefa").font(.system(size: 21, weight: .regular))
                Text("Tarefas locais são executadas com o WisdCode aberto e a conta escolhida conectada.")
                    .font(.system(size: 14)).foregroundStyle(DesktopStyle.muted).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity).padding(.top, 24).padding(.bottom, 22)
            if workspace.project == nil || workspace.accountIdentity == nil {
                Text("Abra um projeto e conecte uma conta ChatGPT para agendar.").foregroundStyle(.secondary)
            }
            ForEach(local.tasks) { task in
                if !onlyPaused || task.paused {
                    let projectName = URL(fileURLWithPath: task.folder).lastPathComponent
                    let sameAccount = task.accountID == workspace.accountIdentity
                    card {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(task.name).font(.headline)
                                Text("\(projectName) · \(scheduleCadence(task.days)) · \(task.paused ? "Em pausa" : task.next.formatted())")
                                    .foregroundStyle(.secondary)
                                if !sameAccount {
                                    Text("Agendada para outra conta").font(.caption).foregroundStyle(.orange)
                                }
                                if let result = task.lastResult { Text(result).font(.caption) }
                            }
                            Spacer()
                            HStack(spacing: 8) {
                                if let threadID = task.lastThreadID {
                                    Button("Abrir") {
                                        page = .chat
                                        workspace.openThread(id: threadID, cwd: task.folder)
                                    }
                                    .disabled(workspace.busy)
                                }
                                Button("Executar agora") { local.runNow(task.id, using: workspace) }
                                    .disabled(!sameAccount || !workspace.ready || workspace.busy || workspace.accountBusy || workspace.scheduledBusy)
                                Button(task.paused ? "Retomar" : "Pausar") { local.togglePaused(task.id) }
                                Button("Remover", systemImage: "trash") { local.removeTask(task.id) }
                                    .labelStyle(.iconOnly)
                            }
                        }
                    }
                    .contextMenu {
                        if let threadID = task.lastThreadID {
                            Button("Abrir conversa") {
                                page = .chat
                                workspace.openThread(id: threadID, cwd: task.folder)
                            }
                            .disabled(workspace.busy)
                        }
                        Button("Executar agora") { local.runNow(task.id, using: workspace) }
                            .disabled(!sameAccount || !workspace.ready || workspace.busy || workspace.accountBusy || workspace.scheduledBusy)
                        Button(task.paused ? "Retomar" : "Pausar") { local.togglePaused(task.id) }
                        Button("Remover", role: .destructive) { local.removeTask(task.id) }
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 275), spacing: 14)], spacing: 14) {
                ForEach(scheduleSuggestions, id: \.0) { suggestion in
                    scheduleTemplate(suggestion.0, icon: suggestion.1, prompt: suggestion.2)
                }
            }
        }
    }

    private let scheduleSuggestions: [(String, String, String)] = [
        ("Revisar alterações", "💻", "Revise as alterações locais do projeto e liste riscos e testes pendentes."),
        ("Planejar meus looks", "👕", "Prepare uma lista de looks usando as roupas e a previsão que eu fornecer."),
        ("Acompanhar prazos", "📅", "Liste os próximos prazos registrados nas notas do projeto."),
        ("Agendar treinos", "💪", "Prepare um plano de treino semanal a partir das minhas notas."),
        ("Encontrar meu próximo livro", "📚", "Sugira três livros a partir dos meus interesses registrados."),
        ("Conferir e-mails do trabalho", "📨", "Analise os e-mails fornecidos e organize prioridades e próximos passos."),
        ("Organizar e-mails", "✉️", "Classifique os e-mails fornecidos e proponha uma organização."),
        ("Receber atualizações de notícias", "📰", "Resuma as notícias fornecidas sobre os tópicos que acompanho."),
        ("Buscar assentos em voos", "✈️", "Organize as opções de assentos e os voos que eu fornecer."),
        ("Atualizar meu orçamento", "💰", "Analise meu orçamento local e proponha atualizações com os gastos fornecidos."),
        ("Acompanhar testes grátis", "⏰", "Confira os prazos de testes gratuitos registrados nas minhas notas."),
        ("Encontrar shows", "🎤", "Compare os shows registrados e prepare uma lista de opções."),
        ("O que assistir", "🎬", "Sugira três filmes ou séries usando os meus gostos registrados."),
        ("Comparar produtos", "🛍️", "Compare os produtos e preços que eu fornecer."),
        ("Ver a previsão do tempo", "🌤️", "Organize a previsão fornecida para os próximos três dias."),
        ("Preparar pedido à seguradora", "🛡️", "Liste a documentação necessária e prepare um rascunho com os dados fornecidos."),
        ("Planejar minha viagem", "🧳", "Organize um roteiro a partir das minhas notas e opções de viagem."),
        ("Acompanhar notícias da empresa", "🏢", "Resuma as atualizações fornecidas sobre a minha empresa."),
        ("Planejar compras de supermercado", "🥕", "Prepare os jantares da semana e uma lista de compras para revisão."),
        ("Tarefas da família", "👨‍👩‍👧", "Organize as tarefas e os prazos da família a partir das notas fornecidas."),
        ("Monitorar quedas de preço", "📉", "Compare os preços registrados e destaque reduções."),
        ("Verificar cobranças", "💳", "Revise os gastos fornecidos e sinalize cobranças que precisam de conferência."),
        ("Rastrear encomendas", "📦", "Organize os códigos, prazos e atualizações de entrega que eu fornecer."),
        ("Candidaturas a vagas", "💼", "Resuma as candidaturas e as próximas etapas registradas."),
        ("Aprender um idioma", "🌍", "Prepare uma lição curta no meu nível com exercícios."),
        ("Acompanhar notícias do setor", "📈", "Resuma os materiais fornecidos sobre o meu setor."),
        ("Encontrar descontos", "🏷️", "Compare as ofertas fornecidas e destaque condições e economia."),
        ("Verificar assinaturas", "💵", "Revise as assinaturas registradas e identifique oportunidades de economia."),
        ("Planejar meu fim de semana", "🎟️", "Monte um plano com as atividades e horários que eu fornecer."),
        ("Lembrar de aniversários", "🎂", "Confira os próximos aniversários registrados e prepare lembretes."),
        ("Seguir um tópico", "🔎", "Resuma as mudanças no tópico a partir dos materiais disponíveis."),
        ("Buscar leituras para o fim de semana", "📖", "Escolha uma leitura entre os artigos fornecidos e explique a escolha.")
    ]

    private func scheduleTemplate(_ name: String, icon: String, prompt: String) -> some View {
        Button { beginSchedule(name, prompt: prompt) } label: {
            HStack(alignment: .center, spacing: 14) {
                Text(icon).font(.system(size: 25)).frame(width: 32)
                VStack(alignment: .leading, spacing: 6) {
                    Text(name).font(.system(size: 15))
                    Text(prompt).font(.system(size: 13)).foregroundStyle(DesktopStyle.muted).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(20).frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(DesktopStyle.line, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
            .modifier(DesktopHover(radius: 22))
        }.buttonStyle(.plain)
    }

    private var scheduleEditor: some View {
        let canSchedule = !scheduleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !schedulePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            workspace.project != nil && workspace.accountIdentity != nil
        let repeatLabel: String = {
            switch scheduleDays {
            case 1: return "Diária"
            case 7: return "Semanal"
            default: return "Uma vez"
            }
        }()

        return WisdModalShell(
            title: "Nova tarefa agendada",
            subtitle: workspace.project?.lastPathComponent ?? "Selecione um projeto antes de agendar",
            statusColor: workspace.project == nil ? WisdTheme.warning : WisdTheme.iconAccent,
            width: 470,
            onClose: { showSchedule = false },
            footer: {
                HStack(spacing: 10) {
                    Spacer()
                    WisdSecondaryButton("Cancelar") { showSchedule = false }
                    WisdPrimaryButton("Agendar", icon: "calendar.badge.plus", disabled: !canSchedule) {
                        guard let folder = workspace.project?.path, let account = workspace.accountIdentity else { return }
                        local.tasks.append(ScheduledTask(name: scheduleName.trimmingCharacters(in: .whitespacesAndNewlines),
                                                        prompt: schedulePrompt, folder: folder, accountID: account,
                                                        next: scheduleDate, days: scheduleDays))
                        showSchedule = false
                    }
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    WisdSecondaryButton("Escolher projeto", icon: "folder") { workspace.chooseProject() }
                        .disabled(workspace.busy)
                    Text(workspace.project?.lastPathComponent ?? "Nenhum projeto selecionado")
                        .font(.system(size: 12.5))
                        .foregroundStyle(WisdTheme.muted(scheme))
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Título")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(WisdTheme.muted(scheme))
                    TextField("Nome da tarefa recorrente…", text: $scheduleName)
                        .wisdFieldSurface()
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("O que fazer")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(WisdTheme.muted(scheme))
                    TextField("Descreva a instrução que será executada…", text: $schedulePrompt, axis: .vertical)
                        .lineLimit(3...6)
                        .wisdFieldSurface()
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Primeira execução")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(WisdTheme.muted(scheme))
                        DatePicker("", selection: $scheduleDate, in: Date().addingTimeInterval(-60)...)
                            .labelsHidden()
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Repetição")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(WisdTheme.muted(scheme))
                        WisdDropdownTrigger(
                            icon: "repeat",
                            title: repeatLabel,
                            isPresented: showScheduleRepeatPopover
                        ) {
                            showScheduleRepeatPopover.toggle()
                        }
                        .frame(width: 155)
                        .popover(isPresented: $showScheduleRepeatPopover, arrowEdge: .bottom) {
                            WisdPopoverShell(
                                title: "Repetição",
                                subtitle: "Frequência da tarefa",
                                statusColor: WisdTheme.iconAccent,
                                width: 220
                            ) {
                                WisdPopoverSection {
                                    VStack(spacing: 2) {
                                        WisdSelectableRow(icon: "1.circle", title: "Uma vez", selected: scheduleDays == 0) {
                                            scheduleDays = 0; showScheduleRepeatPopover = false
                                        }
                                        WisdSelectableRow(icon: "sun.max", title: "Diária", selected: scheduleDays == 1) {
                                            scheduleDays = 1; showScheduleRepeatPopover = false
                                        }
                                        WisdSelectableRow(icon: "calendar", title: "Semanal", selected: scheduleDays == 7) {
                                            scheduleDays = 7; showScheduleRepeatPopover = false
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.top, 8)
                                }
                            }
                            .presentationBackground(.clear)
                        }
                    }
                }

                Text("Executa em modo somente leitura, com o app aberto. O resultado fica em uma nova conversa.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(WisdTheme.muted(scheme))
            }
        }
    }

    private func pickFiles(folders: Bool, files: Bool, multiple: Bool) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = folders
        panel.canChooseFiles = files
        panel.allowsMultipleSelection = multiple
        return panel.runModal() == .OK ? panel.urls : []
    }

    private func importFiles() {
        for url in pickFiles(folders: true, files: true, multiple: true)
        where !local.library.contains(where: { $0.path == url.path }) {
            local.library.append(LibraryEntry(path: url.path))
        }
    }

    private func matches(_ text: String) -> Bool { query.isEmpty || text.localizedCaseInsensitiveContains(query) }

    private var libraryPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Espaço").font(.system(size: 27, weight: .medium))
                Spacer()
                Button(grid ? "Lista" : "Grade", systemImage: grid ? "list.bullet" : "square.grid.2x2") { grid.toggle() }
                    .labelStyle(.iconOnly)
                DesktopSearchField(title: "Pesquisar no Espaço", text: $query).frame(maxWidth: 250)
                Button("Importar", systemImage: "plus", action: importFiles).buttonStyle(.borderedProminent)
            }
            Picker("Filtro", selection: $libraryFilter) {
                ForEach(["Tudo", "Favoritos", "Pastas", "Imagens"], id: \.self) { Text($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 420)
            let entries = local.library.filter { entry in
                matches(entry.url.lastPathComponent) &&
                    (libraryFilter == "Tudo" || (libraryFilter == "Favoritos" && entry.favorite) ||
                     (libraryFilter == "Pastas" && entry.isFolder) || (libraryFilter == "Imagens" && entry.isImage))
            }
            if entries.isEmpty {
                Text("Importe arquivos ou pastas para acessar nesta biblioteca local.").foregroundStyle(.secondary)
            }
            LazyVGrid(columns: grid ? [GridItem(.adaptive(minimum: 170), spacing: 12)] : [GridItem(.flexible())], spacing: 12) {
                ForEach(entries) { entry in
                    card {
                        VStack(alignment: .leading, spacing: 8) {
                            if grid {
                                if entry.isImage, let image = NSImage(contentsOf: entry.url) {
                                    Image(nsImage: image).resizable().scaledToFit().frame(height: 92)
                                } else {
                                    Image(systemName: entry.isFolder ? "folder" : "doc").font(.system(size: 36))
                                        .foregroundStyle(.secondary).frame(height: 92)
                                }
                            }
                            HStack {
                                Button(entry.url.lastPathComponent) { NSWorkspace.shared.open(entry.url) }
                                    .buttonStyle(.plain).lineLimit(1)
                                Spacer(minLength: 2)
                                Button(entry.favorite ? "Remover favorito" : "Favoritar", systemImage: entry.favorite ? "star.fill" : "star") {
                                    if let index = local.library.firstIndex(where: { $0.id == entry.id }) { local.library[index].favorite.toggle() }
                                }
                                .labelStyle(.iconOnly).buttonStyle(.plain)
                            }
                        }
                    }
                    .contextMenu {
                        Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
                        Button("Remover da biblioteca") { local.library.removeAll { $0.id == entry.id } }
                    }
                }
            }
        }
    }

    private var unconnectedPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading(page.rawValue, subtitle: page == .maps ? "Organize lugares e ideias" : "Assistentes para suas tarefas")
            VStack(spacing: 16) {
                Image(systemName: page.icon).font(.system(size: 34)).foregroundStyle(DesktopStyle.muted)
                Text(page == .maps ? "Ainda não há mapas" : "Ainda não há assistentes personalizados")
                    .font(.system(size: 20))
                Text("Esta área visual ainda precisa de integração no WisdCode.")
                    .foregroundStyle(DesktopStyle.muted)
            }.frame(maxWidth: .infinity).padding(.vertical, 180)
        }
    }

    private var sitesPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                heading("Sites", subtitle: "Projetos web locais")
                Spacer()
                DesktopSearchField(title: "Pesquisar sites", text: $query).frame(maxWidth: 230)
                Button("Criar site", systemImage: "plus") { addSite(draft: true) }.buttonStyle(.borderedProminent)
                Button("Adicionar pasta") { addSite(draft: false) }
            }
            if local.sites.isEmpty {
                ContentUnavailableView("Ainda não há sites", systemImage: "square.grid.2x2",
                                       description: Text("Escolha uma pasta para iniciar um site com o WisdCode."))
                    .frame(minHeight: 320)
            }
            ForEach(local.sites.filter { matches($0.url.lastPathComponent) }) { site in
                card {
                    HStack {
                        Label(site.url.lastPathComponent, systemImage: "globe")
                        Spacer()
                        Button("Abrir pasta") { NSWorkspace.shared.open(site.url) }
                        let index = site.url.appendingPathComponent("index.html")
                        if FileManager.default.fileExists(atPath: index.path) {
                            Button("Prévia") { NSWorkspace.shared.open(index) }
                        }
                    }
                }
                .contextMenu { Button("Remover da lista") { local.sites.removeAll { $0.id == site.id } } }
            }
        }
    }

    private func addSite(draft: Bool) {
        guard let folder = pickFiles(folders: true, files: false, multiple: false).first else { return }
        if !local.sites.contains(where: { $0.path == folder.path }) { local.sites.append(LibraryEntry(path: folder.path)) }
        if draft, !workspace.busy {
            workspace.project = folder
            workspace.newConversation()
            workspace.prompt = "Crie um site neste projeto. Requisitos: "
            page = .chat
        }
    }

    private var extensionsPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                heading(skillTab ? "Habilidades" : "Plugins", subtitle: skillTab ? "Habilidades encontradas pelo motor." : "Catálogos e plugins disponíveis para esta instalação.")
                Spacer()
                DesktopSearchField(title: skillTab ? "Procurar habilidades" : "Procurar plugins", text: $query).frame(maxWidth: 250)
                Button("Atualizar", systemImage: "arrow.clockwise") { loadExtensions(force: true) }
                    .labelStyle(.iconOnly).disabled(loadingExtensions || !workspace.ready)
            }
            if let extensionError { Text(extensionError).foregroundStyle(.red) }
            if let extensionNotice { Text(extensionNotice).foregroundStyle(.secondary) }
            let entries = (skillTab ? skills : plugins).filter { matches($0.name) && (skillTab || !installedOnly || $0.installed) }
            if entries.isEmpty {
                if loadingExtensions { ProgressView().controlSize(.small) }
                else { Text("Nenhum item disponível neste catálogo.").foregroundStyle(.secondary) }
            }
            Text(skillTab ? "Suas habilidades" : installedOnly ? "Instalados" : "Público")
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(DesktopStyle.surface, in: Capsule())
            ForEach(Array(Set(entries.map(\.category))).sorted(), id: \.self) { category in
                if !skillTab { Text(category).font(.system(size: 18)).padding(.top, 12) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 285), spacing: 24)], spacing: 18) {
                    ForEach(entries.filter { $0.category == category }) { entry in
                        HStack(spacing: 14) {
                            Button { selectedExtension = entry } label: {
                                HStack(spacing: 14) {
                                    ExtensionLogo(entry: entry)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(entry.name).font(.system(size: 15)).lineLimit(1)
                                        Text(entry.description).font(.system(size: 13)).lineLimit(2).foregroundStyle(DesktopStyle.muted)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            if skillTab {
                                Toggle("Ativar \(entry.name)", isOn: Binding(get: { entry.installed }, set: { _ in changeSkill(entry) }))
                                    .toggleStyle(.switch).labelsHidden().controlSize(.mini)
                            } else {
                                Button { selectedExtension = entry } label: {
                                    Image(systemName: entry.installed ? "ellipsis" : entry.installAllowed ? "plus" : "info.circle")
                                }.accessibilityLabel("Detalhes de \(entry.name)")
                            }
                        }.padding(.vertical, 12)
                    }
                }
            }
        }
        .onChange(of: skillTab) { query = page == .figma && !skillTab ? "Figma" : ""; loadExtensions() }
    }

    private func loadExtensions(force: Bool = false) {
        guard workspace.ready else { return }
        let requestID = UUID()
        extensionRequest = requestID
        loadingExtensions = true
        extensionError = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
            guard extensionRequest == requestID, loadingExtensions else { return }
            loadingExtensions = false
            extensionError = "O catálogo está demorando para responder. Você pode tentar atualizar."
        }
        let cwd = workspace.project.map { [$0.path] } ?? []
        if skillTab {
            workspace.request("skills/list", ["cwds": cwd, "forceReload": force]) { response in
                guard extensionRequest == requestID else { return }
                defer { loadingExtensions = false }
                extensionError = nil
                guard let result = response["result"] as? JSON else {
                    extensionError = (response["error"] as? JSON)?["message"] as? String
                    return
                }
                skills = (result["data"] as? [JSON] ?? []).flatMap { $0["skills"] as? [JSON] ?? [] }.compactMap { raw in
                    guard let name = raw["name"] as? String, let path = raw["path"] as? String else { return nil }
                    return ExtensionEntry(id: path, name: name, description: raw["description"] as? String ?? "",
                                          installed: raw["enabled"] as? Bool ?? false, installAllowed: true,
                                          parameters: ["path": path])
                }
            }
        } else {
            var params: JSON = ["forceRefetch": force]
            if !cwd.isEmpty { params["cwds"] = cwd }
            workspace.request("plugin/list", params) { response in
                guard extensionRequest == requestID else { return }
                defer { loadingExtensions = false }
                extensionError = nil
                guard let result = response["result"] as? JSON else {
                    extensionError = (response["error"] as? JSON)?["message"] as? String
                    return
                }
                plugins = (result["marketplaces"] as? [JSON] ?? []).flatMap { marketplace -> [ExtensionEntry] in
                    let market = marketplace["name"] as? String ?? ""
                    return (marketplace["plugins"] as? [JSON] ?? []).compactMap { raw in
                        guard let id = raw["id"] as? String, let name = raw["name"] as? String else { return nil }
                        var params: JSON = ["pluginName": name]
                        if let path = marketplace["path"] as? String { params["marketplacePath"] = path }
                        else if !market.isEmpty { params["remoteMarketplaceName"] = market }
                        let interface = raw["interface"] as? JSON
                        return ExtensionEntry(id: market + ":" + id, name: interface?["displayName"] as? String ?? name,
                                              description: interface?["shortDescription"] as? String ?? market,
                                              installed: raw["installed"] as? Bool ?? false,
                                              installAllowed: raw["installPolicy"] as? String == "AVAILABLE"
                                                  && raw["mustShowInstallationInterstitial"] as? Bool != true && params.count > 1,
                                              parameters: params.merging(["pluginId": id]) { first, _ in first },
                                              category: interface?["category"] as? String ?? "Ferramentas",
                                              logo: interface?["logo"] as? String,
                                              logoURL: interface?["logoUrl"] as? String,
                                              fullDescription: interface?["longDescription"] as? String)
                    }
                }
            }
        }
    }

    private func changePlugin(_ entry: ExtensionEntry) {
        let params = entry.installed ? entry.parameters.filter { $0.key == "pluginId" } :
            entry.parameters.filter { $0.key != "pluginId" }
        workspace.request(entry.installed ? "plugin/uninstall" : "plugin/install", params) { response in
            if let result = response["result"] as? JSON {
                extensionNotice = (result["appsNeedingAuth"] as? [JSON])?.isEmpty == false
                    ? "Plugin instalado. Algumas conexões ainda precisam de autorização." : nil
                loadExtensions()
            } else { extensionError = (response["error"] as? JSON)?["message"] as? String }
        }
    }

    private func extensionDetail(_ entry: ExtensionEntry) -> some View {
        WisdModalShell(
            title: entry.name,
            subtitle: entry.installed ? "Instalado neste ambiente" : "Disponível no catálogo",
            statusColor: entry.installed ? WisdTheme.success : WisdTheme.iconAccent,
            width: 540,
            onClose: { selectedExtension = nil },
            headerTrailing: { ExtensionLogo(entry: entry) },
            footer: {
                HStack {
                    WisdSecondaryButton("Fechar") { selectedExtension = nil }
                    Spacer()
                    if entry.parameters["path"] != nil {
                        WisdPrimaryButton(entry.installed ? "Desativar habilidade" : "Ativar habilidade") {
                            changeSkill(entry); selectedExtension = nil
                        }
                    } else if entry.installed || entry.installAllowed {
                        WisdPrimaryButton(entry.installed ? "Remover plugin" : "Instalar plugin") {
                            selectedExtension = nil
                            DispatchQueue.main.async { pendingPlugin = entry }
                        }
                    }
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text(entry.description)
                    .font(.system(size: 13))
                    .foregroundStyle(WisdTheme.muted(scheme))

                Rectangle().fill(WisdTheme.divider(scheme)).frame(height: 1)

                ScrollView {
                    Text(entry.fullDescription ?? entry.description)
                        .font(.system(size: 13))
                        .foregroundStyle(WisdTheme.ink(scheme))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)

                if entry.parameters["path"] == nil && !entry.installed && !entry.installAllowed {
                    Text("A instalação deste item requer o fluxo de autorização do fornecedor, ainda pendente neste cliente.")
                        .foregroundStyle(WisdTheme.muted(scheme))
                        .font(.system(size: 11.5))
                }
            }
        }
    }

    private func changeSkill(_ entry: ExtensionEntry) {
        var params = entry.parameters
        params["enabled"] = !entry.installed
        workspace.request("skills/config/write", params) { response in
            if response["result"] != nil { loadExtensions(force: true) }
            else { extensionError = (response["error"] as? JSON)?["message"] as? String }
        }
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading("Configurações", subtitle: "Conta, voz e preferências do WisdCode.")
            card {
                VStack(alignment: .leading, spacing: 10) {
                    Text(workspace.account).font(.headline)
                    if let plan = workspace.plan { Text(plan.capitalized).foregroundStyle(.secondary) }
                    ForEach(workspace.accountChoices) { choice in
                        Button(choice.label, systemImage: choice.active ? "checkmark.circle" : "person.crop.circle") {
                            workspace.switchAccount(choice)
                        }
                        .disabled(choice.active || workspace.busy || workspace.accountBusy || workspace.scheduledBusy)
                    }
                    if workspace.accountBusy { Button("Cancelar login", action: workspace.cancelLogin) }
                    else { Button("Entrar com ChatGPT", action: workspace.login).disabled(!workspace.ready || workspace.busy) }
                    Button("Atualizar conta", action: workspace.refreshAccount).disabled(!workspace.ready)
                }
            }
            card {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Ler respostas em voz alta", isOn: $workspace.speakReplies)
                    Divider()
                    HStack {
                        Text("Voz do agente")
                        Spacer()
                        Picker("Voz do agente", selection: Binding(
                            get: { workspace.voice.voiceGender },
                            set: { workspace.voice.voiceGender = $0 }
                        )) {
                            ForEach(AgentVoiceGender.allCases) { gender in
                                Text(gender.displayName).tag(gender)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 190)
                    }
                    HStack {
                        Text(workspace.voice.activeVoiceSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            workspace.voice.previewVoice()
                        } label: {
                            Label("Testar voz", systemImage: "play.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            Button("Uso e faturamento", systemImage: DesktopPage.usage.icon) { page = .usage }
        }
    }

    private func refreshUsage() {
        guard workspace.ready else { return }
        workspace.refreshAccount()
        let identity = workspace.accountIdentity
        workspace.request("account/usage/read", [:]) { response in
            guard workspace.accountIdentity == identity else { return }
            let result = response["result"] as? JSON
            lifetimeTokens = (result?["summary"] as? JSON)?["lifetimeTokens"] as? Int
        }
    }

    private var usagePanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                heading("Uso e faturamento", subtitle: "Dados retornados pelo servidor para a conta ativa.")
                Spacer()
                Button("Atualizar", systemImage: "arrow.clockwise", action: refreshUsage).disabled(!workspace.ready)
            }
            Picker("Uso", selection: $usageTab) {
                Text("Visão geral").tag("Visão geral")
                Text("Análises").tag("Análises")
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 240)
            if usageTab == "Visão geral" {
                card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Seu plano").font(.headline)
                        Text(workspace.plan?.capitalized ?? "Plano indisponível")
                        Text(workspace.account).foregroundStyle(.secondary)
                        if let url = URL(string: "https://chatgpt.com/settings/usage") {
                            Link("Gerenciar plano e créditos no ChatGPT", destination: url)
                        }
                    }
                }
                card { UsageDetails(workspace: workspace) }
                card {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Redefinições do limite de uso").font(.headline)
                        Text(workspace.resetCredits.map { "\($0) disponíveis" } ?? "Saldo de redefinições indisponível")
                            .foregroundStyle(.secondary)
                        Button("Usar redefinição") { confirmReset = true }
                            .disabled((workspace.resetCredits ?? 0) <= 0 || resetInFlight || workspace.accountBusy)
                        if let resetNotice { Text(resetNotice).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            } else {
                card {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Tokens da conta").font(.headline)
                        Text(lifetimeTokens.map { $0.formatted() } ?? "Histórico indisponível").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func redeemReset() {
        guard !resetInFlight, !workspace.accountBusy, (workspace.resetCredits ?? 0) > 0 else { return }
        resetInFlight = true
        workspace.request("account/rateLimitResetCredit/consume", ["idempotencyKey": resetAttempt.uuidString]) { response in
            resetInFlight = false
            if let result = response["result"] as? JSON, let outcome = result["outcome"] as? String {
                switch outcome {
                case "reset", "alreadyRedeemed": resetNotice = "Redefinição concluída."
                case "nothingToReset": resetNotice = "Nenhum limite elegível para redefinição."
                case "noCredit": resetNotice = "Nenhum crédito de redefinição disponível."
                default: resetNotice = "Resultado não reconhecido pelo app."
                }
                resetAttempt = UUID()
                refreshUsage()
            } else {
                resetNotice = (response["error"] as? JSON)?["message"] as? String ?? "Falha ao redefinir."
            }
        }
    }
}

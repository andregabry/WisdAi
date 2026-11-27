import AppKit
import Combine
import SwiftUI

enum DesktopStyle {
    static func color(dark: Double, light: Double) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(white: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light, alpha: 1)
        })
    }

    static let canvas = color(dark: 0.055, light: 1)
    static let rail = color(dark: 0, light: 0.97)
    static let surface = color(dark: 0.13, light: 0.95)
    static let hover = color(dark: 0.17, light: 0.91)
    static let ink = color(dark: 0.93, light: 0.12)
    static let foreground = ink
    static let muted = color(dark: 0.66, light: 0.43)
    static let line = color(dark: 0.18, light: 0.89)
    static let accent = Color(red: 0.48, green: 0.29, blue: 0.82)
}

struct DesktopHover: ViewModifier {
    var selected = false
    var radius: CGFloat = 10
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(selected || hovering ? DesktopStyle.hover : Color.clear,
                        in: RoundedRectangle(cornerRadius: radius))
            .contentShape(RoundedRectangle(cornerRadius: radius))
            .onHover { hovering = $0 }
    }
}

struct DesktopSearchField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(DesktopStyle.muted)
            TextField(title, text: $text).textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .accessibilityLabel("Limpar pesquisa")
            }
        }
        .padding(.horizontal, 12).frame(height: 36)
        .background(DesktopStyle.canvas, in: Capsule())
        .overlay(Capsule().strokeBorder(DesktopStyle.line))
    }
}

private enum DesktopDeletion: Identifiable {
    case thread(Conversation)
    case project(ProjectItem)
    var id: String {
        switch self {
        case .thread(let thread): return "thread:" + thread.id
        case .project(let project): return "project:" + project.id.uuidString
        }
    }
}

struct DesktopView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var workspace: Workspace
    @ObservedObject var local: DesktopLocalData
    @State private var page: DesktopPage = .chat
    @State private var showSidebar = true
    @State private var showSearch = false
    @State private var search = ""
    @State private var showProfile = false
    @State private var showUsage = false
    @State private var showExplore = false
    @State private var showAttachments = false
    @State private var showModels = false
    @State private var showEffortPopover = false
    @State private var showProjectPopover = false
    @State private var showPermissionPopover = false
    @State private var showVoice = false
    @State private var showVoiceConfigPopover = false
    @State private var voicePopoverMessageID: UUID? = nil
    @State private var isScrolledToBottom = true
    @State private var suppressScrollUpDetectionUntil: Date = .distantPast
    @State private var editingMessageID: UUID? = nil
    @State private var editingMessageText = ""
    @State private var settingsTab = "Perfil"
    @State private var confirmFullAccess = false
    @State private var renameThread: Conversation?
    @State private var threadName = ""
    @State private var collapsedProjects: Set<String> = []
    @State private var showInspector = false
    @State private var inspectorTab: InspectorTab = .browser
    @AppStorage("wisdcode.sidebarWidth") private var sidebarWidth: Double = 288
    @AppStorage("wisdcode.inspectorWidth") private var inspectorWidth: Double = 460
    @StateObject private var inspectorBrowser = AgentBrowserState()
    @StateObject private var inspectorTerminal = AgentTerminalManager()
    @State private var showProjectModal = false
    @State private var editingProject: ProjectItem? = nil
    @State private var showAddAccountModal = false
    @State private var deletion: DesktopDeletion?
    @State private var showSettings = false
    @State private var settingsDestination: DesktopPage = .settings
    private let timer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    private var projectPaths: [String] {
        var seen = Set<String>()
        let current = workspace.project.map { [$0.path] } ?? []
        return (local.projectPaths + current + workspace.conversations.map(\.cwd)).filter { seen.insert($0).inserted }
    }

    private var hasPromptText: Bool {
        !workspace.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !workspace.attachments.isEmpty
    }

    private var canSend: Bool {
        (workspace.ready || workspace.selectedAccount != nil || local.activeAccount != nil) &&
            !workspace.accountBusy && !workspace.recording && hasPromptText
    }

    var body: some View {
        VStack(spacing: 0) {
            // Leave the native traffic lights and a draggable title area above the app.
            Color.clear.frame(height: 28)
            HStack(spacing: 0) {
                navigationRail
                GeometryReader { geo in
                    let totalWidth = max(620.0, Double(geo.size.width))
                    let showLeftSidebar = (page == .chat && showSidebar)
                    let handlesWidth = (showLeftSidebar ? 6.0 : 0.0) + (showInspector ? 6.0 : 0.0)
                    let minSidebar: Double = 200.0
                    let minInspector: Double = 280.0
                    let usableWidth = max(320.0, totalWidth - handlesWidth)
                    let minCenter: Double = min(480.0, max(320.0, usableWidth - (showLeftSidebar ? minSidebar : 0.0) - (showInspector ? minInspector : 0.0)))

                    let maxInspector = max(minInspector, min(880.0, usableWidth - minCenter - (showLeftSidebar ? minSidebar : 0.0)))
                    let activeInspectorWidth = showInspector ? min(maxInspector, max(minInspector, inspectorWidth)) : 0.0
                    let maxSidebar = max(minSidebar, min(460.0, usableWidth - minCenter - activeInspectorWidth))
                    let activeSidebarWidth = showLeftSidebar ? min(maxSidebar, max(minSidebar, sidebarWidth)) : 0.0

                    HStack(spacing: 0) {
                        if page == .chat {
                            if showSidebar {
                                projectSidebar(width: CGFloat(activeSidebarWidth))
                                    .transition(.move(edge: .leading).combined(with: .opacity))
                                    .zIndex(2)
                                WisdSplitHandle(
                                    width: $sidebarWidth,
                                    minWidth: minSidebar,
                                    maxWidth: maxSidebar,
                                    defaultWidth: 288
                                )
                                .zIndex(5)
                            }
                            conversation
                                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                                .zIndex(0)
                        } else if page == .settings {
                            DesktopSettings(workspace: workspace, local: local, selection: $settingsTab, page: $page)
                                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                                .zIndex(0)
                        } else if [.library, .images, .sites].contains(page) {
                            DesktopSpace(workspace: workspace, local: local, page: $page)
                                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                                .zIndex(0)
                        } else {
                            DesktopPanels(workspace: workspace, local: local, page: $page)
                                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                                .zIndex(0)
                        }

                        if showInspector {
                            WisdSplitHandle(
                                width: $inspectorWidth,
                                minWidth: minInspector,
                                maxWidth: maxInspector,
                                defaultWidth: 460,
                                invertDelta: true
                            )
                            .zIndex(5)
                            AgentInspectorPane(
                                workspace: workspace,
                                local: local,
                                browserState: inspectorBrowser,
                                terminalManager: inspectorTerminal,
                                isPresented: $showInspector,
                                activeTab: $inspectorTab,
                                width: CGFloat(activeInspectorWidth)
                            )
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                            .zIndex(2)
                        }
                    }
                    .animation(.easeInOut(duration: 0.18), value: showInspector)
                    .animation(.easeInOut(duration: 0.18), value: showSidebar)
                }
                .background(DesktopStyle.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(DesktopStyle.line.opacity(0.8)))
                .background {
                    Group {
                        Button("") {
                            withAnimation(.easeInOut(duration: 0.18)) { showSidebar.toggle() }
                        }
                        .keyboardShortcut("b", modifiers: .command)

                        Button("") {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                if !showInspector { inspectorTab = .browser }
                                showInspector.toggle()
                            }
                        }
                        .keyboardShortcut("b", modifiers: [.command, .option])
                    }
                    .opacity(0)
                    .allowsHitTesting(false)
                }
            }
            .padding(.bottom, 2).padding(.trailing, 2)
        }
        .background(DesktopStyle.rail)
        .foregroundStyle(DesktopStyle.ink)
        .font(.system(size: 14))
        .tint(DesktopStyle.accent)
        .buttonStyle(.plain)
        .ignoresSafeArea(.container, edges: .top)
        .onReceive(timer) { _ in workspace.recovery.tick(); local.runDue(using: workspace) }
        .onChange(of: workspace.ready) { local.runDue(using: workspace) }
        .onChange(of: workspace.accountIdentity) { local.runDue(using: workspace) }
        .onChange(of: workspace.project) { rememberProject() }
        .sheet(isPresented: $showSearch) { searchDialog.presentationBackground(.clear) }
        .sheet(item: $renameThread) { thread in renameDialog(thread).presentationBackground(.clear) }
        .sheet(isPresented: $showSettings) {
            DesktopSettings(workspace: workspace, local: local, selection: $settingsTab, page: $settingsDestination)
                .frame(width: 980, height: 720)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(WisdTheme.border(.dark), lineWidth: 1))
                .presentationBackground(.clear)
                .onChange(of: settingsDestination) {
                    if settingsDestination != .settings {
                        showSettings = false
                        if settingsDestination != .chat { page = settingsDestination }
                    }
                }
        }
        .sheet(item: $deletion) { target in
            deletionModal(for: target)
                .presentationBackground(.clear)
        }
        .sheet(isPresented: $showProjectModal) {
            ProjectModalView(existingProject: editingProject) { savedProject in
                local.addOrUpdateProject(savedProject)
                let projURL = savedProject.path.isEmpty ? nil : URL(fileURLWithPath: savedProject.path)
                workspace.project = projURL
                workspace.newConversation()
                showProjectModal = false
                editingProject = nil
            } onDelete: {
                if let editing = editingProject {
                    deletion = .project(editing)
                }
                showProjectModal = false
                editingProject = nil
            } onCancel: {
                showProjectModal = false
                editingProject = nil
            }
            .id(editingProject?.id.uuidString ?? "new-project")
            .presentationBackground(.clear)
        }
        .sheet(isPresented: $showAddAccountModal) {
            AddAccountModalView(workspace: workspace) { newAccount in
                local.addAccount(newAccount)
                showAddAccountModal = false
            } onCancel: {
                showAddAccountModal = false
            }
            .presentationBackground(.clear)
        }
        .sheet(item: $workspace.limitAlertAccount) { exhaustedAccount in
            AccountLimitAlertModalView(
                exhaustedAccount: exhaustedAccount,
                availableAccounts: local.aiAccounts
            ) { chosenAccount in
                workspace.continueWithAccount(chosenAccount, for: workspace.selected)
            } onAddNewAccount: {
                workspace.limitAlertAccount = nil
                showAddAccountModal = true
            } onCancel: {
                workspace.limitAlertAccount = nil
            }
            .presentationBackground(.clear)
        }
        .sheet(isPresented: $confirmFullAccess) {
            fullAccessConfirmModal
                .presentationBackground(.clear)
        }
    }

    private var navigationRail: some View {
        VStack(spacing: 14) {
            railButton("Início", icon: "house.fill", selected: page == .chat) { page = .chat }
            railButton("Espaço", icon: "rectangle.on.rectangle", selected: page == .library) { page = .library }
            railButton("Agendado", icon: "calendar.badge.checkmark", selected: page == .schedule) { page = .schedule }
            railButton("Plugins", icon: "puzzlepiece.extension", selected: page == .plugins) { page = .plugins }
            railButton("Explorar", icon: "ellipsis", selected: showExplore) { showExplore.toggle() }
                .popover(isPresented: $showExplore, arrowEdge: .trailing) {
                    WisdPopoverShell(
                        title: "Explorar",
                        subtitle: "Ferramentas e espaços do WisdAI",
                        statusColor: WisdTheme.iconAccent,
                        width: 260
                    ) {
                        WisdPopoverSection {
                            VStack(spacing: 2) {
                                WisdSelectableRow(icon: "folder", title: "Projetos") { showExplore = false; page = .chat; showSidebar = true }
                                WisdSelectableRow(icon: "photo", title: "Imagens") { showExplore = false; page = .images }
                                WisdSelectableRow(icon: "square.grid.2x2", title: "Sites") { showExplore = false; page = .sites }
                                WisdSelectableRow(icon: "map", title: "Mapas") { showExplore = false; page = .maps }
                                WisdSelectableRow(icon: "cube", title: "GPTs") { showExplore = false; page = .assistants }
                                WisdSelectableRow(icon: "circle.hexagongrid", title: "Figma") { showExplore = false; page = .figma }
                                WisdSelectableRow(icon: "terminal", title: "Codex") { showExplore = false; page = .chat }
                                WisdSelectableRow(
                                    icon: "arrow.triangle.branch",
                                    title: "Revisão de código",
                                    disabled: workspace.busy || workspace.project == nil || !workspace.ready
                                ) {
                                    showExplore = false; page = .chat; workspace.reviewChanges()
                                }
                                WisdSelectableRow(icon: "sparkles", title: "Habilidades") { showExplore = false; page = .skills }
                            }
                            .padding(.horizontal, 10)
                            .padding(.top, 8)
                        }
                    }
                    .presentationBackground(.clear)
                }
            Rectangle().fill(DesktopStyle.line).frame(width: 24, height: 1).padding(.vertical, 2)
            railButton("Sites", icon: "square.grid.2x2", selected: page == .sites) { page = .sites }
            Spacer()
            railButton("Uso", icon: "gauge.with.dots.needle.50percent") {
                showUsage.toggle(); if workspace.ready { workspace.refreshAccount() }
            }
            .popover(isPresented: $showUsage, arrowEdge: .trailing) {
                WisdPopoverShell(
                    title: "Uso da conta",
                    subtitle: workspace.plan.map { "Plano \($0.capitalized)" } ?? "Limites e consumo em tempo real",
                    statusColor: WisdTheme.success,
                    width: 320,
                    headerTrailing: {
                        WisdHeaderPillButton(icon: "arrow.clockwise", help: "Atualizar uso agora") {
                            if workspace.ready { workspace.refreshAccount() }
                            Task { await workspace.refreshAllQuotasNow(force: true) }
                        }
                    }
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        UsageDetails(workspace: workspace)
                        Rectangle().fill(WisdTheme.divider(colorScheme)).frame(height: 1)
                        WisdPrimaryButton("Gerenciar uso", icon: "chart.bar.xaxis") {
                            showUsage = false
                            page = .usage
                        }
                    }
                    .padding(16)
                }
                .presentationBackground(.clear)
            }
            Button { showProfile.toggle() } label: {
                Text(accountInitials).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white).frame(width: 27, height: 27)
                    .background(Color(red: 0.05, green: 0.66, blue: 0.58), in: Circle())
            }
            .accessibilityLabel("Abrir menu do perfil")
            .popover(isPresented: $showProfile, arrowEdge: .trailing) { profileMenu }
        }
        .padding(.top, 8).padding(.bottom, 14).frame(width: 52)
    }

    private func railButton(_ title: String, icon: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 18, weight: .regular))
                .foregroundStyle(selected ? DesktopStyle.ink : DesktopStyle.muted)
                .frame(width: 36, height: 36)
                .modifier(DesktopHover(selected: selected, radius: 18))
        }.accessibilityLabel(title).help(title)
    }

    private func menuRow(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).frame(height: 36).modifier(DesktopHover())
        }
    }

    private var accountInitials: String {
        let text = workspace.account.split(separator: "@").first.map(String.init) ?? ""
        return text.hasPrefix("Verificando") || text.isEmpty ? "W" : String(text.prefix(2)).uppercased()
    }

    private var profileMenu: some View {
        WisdPopoverShell(
            title: workspace.account,
            subtitle: workspace.plan?.capitalized ?? "Conta local",
            statusColor: WisdTheme.success,
            width: 280
        ) {
            VStack(alignment: .leading, spacing: 0) {
                WisdPopoverSection("Conta & Preferências") {
                    VStack(spacing: 2) {
                        WisdSelectableRow(icon: "person.crop.circle", title: "Perfil") { openSettings("Perfil") }
                        WisdSelectableRow(icon: "person.2", title: "Contas") { openSettings("Contas") }
                        WisdSelectableRow(icon: "key", title: "Chaves de API") { openSettings("Chaves de API") }
                        WisdSelectableRow(icon: "gearshape", title: "Configurações") { openSettings("Geral") }
                    }
                    .padding(.horizontal, 10)
                }

                Rectangle().fill(WisdTheme.divider(colorScheme)).frame(height: 1)

                WisdPopoverSection {
                    VStack(spacing: 2) {
                        WisdSelectableRow(icon: "questionmark.circle", title: "Ajuda") { openSettings("Ajuda") }
                        WisdSelectableRow(
                            icon: "rectangle.portrait.and.arrow.right",
                            iconColor: WisdTheme.danger,
                            title: "Sair",
                            disabled: workspace.busy || workspace.accountBusy || workspace.scheduledBusy || !workspace.ready
                        ) {
                            showProfile = false
                            workspace.logout()
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                }
            }
        }
        .presentationBackground(.clear)
    }

    private func openSettings(_ tab: String) {
        settingsTab = tab; showProfile = false; settingsDestination = .settings; showSettings = true
    }

    private func rememberProject() {
        guard let path = workspace.project?.path, !path.isEmpty else { return }
        let normPath = URL(fileURLWithPath: path).standardized.resolvingSymlinksInPath().path
        if !local.projectPaths.contains(normPath) { local.projectPaths.append(normPath) }
    }

    private func projectSidebar(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                BrandLogoView(height: 28)
                if !workspace.activeTasks.isEmpty {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("\(workspace.activeTasks.count)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(DesktopStyle.accent)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(DesktopStyle.accent.opacity(0.15), in: Capsule())
                }
                Spacer()
                Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("Pesquisar").keyboardShortcut("k")
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { showSidebar = false }
                } label: { Image(systemName: "sidebar.left") }
                    .accessibilityLabel("Alternar barra lateral")
            }.padding(.horizontal, 18).frame(height: 52)
            menuRow("Novo chat", icon: "square.and.pencil", action: workspace.newConversation)
                .disabled(workspace.busy).keyboardShortcut("n").padding(.horizontal, 8).padding(.bottom, 22)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if !local.projects.filter(\.pinned).isEmpty || !local.pinnedThreads.isEmpty {
                        sectionLabel("Fixados")
                        ForEach(local.projects.filter(\.pinned)) { projectItem in
                            projectRow(projectItem)
                        }
                        ForEach(workspace.conversations.filter { local.pinnedThreads.contains($0.id) }) { threadRow($0) }
                    }
                    HStack {
                        sectionLabel("Projetos")
                        Spacer()
                        Button {
                            editingProject = nil
                            showProjectModal = true
                        } label: { Image(systemName: "plus") }
                            .accessibilityLabel("Adicionar novo projeto")
                            .padding(.trailing, 14)
                    }
                    ForEach(local.projects.filter { !$0.pinned }) { projectItem in
                        projectRow(projectItem)
                    }
                    if local.projects.isEmpty {
                        menuRow("Adicionar projeto", icon: "folder.badge.plus") {
                            editingProject = nil
                            showProjectModal = true
                        }
                    }
                    HStack {
                        sectionLabel("Recentes")
                        Spacer()
                        Button {
                            local.recentCollapsed.toggle()
                        } label: {
                            Image(systemName: local.recentCollapsed ? "chevron.right" : "chevron.down")
                                .font(.system(size: 11))
                                .foregroundStyle(DesktopStyle.muted)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 14)
                    }
                    .padding(.top, 20)
                    if !local.recentCollapsed {
                        let nonProjectThreads = workspace.conversations.filter { thread in
                            !local.projects.contains { $0.matchesPath(thread.cwd) } &&
                            !local.pinnedThreads.contains(thread.id)
                        }
                        ForEach(nonProjectThreads) { thread in
                            threadRow(thread)
                        }
                        if nonProjectThreads.isEmpty {
                            Text(workspace.ready ? "Nenhum chat recente fora de projetos" : "Conectando ao motor…")
                                .foregroundStyle(DesktopStyle.muted).font(.system(size: 12)).padding(12)
                        }
                    }
                }.padding(.horizontal, 8).padding(.bottom, 20)
            }.scrollIndicators(.hidden)
        }
        .frame(width: width).clipped().background(DesktopStyle.canvas)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).foregroundStyle(DesktopStyle.muted).padding(.horizontal, 10).padding(.vertical, 13)
    }

    private func projectRow(_ project: ProjectItem) -> some View {
        let projectThreads = workspace.conversations.filter { project.matchesPath($0.cwd) }
        let isCollapsed = collapsedProjects.contains(project.path)
        let hasActiveThreadInside = projectThreads.contains { $0.id == workspace.selected }
        let isProjectActive = (workspace.project.map { project.matchesPath($0.path) } ?? false) || hasActiveThreadInside
        let showActiveOnProject = isProjectActive && (isCollapsed || projectThreads.isEmpty)

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Button {
                    workspace.project = project.path.isEmpty ? nil : URL(fileURLWithPath: project.path)
                    workspace.newConversation()
                } label: {
                    HStack(spacing: 8) {
                        Group {
                            if project.icon.hasPrefix("emoji:") {
                                Text(String(project.icon.dropFirst(6)))
                                    .font(.system(size: 16))
                            } else {
                                Image(systemName: project.icon)
                                    .font(.system(size: 15))
                                    .foregroundStyle(project.resolvedIconColor)
                            }
                        }
                        .frame(width: 20, height: 20)

                        Text(project.name)
                            .foregroundStyle(project.resolvedNameColor)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 8)
                    .frame(height: 34)
                }

                Button {
                    workspace.project = project.path.isEmpty ? nil : URL(fileURLWithPath: project.path)
                    workspace.newConversation()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DesktopStyle.muted)
                        .frame(width: 22, height: 26)
                }
                .buttonStyle(.plain)
                .help("Novo chat em \(project.name)")
                .accessibilityLabel("Novo chat em \(project.name)")

                Button {
                    if isCollapsed {
                        collapsedProjects.remove(project.path)
                    } else {
                        collapsedProjects.insert(project.path)
                    }
                } label: {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(DesktopStyle.muted)
                        .frame(width: 20, height: 30)
                }
                .accessibilityLabel("Expandir \(project.name)")
            }
            .modifier(DesktopHover(selected: showActiveOnProject))
            .contentShape(Rectangle())
            .contextMenu { projectActions(project) }

            if !isCollapsed {
                ForEach(projectThreads) { thread in
                    threadRow(thread).padding(.leading, 18)
                }
            }
        }
    }

    @ViewBuilder private func projectActions(_ project: ProjectItem) -> some View {
        Button {
            workspace.project = project.path.isEmpty ? nil : URL(fileURLWithPath: project.path)
            workspace.newConversation()
        } label: {
            Label("Novo chat neste projeto", systemImage: "plus.bubble")
        }

        Button {
            local.togglePinProject(project)
        } label: {
            Label(project.pinned ? "Desafixar" : "Fixar", systemImage: project.pinned ? "pin.slash" : "pin.fill")
        }

        Button {
            editingProject = project
            showProjectModal = true
        } label: {
            Label("Editar", systemImage: "gearshape")
        }

        Menu {
            Button("Padrão") { }
            Button("Nova seção…") { }
        } label: {
            Label("Seção", systemImage: "list.bullet.indent")
        }

        Button {
            NSWorkspace.shared.open(URL(fileURLWithPath: project.path))
        } label: {
            Label("Mostrar no Finder", systemImage: "folder")
        }

        Button {
            workspace.archiveThreads(workspace.conversations.filter { project.allPaths.contains($0.cwd) })
        } label: {
            Label("Arquivar chats", systemImage: "archivebox")
        }

        Divider()

        Button(role: .destructive) {
            deletion = .project(project)
        } label: {
            Label("Remover projeto", systemImage: "xmark")
        }
    }

    private func removeProject(_ project: ProjectItem) {
        local.deleteProject(project)
        if workspace.project?.path == project.path { workspace.project = nil }
    }

    private func threadRow(_ thread: Conversation) -> some View {
        let isSelected = workspace.selected == thread.id
        let isWorking = workspace.activeTasks[thread.id] != nil
        let isUnseen = workspace.unseenCompletedThreads.contains(thread.id)

        return Button {
            workspace.open(thread)
        } label: {
            HStack(spacing: 8) {
                // Indicador visual de status do chat (sem visual pesado de botão de sidebar)
                if isSelected {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                } else if isWorking {
                    Circle()
                        .fill(Color.purple)
                        .frame(width: 7, height: 7)
                } else if isUnseen {
                    Circle()
                        .fill(Color.yellow)
                        .frame(width: 7, height: 7)
                } else {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 7, height: 7)
                }

                Text(thread.title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? DesktopStyle.foreground : DesktopStyle.muted)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isWorking && !isSelected {
                    ProgressView().controlSize(.mini)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(DesktopHover(selected: isSelected, radius: 9))
        .help(thread.title)
        .contextMenu { threadActions(thread) }
    }

    @ViewBuilder private func threadActions(_ thread: Conversation) -> some View {

            Button(local.pinnedThreads.contains(thread.id) ? "Desafixar chat" : "Fixar chat") {
                if local.pinnedThreads.contains(thread.id) { local.pinnedThreads.removeAll { $0 == thread.id } }
                else { local.pinnedThreads.append(thread.id) }
            }
            Button("Renomear") { threadName = thread.title; renameThread = thread }
            Button("Arquivar") { workspace.archiveThreads([thread]) }
            Button("Copiar título") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(thread.title, forType: .string) }
            Divider()
            Button("Excluir chat", role: .destructive) {
                deletion = .thread(thread)
            }
            }

    private func projectColor(_ path: String) -> Color {
        let colors: [Color] = [.orange, .blue, .green, .pink, .purple, .teal]
        return colors[path.utf8.reduce(0) { ($0 + Int($1)) % colors.count }]
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            HStack {
                if !showSidebar {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { showSidebar = true }
                    } label: { Image(systemName: "sidebar.left") }
                        .accessibilityLabel("Mostrar barra lateral").padding(.leading, 18)
                }
                Spacer()
                HStack(spacing: 8) {
                    if let project = workspace.project {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                inspectorTab = .project
                                showInspector = true
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "folder")
                                    .font(.system(size: 12))
                                Text(project.lastPathComponent)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .foregroundStyle(DesktopStyle.muted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(DesktopStyle.surface, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Detalhes do projeto")
                    }
                    Button {
                        workspace.newConversation()
                        workspace.temporaryChat.toggle()
                    } label: {
                        Image(systemName: "eyeglasses").foregroundStyle(workspace.temporaryChat ? DesktopStyle.ink : DesktopStyle.muted)
                            .frame(width: 34, height: 34).modifier(DesktopHover(selected: workspace.temporaryChat))
                    }.accessibilityLabel("Chat temporário").disabled(workspace.busy)

                    // Ícone de janela lateral direita SEMPRE DISPONÍVEL (Navegador e Terminal do Agente)
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            if !showInspector {
                                inspectorTab = .browser
                            }
                            showInspector.toggle()
                        }
                    } label: {
                        Image(systemName: "sidebar.right")
                            .font(.system(size: 14))
                            .foregroundStyle(showInspector ? WisdTheme.iconAccent : DesktopStyle.muted)
                            .frame(width: 32, height: 32)
                            .background(showInspector ? WisdTheme.accent.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Abrir navegador e terminal do agente")
                    .help("Alternar painel lateral direito (⌘⌥B)")
                }
                .padding(.trailing, 18)
            }.frame(height: 54)
            recoveryBanner
            if workspace.messages.isEmpty {
                home
            } else {
                ZStack(alignment: .bottom) {
                    transcript
                    if workspace.voice.isVoiceModeActive {
                        FloatingVoiceOrbOverlayView(workspace: workspace, voice: workspace.voice, coverBackground: true)
                            .transition(.opacity)
                    }
                }
                approvals
                errorBanner
                composer.padding(.horizontal, 28).padding(.bottom, 18)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var recoveryBanner: some View {
        VStack(spacing: 6) {
            ForEach(workspace.recoveryNotices) { record in
                HStack(spacing: 12) {
                    Image(systemName: record.phase == "paused" ? "pause.circle" : "arrow.triangle.2.circlepath")
                        .foregroundStyle(Color.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.phase == "paused" ? "Recuperação de tarefa pausada" : "Preservando o progresso da tarefa").font(.system(size: 13, weight: .semibold))
                        Text(record.notice).font(.system(size: 12)).foregroundStyle(DesktopStyle.muted).lineLimit(3)
                    }
                    Spacer()
                    if record.phase == "paused" {
                        Button("Retomar") { workspace.recovery.retry(record.threadID) }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("Pausar") { workspace.recovery.cancel(record.threadID) }
                            .buttonStyle(.bordered)
                    }
                    Button {
                        workspace.recovery.discard(record.threadID)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DesktopStyle.muted)
                            .frame(width: 24, height: 24)
                            .background(DesktopStyle.hover, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Descartar aviso de recuperação")
                }
                .padding(12)
                .background(DesktopStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(DesktopStyle.line))
            }
        }.padding(.horizontal, 24)
    }

    private var home: some View {
        GeometryReader { geometry in
            ZStack {
                ScrollView {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: max(50, geometry.size.height * 0.28))
                        BrandLogoView(height: 56).padding(.bottom, 24)
                        let currentProjectName = local.projects.first(where: { $0.matchesPath(workspace.project?.path ?? "") })?.name ?? workspace.project?.lastPathComponent
                        Text(workspace.temporaryChat ? "Chat temporário" : currentProjectName != nil ? "O que vamos fazer em \(currentProjectName!)?" : "Por onde começamos?")
                            .font(.system(size: 26, weight: .regular)).multilineTextAlignment(.center)
                            .padding(.bottom, workspace.voice.isVoiceModeActive ? 196 : 36)
                        composer
                        VStack(spacing: 6) {
                            suggestion("Revisar as alterações do projeto", icon: "arrow.triangle.branch",
                                       prompt: "Revise as alterações atuais do projeto e aponte riscos e testes pendentes.")
                            suggestion("Continuar o desenvolvimento", icon: "terminal",
                                       prompt: "Leia o progresso documentado neste projeto e continue a próxima tarefa pendente.")
                            suggestion("Agendar uma tarefa", icon: "calendar.badge.clock", prompt: nil)
                        }.padding(.top, 26)
                        errorBanner.padding(.top, 12)
                        Spacer(minLength: 48)
                    }.frame(minWidth: 0, maxWidth: 768).padding(.horizontal, 28).frame(minWidth: 0, maxWidth: .infinity)
                }.scrollIndicators(.hidden).clipped()

                if workspace.voice.isVoiceModeActive {
                    VStack(spacing: 0) {
                        FloatingVoiceOrbOverlayView(workspace: workspace, voice: workspace.voice, coverBackground: true)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Spacer(minLength: 0).frame(height: max(120, geometry.size.height * 0.36))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(true)
                    .transition(.opacity)
                }
            }
        }
        .clipped()
    }

    private func suggestion(_ title: String, icon: String, prompt: String?) -> some View {
        Button {
            if let prompt { workspace.prompt = prompt } else { page = .schedule }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon).frame(width: 22)
                Text(title).lineLimit(1).fontWeight(.regular)
                Spacer()
                Image(systemName: "arrow.up.left").font(.system(size: 11)).opacity(0.4)
            }.foregroundStyle(DesktopStyle.muted).padding(.horizontal, 16).frame(height: 45).modifier(DesktopHover())
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !workspace.voice.isVoiceModeActive && (workspace.voice.dictationPhase == .starting || workspace.voice.dictationPhase == .recording || workspace.voice.dictationPhase == .processing) {
                InlineDictationBarView(voice: workspace.voice, onSendNow: { transcribed in
                    appendDictatedDraftAndSend(transcribed, sendImmediately: true)
                }, onAcceptOnly: { transcribed in
                    appendDictatedDraftAndSend(transcribed, sendImmediately: false)
                })
            } else if let recovery = workspace.voice.dictationRecovery {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.orange)
                    Text(recovery.reason)
                        .font(.system(size: 11.5))
                        .foregroundStyle(DesktopStyle.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if !recovery.recoveredText.isEmpty {
                        Button("Inserir texto") {
                            appendDictatedDraftAndSend(recovery.recoveredText, sendImmediately: false)
                            workspace.voice.dismissDictationRecovery()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    if recovery.canRetry {
                        Button("Tentar") {
                            workspace.voice.dismissDictationRecovery()
                            startInlineDictation()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    if recovery.reason.localizedCaseInsensitiveContains("Ajustes") || recovery.reason.localizedCaseInsensitiveContains("Permita") || recovery.reason.localizedCaseInsensitiveContains("Microfone") {
                        Button("Ajustes…") {
                            workspace.voice.openPrivacySettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    Button {
                        workspace.voice.dismissDictationRecovery()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DesktopStyle.muted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.orange.opacity(0.28), lineWidth: 1))
                .padding(.horizontal, 10)
            } else if let err = workspace.voice.voiceErrorMessage, !err.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.red)
                    Text(err)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button("Tentar") {
                        startInlineDictation()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    if err.localizedCaseInsensitiveContains("Ajustes") || err.localizedCaseInsensitiveContains("Permita") || err.localizedCaseInsensitiveContains("Microfone") || err.localizedCaseInsensitiveContains("Reconhecimento") {
                        Button("Ajustes…") {
                            workspace.voice.openPrivacySettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    Button {
                        workspace.voice.voiceErrorMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DesktopStyle.muted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.red.opacity(0.28), lineWidth: 1))
                .padding(.horizontal, 10)
            }

            // Barra com seletor de projeto do chat: exibida apenas na criação de um novo chat (quando não há mensagens ainda)
            if workspace.messages.isEmpty {
                HStack(spacing: 8) {
                    Button {
                        showProjectPopover.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: workspace.project == nil ? "bubble.left.and.bubble.right" : "folder.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(workspace.project == nil ? DesktopStyle.muted : WisdTheme.iconAccent)
                            Text(workspace.project != nil ? (local.projects.first(where: { $0.matchesPath(workspace.project?.path ?? "") })?.name ?? workspace.project!.lastPathComponent) : "Sem projeto")
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(DesktopStyle.muted)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(DesktopStyle.surface, in: Capsule())
                        .overlay(Capsule().stroke(showProjectPopover ? WisdTheme.accent.opacity(0.6) : DesktopStyle.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showProjectPopover, arrowEdge: .bottom) {
                        projectSelectorPopover
                    }
                    .accessibilityLabel("Escolher projeto para o chat")

                    if workspace.project != nil {
                        Text("·").foregroundStyle(DesktopStyle.muted)
                        permissionMenu
                    }

                    Spacer()
                }
                .font(.system(size: 12))
                .padding(.horizontal, 14)
                .padding(.top, 4)
            }
            if !workspace.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(workspace.attachments) { attachment in
                            Button { workspace.removeAttachment(attachment) } label: {
                                Label(attachment.name, systemImage: "doc.badge.ellipsis")
                                Image(systemName: "xmark").font(.system(size: 10))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(DesktopStyle.hover, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 4)
            }

            // LINHA DE CIMA: Campo onde você digita o chat (livre para digitar e intervir a qualquer momento)
            TextField("Trabalhe com o WisdAI", text: $workspace.prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .lineLimit(2...8)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 2)
                .onSubmit(send)

            // LINHA DE BAIXO: Ações e controles (Adicionar arquivos, modelo, voz, esforço, ditado, enviar)
            HStack(spacing: 8) {
                // Ícone para adicionar arquivos (+)
                Button { showAttachments.toggle() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(DesktopStyle.muted)
                        .frame(width: 32, height: 32)
                        .background(DesktopStyle.hover, in: Circle())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityLabel("Adicionar arquivos e mais")
                .disabled(workspace.busy || workspace.recording)
                .popover(isPresented: $showAttachments, arrowEdge: .top) { attachmentMenu }

                // Seletor de Modelo de IA
                Button { showModels.toggle() } label: {
                    HStack(spacing: 6) {
                        let runningTask = workspace.activeTasks[workspace.selected ?? ""]
                        let activeAcc: AIAccount? = {
                            if let runningTask, let accId = runningTask.accountId,
                               let found = local.aiAccounts.first(where: { $0.id == accId }) {
                                return found
                            }
                            return workspace.selectedAccount ?? local.activeAccount
                        }()
                        let effectiveProvider = activeAcc?.provider ?? (runningTask != nil ? .gemini : .openai)
                        let effectiveAccName = runningTask?.accountName ?? activeAcc?.name

                        Image(systemName: effectiveProvider.iconName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WisdTheme.iconAccent)

                        if let effectiveAccName, !effectiveAccName.isEmpty {
                            Text(effectiveAccName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .font(.system(size: 11, weight: .medium))
                            Text("·").foregroundStyle(DesktopStyle.muted)
                        }

                        let rawModel: String = {
                            if let runningTask, !runningTask.modelName.isEmpty && runningTask.modelName != "auto" {
                                return runningTask.modelName
                            }
                            if workspace.selectedModel != "auto" && !workspace.selectedModel.isEmpty {
                                return workspace.selectedModel
                            }
                            return activeAcc?.currentModel ?? "Auto"
                        }()

                        if let acc = activeAcc {
                            let avail = workspace.quotaStore.availability(accountID: acc.id, modelID: rawModel, account: acc)
                            if avail != .unknown {
                                Circle()
                                    .fill(quotaColor(for: avail))
                                    .frame(width: 6, height: 6)
                            }
                        }

                        Text(AIProvider.modelDisplayName(for: rawModel))
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if let acc = activeAcc,
                           let rem = workspace.quotaStore.remainingPercent(accountID: acc.id, modelID: rawModel) {
                            Text("\(rem)%")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(quotaColor(for: workspace.quotaStore.availability(accountID: acc.id, modelID: rawModel, account: acc)))
                                .fixedSize()
                        }

                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                            .foregroundStyle(DesktopStyle.muted)
                    }
                    .foregroundStyle(DesktopStyle.muted)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .frame(minWidth: 0, maxWidth: 270)
                    .background(DesktopStyle.hover.opacity(0.8), in: Capsule())
                    .overlay(Capsule().stroke(DesktopStyle.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .layoutPriority(-1)
                .accessibilityLabel("Selecionar conta e modelo de IA")
                .popover(isPresented: $showModels, arrowEdge: .top) { modelPopover }

                // Botão de Selecionar Esforço de Raciocínio (Popover Slider)
                Button {
                    showEffortPopover.toggle()
                } label: {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(workspace.selectedEffort != "default" ? WisdTheme.iconAccent : DesktopStyle.muted)
                            Text("Selecionar esforço")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(Color(white: 0.86))
                                .lineLimit(1)
                            if workspace.selectedEffort != "default" {
                                Text(workspace.reasoningLevel.title)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(WisdTheme.softAccentText)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(WisdTheme.accent.opacity(0.22), in: Capsule())
                            }
                        }
                        HStack(spacing: 5) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(workspace.selectedEffort != "default" ? WisdTheme.iconAccent : DesktopStyle.muted)
                            Text(workspace.selectedEffort != "default" ? workspace.reasoningLevel.title : "Esforço")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(white: 0.86))
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 32)
                    .background(Color(red: 0.17, green: 0.18, blue: 0.20), in: Capsule())
                    .overlay(
                        Capsule().stroke(
                            (showEffortPopover || workspace.selectedEffort != "default") ? WisdTheme.accent.opacity(0.45) : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                    )
                }
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityLabel("Selecionar esforço de raciocínio")
                .popover(isPresented: $showEffortPopover, arrowEdge: .top) {
                    ReasoningEffortSliderView(workspace: workspace, showModels: $showModels)
                        .presentationBackground(.clear)
                }

                Spacer(minLength: 4)

                // Lado direito: botões de voz, microfone e enviar agrupados lado a lado
                HStack(spacing: 6) {
                    // Ativar modo de conversação por voz estilo Codex
                    Button {
                        workspace.toggleVoiceConversation()
                    } label: {
                        HStack(spacing: 5) {
                            if workspace.voice.isVoiceModeActive {
                                CodexHorizonOrbView(
                                    phase: workspace.voice.voicePhase,
                                    activity: workspace.voice.voiceActivity,
                                    levels: workspace.voice.orbLevels,
                                    palette: workspace.voice.orbPalette,
                                    isMuted: workspace.voice.isMuted,
                                    size: 16
                                )
                                Text(workspace.voice.voicePhase == .starting ? "Iniciando" : "Voz ativa")
                                    .font(.system(size: 11, weight: .medium))
                            } else {
                                Image(systemName: "waveform")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                        }
                        .foregroundStyle(workspace.voice.isVoiceModeActive ? Color.white : WisdTheme.softAccentText)
                        .padding(.horizontal, workspace.voice.isVoiceModeActive ? 10 : 8)
                        .frame(height: 32)
                        .background(
                            workspace.voice.isVoiceModeActive ? WisdTheme.accent : WisdTheme.accent.opacity(0.14),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .accessibilityLabel(workspace.voice.isVoiceModeActive ? "Encerrar conversa por voz" : (workspace.messages.isEmpty ? "Iniciar novo chat por voz" : "Iniciar conversa por voz"))
                    .help(workspace.messages.isEmpty ? "Iniciar novo chat por voz · Clique direito para ajustar voz" : "Iniciar conversa por voz · Clique direito para ajustar voz")
                    .contextMenu {
                        ForEach(AgentVoiceGender.allCases) { gender in
                            Button {
                                workspace.voice.selectedVoiceID = "auto"
                                workspace.voice.voiceGender = gender
                            } label: {
                                Label(
                                    "Voz: \(gender.displayName)\(workspace.voice.voiceGender == gender ? " ✓" : "")",
                                    systemImage: gender.iconName
                                )
                            }
                        }
                        Divider()
                        Button {
                            workspace.voice.previewVoice()
                        } label: {
                            Label("Testar voz atual", systemImage: "play.circle")
                        }
                        Button {
                            showVoiceConfigPopover = true
                        } label: {
                            Label("Configurar voz, orbe e velocidade…", systemImage: "slider.horizontal.3")
                        }
                    }
                    .popover(isPresented: $showVoiceConfigPopover, arrowEdge: .top) {
                        VoiceSelectorPopoverView(voice: workspace.voice)
                            .presentationBackground(.clear)
                    }

                    // Botão de ditado por voz estilo Codex (onda contínua + inserção ao texto)
                    Button {
                        if workspace.voice.isVoiceModeActive && workspace.voice.isSpeaking {
                            workspace.voice.interruptAndListen()
                        } else if workspace.voice.isVoiceModeActive {
                            workspace.voice.toggleMute()
                        } else if workspace.voice.dictationPhase == .recording || workspace.voice.dictationPhase == .starting || workspace.voice.isListening {
                            workspace.voice.stopDictation(cancel: false)
                        } else {
                            startInlineDictation()
                        }
                    } label: {
                        let isDictatingActive = workspace.voice.dictationPhase == .recording || workspace.voice.dictationPhase == .starting || (workspace.voice.isListening && !workspace.voice.isVoiceModeActive)
                        Image(systemName: (workspace.voice.isMuted && workspace.voice.isVoiceModeActive) ? "mic.slash.fill" : (isDictatingActive || (workspace.voice.isVoiceModeActive && !workspace.voice.isMuted) ? "mic.fill" : "mic"))
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle((isDictatingActive || (workspace.voice.isMuted && workspace.voice.isVoiceModeActive)) ? Color.red : Color(white: 0.8))
                            .frame(width: 30, height: 32)
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .accessibilityLabel(workspace.voice.dictationPhase == .recording ? "Parar ditado" : "Ditar por voz")
                    .help(workspace.voice.dictationPhase == .recording ? "Finalizar ditado" : "Ditar mensagem por voz")

                    // Botão de Enviar Mensagem / Parar geração / Intervir
                    Button {
                        if workspace.busy && !hasPromptText {
                            workspace.interrupt()
                        } else if canSend {
                            send()
                        }
                    } label: {
                        let isStop = workspace.busy && !hasPromptText
                        Image(systemName: isStop ? "stop.fill" : "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 32, height: 32)
                            .foregroundStyle(Color.white)
                            .background(
                                isStop ? Color.red : (canSend ? Color(red: 0.43, green: 0.28, blue: 0.72) : Color(white: 0.28)),
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .disabled(!canSend && !workspace.busy)
                    .accessibilityLabel(workspace.busy && !hasPromptText ? "Parar geração" : "Enviar mensagem")
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .padding(.vertical, 2)
        .frame(minWidth: 0, maxWidth: 768)
        .background(DesktopStyle.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(DesktopStyle.line))
        .clipped()
    }

    private func send() {
        guard canSend else { return }
        workspace.send()
    }

    private func startInlineDictation() {
        let baseDraft = workspace.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        workspace.voice.startDictation(
            onLiveUpdate: { _ in },
            onFinalResult: { finalText in
                appendDictatedDraftAndSend(finalText, existingBase: baseDraft, sendImmediately: false)
            }
        )
    }

    private func appendDictatedDraftAndSend(_ text: String, existingBase: String? = nil, sendImmediately: Bool) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let current = existingBase ?? workspace.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty {
            workspace.prompt = clean
        } else if !current.contains(clean) {
            workspace.prompt = current + " " + clean
        }
        if sendImmediately {
            workspace.send()
        }
    }

    private var projectSelectorPopover: some View {
        WisdPopoverShell(
            title: "Projeto do Chat",
            subtitle: workspace.project?.lastPathComponent ?? "Conversa livre sem vínculo",
            statusColor: workspace.project == nil ? WisdTheme.iconAccent : WisdTheme.success,
            width: 310,
            headerTrailing: {
                WisdHeaderPillButton(icon: "plus", title: "Projeto") {
                    showProjectPopover = false
                    editingProject = nil
                    showProjectModal = true
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 0) {
                WisdPopoverSection {
                    VStack(spacing: 2) {
                        WisdSelectableRow(
                            icon: "bubble.left.and.bubble.right",
                            title: "Trabalhar sem projeto",
                            subtitle: "Chat avulso sem pasta fixa",
                            selected: workspace.project == nil
                        ) {
                            workspace.project = nil
                            rememberProject()
                            showProjectPopover = false
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                }

                if !local.projects.isEmpty {
                    Rectangle().fill(WisdTheme.divider(colorScheme)).frame(height: 1)

                    WisdPopoverSection("Projetos Criados") {
                        ScrollView {
                            VStack(spacing: 3) {
                                ForEach(local.projects) { proj in
                                    let isSelected = workspace.project.map { proj.matchesPath($0.path) } ?? false
                                    WisdSelectableRow(
                                        icon: proj.icon.hasPrefix("emoji:") ? "folder.fill" : proj.icon,
                                        iconColor: proj.resolvedIconColor,
                                        title: proj.name,
                                        subtitle: URL(fileURLWithPath: proj.path).lastPathComponent,
                                        selected: isSelected
                                    ) {
                                        workspace.project = URL(fileURLWithPath: proj.path)
                                        rememberProject()
                                        showProjectPopover = false
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                        }
                        .frame(maxHeight: 200)
                    }
                }
            }
        }
        .presentationBackground(.clear)
    }

    private var attachmentMenu: some View {
        WisdPopoverShell(
            title: "Adicionar ao Chat",
            subtitle: "Arquivos, projetos e nível de acesso",
            statusColor: WisdTheme.iconAccent,
            width: 295
        ) {
            VStack(alignment: .leading, spacing: 0) {
                WisdPopoverSection("Recursos") {
                    VStack(spacing: 2) {
                        WisdSelectableRow(icon: "paperclip", title: "Adicionar fotos e arquivos") {
                            showAttachments = false; workspace.attachFiles()
                        }
                        WisdSelectableRow(icon: "folder", title: "Escolher projeto") {
                            showAttachments = false; workspace.chooseProject(); rememberProject()
                        }
                        WisdSelectableRow(icon: "rectangle.on.rectangle", title: "Biblioteca") {
                            showAttachments = false; page = .library
                        }
                    }
                    .padding(.horizontal, 10)
                }

                Rectangle().fill(WisdTheme.divider(colorScheme)).frame(height: 1)

                WisdPopoverSection("Automação & Extensões") {
                    VStack(spacing: 2) {
                        WisdSelectableRow(icon: "puzzlepiece.extension", title: "Plugins") {
                            showAttachments = false; page = .plugins
                        }
                        WisdSelectableRow(icon: "calendar.badge.clock", title: "Agendar uma tarefa") {
                            showAttachments = false; page = .schedule
                        }
                    }
                    .padding(.horizontal, 10)
                }

                Rectangle().fill(WisdTheme.divider(colorScheme)).frame(height: 1)

                WisdPopoverSection("Permissão do Agente") {
                    VStack(spacing: 2) {
                        permissionRows(closeAttachments: true)
                    }
                    .padding(.horizontal, 10)
                }
            }
        }
        .disabled(workspace.busy || workspace.recording)
        .presentationBackground(.clear)
    }

    private var permissionMenu: some View {
        Button {
            showPermissionPopover.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "shield")
                Text(workspace.modeName())
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(workspace.mode == 2 ? Color.orange : DesktopStyle.muted)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(DesktopStyle.surface, in: Capsule())
            .overlay(Capsule().stroke(showPermissionPopover ? WisdTheme.accent.opacity(0.6) : DesktopStyle.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(workspace.busy)
        .popover(isPresented: $showPermissionPopover, arrowEdge: .bottom) {
            WisdPopoverShell(
                title: "Permissão do Agente",
                subtitle: "Controle de leitura e execução",
                statusColor: workspace.mode == 2 ? WisdTheme.warning : WisdTheme.success,
                width: 280
            ) {
                WisdPopoverSection {
                    VStack(spacing: 2) {
                        permissionRows(closeAttachments: false)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                }
            }
            .presentationBackground(.clear)
        }
    }

    @ViewBuilder
    private func permissionRows(closeAttachments: Bool) -> some View {
        WisdSelectableRow(
            icon: "eye",
            title: "Somente leitura",
            subtitle: "Analisa e lê arquivos sem modificar",
            selected: workspace.mode == 0
        ) {
            workspace.setMode(0)
            if closeAttachments { showAttachments = false } else { showPermissionPopover = false }
        }
        WisdSelectableRow(
            icon: "pencil.and.outline",
            title: "Escrita no projeto",
            subtitle: "Edita arquivos dentro da pasta selecionada",
            selected: workspace.mode == 1
        ) {
            workspace.setMode(1)
            if closeAttachments { showAttachments = false } else { showPermissionPopover = false }
        }
        WisdSelectableRow(
            icon: "shield.lefthalf.filled",
            iconColor: WisdTheme.warning,
            title: "Acesso completo",
            subtitle: "Executa comandos sem pedir aprovação",
            selected: workspace.mode == 2
        ) {
            if closeAttachments { showAttachments = false } else { showPermissionPopover = false }
            confirmFullAccess = true
        }
    }

    private func quotaColor(for availability: QuotaAvailability) -> Color {
        switch availability {
        case .available: return .green
        case .nearLimit: return .orange
        case .exhausted: return .red
        case .unknown: return DesktopStyle.muted
        }
    }

    @ViewBuilder
    private func quotaStatusBadge(availability: QuotaAvailability, remaining: Int?, resetAt: Date?, tokens: Int) -> some View {
        switch availability {
        case .exhausted:
            let resetLabel = resetAt.map { " · \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
            Text("Esgotado\(resetLabel)")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.red)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.14), in: Capsule())
        case .nearLimit:
            Text("\(remaining ?? 0)% livre")
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.14), in: Capsule())
        case .available:
            if let remaining {
                Text("\(remaining)% livre")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.12), in: Capsule())
            } else if tokens > 0 {
                Text(formatCompactTokens(tokens))
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(DesktopStyle.muted)
            }
        case .unknown:
            if tokens > 0 {
                Text(formatCompactTokens(tokens))
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(DesktopStyle.muted)
            }
        }
    }

    private func formatCompactTokens(_ tokens: Int) -> String {
        tokens >= 1000 ? String(format: "%.1fk tok", Double(tokens) / 1000.0) : "\(tokens) tok"
    }

    private var modelPopover: some View {
        let subtitle: String = {
            if let syncedAt = workspace.quotaStore.lastGlobalRefreshAt {
                return "Memória em tempo real · \(syncedAt.formatted(date: .omitted, time: .standard))"
            }
            return "Monitoramento em tempo real ativo"
        }()

        return WisdPopoverShell(
            title: "Contas e Modelos de IA",
            subtitle: subtitle,
            statusColor: WisdTheme.success,
            width: 396,
            headerTrailing: {
                HStack(spacing: 8) {
                    WisdHeaderPillButton(
                        icon: "arrow.clockwise",
                        help: "Sincronizar limites em memória agora"
                    ) {
                        Task { await workspace.refreshAllQuotasNow(force: true) }
                    }
                    WisdHeaderPillButton(icon: "plus", title: "Conta") {
                        showModels = false
                        showAddAccountModal = true
                    }
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 0) {
                WisdPopoverSection("Conta Conectada") {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(local.aiAccounts) { acc in
                                let snap = workspace.quotaStore.accountSnapshot(for: acc.id)
                                let canRun = workspace.isAccountExecutableNow(acc)
                                let accAvail = snap?.availability ?? ((acc.models.isEmpty || acc.hasAvailableModels) ? .unknown : .exhausted)
                                let isSelected = (workspace.selectedAccount?.id == acc.id) || (workspace.selectedAccount == nil && acc.isActive)
                                let statusBadge: (String?, Color) = {
                                    if !canRun {
                                        return (acc.provider == .openai ? "Sem sessão" : "CLI ausente", WisdTheme.warning)
                                    }
                                    switch accAvail {
                                    case .exhausted:
                                        let r = snap?.nextResetAt.map { " · \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
                                        return ("Esgotado\(r)", WisdTheme.danger)
                                    case .nearLimit:
                                        return ("\(snap?.remainingPercent ?? 0)% livre", WisdTheme.warning)
                                    case .available:
                                        if let rem = snap?.remainingPercent { return ("\(rem)% livre", WisdTheme.success) }
                                        return (nil, WisdTheme.success)
                                    case .unknown:
                                        return (nil, WisdTheme.muted(colorScheme))
                                    }
                                }()

                                WisdSelectableRow(
                                    icon: acc.provider.iconName,
                                    iconColor: !canRun ? WisdTheme.warning : (accAvail == .exhausted ? WisdTheme.danger : WisdTheme.iconAccent),
                                    title: acc.name,
                                    subtitle: "\(acc.provider.displayName) · \(acc.connectionLabel)",
                                    selected: isSelected,
                                    badge: statusBadge.0,
                                    badgeColor: statusBadge.1,
                                    disabled: !workspace.activeTasks.isEmpty || workspace.accountBusy || !canRun
                                ) {
                                    workspace.activateAccount(acc)
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                    }
                    .frame(maxHeight: 150)
                }

                Rectangle()
                    .fill(WisdTheme.divider(colorScheme))
                    .frame(height: 1)

                WisdPopoverSection("Modelos da Conta") {
                    ScrollView {
                        VStack(spacing: 3) {
                            let currentAcc = workspace.selectedAccount ?? local.activeAccount
                            let accountModels: [String] = {
                                if let acc = currentAcc {
                                    if !acc.models.isEmpty {
                                        let filtered = acc.models.filter { acc.provider.ownsModel($0) }
                                        return filtered.isEmpty ? acc.models : filtered
                                    }
                                    if acc.provider == .openai && !workspace.models.isEmpty {
                                        return workspace.models.map(\.id).filter { AIProvider.openai.ownsModel($0) }
                                    }
                                    return acc.provider.defaultModels
                                }
                                return workspace.models.map(\.id)
                            }()

                            ForEach(Array(accountModels.enumerated()), id: \.offset) { index, modelName in
                                let metric = currentAcc.flatMap { workspace.quotaStore.metrics(accountID: $0.id, modelID: modelName) }
                                let modelAvail: QuotaAvailability = {
                                    guard let acc = currentAcc else { return .unknown }
                                    return workspace.quotaStore.availability(accountID: acc.id, modelID: modelName, account: acc)
                                }()
                                let remPct = currentAcc.flatMap { workspace.quotaStore.remainingPercent(accountID: $0.id, modelID: modelName) }
                                let resetDate = currentAcc.flatMap { workspace.quotaStore.nextResetAt(accountID: $0.id, modelID: modelName) }
                                let isSelected = workspace.selectedModel == modelName || (workspace.selectedModel == "auto" && index == 0)

                                let displayTitle = AIProvider.modelDisplayName(for: modelName)
                                let displaySub = displayTitle != modelName ? modelName : nil

                                Button {
                                    workspace.selectedModel = modelName
                                    if var acc = currentAcc {
                                        let filteredCatalog = acc.models.filter { acc.provider.ownsModel($0) }
                                        if !filteredCatalog.isEmpty && filteredCatalog.count != acc.models.count {
                                            acc.models = filteredCatalog
                                        }
                                        acc.activeModelIndex = acc.models.firstIndex(of: modelName) ?? index
                                        local.addAccount(acc)
                                        workspace.selectedAccount = acc
                                    }
                                } label: {
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(displayTitle)
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(WisdTheme.ink(colorScheme))
                                                .lineLimit(1)
                                            if let displaySub {
                                                Text(displaySub)
                                                    .font(.system(size: 10.5))
                                                    .foregroundStyle(WisdTheme.muted(colorScheme))
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                        quotaStatusBadge(
                                            availability: modelAvail,
                                            remaining: remPct,
                                            resetAt: resetDate,
                                            tokens: metric?.totalTokensConsumed ?? 0
                                        )
                                        if isSelected {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 12.5, weight: .bold))
                                                .foregroundStyle(WisdTheme.iconAccent)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(isSelected ? WisdTheme.elevated(colorScheme) : Color.clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(isSelected ? WisdTheme.border(colorScheme) : Color.clear, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                    }
                    .frame(maxHeight: 200)
                }
            }
        }
        .disabled(workspace.busy)
        .presentationBackground(.clear)
    }

    private func modelRow(_ name: String, id: String) -> some View {
        WisdSelectableRow(title: name, selected: workspace.selectedModel == id) {
            workspace.selectedModel = id
        }
    }

    private func scrollToBottomSettling(_ proxy: ScrollViewProxy, animated: Bool) {
        isScrolledToBottom = true
        suppressScrollUpDetectionUntil = Date().addingTimeInterval(0.28)
        if animated {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo("end", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("end", anchor: .bottom)
        }
        DispatchQueue.main.async {
            proxy.scrollTo("end", anchor: .bottom)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            proxy.scrollTo("end", anchor: .bottom)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            proxy.scrollTo("end", anchor: .bottom)
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 0) {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            let blocks = groupedTranscriptBlocks()
                            ForEach(blocks) { block in
                                switch block {
                                case .user(let message):
                                    userMessageBubble(message)
                                        .padding(.top, 6)
                                case .systemNotice(let message):
                                    systemNoticeRow(message)
                                case .thought(let message):
                                    ThoughtBlockView(message: message)
                                case .plan(let message):
                                    PlanChecklistView(message: message)
                                case .actionGroup(_, let items):
                                    ActivityGroupView(items: items)
                                case .assistantText(let message, let showActions):
                                    assistantMessageBubble(message, showActions: showActions)
                                }
                            }
                            if workspace.isTaskActiveForSelectedChat {
                                LiveFocusRow(workspace: workspace)
                                    .id("liveFocus")
                            }
                            Color.clear.frame(height: 1).id("end")
                        }
                        .frame(minWidth: 0, maxWidth: 768)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 24)
                        .frame(minWidth: 0, maxWidth: .infinity)
                    }
                    .background(
                        MacChatScrollBottomObserver(
                            isNearBottom: $isScrolledToBottom,
                            suppressScrollUpUntil: suppressScrollUpDetectionUntil
                        )
                    )
                }
                .clipped()
                .onAppear {
                    scrollToBottomSettling(proxy, animated: false)
                }
                .onChange(of: workspace.selected) {
                    editingMessageID = nil
                    editingMessageText = ""
                    scrollToBottomSettling(proxy, animated: false)
                }
                .onChange(of: workspace.messages.count) {
                    if isScrolledToBottom || Date() < suppressScrollUpDetectionUntil || workspace.messages.last?.author == "Você" {
                        scrollToBottomSettling(proxy, animated: false)
                    }
                }
                .onChange(of: workspace.messages.last?.text) {
                    if isScrolledToBottom {
                        proxy.scrollTo("end", anchor: .bottom)
                    }
                }
                .onChange(of: workspace.messages.last?.status) {
                    if isScrolledToBottom {
                        proxy.scrollTo("end", anchor: .bottom)
                    }
                }
                .onChange(of: workspace.currentActivityNote) {
                    if isScrolledToBottom {
                        proxy.scrollTo("end", anchor: .bottom)
                    }
                }
                .onChange(of: workspace.currentActivitySteps.count) {
                    if isScrolledToBottom {
                        proxy.scrollTo("end", anchor: .bottom)
                    }
                }
                .onChange(of: workspace.currentActivityDetail) {
                    if isScrolledToBottom {
                        proxy.scrollTo("end", anchor: .bottom)
                    }
                }

                // Botão flutuante para voltar rapidamente à última interação quando o usuário rolar para cima
                if !isScrolledToBottom && !workspace.messages.isEmpty && !workspace.voice.isVoiceModeActive {
                    Button {
                        scrollToBottomSettling(proxy, animated: true)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 11.5, weight: .bold))
                            Text("Ir para a última interação")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .foregroundStyle(WisdTheme.ink(colorScheme))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                        .background(WisdTheme.surface(colorScheme).opacity(0.92), in: Capsule())
                        .overlay(Capsule().strokeBorder(WisdTheme.border(colorScheme), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.28), radius: 10, y: 4)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .accessibilityLabel("Rolar para o final do chat")
                    .help("Voltar para a última interação do chat")
                }
            }
        }
    }

    private func groupedTranscriptBlocks() -> [TranscriptBlock] {
        var result: [TranscriptBlock] = []
        var actionBuffer: [Message] = []
        let msgs = workspace.messages

        func flushActions() {
            guard !actionBuffer.isEmpty else { return }
            let groupId = actionBuffer[0].id.uuidString
            result.append(.actionGroup(id: groupId, items: actionBuffer))
            actionBuffer.removeAll()
        }

        for index in msgs.indices {
            let msg = msgs[index]
            if msg.author == "Você" {
                flushActions()
                result.append(.user(msg))
            } else if msg.author == "Sistema" {
                flushActions()
                result.append(.systemNotice(msg))
            } else if msg.kind.isAction {
                actionBuffer.append(msg)
            } else if msg.kind == .reasoning {
                flushActions()
                if !msg.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || msg.durationSeconds != nil {
                    result.append(.thought(msg))
                }
            } else if msg.kind == .plan {
                flushActions()
                result.append(.plan(msg))
            } else {
                flushActions()
                let trimmed = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty || !(msg.detail ?? "").isEmpty else { continue }
                let nextUserIdx = msgs[(index + 1)...].firstIndex(where: { $0.author == "Você" }) ?? msgs.endIndex
                let hasMoreTextBeforeNextUser = msgs[(index + 1)..<nextUserIdx].contains {
                    $0.author != "Você" && $0.author != "Sistema" && $0.kind == .text && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                let isCurrentlyStreamingLast = (nextUserIdx == msgs.count) && workspace.isTaskActiveForSelectedChat
                let showActions = !hasMoreTextBeforeNextUser && !isCurrentlyStreamingLast
                result.append(.assistantText(msg, showActions: showActions))
            }
        }
        flushActions()
        return result
    }

    private func userMessageBubble(_ message: Message) -> some View {
        UserMessageBubbleView(
            message: message,
            workspace: workspace,
            editingMessageID: $editingMessageID,
            editingMessageText: $editingMessageText
        )
    }

    private func systemNoticeRow(_ message: Message) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
            Text(message.text)
                .font(.system(size: 12.5))
                .foregroundStyle(DesktopStyle.muted)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.orange.opacity(0.2), lineWidth: 1))
    }

    private func assistantMessageBubble(_ message: Message, showActions: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !message.text.isEmpty {
                MarkdownContentView(text: message.text)
            }
            if let detail = message.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(DesktopStyle.muted)
                    .textSelection(.enabled)
            }
            if let code = message.exitCode, code != 0 {
                Text("Código de saída \(code)")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }
            if showActions && (message.author == "WisdAI" || message.author == "WisdCode") {
                responseActions(message)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func responseActions(_ message: Message) -> some View {
        HStack(spacing: 14) {
            Button {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.text, forType: .string)
            } label: { Image(systemName: "doc.on.doc") }.accessibilityLabel("Copiar resposta")
            Button {
                if workspace.voice.isSpeaking {
                    workspace.voice.stopSpeaking()
                } else {
                    workspace.speak(message.text)
                }
            } label: {
                Image(systemName: workspace.voice.isSpeaking ? "speaker.slash.fill" : "speaker.wave.2")
            }
            .accessibilityLabel(workspace.voice.isSpeaking ? "Parar leitura" : "Ouvir resposta")

            Button {
                voicePopoverMessageID = (voicePopoverMessageID == message.id) ? nil : message.id
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: workspace.voice.voiceGender.iconName)
                        .font(.system(size: 11))
                    Text(workspace.voice.voiceGender.displayName)
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8.5, weight: .semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(DesktopStyle.hover.opacity(0.65), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Escolher voz do agente")
            .popover(
                isPresented: Binding(
                    get: { voicePopoverMessageID == message.id },
                    set: { if !$0 && voicePopoverMessageID == message.id { voicePopoverMessageID = nil } }
                ),
                arrowEdge: .top
            ) {
                VoiceSelectorPopoverView(voice: workspace.voice)
                    .presentationBackground(.clear)
            }
        }.font(.system(size: 12)).foregroundStyle(DesktopStyle.muted).padding(.top, 2)
    }

    private var approvals: some View {
        ForEach(workspace.pendingApprovals) { approval in
            VStack(alignment: .leading, spacing: 10) {
                Label(approval.isFileChange ? "Aprovar alteração de arquivos?" : "Aprovar comando?", systemImage: "shield.lefthalf.filled")
                if let command = approval.command { Text(command).font(.system(.body, design: .monospaced)).textSelection(.enabled) }
                if let reason = approval.reason { Text(reason).foregroundStyle(DesktopStyle.muted) }
                HStack {
                    Button("Recusar") { workspace.respondApproval(approval, decision: "decline") }
                    Spacer()
                    Button("Aprovar uma vez") { workspace.respondApproval(approval, decision: "accept") }.buttonStyle(.borderedProminent)
                }
            }.padding(16).frame(maxWidth: 730).background(DesktopStyle.surface, in: RoundedRectangle(cornerRadius: 16)).padding(10)
        }
    }

    @ViewBuilder private var errorBanner: some View {
        if let error = workspace.error {
            HStack(alignment: .top) {
                Image(systemName: "exclamationmark.circle")
                Text(error).textSelection(.enabled)
                Button { workspace.error = nil } label: { Image(systemName: "xmark") }.accessibilityLabel("Fechar aviso")
            }.font(.system(size: 12)).foregroundStyle(.red).padding(12).frame(maxWidth: 768)
        }
    }

    private var searchDialog: some View {
        let filtered = workspace.conversations.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
        return WisdModalShell(
            title: "Pesquisar Conversas",
            subtitle: "\(filtered.count) de \(workspace.conversations.count) conversas salvas",
            statusColor: WisdTheme.iconAccent,
            width: 560,
            onClose: { showSearch = false }
        ) {
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundStyle(WisdTheme.iconAccent)
                    TextField("Buscar por título do chat…", text: $search)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13.5))
                    if !search.isEmpty {
                        Button { search = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(WisdTheme.muted(colorScheme))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .wisdFieldSurface()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(filtered) { thread in
                            WisdSelectableRow(
                                icon: "bubble.left.and.bubble.right",
                                title: thread.title,
                                subtitle: thread.cwd.isEmpty ? "Chat avulso" : URL(fileURLWithPath: thread.cwd).lastPathComponent,
                                selected: workspace.selected == thread.id,
                                disabled: workspace.busy
                            ) {
                                workspace.open(thread)
                                page = .chat
                                showSearch = false
                            }
                        }
                        if filtered.isEmpty {
                            Text("Nenhuma conversa encontrada.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(WisdTheme.muted(colorScheme))
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 28)
                        }
                    }
                }
                .frame(height: 290)
            }
        }
    }

    private func renameDialog(_ thread: Conversation) -> some View {
        let trimmed = threadName.trimmingCharacters(in: .whitespacesAndNewlines)
        return WisdModalShell(
            title: "Renomear Chat",
            subtitle: thread.cwd.isEmpty ? "Conversa salva no histórico" : URL(fileURLWithPath: thread.cwd).lastPathComponent,
            statusColor: WisdTheme.iconAccent,
            width: 420,
            onClose: { renameThread = nil },
            footer: {
                HStack(spacing: 10) {
                    Spacer()
                    WisdSecondaryButton("Cancelar") { renameThread = nil }
                        .keyboardShortcut(.cancelAction)
                    WisdPrimaryButton("Salvar", icon: "checkmark", disabled: trimmed.isEmpty) {
                        workspace.renameConversation(thread, to: trimmed)
                        renameThread = nil
                    }
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Título da conversa")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WisdTheme.muted(colorScheme))
                TextField("Digite o novo título…", text: $threadName)
                    .font(.system(size: 13.5))
                    .wisdFieldSurface(focused: true)
            }
        }
    }

    private func deletionModal(for target: DesktopDeletion) -> some View {
        let isThread: Bool
        let title: String
        let description: String
        let buttonTitle: String
        switch target {
        case .thread(let thread):
            isThread = true
            title = "Excluir conversa?"
            description = "A conversa \"\(thread.title)\" e todo o histórico salvo no banco interno serão removidos permanentemente."
            buttonTitle = "Excluir chat"
        case .project(let project):
            isThread = false
            title = "Remover projeto?"
            description = "Remover \"\(project.name)\" da barra lateral? Os arquivos e o histórico de chats serão preservados."
            buttonTitle = "Remover projeto"
        }

        return WisdModalShell(
            title: title,
            subtitle: isThread ? "Ação irreversível" : "Gerenciamento de projetos",
            statusColor: WisdTheme.danger,
            width: 430,
            onClose: { deletion = nil },
            footer: {
                HStack(spacing: 10) {
                    Spacer()
                    WisdSecondaryButton("Cancelar") { deletion = nil }
                    Button {
                        switch target {
                        case .thread(let thread): workspace.deleteThread(thread)
                        case .project(let project): removeProject(project)
                        }
                        deletion = nil
                    } label: {
                        Text(buttonTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(WisdTheme.danger))
                    }
                    .buttonStyle(.plain)
                }
            }
        ) {
            HStack(spacing: 12) {
                Image(systemName: isThread ? "trash.fill" : "folder.badge.minus")
                    .font(.system(size: 18))
                    .foregroundStyle(WisdTheme.danger)
                    .frame(width: 38, height: 38)
                    .background(WisdTheme.danger.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(WisdTheme.ink(colorScheme))
            }
        }
    }

    private var fullAccessConfirmModal: some View {
        WisdModalShell(
            title: "Ativar acesso completo?",
            subtitle: "Modo de execução sem bloqueios",
            statusColor: WisdTheme.warning,
            width: 440,
            onClose: { confirmFullAccess = false },
            footer: {
                HStack(spacing: 10) {
                    Spacer()
                    WisdSecondaryButton("Cancelar") { confirmFullAccess = false }
                    WisdPrimaryButton("Ativar acesso completo", icon: "shield.lefthalf.filled") {
                        workspace.setMode(2)
                        confirmFullAccess = false
                    }
                }
            }
        ) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(WisdTheme.warning)
                    .frame(width: 40, height: 40)
                    .background(WisdTheme.warning.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                Text("O agente poderá executar comandos e editar arquivos fora da pasta do projeto sem solicitar aprovação manual a cada etapa.")
                    .font(.system(size: 13))
                    .foregroundStyle(WisdTheme.ink(colorScheme))
            }
        }
    }

    // Barra inline reativa movida para InlineVoiceBarView (abaixo) para observar @Published de VoiceController.

    private var voiceDialog: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(workspace.voice.isListening ? Color.green : (workspace.voice.isSpeaking ? Color.blue : Color.orange))
                        .frame(width: 8, height: 8)
                    Text("Assistente de Voz no Chat")
                        .font(.system(size: 14, weight: .semibold))
                }
                Spacer()
                Button {
                    workspace.voice.stopVoiceConversation()
                    workspace.speakReplies = false
                    showVoice = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DesktopStyle.muted)
                        .padding(6)
                        .background(DesktopStyle.surface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fechar controle por voz")
            }

            Spacer(minLength: 8)

            // Dynamic Audio Reactive Sphere
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: workspace.voice.isListening ?
                                [Color.green.opacity(0.8), Color.blue, DesktopStyle.accent] :
                                (workspace.voice.isSpeaking ?
                                    [Color.cyan, Color.purple, Color.blue] :
                                    [Color.blue.opacity(0.7), Color.indigo, DesktopStyle.accent]),
                            center: .topLeading,
                            startRadius: 8,
                            endRadius: 160
                        )
                    )
                    .frame(width: 140, height: 140)
                    .scaleEffect(workspace.voice.isListening ? (1.0 + CGFloat(workspace.voice.audioLevel) * 0.45) : (workspace.voice.isSpeaking ? 1.08 : 1.0))
                    .shadow(
                        color: (workspace.voice.isListening ? Color.green : Color.blue).opacity(workspace.voice.isListening ? 0.6 : 0.35),
                        radius: CGFloat(20.0 + workspace.voice.audioLevel * 30.0)
                    )
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: workspace.voice.audioLevel)
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: workspace.voice.isSpeaking)

                Image(systemName: workspace.voice.isListening ? "waveform" : (workspace.voice.isSpeaking ? "speaker.wave.3.fill" : (workspace.busy ? "gearshape.arrow.triangle.2.circlepath" : "mic.fill")))
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
            }
            .frame(height: 160)

            // Status Title
            VStack(spacing: 6) {
                Text(
                    workspace.voice.isSpeaking ? "WisdAI respondendo…" :
                    (workspace.busy ? "Pensando na resposta…" :
                    (workspace.voice.isListening ? "Ouvindo você…" : "Pronto para conversar"))
                )
                .font(.system(size: 22, weight: .bold))

                Text(workspace.voice.voiceFeedbackStatus ?? "Converse naturalmente — suas falas e respostas aparecem direto no chat.")
                    .font(.system(size: 13))
                    .foregroundStyle(DesktopStyle.muted)
                    .multilineTextAlignment(.center)
            }

            // Real-time speech transcription bubble
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Conversa ao vivo:", systemImage: "quote.bubble")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DesktopStyle.muted)
                    Spacer()
                }

                Text(
                    !workspace.voice.liveTranscribedText.isEmpty ?
                        workspace.voice.liveTranscribedText :
                        (workspace.prompt.isEmpty ? "Fale normalmente em português como se estivesse digitando no chat..." : workspace.prompt)
                )
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(!workspace.voice.liveTranscribedText.isEmpty || !workspace.prompt.isEmpty ? Color.primary : DesktopStyle.muted.opacity(0.8))
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(DesktopStyle.surface, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 8)

            if let errorMsg = workspace.voice.voiceErrorMessage {
                Text(errorMsg)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }

            Spacer(minLength: 8)

            // Settings toggles
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Text("Voz")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DesktopStyle.muted)
                    Spacer()
                    ForEach(AgentVoiceGender.allCases) { gender in
                        let selected = workspace.voice.voiceGender == gender
                        Button {
                            workspace.voice.selectedVoiceID = "auto"
                            workspace.voice.voiceGender = gender
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: gender.iconName)
                                    .font(.system(size: 11))
                                Text(gender.displayName)
                                    .font(.system(size: 11.5, weight: .semibold))
                            }
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(selected ? WisdTheme.accent : DesktopStyle.surface)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        workspace.voice.previewVoice()
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10.5))
                            .padding(6)
                            .background(DesktopStyle.surface, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Testar voz selecionada")
                }

                Toggle("Conversa contínua no chat", isOn: $workspace.voice.continuousConversation)
                    .toggleStyle(.switch)
                    .font(.system(size: 12))
            }
            .frame(width: 320)
            .padding(.horizontal, 10)

            // Main Action Button
            HStack(spacing: 12) {
                if workspace.busy {
                    Button {
                        workspace.interrupt()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "stop.fill")
                            Text("Interromper Resposta")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else if workspace.voice.isSpeaking {
                    Button {
                        workspace.voice.interruptAndListen()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "speaker.slash.fill")
                            Text("Pausar Áudio e Falar Novamente")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                } else if workspace.voice.isListening {
                    Button {
                        let spokenText = workspace.voice.stopListening()
                        if !spokenText.isEmpty {
                            workspace.prompt = spokenText
                            send()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.circle.fill")
                            Text("Enviar para o Chat")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(workspace.voice.liveTranscribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Button {
                        workspace.voice.startListening()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "mic.fill")
                            Text("Começar a Falar")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(24)
        .frame(width: 480, height: 570)
        .background(DesktopStyle.canvas)
        .onAppear {
            workspace.voice.isVoiceModeActive = true
            workspace.voice.startListening()
        }
        .onDisappear {
            workspace.voice.isVoiceModeActive = false
            workspace.voice.stopListening()
        }
    }
}

// MARK: - Seletor de Esforço de Raciocínio (Custom 5-Step Popover Slider)

struct ReasoningEffortSliderView: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var workspace: Workspace
    @Binding var showModels: Bool

    @State private var dragPosition: CGFloat? = nil

    private let levels = ReasoningEffortLevel.allCases

    var body: some View {
        VStack(spacing: 12) {
            // Header: [bolt] ... [Title / Model >] ... [counterclockwise]
            HStack(alignment: .top) {
                Image(systemName: "bolt")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color(white: 0.6))
                    .frame(width: 24, height: 24, alignment: .topLeading)

                Spacer()

                VStack(spacing: 2) {
                    Text(workspace.reasoningLevel.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(
                            workspace.reasoningLevel == .ultra ?
                                Color(red: 0.78, green: 0.50, blue: 1.0) :
                                Color(red: 0.76, green: 0.60, blue: 0.98)
                        )

                    Button {
                        showModels = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(currentModelLabel)
                                .font(.system(size: 12.5, weight: .regular))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(Color(white: 0.65))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        workspace.reasoningLevel = .medio
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(white: 0.6))
                        .frame(width: 24, height: 24, alignment: .topTrailing)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Redefinir esforço para o padrão")
            }
            .padding(.horizontal, 2)

            // Slider Track Container
            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height
                let thumbDiameter: CGFloat = 26
                let trackPadding: CGFloat = thumbDiameter / 2
                let usableWidth = max(1, width - thumbDiameter)

                let currentLevel = workspace.reasoningLevel.rawValue
                let progressFraction: CGFloat = {
                    if let drag = dragPosition {
                        return min(1.0, max(0.0, drag / usableWidth))
                    }
                    return CGFloat(currentLevel) / 4.0
                }()
                let thumbOffset = progressFraction * usableWidth

                ZStack(alignment: .leading) {
                    // Track Background (Dark Capsule)
                    Capsule()
                        .fill(Color(red: 0.17, green: 0.175, blue: 0.19))
                        .frame(height: height)

                    // Track Fill (Left to Thumb)
                    if progressFraction > 0.01 {
                        if workspace.reasoningLevel == .ultra {
                            // ULTRA Cosmic Galaxy Starry Gradient!
                            ZStack {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.42, green: 0.52, blue: 0.98),
                                                Color(red: 0.58, green: 0.38, blue: 0.95),
                                                Color(red: 0.75, green: 0.48, blue: 0.98)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )

                                // Estrelinhas cintilantes espalhadas na trilha espacial
                                GeometryReader { starGeo in
                                    let sw = starGeo.size.width
                                    let sh = starGeo.size.height
                                    ZStack {
                                        Circle().fill(Color.white.opacity(0.9)).frame(width: 2, height: 2).position(x: sw * 0.10, y: sh * 0.65)
                                        Circle().fill(Color.white.opacity(0.75)).frame(width: 2.5, height: 2.5).position(x: sw * 0.18, y: sh * 0.72)
                                        Circle().fill(Color.white.opacity(0.85)).frame(width: 1.5, height: 1.5).position(x: sw * 0.30, y: sh * 0.60)
                                        Circle().fill(Color.white.opacity(0.7)).frame(width: 2, height: 2).position(x: sw * 0.42, y: sh * 0.75)
                                        Circle().fill(Color.white.opacity(0.95)).frame(width: 3, height: 3).position(x: sw * 0.52, y: sh * 0.35)
                                        Circle().fill(Color.white.opacity(0.8)).frame(width: 2, height: 2).position(x: sw * 0.58, y: sh * 0.50)
                                        Circle().fill(Color.white.opacity(0.9)).frame(width: 2.5, height: 2.5).position(x: sw * 0.70, y: sh * 0.42)
                                        Circle().fill(Color.white.opacity(0.7)).frame(width: 2, height: 2).position(x: sw * 0.82, y: sh * 0.68)
                                        Circle().fill(Color.white.opacity(0.85)).frame(width: 2, height: 2).position(x: sw * 0.92, y: sw * 0.50)
                                    }
                                }
                            }
                            .frame(width: thumbOffset + trackPadding, height: height)
                            .clipShape(Capsule())
                        } else {
                            // Lavender/Purple fill
                            Capsule()
                                .fill(Color(red: 0.65, green: 0.45, blue: 0.98))
                                .frame(width: thumbOffset + trackPadding, height: height)
                        }
                    }

                    // 5 Discrete Markers (Dots)
                    HStack {
                        ForEach(0..<5) { idx in
                            let dotFraction = CGFloat(idx) / 4.0
                            let isFilled = dotFraction <= progressFraction && workspace.reasoningLevel != .ultra
                            Circle()
                                .fill(isFilled ? Color.white.opacity(0.7) : Color.white.opacity(0.35))
                                .frame(width: 3.5, height: 3.5)
                            if idx < 4 { Spacer() }
                        }
                    }
                    .padding(.horizontal, trackPadding)

                    // White Thumb
                    Circle()
                        .fill(Color.white)
                        .frame(width: thumbDiameter, height: thumbDiameter)
                        .shadow(color: Color.black.opacity(0.4), radius: 3, x: 0, y: 1)
                        .offset(x: thumbOffset)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let clampedX = min(usableWidth, max(0, value.location.x - trackPadding))
                            dragPosition = clampedX
                            let nearestIndex = min(4, max(0, Int(round((clampedX / usableWidth) * 4.0))))
                            if let newLevel = ReasoningEffortLevel(rawValue: nearestIndex), workspace.reasoningLevel != newLevel {
                                workspace.reasoningLevel = newLevel
                            }
                        }
                        .onEnded { value in
                            let clampedX = min(usableWidth, max(0, value.location.x - trackPadding))
                            let nearestIndex = min(4, max(0, Int(round((clampedX / usableWidth) * 4.0))))
                            dragPosition = nil
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                if let newLevel = ReasoningEffortLevel(rawValue: nearestIndex) {
                                    workspace.reasoningLevel = newLevel
                                }
                            }
                        }
                )
            }
            .frame(height: 30)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 268)
        .background(
            ZStack {
                WisdTheme.surface(scheme).opacity(0.95)
                Rectangle().fill(.ultraThinMaterial).opacity(scheme == .dark ? 0.35 : 0.65)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(WisdTheme.border(scheme), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(scheme == .dark ? 0.42 : 0.16), radius: 20, x: 0, y: 10)
    }

    private var currentModelLabel: String {
        let runningTask = workspace.activeTasks[workspace.selected ?? ""]
        let rawModel: String = {
            if let runningTask, !runningTask.modelName.isEmpty && runningTask.modelName != "auto" {
                return runningTask.modelName
            }
            if workspace.selectedModel != "auto" && !workspace.selectedModel.isEmpty {
                return workspace.selectedModel
            }
            return workspace.selectedAccount?.currentModel ?? "GPT-6.2 Sol"
        }()
        return AIProvider.modelDisplayName(for: rawModel)
    }
}

// MARK: - Feed Cronológico Estilo Antigravity (Pensamentos, Etapas, Ações Agrupadas e Markdown)

private enum TranscriptBlock: Identifiable {
    case user(Message)
    case assistantText(Message, showActions: Bool)
    case systemNotice(Message)
    case thought(Message)
    case plan(Message)
    case actionGroup(id: String, items: [Message])

    var id: String {
        switch self {
        case .user(let m): return "u-\(m.id.uuidString)"
        case .assistantText(let m, _): return "t-\(m.id.uuidString)"
        case .systemNotice(let m): return "s-\(m.id.uuidString)"
        case .thought(let m): return "r-\(m.id.uuidString)"
        case .plan(let m): return "p-\(m.id.uuidString)"
        case .actionGroup(let id, _): return "g-\(id)"
        }
    }
}

/// Linha recolhível e discreta de pensamento ("Pensou por Xs"), idêntica ao estilo do Antigravity.
private struct ThoughtBlockView: View {
    let message: Message
    @State private var isExpanded = false

    private var headerTitle: String {
        if message.status == "em andamento" {
            return "Pensando…"
        }
        if message.text.localizedCaseInsensitiveContains("intervenção") {
            return "Intervenção recebida · avaliando contexto"
        }
        if let dur = message.durationSeconds {
            let secs = max(1, Int(round(dur)))
            return "Pensou por \(secs)s"
        }
        return "Pensamento"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DesktopStyle.muted.opacity(0.8))
                        .frame(width: 12)
                    Text(headerTitle)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(message.status == "em andamento" ? WisdTheme.softAccentText : DesktopStyle.muted)
                    if message.status == "em andamento" {
                        ThinkingWaveDots()
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                HStack(alignment: .top, spacing: 10) {
                    Rectangle()
                        .fill(DesktopStyle.line)
                        .frame(width: 1.5)
                        .padding(.vertical, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        if let detail = message.detail, !detail.isEmpty {
                            Text(detail)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(DesktopStyle.muted)
                                .textSelection(.enabled)
                        }
                        if !message.text.isEmpty {
                            MarkdownContentView(text: message.text, isMuted: true)
                        }
                    }
                }
                .padding(.leading, 6)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Bloco de checklist de etapas ("Etapas" com marcadores ○ / ◉ / ✓).
private struct PlanChecklistView: View {
    let message: Message
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.indigo)
                    Text(message.steps?.isEmpty == false ? "Etapas" : "Plano")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.primary)

                    if let steps = message.steps, !steps.isEmpty {
                        let done = steps.filter { $0.status == "done" }.count
                        Text("\(done)/\(steps.count)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(DesktopStyle.muted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.05), in: Capsule())
                    }

                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DesktopStyle.muted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().opacity(0.45)
                if let steps = message.steps, !steps.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(steps) { step in
                            HStack(alignment: .top, spacing: 8) {
                                stepStatusIcon(step.status)
                                    .frame(width: 15, height: 16)
                                Text(step.title)
                                    .font(.system(size: 13, weight: step.status == "in_progress" ? .medium : .regular))
                                    .foregroundStyle(step.status == "done" ? DesktopStyle.muted : Color.primary)
                                    .textSelection(.enabled)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                } else {
                    MarkdownContentView(text: message.text)
                        .padding(12)
                }
            }
        }
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DesktopStyle.line.opacity(0.7), lineWidth: 1))
    }

    @ViewBuilder
    private func stepStatusIcon(_ status: String) -> some View {
        switch status {
        case "done":
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
        case "in_progress":
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.78)
        case "failed":
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)
        case "skipped":
            Image(systemName: "minus.circle")
                .font(.system(size: 12))
                .foregroundStyle(DesktopStyle.muted)
        default:
            Image(systemName: "circle")
                .font(.system(size: 12))
                .foregroundStyle(DesktopStyle.muted.opacity(0.6))
        }
    }
}

/// Grupo unificado e compacto de ações consecutivas (leitura, edição, comando, busca web).
private struct ActivityGroupView: View {
    let items: [Message]
    @State private var isGroupExpanded = true

    private var hasActiveItem: Bool {
        items.contains { $0.status == "em andamento" || $0.status == "em execução" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if items.count >= 4 {
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) { isGroupExpanded.toggle() }
                } label: {
                    HStack(spacing: 7) {
                        if hasActiveItem {
                            ProgressView().controlSize(.mini).scaleEffect(0.75)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.green.opacity(0.85))
                        }
                        Text(hasActiveItem ? "Executando ações (\(items.count))…" : "\(items.count) ações realizadas")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DesktopStyle.muted)
                        Spacer()
                        Image(systemName: isGroupExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(DesktopStyle.muted.opacity(0.8))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isGroupExpanded {
                    Divider().opacity(0.4)
                }
            }

            if isGroupExpanded || items.count < 4 {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ActivityStepRowView(message: item)
                        if index < items.count - 1 {
                            Divider().opacity(0.28).padding(.leading, 32)
                        }
                    }
                }
            }
        }
        .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DesktopStyle.line.opacity(0.65), lineWidth: 1))
    }
}

/// Linha compacta de uma ação individual dentro de um ActivityGroupView, expansível sob demanda.
private struct ActivityStepRowView: View {
    let message: Message
    @State private var isExpanded = false

    private var iconSpec: (name: String, color: Color) {
        switch message.subKind {
        case "read": return ("doc.text", Color.blue)
        case "edit": return ("pencil", Color.orange)
        case "write": return ("doc.badge.plus", Color.green)
        case "list": return ("folder", Color.teal)
        case "search": return ("magnifyingglass", Color.cyan)
        case "command": return ("terminal", Color.mint)
        case "web": return ("globe", Color.blue)
        default:
            switch message.kind {
            case .command: return ("terminal", Color.mint)
            case .fileChange: return ("doc.text", Color.blue)
            case .web: return ("globe", Color.cyan)
            default: return ("wrench.and.screwdriver", Color(red: 0.75, green: 0.55, blue: 0.98))
            }
        }
    }

    private var displayTarget: String? {
        if let target = message.target, !target.isEmpty { return target }
        if let detail = message.detail, !detail.isEmpty {
            return detail.components(separatedBy: .newlines).first ?? detail
        }
        return nil
    }

    private var hasExpandableContent: Bool {
        if let out = message.output, !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if let detail = message.detail, let t = displayTarget, detail != t && !detail.isEmpty { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                guard hasExpandableContent else { return }
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: iconSpec.name)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(iconSpec.color)
                        .frame(width: 16)

                    Text(message.text)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.secondary)
                        .fixedSize()

                    if let target = displayTarget {
                        Text(target)
                            .font(.system(size: 11.5, design: message.kind == .web ? .default : .monospaced))
                            .foregroundStyle(Color.primary.opacity(0.92))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
                    }

                    Spacer(minLength: 8)

                    statusTrailing

                    if hasExpandableContent {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(DesktopStyle.muted.opacity(0.75))
                            .frame(width: 10)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded && hasExpandableContent {
                VStack(alignment: .leading, spacing: 6) {
                    if let detail = message.detail, !detail.isEmpty, detail != displayTarget {
                        Text(detail)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(DesktopStyle.muted)
                            .textSelection(.enabled)
                    }
                    if let output = message.output, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ScrollView {
                            Text(output)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.primary.opacity(0.85))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 190)
                        .padding(8)
                        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 7))
                    }
                }
                .padding(.leading, 34)
                .padding(.trailing, 10)
                .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    private var statusTrailing: some View {
        let isRunning = message.status == "em andamento" || message.status == "em execução"
        if isRunning {
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.75)
        } else if let code = message.exitCode, code != 0 {
            Text("exit \(code)")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.orange)
        } else if message.status == "falhou" || message.status == "recusado" {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.red)
        } else if let dur = message.durationSeconds {
            Text(dur < 1 ? String(format: "%.2fs", dur) : String(format: "%.1fs", dur))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(DesktopStyle.muted.opacity(0.75))
        } else {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.green.opacity(0.8))
        }
    }
}

/// Pontinhos animados contínuos durante raciocínio/execução.
private struct ThinkingWaveDots: View {
    var color: Color = WisdTheme.iconAccent

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3.5) {
                ForEach(0..<3, id: \.self) { index in
                    let phase = t * 5.2 - Double(index) * 0.75
                    let wave = (sin(phase) + 1.0) * 0.5
                    Circle()
                        .fill(color.opacity(0.45 + wave * 0.55))
                        .frame(width: 4.5, height: 4.5)
                        .offset(y: -wave * 3.0)
                }
            }
            .frame(height: 10)
        }
    }
}

/// Orbe orbital animado mostrando continuamente que o agente está pensando e trabalhando.
private struct AnimatedThinkingOrb: View {
    let isResponding: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.04)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let pulse = (sin(t * 3.2) + 1.0) * 0.5
            let angle = t.truncatingRemainder(dividingBy: 2.0) * 180.0
            let coreColor = isResponding ? WisdTheme.success : WisdTheme.iconAccent

            ZStack {
                Circle()
                    .fill(coreColor.opacity(0.10 + pulse * 0.14))
                    .frame(width: 30, height: 30)
                    .scaleEffect(0.92 + pulse * 0.14)

                Circle()
                    .trim(from: 0.0, to: 0.62)
                    .stroke(
                        AngularGradient(
                            colors: [coreColor.opacity(0.15), coreColor],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .frame(width: 24, height: 24)
                    .rotationEffect(.degrees(angle))

                Image(systemName: isResponding ? "text.bubble.fill" : "sparkles")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(coreColor)
                    .scaleEffect(0.94 + pulse * 0.12)
            }
            .frame(width: 32, height: 32)
        }
    }
}

/// Painel animado em tempo real na base do chat exibindo o raciocínio e cada etapa executada pelo agente.
private struct LiveFocusRow: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var workspace: Workspace
    @State private var elapsedSeconds: Int = 0
    let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    private var activeHeadline: String {
        if let note = workspace.currentActivityNote, !note.isEmpty {
            return note
        }
        return "Pensando…"
    }

    private var contextualSubline: String? {
        if let detail = workspace.currentActivityDetail, !detail.isEmpty {
            return detail
        }
        if workspace.currentActivityKind == .thinking {
            if elapsedSeconds >= 6 {
                return "Processando contexto e preparando a resposta passo a passo…"
            }
            if elapsedSeconds >= 2 {
                return "Avaliando contexto do projeto e raciocinando…"
            }
        }
        return nil
    }

    private func iconForKind(_ kind: TaskActivityStep.StepKind) -> (name: String, color: Color) {
        switch kind {
        case .thinking: return ("sparkles", WisdTheme.iconAccent)
        case .command: return ("terminal", .green)
        case .fileChange: return ("doc.badge.gearshape", .orange)
        case .search: return ("magnifyingglass", .cyan)
        case .tool: return ("wrench.and.screwdriver", WisdTheme.softAccentText)
        case .response: return ("text.bubble", WisdTheme.success)
        case .generic: return ("circle.dotted", WisdTheme.muted(scheme))
        }
    }

    var body: some View {
        let recentSteps = Array(workspace.currentActivitySteps.suffix(5))

        VStack(alignment: .leading, spacing: 10) {
            // Cabeçalho animado de raciocínio e status atual
            HStack(spacing: 10) {
                AnimatedThinkingOrb(isResponding: workspace.currentActivityKind == .response)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(activeHeadline)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WisdTheme.ink(scheme))
                            .lineLimit(2)

                        ThinkingWaveDots(
                            color: workspace.currentActivityKind == .response ? WisdTheme.success : WisdTheme.iconAccent
                        )
                    }

                    if let subline = contextualSubline {
                        Text(subline)
                            .font(.system(size: 11.5))
                            .foregroundStyle(WisdTheme.muted(scheme))
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                Text(String(format: "%02d:%02d", elapsedSeconds / 60, elapsedSeconds % 60))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(WisdTheme.softAccentText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(WisdTheme.accent.opacity(0.14), in: Capsule())
                    .overlay(Capsule().stroke(WisdTheme.accent.opacity(0.28), lineWidth: 1))
            }

            // Linha do tempo em tempo real do que o agente está executando na tela
            if !recentSteps.isEmpty {
                Rectangle()
                    .fill(WisdTheme.divider(scheme))
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(recentSteps) { step in
                        let icon = iconForKind(step.kind)
                        HStack(alignment: .top, spacing: 8) {
                            if step.isCompleted {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(WisdTheme.success.opacity(0.85))
                                    .frame(width: 14, height: 15)
                            } else {
                                Image(systemName: icon.name)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(icon.color)
                                    .frame(width: 14, height: 15)
                            }

                            VStack(alignment: .leading, spacing: 1) {
                                Text(step.title)
                                    .font(.system(size: 12, weight: step.isCompleted ? .regular : .medium))
                                    .foregroundStyle(step.isCompleted ? WisdTheme.muted(scheme) : WisdTheme.ink(scheme))
                                    .lineLimit(2)

                                if let detail = step.detail, !detail.isEmpty {
                                    Text(detail)
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(WisdTheme.muted(scheme).opacity(0.85))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }

                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(WisdTheme.elevated(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(WisdTheme.accent.opacity(0.28), lineWidth: 1)
        )
        .onReceive(timer) { _ in
            if let start = workspace.taskStartedAt {
                elapsedSeconds = max(0, Int(Date().timeIntervalSince(start)))
            }
        }
        .onAppear {
            if let start = workspace.taskStartedAt {
                elapsedSeconds = max(0, Int(Date().timeIntervalSince(start)))
            }
        }
    }
}

/// Renderizador leve de Markdown nativo para respostas do agente (títulos, listas, código, negrito, links).
private struct MarkdownContentView: View {
    let text: String
    var isMuted: Bool = false

    private enum Block {
        case heading(level: Int, text: String)
        case paragraph(String)
        case listItem(prefix: String, text: String)
        case quote(String)
        case code(language: String, code: String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parseBlocks(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let content):
                    inlineMarkdown(content, size: level == 1 ? 18 : (level == 2 ? 16 : 14.5), weight: .semibold)
                        .padding(.top, 4)
                case .paragraph(let content):
                    inlineMarkdown(content, size: isMuted ? 13 : 14.5, weight: .regular)
                        .lineSpacing(5)
                case .listItem(let prefix, let content):
                    HStack(alignment: .top, spacing: 7) {
                        Text(prefix)
                            .font(.system(size: isMuted ? 12.5 : 14, weight: .semibold))
                            .foregroundStyle(DesktopStyle.muted)
                            .frame(minWidth: 12, alignment: .trailing)
                        inlineMarkdown(content, size: isMuted ? 13 : 14.5, weight: .regular)
                            .lineSpacing(4)
                    }
                    .padding(.leading, 4)
                case .quote(let content):
                    HStack(alignment: .top, spacing: 10) {
                        Rectangle()
                            .fill(Color.blue.opacity(0.45))
                            .frame(width: 2.5)
                        inlineMarkdown(content, size: isMuted ? 12.5 : 14, weight: .regular)
                            .foregroundStyle(DesktopStyle.muted)
                            .lineSpacing(4)
                    }
                    .padding(.vertical, 2)
                case .code(let lang, let code):
                    MarkdownCodeBlock(language: lang, code: code)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func inlineMarkdown(_ raw: String, size: CGFloat, weight: Font.Weight) -> some View {
        let color: Color = isMuted ? DesktopStyle.muted : .primary
        if let attr = try? AttributedString(markdown: raw, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attr)
                .font(.system(size: size, weight: weight))
                .foregroundStyle(color)
                .textSelection(.enabled)
        } else {
            Text(raw)
                .font(.system(size: size, weight: weight))
                .foregroundStyle(color)
                .textSelection(.enabled)
        }
    }

    private func parseBlocks(_ source: String) -> [Block] {
        var blocks: [Block] = []
        let lines = source.components(separatedBy: .newlines)
        var i = 0
        var paragraphBuffer: [String] = []

        func flushParagraph() {
            let joined = paragraphBuffer.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !joined.isEmpty { blocks.append(.paragraph(joined)) }
            paragraphBuffer.removeAll()
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushParagraph()
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        break
                    }
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.code(language: lang, code: codeLines.joined(separator: "\n")))
                i += 1
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            if trimmed.hasPrefix("### ") {
                flushParagraph()
                blocks.append(.heading(level: 3, text: String(trimmed.dropFirst(4))))
            } else if trimmed.hasPrefix("## ") {
                flushParagraph()
                blocks.append(.heading(level: 2, text: String(trimmed.dropFirst(3))))
            } else if trimmed.hasPrefix("# ") {
                flushParagraph()
                blocks.append(.heading(level: 1, text: String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("> ") {
                flushParagraph()
                blocks.append(.quote(String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                blocks.append(.listItem(prefix: "•", text: String(trimmed.dropFirst(2))))
            } else if let dotRange = numberedListSplit(trimmed) {
                flushParagraph()
                blocks.append(.listItem(prefix: dotRange.prefix, text: dotRange.content))
            } else {
                paragraphBuffer.append(line)
            }
            i += 1
        }
        flushParagraph()
        return blocks
    }

    private func numberedListSplit(_ line: String) -> (prefix: String, content: String)? {
        guard let dotIdx = line.firstIndex(of: "."), dotIdx > line.startIndex else { return nil }
        let numPart = line[..<dotIdx]
        guard numPart.count <= 3, numPart.allSatisfy(\.isNumber) else { return nil }
        let afterDot = line.index(after: dotIdx)
        guard afterDot < line.endIndex, line[afterDot] == " " else { return nil }
        let contentStart = line.index(after: afterDot)
        return ("\(numPart).", String(line[contentStart...]))
    }
}

private struct MarkdownCodeBlock: View {
    let language: String
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "código" : language)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesktopStyle.muted)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Copiado" : "Copiar")
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(copied ? Color.green : DesktopStyle.muted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.04))

            Divider().opacity(0.35)

            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.95))
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(Color.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DesktopStyle.line.opacity(0.75), lineWidth: 1))
    }
}

private struct InlineDictationBarView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var voice: VoiceController
    let onSendNow: (String) -> Void
    let onAcceptOnly: (String) -> Void

    private var elapsedLabel: String {
        let totalSecs = max(0, voice.recordingDurationMs / 1000)
        return String(format: "%d:%02d", totalSecs / 60, totalSecs % 60)
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                if voice.dictationPhase == .processing {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Circle()
                        .fill(voice.dictationPhase == .recording ? Color.red : Color.orange)
                        .frame(width: 7, height: 7)
                }
                Text(voice.dictationPhase == .processing ? "Transcrevendo…" : (voice.dictationPhase == .starting ? "Preparando…" : elapsedLabel))
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(voice.dictationPhase == .recording ? Color.red : DesktopStyle.muted)
            }
            .fixedSize()

            VStack(alignment: .leading, spacing: 2) {
                CodexWaveformCanvasView(
                    mode: .scrolling,
                    samples: voice.dictationWaveformHistory,
                    levels: voice.orbLevels,
                    isActive: voice.dictationPhase == .recording || voice.dictationPhase == .processing,
                    isProcessing: voice.dictationPhase == .processing,
                    isMuted: false,
                    tint: voice.dictationPhase == .recording ? WisdTheme.iconAccent : DesktopStyle.muted
                )
                .frame(height: 18)

                if !voice.liveTranscribedText.isEmpty {
                    Text(voice.liveTranscribedText)
                        .font(.system(size: 11))
                        .foregroundStyle(DesktopStyle.muted)
                        .lineLimit(1)
                }
            }

            Button {
                voice.stopDictation(cancel: true)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesktopStyle.muted)
                    .frame(width: 24, height: 24)
                    .background(DesktopStyle.hover, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Cancelar ditado")

            Button {
                voice.stopDictation(cancel: false, onFinal: onAcceptOnly)
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(WisdTheme.ink(colorScheme))
                    .frame(width: 26, height: 26)
                    .background(WisdTheme.elevated(colorScheme), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(voice.dictationPhase == .processing)
            .help("Inserir transcrição na caixa de texto")

            Button {
                voice.stopDictation(cancel: false, onFinal: onSendNow)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 26, height: 26)
                    .background(WisdTheme.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(voice.dictationPhase == .processing)
            .help("Parar ditado e enviar mensagem")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(DesktopStyle.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(WisdTheme.accent.opacity(0.28), lineWidth: 1)
        )
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }
}

private struct FloatingVoiceOrbOverlayView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var workspace: Workspace
    @ObservedObject var voice: VoiceController
    var coverBackground: Bool = true
    @State private var hoverClose = false

    private var hasPermissionBlock: Bool {
        guard let err = voice.voiceErrorMessage else { return false }
        return err.localizedCaseInsensitiveContains("Ajustes")
            || err.localizedCaseInsensitiveContains("Permita")
            || err.localizedCaseInsensitiveContains("Microfone")
            || err.localizedCaseInsensitiveContains("Reconhecimento")
    }

    var body: some View {
        if voice.orchestrator.showVoiceHUDWindow || voice.orchestrator.presentationMode != .floatingOverlay {
            VoiceHUDModalView(workspace: workspace, orchestrator: voice.orchestrator)
        } else {
            ZStack(alignment: .bottom) {
                if coverBackground {
                    // Fundo overlay translúcido (60% de transparência) deixando o chat visível atrás
                    ZStack {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .opacity(0.28)
                        Color.black
                            .opacity(colorScheme == .dark ? 0.60 : 0.42)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                }

                VStack(spacing: 20) {
                    // Animação circular WisdAI pura sem contorno ao redor, centralizada acima do campo de entrada
                    Button {
                        if voice.isSpeaking || voice.orchestrator.state == .assistantSpeaking {
                            voice.interruptAndListen()
                        }
                    } label: {
                        WisdBrandVoiceOrbView(
                            size: 98,
                            palette: voice.orchestrator.orbPalette,
                            state: voice.orchestrator.isVoiceSessionActive ? voice.orchestrator.state : (voice.isSpeaking ? .assistantSpeaking : (voice.isProcessing ? .processing : .listening)),
                            levels: voice.orchestrator.isVoiceSessionActive ? voice.orchestrator.audioEngine.liveLevels : voice.orbLevels
                        )
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Assistente de voz WisdAI ativo")

                    // Botão X exatos 20px abaixo, centralizado, como modal circular translúcido sem contorno
                    Button {
                        voice.stopVoiceConversation()
                        workspace.speakReplies = false
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .opacity(0.60)
                            Circle()
                                .fill(hoverClose ? Color.red.opacity(0.62) : Color.black.opacity(0.42))
                                .shadow(color: Color.black.opacity(0.28), radius: 12, y: 4)

                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.95))
                        }
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hoverClose = $0 }
                    .accessibilityLabel("Encerrar assistente de voz")

                    HStack(spacing: 8) {
                        Button {
                            voice.toggleMute()
                        } label: {
                            Image(systemName: voice.isMuted ? "mic.slash.fill" : "mic.fill")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(voice.isMuted ? Color.red : Color.white.opacity(0.92))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.45), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        Button {
                            voice.orchestrator.openHUDWindow(expanded: true)
                        } label: {
                            Label(voice.orchestrator.state.displayTitle, systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.92))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.45), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    if let err = voice.voiceErrorMessage ?? voice.orchestrator.lastErrorSummary,
                       !err.isEmpty,
                       (voice.orchestrator.state == .error || voice.voiceErrorMessage != nil) {
                        VStack(spacing: 8) {
                            Text(err)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .lineLimit(4)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.red.opacity(0.82), in: RoundedRectangle(cornerRadius: 10))

                            HStack(spacing: 8) {
                                Button("Reiniciar Motor") {
                                    Task {
                                        await voice.orchestrator.restartVoiceEngine()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)

                                Button("Diagnóstico") {
                                    voice.orchestrator.openHUDWindow(expanded: true)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                if hasPermissionBlock {
                                    Button("Ajustes…") {
                                        voice.openPrivacySettings()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                        .frame(maxWidth: 420)
                    } else if hasPermissionBlock {
                        Button("Autorizar microfone nos Ajustes…") {
                            voice.openPrivacySettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.bottom, 22)
            }
            .frame(maxWidth: .infinity, maxHeight: coverBackground ? .infinity : nil, alignment: .bottom)
            .sheet(isPresented: Binding(
                get: { voice.orchestrator.showConsentDialog },
                set: { voice.orchestrator.showConsentDialog = $0 }
            )) {
                VoiceConsentAndOptInSheet(orchestrator: voice.orchestrator)
            }
        }
    }
}

private struct InlineVoiceBarView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var workspace: Workspace
    @ObservedObject var voice: VoiceController
    @State private var showVoiceConfig = false

    private var statusTitle: String {
        if voice.orchestrator.isVoiceSessionActive {
            if voice.orchestrator.isMuted && voice.orchestrator.isOutputMuted { return "Áudio e microfone mudo" }
            if voice.orchestrator.isMuted { return "Microfone silenciado" }
            if voice.orchestrator.isOutputMuted { return "Áudio mudo · lendo legenda" }
            return voice.orchestrator.state.displayTitle
        }
        switch voice.voicePhase {
        case .starting:
            return voice.orchestrator.state != .idle ? voice.orchestrator.state.displayTitle : "Inicializando motor local…"
        case .stopping:
            return "Encerrando…"
        case .inactive, .active:
            if voice.isMuted && voice.isOutputMuted { return "Áudio e microfone mudo" }
            if voice.isMuted { return "Microfone silenciado" }
            if voice.isOutputMuted { return "Áudio mudo · lendo legenda" }
            if voice.voiceActivity == .speaking || voice.isSpeaking { return "WisdAI respondendo…" }
            if voice.voiceActivity == .thinking || workspace.busy { return "Pensando no chat…" }
            if voice.isListening || voice.realtimeSessionActive { return "Ouvindo você…" }
            return voice.voiceFeedbackStatus ?? "Assistente pronto"
        }
    }

    private var statusAccent: Color {
        if voice.isMuted { return .gray }
        switch voice.voiceActivity {
        case .speaking: return WisdTheme.iconAccent
        case .thinking: return .orange
        case .listening: return .green
        case .idle: return voice.voicePhase == .starting ? .orange : WisdTheme.iconAccent
        }
    }

    private var endButtonTitle: String {
        switch voice.voicePhase {
        case .starting: return "Cancelar"
        case .stopping: return "Encerrando…"
        case .active, .inactive: return "Encerrar"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            // 1:1 Orbe Horizon animada pelo áudio ao vivo
            CodexHorizonOrbView(
                phase: voice.voicePhase,
                activity: voice.voiceActivity,
                levels: voice.orbLevels,
                palette: voice.orbPalette,
                isMuted: voice.isMuted,
                size: 30
            )
            .help(voice.activeVoiceSummary)

            // Estado ao vivo, legenda automática quando som mudo (QVc9) e feedback de erro
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(statusTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(statusAccent)

                    Text("· \(voice.orchestrator.voiceIdentity.persona.displayName)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(DesktopStyle.muted)
                        .lineLimit(1)

                    if let note = workspace.currentActivityNote, workspace.busy {
                        Text("· \(note)")
                            .font(.system(size: 11))
                            .foregroundStyle(DesktopStyle.muted)
                            .lineLimit(1)
                    }
                }

                if let err = voice.voiceErrorMessage, !err.isEmpty {
                    Text(err)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !voice.liveTranscribedText.isEmpty {
                    Text("Você: «\(voice.liveTranscribedText)»")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(DesktopStyle.ink)
                        .lineLimit(1)
                } else if voice.isOutputMuted && !voice.liveAssistantTranscript.isEmpty {
                    Text("WisdAI: \(voice.liveAssistantTranscript)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(DesktopStyle.ink)
                        .lineLimit(2)
                } else if !voice.liveAssistantTranscript.isEmpty && (voice.isSpeaking || voice.voiceActivity == .speaking) {
                    Text("WisdAI: \(voice.liveAssistantTranscript)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(DesktopStyle.muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            // Forma de onda compacta ao vivo no rodapé de voz (173367 / TDKe)
            CodexWaveformCanvasView(
                mode: .compact,
                samples: voice.isSpeaking ? voice.speakerHistory : voice.micHistory,
                levels: voice.orbLevels,
                isActive: voice.voicePhase == .active,
                isProcessing: voice.voiceActivity == .thinking,
                isMuted: voice.isMuted && !voice.isSpeaking,
                tint: statusAccent
            )
            .frame(width: 24, height: 18)

            if let err = voice.voiceErrorMessage, !err.isEmpty {
                Button("Tentar") {
                    if voice.realtimeSessionActive {
                        voice.interruptAndListen()
                    } else {
                        voice.startListening()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if err.localizedCaseInsensitiveContains("Ajustes") || err.localizedCaseInsensitiveContains("Permita") || err.localizedCaseInsensitiveContains("Microfone") || err.localizedCaseInsensitiveContains("Reconhecimento") {
                    Button("Ajustes…") {
                        voice.openPrivacySettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            // Interromper fala e voltar a falar / Enviar turno no modo chat
            if voice.isSpeaking {
                Button("Falar") {
                    voice.interruptAndListen()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Interromper resposta e falar agora")
            } else if voice.isListening && !voice.realtimeSessionActive && !voice.liveTranscribedText.isEmpty {
                Button("Enviar") {
                    voice.finalizeSpeech()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Botão Mudo / Ativar microfone (173367)
            Button {
                voice.toggleMute()
            } label: {
                Image(systemName: voice.isMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(voice.isMuted ? Color.red : DesktopStyle.ink)
                    .frame(width: 28, height: 26)
                    .background((voice.isMuted ? Color.red.opacity(0.16) : DesktopStyle.hover), in: Circle())
            }
            .buttonStyle(.plain)
            .help(voice.isMuted ? "Ativar microfone" : "Silenciar microfone")

            // Botão Silenciar saída de áudio do assistente (173367)
            Button {
                voice.toggleOutputMute()
            } label: {
                Image(systemName: voice.isOutputMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(voice.isOutputMuted ? Color.orange : DesktopStyle.ink)
                    .frame(width: 28, height: 26)
                    .background((voice.isOutputMuted ? Color.orange.opacity(0.16) : DesktopStyle.hover), in: Circle())
            }
            .buttonStyle(.plain)
            .help(voice.isOutputMuted ? "Ativar som das respostas" : "Silenciar som e exibir legenda")

            // Botão para selecionar voz Codex, gênero, orbe e ritmo
            Button {
                showVoiceConfig.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(WisdTheme.softAccentText)
                    .frame(width: 26, height: 26)
                    .background(WisdTheme.accent.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Voz Codex, gênero, orbe e ritmo")
            .popover(isPresented: $showVoiceConfig, arrowEdge: .top) {
                VoiceSelectorPopoverView(voice: voice)
                    .presentationBackground(.clear)
            }

            // Botão principal Encerrar / Cancelar estilo Codex (173367)
            Button {
                voice.stopVoiceConversation()
                workspace.speakReplies = false
            } label: {
                Text(endButtonTitle)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 11)
                    .frame(height: 26)
                    .background(Color.red.opacity(0.85), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(voice.voicePhase == .stopping)
            .help(endButtonTitle)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(WisdTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(statusAccent.opacity(0.30), lineWidth: 1))
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }
}

private struct MacChatScrollBottomObserver: NSViewRepresentable {
    @Binding var isNearBottom: Bool
    var suppressScrollUpUntil: Date

    func makeCoordinator() -> Coordinator {
        Coordinator(isNearBottom: $isNearBottom, suppressScrollUpUntil: suppressScrollUpUntil)
    }

    func makeNSView(context: Context) -> ObserverNSView {
        let view = ObserverNSView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: ObserverNSView, context: Context) {
        context.coordinator.isNearBottom = $isNearBottom
        context.coordinator.suppressScrollUpUntil = suppressScrollUpUntil
        nsView.coordinator = context.coordinator
        nsView.attachIfNeeded()
        context.coordinator.evaluateScrollPosition()
    }

    final class ObserverNSView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attachIfNeeded()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            attachIfNeeded()
        }

        func attachIfNeeded() {
            if let scrollView = enclosingScrollView {
                coordinator?.observe(scrollView: scrollView)
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, let scrollView = self.enclosingScrollView else { return }
                self.coordinator?.observe(scrollView: scrollView)
            }
        }
    }

    final class Coordinator: NSObject {
        var isNearBottom: Binding<Bool>
        var suppressScrollUpUntil: Date
        private weak var observedScrollView: NSScrollView?
        private var boundsObserver: NSObjectProtocol?
        private var clipFrameObserver: NSObjectProtocol?
        private var docFrameObserver: NSObjectProtocol?

        init(isNearBottom: Binding<Bool>, suppressScrollUpUntil: Date) {
            self.isNearBottom = isNearBottom
            self.suppressScrollUpUntil = suppressScrollUpUntil
        }

        deinit {
            clearObservers()
        }

        func observe(scrollView: NSScrollView) {
            if observedScrollView === scrollView {
                evaluateScrollPosition()
                return
            }
            clearObservers()
            observedScrollView = scrollView

            let clipView = scrollView.contentView
            clipView.postsBoundsChangedNotifications = true
            clipView.postsFrameChangedNotifications = true

            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                self?.evaluateScrollPosition()
            }

            clipFrameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                self?.evaluateScrollPosition()
            }

            if let docView = scrollView.documentView {
                docView.postsFrameChangedNotifications = true
                docFrameObserver = NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification,
                    object: docView,
                    queue: .main
                ) { [weak self] _ in
                    self?.evaluateScrollPosition()
                }
            }

            evaluateScrollPosition()
        }

        func evaluateScrollPosition() {
            guard let scrollView = observedScrollView,
                  let docView = scrollView.documentView else { return }
            let clipView = scrollView.contentView
            let visibleRect = clipView.documentVisibleRect
            let docBounds = docView.bounds
            let hasOverflow = docBounds.height > clipView.bounds.height + 24

            let distanceFromBottom: CGFloat = docView.isFlipped
                ? (docBounds.maxY - visibleRect.maxY)
                : (visibleRect.minY - docBounds.minY)
            let nearBottom = !hasOverflow || distanceFromBottom <= 56

            if !nearBottom && Date() < suppressScrollUpUntil {
                return
            }
            let current = isNearBottom.wrappedValue
            guard current != nearBottom else { return }
            let binding = isNearBottom
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.16)) {
                    binding.wrappedValue = nearBottom
                }
            }
        }

        private func clearObservers() {
            if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
            if let clipFrameObserver { NotificationCenter.default.removeObserver(clipFrameObserver) }
            if let docFrameObserver { NotificationCenter.default.removeObserver(docFrameObserver) }
            boundsObserver = nil
            clipFrameObserver = nil
            docFrameObserver = nil
        }
    }
}

private struct UserMessageBubbleView: View {
    @Environment(\.colorScheme) private var colorScheme
    let message: Message
    @ObservedObject var workspace: Workspace
    @Binding var editingMessageID: UUID?
    @Binding var editingMessageText: String
    @State private var hovered = false
    @FocusState private var editorFocused: Bool

    private var isEditing: Bool {
        editingMessageID == message.id
    }

    private var canSubmitEdit: Bool {
        !workspace.busy && !workspace.accountBusy && !editingMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            if isEditing {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Edite sua mensagem…", text: $editingMessageText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14.5))
                        .lineSpacing(4)
                        .lineLimit(1...12)
                        .focused($editorFocused)
                        .onAppear {
                            DispatchQueue.main.async {
                                editorFocused = true
                            }
                        }
                        .onExitCommand {
                            editingMessageID = nil
                            editingMessageText = ""
                        }

                    HStack(spacing: 8) {
                        Text("Considera o contexto até esta mensagem.")
                            .font(.system(size: 11))
                            .foregroundStyle(WisdTheme.muted(colorScheme))
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        WisdSecondaryButton("Cancelar") {
                            editingMessageID = nil
                            editingMessageText = ""
                        }

                        WisdPrimaryButton("Salvar e enviar", icon: "arrow.up", disabled: !canSubmitEdit) {
                            submitEdit()
                        }
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .frame(maxWidth: 560, alignment: .leading)
                .background(WisdTheme.surface(colorScheme), in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(WisdTheme.accent.opacity(0.65), lineWidth: 1.3)
                )
            } else {
                Text(message.text)
                    .font(.system(size: 14.5))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .background(DesktopStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(DesktopStyle.line.opacity(0.6), lineWidth: 1))
                    .contextMenu {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.text, forType: .string)
                        } label: {
                            Label("Copiar mensagem", systemImage: "doc.on.doc")
                        }
                        Button {
                            editingMessageText = message.text
                            editingMessageID = message.id
                        } label: {
                            Label("Editar mensagem…", systemImage: "pencil")
                        }
                        .disabled(workspace.busy || workspace.accountBusy)
                    }

                HStack(spacing: 12) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.text, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Copiar mensagem")
                    .help("Copiar")

                    Button {
                        editingMessageText = message.text
                        editingMessageID = message.id
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                                .font(.system(size: 11))
                            if hovered {
                                Text("Editar")
                                    .font(.system(size: 11, weight: .medium))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(workspace.busy || workspace.accountBusy)
                    .accessibilityLabel("Editar mensagem enviada")
                    .help("Editar mensagem e continuar a partir daqui")
                }
                .foregroundStyle(DesktopStyle.muted)
                .opacity(hovered ? 0.95 : 0.45)
                .padding(.trailing, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .onHover { hovered = $0 }
    }

    private func submitEdit() {
        let updated = editingMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.isEmpty, !workspace.busy, !workspace.accountBusy else { return }
        editingMessageID = nil
        editingMessageText = ""
        workspace.editMessageAndResend(messageID: message.id, newText: updated)
    }
}

import AppKit
import Foundation
import SwiftUI

// MARK: - Modal de Edição e Criação de Projetos (Fiel às Imagens 1 e 2)

struct ProjectModalView: View {
    @Environment(\.colorScheme) private var scheme
    let existingProject: ProjectItem?
    let onSave: (ProjectItem) -> Void
    let onDelete: (() -> Void)?
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var folders: [String] = []
    @State private var selectedIcon: String = "terminal"
    @State private var selectedIconColor: String = "red"
    @State private var showIconPicker: Bool = false
    @State private var iconSearchText: String = ""
    @State private var errorMessage: String?
    @State private var iconTab: String = "icons" // "emoji" ou "icons"

    private enum FocusField: Hashable {
        case name
        case iconSearch
    }

    @FocusState private var focusedField: FocusField?

    // 32 ícones exatos da Imagem 1 (4 linhas de 8 colunas)
    private let gridIcons: [String] = [
        // Linha 1
        "folder", "dollarsign.circle", "iphone", "graduationcap",
        "pencil", "paintbrush.pointed", "curlybraces", "terminal",
        // Linha 2
        "music.note", "popcorn", "atom", "paintpalette",
        "stethoscope", "seal", "leaf", "briefcase",
        // Linha 3
        "chart.bar", "scalemass", "dumbbell", "text.book.closed",
        "scale.3d", "globe.americas", "airplane", "network",
        // Linha 4
        "wrench.and.screwdriver", "pawprint", "flask", "brain.head.profile",
        "heart", "gift", "cube", "sparkles"
    ]

    private var filteredIcons: [String] {
        if iconSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return gridIcons
        }
        return gridIcons.filter { $0.localizedCaseInsensitiveContains(iconSearchText) }
    }

    init(
        existingProject: ProjectItem? = nil,
        onSave: @escaping (ProjectItem) -> Void,
        onDelete: (() -> Void)? = nil,
        onCancel: @escaping () -> Void
    ) {
        self.existingProject = existingProject
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel

        let initialName = existingProject?.name ?? ""
        let initialPaths = existingProject?.allPaths ?? []
        _name = State(initialValue: initialName)
        _folders = State(initialValue: initialPaths)
        _selectedIcon = State(initialValue: existingProject?.icon ?? "terminal")
        _selectedIconColor = State(initialValue: existingProject?.iconColor ?? "red")
    }

    var body: some View {
        let canSave = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return WisdModalShell(
            title: existingProject == nil ? "Criar projeto" : "Editar projeto",
            subtitle: folders.isEmpty ? "Configure nome, ícone e pastas de origem" : "\(folders.count) pasta(s) vinculada(s)",
            statusColor: WisdTheme.iconAccent,
            width: 540,
            onClose: onCancel,
            footer: {
                HStack(spacing: 10) {
                    if existingProject != nil, let onDelete {
                        Button(action: onDelete) {
                            Text("Remover projeto local")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(red: 0.96, green: 0.45, blue: 0.45))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(WisdTheme.danger.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(WisdTheme.danger.opacity(0.28), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    WisdSecondaryButton("Cancelar", action: onCancel)
                        .keyboardShortcut(.cancelAction)

                    WisdPrimaryButton("Salvar", icon: "checkmark", disabled: !canSave) {
                        let projectID = existingProject?.id ?? UUID()
                        var mainPath = folders.first ?? ""
                        if mainPath.isEmpty {
                            let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/WisdAI/Projects/\(projectID.uuidString)")
                            do { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]); mainPath = root.path }
                            catch { errorMessage = "Não foi possível criar a pasta do projeto."; return }
                        }
                        let extras = folders.count > 1 ? Array(folders.dropFirst()) : []
                        let finalName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? (mainPath.isEmpty ? "Novo Projeto" : URL(fileURLWithPath: mainPath).lastPathComponent)
                            : name.trimmingCharacters(in: .whitespacesAndNewlines)

                        let item = ProjectItem(
                            id: projectID,
                            name: finalName,
                            path: mainPath,
                            additionalPaths: extras,
                            icon: selectedIcon,
                            iconColor: selectedIconColor,
                            nameColor: existingProject?.nameColor ?? "primary",
                            pinned: existingProject?.pinned ?? false
                        )
                        onSave(item)
                    }
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Button {
                        showIconPicker.toggle()
                    } label: {
                        Group {
                            if selectedIcon.hasPrefix("emoji:") {
                                Text(String(selectedIcon.dropFirst(6)))
                                    .font(.system(size: 20))
                            } else {
                                Image(systemName: selectedIcon)
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(DesktopColorHelper.color(named: selectedIconColor))
                            }
                        }
                        .frame(width: 32, height: 32)
                        .background(WisdTheme.elevated(scheme), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(WisdTheme.border(scheme), lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showIconPicker, arrowEdge: .bottom) {
                        iconPickerPopover
                            .presentationBackground(.clear)
                    }

                    TextField("Nome do projeto", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(WisdTheme.ink(scheme))
                        .focused($focusedField, equals: .name)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(WisdTheme.elevated(scheme)))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(focusedField == .name ? WisdTheme.accent.opacity(0.65) : WisdTheme.border(scheme), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Pastas de origem")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WisdTheme.muted(scheme))

                    VStack(spacing: 0) {
                        ForEach(Array(folders.enumerated()), id: \.offset) { index, folderPath in
                            HStack(spacing: 12) {
                                Image(systemName: "folder")
                                    .font(.system(size: 14))
                                    .foregroundStyle(WisdTheme.iconAccent)
                                Text(URL(fileURLWithPath: folderPath).lastPathComponent.isEmpty ? folderPath : URL(fileURLWithPath: folderPath).lastPathComponent)
                                    .font(.system(size: 13.5, weight: .medium))
                                    .foregroundStyle(WisdTheme.ink(scheme))
                                    .lineLimit(1)
                                Spacer()
                                Button {
                                    folders.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 11))
                                        .foregroundStyle(WisdTheme.muted(scheme))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)

                            Rectangle().fill(WisdTheme.divider(scheme)).frame(height: 1)
                        }

                        Button {
                            chooseFolder()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 14))
                                    .foregroundStyle(WisdTheme.iconAccent)
                                Text("Adicionar pasta")
                                    .font(.system(size: 13.5, weight: .medium))
                                    .foregroundStyle(WisdTheme.ink(scheme))
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(WisdTheme.elevated(scheme)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(WisdTheme.border(scheme), lineWidth: 1))
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(WisdTheme.danger)
                }
            }
        }
        .onAppear {
            if let existing = existingProject {
                name = existing.name
                folders = existing.allPaths
                selectedIcon = existing.icon
                selectedIconColor = existing.iconColor
            } else {
                name = ""
                folders = []
                selectedIcon = "terminal"
                selectedIconColor = "red"
            }
        }
    }

    // MARK: - Popover de Ícones (Estilo Unificado)
    private var iconPickerPopover: some View {
        WisdPopoverShell(
            title: "Ícone e Cor",
            subtitle: "Personalize a identificação do projeto",
            statusColor: DesktopColorHelper.color(named: selectedIconColor),
            width: 372,
            headerTrailing: {
                WisdHeaderPillButton(title: "Limpar") {
                    selectedIcon = "terminal"
                    selectedIconColor = "white"
                    iconSearchText = ""
                }
            }
        ) {
            VStack(spacing: 12) {
                HStack(spacing: 0) {
                    Button { iconTab = "emoji" } label: {
                        Text("Emoji")
                            .font(.system(size: 12.5, weight: iconTab == "emoji" ? .semibold : .medium))
                            .foregroundStyle(iconTab == "emoji" ? WisdTheme.ink(scheme) : WisdTheme.muted(scheme))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(iconTab == "emoji" ? WisdTheme.accent.opacity(0.28) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    Button { iconTab = "icons" } label: {
                        Text("Ícones")
                            .font(.system(size: 12.5, weight: iconTab == "icons" ? .semibold : .medium))
                            .foregroundStyle(iconTab == "icons" ? WisdTheme.ink(scheme) : WisdTheme.muted(scheme))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(iconTab == "icons" ? WisdTheme.accent.opacity(0.28) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(3)
                .background(WisdTheme.elevated(scheme), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(WisdTheme.border(scheme), lineWidth: 1))

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(WisdTheme.muted(scheme))
                    TextField("Pesquisar ícones", text: $iconSearchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(WisdTheme.ink(scheme))
                        .focused($focusedField, equals: .iconSearch)

                    if !iconSearchText.isEmpty {
                        Button { iconSearchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(WisdTheme.muted(scheme))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .wisdFieldSurface(focused: focusedField == .iconSearch)

                HStack(spacing: 10) {
                    ForEach(DesktopColorHelper.availableColors, id: \.self) { colorName in
                        Button {
                            selectedIconColor = colorName
                        } label: {
                            Circle()
                                .fill(DesktopColorHelper.color(named: colorName))
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: selectedIconColor == colorName ? 2.5 : 0)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)

                if iconTab == "emoji" {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                            ForEach(["📁", "💻", "🎨", "📚", "🚀", "💡", "🌍", "🎯", "🏠", "⚙️", "🧠", "🎵", "🎬", "💼", "🧪", "🌱",
                                     "⚡", "🔥", "✨", "⭐", "🏆", "📊", "🔒", "🔑", "🛠️", "📦", "🤖", "🌐", "💬", "📝", "🎉", "❤️"], id: \.self) { emoji in
                                Button {
                                    selectedIcon = "emoji:" + emoji
                                } label: {
                                    Text(emoji)
                                        .font(.system(size: 20))
                                        .frame(width: 32, height: 32)
                                        .background(selectedIcon == "emoji:" + emoji ? WisdTheme.accent.opacity(0.25) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 170)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 10) {
                        ForEach(filteredIcons, id: \.self) { iconName in
                            Button {
                                selectedIcon = iconName
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selectedIcon == iconName ? WisdTheme.accent.opacity(0.25) : Color.clear)
                                        .frame(width: 32, height: 32)
                                    Image(systemName: iconName)
                                        .font(.system(size: 15))
                                        .foregroundStyle(DesktopColorHelper.color(named: selectedIconColor))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Selecionar Pasta"
        NSApp.activate(ignoringOtherApps: true)
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            if !folders.contains(url.path) { folders.append(url.path) }
            if name.isEmpty { name = url.lastPathComponent }
        }
    }
}

// MARK: - Modal de Conexão Rápida e Otimizada de Contas de IA

struct AddAccountModalView: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var workspace: Workspace
    var existingAccount: AIAccount? = nil
    let onAdd: (AIAccount) -> Void
    let onCancel: () -> Void

    @State private var provider: AIProvider = .openai
    @State private var name = ""
    @State private var emailOrIdentity = ""
    @State private var password = ""
    @State private var accountID = UUID()
    @State private var connecting = false
    @State private var notice: String?
    @State private var isError = false
    @State private var catalog: [String] = []
    @State private var catalogChecked = false
    @State private var authSuccess = false
    @State private var showProviderPopover = false

    var body: some View {
        WisdModalShell(
            title: existingAccount == nil ? "Adicionar Conta de Agente CLI" : "Editar Conta de Agente CLI",
            subtitle: authSuccess ? "Conta conectada ao agente CLI" : "Autenticação local e sincronização de cotas",
            statusColor: authSuccess ? WisdTheme.success : WisdTheme.iconAccent,
            width: 540,
            maxHeight: 470,
            onClose: onCancel,
            footer: {
                HStack {
                    WisdSecondaryButton("Cancelar", action: onCancel)
                        .keyboardShortcut(.cancelAction)

                    Spacer()

                    WisdPrimaryButton(
                        existingAccount == nil ? "Salvar Conta" : "Salvar Alterações",
                        icon: "checkmark",
                        disabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || connecting
                    ) {
                        save()
                    }
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 18) {
                // 1. Seletor de Provedor (Dropdown no padrão Popover unificado)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Fornecedor / Agente")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WisdTheme.muted(scheme))

                    WisdDropdownTrigger(
                        icon: provider.iconName,
                        title: provider.displayName,
                        subtitle: "Agente CLI: \(provider.cliName)",
                        isPresented: showProviderPopover
                    ) {
                        showProviderPopover.toggle()
                    }
                    .disabled(existingAccount != nil || connecting)
                    .popover(isPresented: $showProviderPopover, arrowEdge: .bottom) {
                        WisdPopoverShell(
                            title: "Fornecedor / Agente",
                            subtitle: "Escolha o motor de IA para esta conta",
                            statusColor: WisdTheme.iconAccent,
                            width: 340
                        ) {
                            WisdPopoverSection {
                                VStack(spacing: 3) {
                                    ForEach(AIProvider.allCases) { p in
                                        WisdSelectableRow(
                                            icon: p.iconName,
                                            title: p.displayName,
                                            subtitle: "Agente CLI: \(p.cliName)",
                                            selected: provider == p
                                        ) {
                                            provider = p
                                            if name.isEmpty || AIProvider.allCases.contains(where: { name.hasPrefix($0.displayName) }) {
                                                name = "\(p.displayName) - Conta"
                                            }
                                            catalog = []
                                            catalogChecked = false
                                            notice = nil
                                            authSuccess = false
                                            showProviderPopover = false
                                        }
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.top, 8)
                            }
                        }
                        .presentationBackground(.clear)
                    }
                }

                // 2. Status do Agente CLI no Sistema
                HStack(spacing: 8) {
                    let cliPath = AgentCLIAuthenticator.locateCLI(for: provider)
                    if let path = cliPath {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(WisdTheme.success).font(.system(size: 13))
                        Text("CLI \(provider.cliName) detectado: \(path)")
                            .font(.system(size: 11)).foregroundStyle(WisdTheme.muted(scheme)).lineLimit(1)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(WisdTheme.warning).font(.system(size: 13))
                        Text("CLI \(provider.cliName) será baixado/incorporado para esta conta")
                            .font(.system(size: 11)).foregroundStyle(WisdTheme.muted(scheme))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WisdTheme.elevated(scheme), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(WisdTheme.border(scheme), lineWidth: 1))

                // 3. Credenciais da Conta
                VStack(alignment: .leading, spacing: 12) {
                    Text("Dados de Acesso da Conta")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(WisdTheme.ink(scheme))

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Identificador do Perfil")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(WisdTheme.muted(scheme))
                        TextField("Ex: \(provider.displayName) Trabalho, \(provider.displayName) Pessoal", text: $name)
                            .wisdFieldSurface()
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Usuário ou E-mail da Conta")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(WisdTheme.muted(scheme))
                        TextField("Digite seu usuário ou e-mail de login do agente", text: $emailOrIdentity)
                            .wisdFieldSurface()
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Senha da Conta")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(WisdTheme.muted(scheme))
                        SecureField("Digite a senha da sua conta de agente", text: $password)
                            .wisdFieldSurface()
                    }

                    Button {
                        authenticateReal()
                    } label: {
                        HStack(spacing: 8) {
                            if connecting {
                                ProgressView().controlSize(.small)
                                Text("Autenticando conta no CLI…")
                            } else {
                                Image(systemName: authSuccess ? "checkmark.seal.fill" : "lock.shield")
                                Text(authSuccess ? "Conta Autenticada de Verdade" : "Autenticar Conta no Agente CLI")
                            }
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(authSuccess ? WisdTheme.success.opacity(0.85) : WisdTheme.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .foregroundStyle(Color.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(connecting || emailOrIdentity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let notice {
                        Text(notice)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(isError ? WisdTheme.danger : WisdTheme.success)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background((isError ? WisdTheme.danger : WisdTheme.success).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }
                }

                // 4. Modelos Desta Conta
                if !catalog.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(catalog.count) modelos disponíveis para esta conta:")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WisdTheme.ink(scheme))

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 125))], spacing: 6) {
                            ForEach(catalog, id: \.self) { model in
                                Text(AIProvider.modelDisplayName(for: model))
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(WisdTheme.elevated(scheme), in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(WisdTheme.border(scheme), lineWidth: 1))
                                    .foregroundStyle(WisdTheme.ink(scheme))
                            }
                        }
                    }
                    .padding(12)
                    .background(WisdTheme.elevated(scheme), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(WisdTheme.border(scheme), lineWidth: 1))
                }
            }
        }
        .onAppear {
            if let account = existingAccount {
                provider = account.provider
                name = account.name
                emailOrIdentity = account.emailOrIdentity
                accountID = account.id
                catalog = account.models
                catalogChecked = !account.models.isEmpty
                authSuccess = !account.models.isEmpty
                if let pass = AccountKeychain.readAccountPassword(accountID: account.id) {
                    password = pass
                }
            } else {
                if name.isEmpty { name = "\(provider.displayName) - Conta" }
                catalog = []
                catalogChecked = false
            }
        }
        .onChange(of: provider) {
            if existingAccount == nil {
                name = "\(provider.displayName) - Conta"
                catalog = []
                password = ""
                notice = nil
                isError = false
                authSuccess = false
                catalogChecked = false
            }
        }
    }

    private func authenticateReal() {
        connecting = true
        notice = nil
        isError = false
        let targetProvider = provider
        let targetUser = emailOrIdentity
        let targetPass = password
        let targetID = accountID

        Task { @MainActor in
            defer { connecting = false }
            do {
                let result = try await AgentCLIAuthenticator.authenticate(
                    provider: targetProvider,
                    user: targetUser,
                    password: targetPass,
                    accountID: targetID
                )
                catalog = result.models
                catalogChecked = true
                authSuccess = true
                isError = false
                notice = "✓ Autenticado com sucesso de verdade! \(result.sessionLabel)"
            } catch {
                authSuccess = false
                isError = true
                notice = error.localizedDescription
            }
        }
    }

    private func save() {
        do {
            if !password.isEmpty {
                try AccountKeychain.saveAccountPassword(password, accountID: accountID)
            }
            var account = existingAccount ?? AIAccount(name: name, provider: provider, cliInstalled: false)
            account.id = accountID
            account.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "\(provider.displayName) - Conta"
                : name.trimmingCharacters(in: .whitespacesAndNewlines)
            account.emailOrIdentity = emailOrIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
            account.apiKeyOrToken = nil
            account.cliPath = AgentCLIAuthenticator.locateCLI(for: provider)
            account.cliInstalled = account.cliPath != nil
            account.models = !catalog.isEmpty ? catalog : provider.defaultModels
            account.activeModelIndex = 0
            account.modelsUpdatedAt = Date()
            account.catalogSource = "Conta de Agente CLI (\(account.emailOrIdentity))"

            if provider == .claude, account.profileDirectory == nil {
                account.profileDirectory = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support/WisdAI/Accounts/\(accountID.uuidString)/claude").path
            }
            onAdd(account)
        } catch {
            isError = true
            notice = error.localizedDescription
        }
    }
}

// MARK: - Modal de Alerta de Limite de Conta Atingido

struct AccountLimitAlertModalView: View {
    @Environment(\.colorScheme) private var scheme
    let exhaustedAccount: AIAccount
    let availableAccounts: [AIAccount]
    let onSelectAccount: (AIAccount) -> Void
    let onAddNewAccount: () -> Void
    let onCancel: () -> Void

    var body: some View {
        let validAccounts = availableAccounts.filter { $0.id != exhaustedAccount.id && $0.supportsExecution }

        return WisdModalShell(
            title: "Limite da sessão atingido",
            subtitle: "\(exhaustedAccount.name) · \(exhaustedAccount.provider.displayName)",
            statusColor: WisdTheme.warning,
            width: 500,
            onClose: onCancel,
            footer: {
                HStack {
                    WisdSecondaryButton("Pausar Tarefa", action: onCancel)
                    Spacer()
                    WisdPrimaryButton("Adicionar Outra Conta", icon: "plus", action: onAddNewAccount)
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(WisdTheme.warning)
                        .frame(width: 40, height: 40)
                        .background(WisdTheme.warning.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                    Text("O provedor informou um limite para esta sessão. Escolha outra conta conectada abaixo para retomar a tarefa imediatamente.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(WisdTheme.muted(scheme))
                }

                Rectangle().fill(WisdTheme.divider(scheme)).frame(height: 1)

                Text("Escolha outra conta conectada:")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WisdTheme.muted(scheme))

                if validAccounts.isEmpty {
                    VStack(spacing: 10) {
                        Text("Nenhuma outra conta conectada possui saldo livre no momento.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(WisdTheme.muted(scheme))
                        WisdPrimaryButton("Adicionar Nova Conta de IA", icon: "plus", action: onAddNewAccount)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(WisdTheme.elevated(scheme), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(WisdTheme.border(scheme), lineWidth: 1))
                } else {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(validAccounts) { account in
                                WisdSelectableRow(
                                    icon: account.provider.iconName,
                                    title: account.name,
                                    subtitle: "Modelo ativo: \(AIProvider.modelDisplayName(for: account.currentModel))",
                                    trailing: {
                                        Image(systemName: "arrow.right.circle.fill")
                                            .font(.system(size: 15))
                                            .foregroundStyle(WisdTheme.iconAccent)
                                    }
                                ) {
                                    onSelectAccount(account)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }
        }
    }
}

// MARK: - View Auxiliar para Exibição de Tags de Modelos

struct WrapTagsView: View {
    let tags: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(white: 0.15), in: Capsule())
                    .overlay(Capsule().stroke(Color(white: 0.25), lineWidth: 1))
                    .foregroundStyle(Color.white)
            }
        }
    }
}

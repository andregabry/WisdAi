import AppKit
import SwiftUI

struct DesktopSettings: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var workspace: Workspace
    @ObservedObject var local: DesktopLocalData
    @Binding var selection: String
    @Binding var page: DesktopPage
    @State private var search = ""
    @State private var archived: [Conversation] = []
    @State private var archiveNotice: String?
    @State private var showAccountEditor = false
    @State private var editingAccount: AIAccount?
    @State private var removingAccount: AIAccount?
    @State private var accountMenuTargetID: UUID? = nil
    @AppStorage("wisdcode.appearance") private var appearance = "dark"
    @State private var apiKeys: [String: String] = [:]
    @State private var savedKeyStatus: [String: Bool] = [:]
    @State private var testingProvider: String? = nil
    @State private var testResults: [String: (success: Bool, message: String)] = [:]

    private let groups: [(String, [(String, String)])] = [
        ("Perfil", [
            ("Perfil", "person.crop.circle"),
            ("Voz", "waveform.and.mic")
        ]),
        ("Acesso e IA", [
            ("Contas", "person.2.crop.square.stack"),
            ("Chaves de API", "key"),
            ("Uso", "gauge.with.dots.needle.50percent")
        ]),
        ("App", [("Geral", "gearshape"), ("Notificações", "bell"), ("Teclado", "command")]),
        ("Dados e privacidade", [("Chats arquivados", "archivebox"), ("Armazenamento", "folder"), ("Controles de dados", "shield")]),
        ("Integrações e Código", [("Plugins", "puzzlepiece.extension"), ("Revisão de código", "arrow.triangle.branch")])
    ]

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    BrandLogoView(height: 24)
                    Spacer()
                }.padding(.horizontal, 8).padding(.top, 8)
                DesktopSearchField(title: "Pesquisar", text: $search).padding(.horizontal, 4)
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(groups, id: \.0) { group in
                            let items = group.1.filter { search.isEmpty || $0.0.localizedCaseInsensitiveContains(search) }
                            if !items.isEmpty {
                                Text(group.0).foregroundStyle(DesktopStyle.muted).font(.system(size: 12))
                                    .padding(.horizontal, 12).padding(.top, 17).padding(.bottom, 8)
                                ForEach(items, id: \.0) { item in
                                    Button { selection = item.0 } label: {
                                        Label(item.0, systemImage: item.1).frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 12).frame(height: 35)
                                            .modifier(DesktopHover(selected: selection == item.0))
                                    }
                                }
                            }
                        }
                    }.padding(.horizontal, 4).padding(.bottom, 20)
                }.scrollIndicators(.hidden)
            }.padding(12).frame(width: 230)
            Rectangle().fill(DesktopStyle.line).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text(selection).font(.system(size: 28, weight: .medium))
                    settingsContent
                }.frame(maxWidth: 700, alignment: .leading).padding(32).frame(maxWidth: .infinity)
            }
        }
        .background(DesktopStyle.canvas)
        .foregroundStyle(DesktopStyle.ink)
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Button { page = .chat } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DesktopStyle.muted)
                    .frame(width: 32, height: 32)
                    .modifier(DesktopHover(radius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fechar configurações")
            .help("Fechar configurações")
            .keyboardShortcut(.cancelAction)
            .padding(12)
        }
        .sheet(isPresented: $showAccountEditor) {
            AddAccountModalView(workspace: workspace, existingAccount: editingAccount) { account in
                local.addAccount(account)
                showAccountEditor = false
                editingAccount = nil
            } onCancel: {
                showAccountEditor = false
                editingAccount = nil
            }
            .id(editingAccount?.id.uuidString ?? "new-account")
            .presentationBackground(.clear)
        }
        .sheet(item: $removingAccount) { account in
            WisdModalShell(
                title: "Remover perfil local?",
                subtitle: "\(account.name) · \(account.provider.displayName)",
                statusColor: WisdTheme.danger,
                width: 430,
                onClose: { removingAccount = nil },
                footer: {
                    HStack(spacing: 10) {
                        Spacer()
                        WisdSecondaryButton("Cancelar") { removingAccount = nil }
                        Button {
                            do { try AccountKeychain.delete(accountID: account.id); local.deleteAccount(account) }
                            catch { workspace.error = error.localizedDescription }
                            removingAccount = nil
                        } label: {
                            Text("Remover")
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
                Text("Remover \"\(account.name)\" e sua chave de API salva neste app? As conversas salvas e o login da CLI oficial serão preservados.")
                    .font(.system(size: 13))
                    .foregroundStyle(WisdTheme.ink(scheme))
            }
            .presentationBackground(.clear)
        }
        .onAppear { if workspace.ready { workspace.refreshAccount() } }
        .onChange(of: selection, initial: true) { if selection == "Chats arquivados" { loadArchive() } }
        .onChange(of: workspace.accountIdentity) { archived = []; if selection == "Chats arquivados" { loadArchive() } }
    }

    @ViewBuilder private var settingsContent: some View {
        switch selection {
        case "Perfil", "Aparência", "Personalização":
            profilePanel
        case "Voz":
            VoiceSettingsSection(workspace: workspace, voice: workspace.voice, showTitle: false)
        case "Contas", "Conta", "Segurança e login":
            accountPanel
        case "Chaves de API":
            apiKeysPanel
        case "Geral":
            settingsCard {
                settingsRow("Aplicativo", value: "WisdAI \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                Divider().padding(.vertical, 12)
                settingsRow("Idioma", value: "Português")
                Divider().padding(.vertical, 12)
                settingsRow("Execução", value: "Neste computador")
            }
            Button("Escolher pasta do projeto", systemImage: "folder", action: workspace.chooseProject).disabled(workspace.busy)
        case "Notificações":
            settingsCard {
                Toggle("Notificações de conclusão de tarefas", isOn: .constant(true)).toggleStyle(.switch)
                Divider().padding(.vertical, 12)
                Toggle("Alertas de limite de tokens da conta", isOn: .constant(true)).toggleStyle(.switch)
            }
        case "Uso":
            settingsCard { UsageDetails(workspace: workspace) }
            Button("Ver detalhes de uso") { page = .usage }.buttonStyle(.bordered)
        case "Plugins":
            Text("Conecte ferramentas e gerencie as habilidades disponíveis para o agente.").foregroundStyle(DesktopStyle.muted)
            Button("Abrir plugins") { page = .plugins }.buttonStyle(.bordered)
        case "Armazenamento":
            settingsCard {
                settingsRow("Biblioteca local", value: "\(local.library.count) itens")
                Divider().padding(.vertical, 12)
                settingsRow("Tarefas locais", value: "\(local.tasks.count) tarefas")
                Divider().padding(.vertical, 12)
                settingsRow("Projetos salvos", value: "\(local.projectPaths.count) projetos")
            }
            Button("Abrir biblioteca") { page = .library }.buttonStyle(.bordered)
        case "Teclado":
            settingsCard {
                settingsRow("Novo chat", value: "⌘ N")
                Divider().padding(.vertical, 12)
                settingsRow("Pesquisar chats", value: "⌘ K")
                Divider().padding(.vertical, 12)
                settingsRow("Enviar mensagem", value: "Enter")
            }
        case "Revisão de código":
            Text("Revise as alterações do projeto escolhido com o modelo conectado.").foregroundStyle(DesktopStyle.muted)
            Button("Revisar alterações", systemImage: "arrow.triangle.branch") { page = .chat; workspace.reviewChanges() }
                .buttonStyle(.bordered).disabled(workspace.project == nil || !workspace.ready || workspace.busy)
        case "Controles de dados":
            settingsCard {
                Text("O histórico das conversas é gerenciado pelo motor Codex. A biblioteca, as tarefas e os favoritos são salvos neste Mac.")
                    .foregroundStyle(DesktopStyle.muted)
            }
        case "Chats arquivados":
            if let archiveNotice { Text(archiveNotice).foregroundStyle(DesktopStyle.muted) }
            if archived.isEmpty { Text("Nenhum chat arquivado disponível.").foregroundStyle(DesktopStyle.muted) }
            ForEach(archived) { thread in
                settingsCard {
                    HStack {
                        Text(thread.title).lineLimit(2)
                        Spacer()
                        Button("Restaurar") {
                            workspace.request("thread/unarchive", ["threadId": thread.id]) { response in
                                if workspace.accept(response) != nil { loadArchive(); workspace.refresh() }
                            }
                        }.disabled(workspace.busy || workspace.accountBusy)
                    }
                }
            }
        case "Ajuda":
            Text("WisdAI para macOS").font(.title3)
            Text("Abra um projeto, conecte uma conta e inicie uma conversa.").foregroundStyle(DesktopStyle.muted)
        default:
            VStack(spacing: 16) {
                Image(systemName: "slider.horizontal.3").font(.system(size: 32)).foregroundStyle(DesktopStyle.muted)
                Text("\(selection) está integrado ao WisdAI.")
                    .foregroundStyle(DesktopStyle.muted).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity).padding(.vertical, 80)
        }
    }

    private var profilePanel: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Perfil do Usuário
            settingsCard {
                HStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(DesktopStyle.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(workspace.account.isEmpty ? "Usuário WisdAI" : workspace.account)
                            .font(.system(size: 16, weight: .semibold))
                        Text(workspace.plan?.capitalized ?? "Plano Local")
                            .font(.system(size: 13))
                            .foregroundStyle(DesktopStyle.muted)
                    }
                    Spacer()
                    Button("Sair", role: .destructive) { workspace.logout() }
                        .buttonStyle(.bordered)
                        .disabled(workspace.busy || workspace.accountBusy)
                }
            }

            // Aparência e Tema
            VStack(alignment: .leading, spacing: 12) {
                Text("Aparência").font(.system(size: 17, weight: .medium))
                Text("Escolha as cores e o tema de visualização do WisdAI.").foregroundStyle(DesktopStyle.muted).font(.system(size: 13))

                settingsCard {
                    HStack {
                        Text("Modo")
                        Spacer()
                        Picker("Tema", selection: $appearance) {
                            Text("Sistema").tag("system")
                            Text("Claro").tag("light")
                            Text("Escuro").tag("dark")
                        }.pickerStyle(.segmented).labelsHidden().frame(width: 270)
                    }
                }

                HStack(spacing: 16) {
                    themePreview("Claro", dark: false)
                    themePreview("Escuro", dark: true)
                }
            }

            // Personalização e Agente
            VStack(alignment: .leading, spacing: 12) {
                Text("Personalização").font(.system(size: 17, weight: .medium))
                Text("As instruções do projeto e as habilidades instaladas orientam o agente.").foregroundStyle(DesktopStyle.muted).font(.system(size: 13))
                Button("Gerenciar habilidades", systemImage: "sparkles") { page = .skills }.buttonStyle(.bordered)
            }

            // Voz e Áudio
            VoiceSettingsSection(workspace: workspace, voice: workspace.voice, showTitle: true)
        }
    }

    private var accountPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let notice = local.credentialMigrationNotice { Text(notice).foregroundStyle(.orange) }

            // Segurança e Continuidade de Tarefas
            VStack(alignment: .leading, spacing: 10) {
                Text("Segurança e Execução").font(.system(size: 17, weight: .medium))
                settingsCard {
                    Toggle("Continuar automaticamente ao atingir limite", isOn: $workspace.automaticFallback).toggleStyle(.switch)
                    Text("Usa modelos da conta ativa e outras sessões conectadas. Preserva o mesmo chat e suas permissões. Se uma conta atingir o limite de tokens, o WisdAI alterna de forma inteligente para os próximos modelos disponíveis sem interromper o fluxo de trabalho.")
                        .font(.system(size: 12)).foregroundStyle(DesktopStyle.muted)
                    Divider().padding(.vertical, 12)
                    settingsRow("Criptografia", value: "macOS Keychain (Hardware Enclave)")
                    Divider().padding(.vertical, 12)
                    settingsRow("Sessão ativa", value: workspace.account)
                    Divider().padding(.vertical, 12)
                    settingsRow("Plano", value: workspace.plan?.capitalized ?? "Não informado")
                }
            }

            // Gerenciamento de Contas de IA
            HStack {
                Text("Contas de IA").font(.system(size: 17, weight: .medium))
                Spacer()
                Button("Adicionar conta", systemImage: "plus") { editingAccount = nil; showAccountEditor = true }.buttonStyle(.bordered)
            }
            Text("Mantenha várias contas do mesmo provedor e selecione a sessão que executa o trabalho.").foregroundStyle(DesktopStyle.muted).font(.system(size: 13))

            ForEach(AIProvider.allCases.filter { provider in local.aiAccounts.contains { $0.provider == provider } }) { provider in
                Text(provider.displayName).font(.system(size: 13, weight: .semibold)).foregroundStyle(DesktopStyle.muted)
                ForEach(local.aiAccounts.filter { $0.provider == provider }) { account in
                    let snap = workspace.quotaStore.accountSnapshot(for: account.id)
                    let avail = snap?.availability ?? (account.hasAvailableModels ? .unknown : .exhausted)
                    settingsCard {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: provider.iconName).font(.system(size: 20))
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Text(account.name).font(.system(size: 14, weight: .semibold))
                                    if avail == .exhausted {
                                        let reset = snap?.nextResetAt.map { " · renova \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
                                        Text("Esgotado\(reset)")
                                            .font(.system(size: 10.5, weight: .semibold))
                                            .foregroundStyle(.red)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Color.red.opacity(0.14), in: Capsule())
                                    } else if let rem = snap?.remainingPercent {
                                        Text("\(rem)% livre")
                                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(avail == .nearLimit ? .orange : .green)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background((avail == .nearLimit ? Color.orange : Color.green).opacity(0.14), in: Capsule())
                                    }
                                }
                                Text(account.connectionLabel).font(.system(size: 12)).foregroundStyle(DesktopStyle.muted)
                                if let source = account.catalogSource { Text(source).font(.system(size: 11)).foregroundStyle(DesktopStyle.muted) }
                                if let date = account.modelsUpdatedAt {
                                    let tokNote = (snap?.totalTokensConsumed ?? 0) > 0 ? " · \(snap!.totalTokensConsumed.formatted()) tok nesta sessão" : ""
                                    Text("\(account.models.count) modelos · atualizado \(date.formatted(date: .abbreviated, time: .shortened))\(tokNote)")
                                        .font(.system(size: 11)).foregroundStyle(DesktopStyle.muted)
                                } else { Text("Modelos ainda não consultados nesta conta").font(.system(size: 11)).foregroundStyle(DesktopStyle.muted) }
                            }
                            Spacer()
                            if account.isActive && account.supportsExecution { Text("Ativa").foregroundStyle(.green) }
                            else if account.supportsExecution {
                                Button("Usar") { workspace.activateAccount(account) }.buttonStyle(.bordered)
                                    .disabled(!workspace.activeTasks.isEmpty || workspace.accountBusy)
                            }
                            Button {
                                accountMenuTargetID = account.id
                            } label: {
                                accountMenuIcon
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Ações da conta \(account.name)")
                            .popover(
                                isPresented: Binding(
                                    get: { accountMenuTargetID == account.id },
                                    set: { if !$0 && accountMenuTargetID == account.id { accountMenuTargetID = nil } }
                                ),
                                arrowEdge: .bottom
                            ) {
                                WisdPopoverShell(
                                    title: account.name,
                                    subtitle: account.provider.displayName,
                                    statusColor: avail == .exhausted ? WisdTheme.danger : WisdTheme.success,
                                    width: 280
                                ) {
                                    VStack(alignment: .leading, spacing: 0) {
                                        WisdPopoverSection {
                                            VStack(spacing: 2) {
                                                WisdSelectableRow(icon: "arrow.triangle.2.circlepath", title: "Carregar / Atualizar modelos") {
                                                    accountMenuTargetID = nil
                                                    editingAccount = account
                                                    showAccountEditor = true
                                                }
                                                WisdSelectableRow(icon: "gauge.with.dots.needle.50percent", title: "Sincronizar cota em memória") {
                                                    accountMenuTargetID = nil
                                                    Task { await workspace.refreshAllQuotasNow(force: true) }
                                                }
                                                if avail == .exhausted || !account.exhaustedModelIndices.isEmpty {
                                                    WisdSelectableRow(icon: "lock.open", iconColor: WisdTheme.warning, title: "Liberar bloqueio de limite") {
                                                        accountMenuTargetID = nil
                                                        workspace.quotaStore.clearLimits(accountID: account.id)
                                                        if var updated = local.aiAccounts.first(where: { $0.id == account.id }) {
                                                            updated.resetExhaustedModels()
                                                            local.addAccount(updated)
                                                        }
                                                    }
                                                }
                                                WisdSelectableRow(icon: "pencil", title: "Editar configuração") {
                                                    accountMenuTargetID = nil
                                                    editingAccount = account
                                                    showAccountEditor = true
                                                }
                                                if !account.isActive {
                                                    WisdSelectableRow(icon: "checkmark.circle", title: "Ativar conta") {
                                                        accountMenuTargetID = nil
                                                        workspace.activateAccount(account)
                                                    }
                                                }
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.top, 8)
                                        }

                                        Rectangle().fill(WisdTheme.divider(scheme)).frame(height: 1)

                                        WisdPopoverSection {
                                            VStack(spacing: 2) {
                                                WisdSelectableRow(icon: "trash", iconColor: WisdTheme.danger, title: "Remover perfil local") {
                                                    accountMenuTargetID = nil
                                                    removingAccount = account
                                                }
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.top, 8)
                                        }
                                    }
                                }
                                .presentationBackground(.clear)
                            }
                        }
                    }
                }
            }
            if local.aiAccounts.isEmpty { Text("Adicione uma conta para começar.").foregroundStyle(DesktopStyle.muted) }
            HStack(spacing: 10) {
                Button("Atualizar sessões", systemImage: "arrow.clockwise", action: workspace.refreshAccount).disabled(!workspace.ready || workspace.accountBusy)
                Button("Sincronizar limites agora", systemImage: "gauge.with.dots.needle.50percent") {
                    Task { await workspace.refreshAllQuotasNow(force: true) }
                }.disabled(workspace.quotaStore.isRefreshing)
            }
        }
    }

    private var apiKeysPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Chaves de API dos Fornecedores")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Cadastre as chaves de API oficiais para acesso direto aos provedores de IA. Todas as chaves são criptografadas e salvas no macOS Keychain com proteção por hardware.")
                        .font(.system(size: 12))
                        .foregroundStyle(DesktopStyle.muted)
                }
            }

            Text("Provedores de IA").font(.system(size: 15, weight: .medium))

            ForEach(AIProvider.allCases) { provider in
                let providerKey = provider.rawValue
                let hasKey = savedKeyStatus[providerKey] ?? false
                let keyBinding = Binding<String>(
                    get: { apiKeys[providerKey] ?? "" },
                    set: { apiKeys[providerKey] = $0 }
                )
                let isTesting = testingProvider == providerKey
                let testResult = testResults[providerKey]

                settingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: provider.iconName)
                                .font(.system(size: 20))
                                .foregroundStyle(DesktopStyle.accent)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.displayName)
                                    .font(.system(size: 14, weight: .semibold))
                                Text("CLI oficial: \(provider.cliName)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(DesktopStyle.muted)
                            }

                            Spacer()

                            if hasKey {
                                Label("Chave salva no Keychain", systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.green)
                            } else {
                                Text("Nenhuma chave salva")
                                    .font(.system(size: 11))
                                    .foregroundStyle(DesktopStyle.muted)
                            }
                        }

                        HStack(spacing: 8) {
                            SecureField(hasKey ? "••••••••••••••••••••••••" : "Informe a chave de API de \(provider.displayName)", text: keyBinding)
                                .textFieldStyle(.plain)
                                .padding(9)
                                .background(DesktopStyle.surface, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.22), lineWidth: 1))

                            Button("Salvar") {
                                let keyToSave = keyBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !keyToSave.isEmpty else { return }
                                do {
                                    try AccountKeychain.saveProviderKey(keyToSave, provider: provider)
                                    savedKeyStatus[providerKey] = true
                                    testResults[providerKey] = (true, "Chave de \(provider.displayName) salva com sucesso no macOS Keychain!")
                                } catch {
                                    testResults[providerKey] = (false, "Erro ao salvar: \(error.localizedDescription)")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(keyBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Button {
                                testKey(provider: provider)
                            } label: {
                                if isTesting {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Text("Testar")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isTesting || (keyBinding.wrappedValue.isEmpty && !hasKey))

                            if hasKey {
                                Button(role: .destructive) {
                                    try? AccountKeychain.deleteProviderKey(provider: provider)
                                    savedKeyStatus[providerKey] = false
                                    apiKeys[providerKey] = ""
                                    testResults[providerKey] = nil
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remover chave")
                            }
                        }

                        if let result = testResult {
                            HStack(spacing: 6) {
                                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(result.success ? .green : .red)
                                Text(result.message)
                                    .font(.system(size: 11))
                                    .foregroundStyle(result.success ? .green : .red)
                            }
                            .padding(.top, 4)
                        }
                    }
                }
            }
        }
        .onAppear {
            loadProviderKeyStatuses()
        }
    }

    private func loadProviderKeyStatuses() {
        for provider in AIProvider.allCases {
            let key = AccountKeychain.readProviderKey(provider: provider)
            savedKeyStatus[provider.rawValue] = key != nil && !key!.isEmpty
        }
    }

    private func testKey(provider: AIProvider) {
        let providerKey = provider.rawValue
        testingProvider = providerKey
        let keyToTest = (apiKeys[providerKey]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? apiKeys[providerKey]!
            : (AccountKeychain.readProviderKey(provider: provider) ?? "")

        guard !keyToTest.isEmpty else {
            testingProvider = nil
            testResults[providerKey] = (false, "Informe a chave de API para testar.")
            return
        }

        Task { @MainActor in
            defer { testingProvider = nil }
            do {
                let models = try await ProviderCatalogClient().models(provider: provider, key: keyToTest)
                testResults[providerKey] = (true, "✓ Chave válida de verdade! \(models.count) modelos retornados pelo provedor.")
            } catch {
                testResults[providerKey] = (false, "Falha na validação oficial: \(error.localizedDescription)")
            }
        }
    }

    private func loadArchive() {
        guard workspace.ready else { return }
        archiveNotice = nil
        let identity = workspace.accountIdentity
        workspace.request("thread/list", ["limit": 50, "archived": true, "currentAccountOnly": true]) { response in
            guard workspace.accountIdentity == identity else { return }
            if let result = response["result"] as? JSON {
                archived = (result["data"] as? [JSON] ?? []).compactMap(Conversation.init)
            } else {
                archiveNotice = (response["error"] as? JSON)?["message"] as? String ?? "Não foi possível ler os chats arquivados."
            }
        }
    }

    private var accountMenuIcon: some View {
        AccountActionIcon()
    }

    private func settingsRow(_ name: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(name)
            Spacer(minLength: 20)
            Text(value).foregroundStyle(DesktopStyle.muted).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6, content: content).padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesktopStyle.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(DesktopStyle.line))
    }

    private func themePreview(_ title: String, dark: Bool) -> some View {
        Button { appearance = dark ? "dark" : "light" } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 4).fill(dark ? Color.black : Color(white: 0.93)).frame(width: 32)
                    VStack(spacing: 8) {
                        Capsule().fill(dark ? Color(white: 0.2) : Color(white: 0.88)).frame(width: 72, height: 8)
                        Capsule().fill(dark ? Color(white: 0.2) : Color(white: 0.88)).frame(width: 100, height: 18)
                    }.frame(maxWidth: .infinity)
                }.frame(height: 110).background(dark ? Color(white: 0.055) : .white, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DesktopStyle.line))
                Text(title)
            }.padding(12).frame(width: 195)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(appearance == (dark ? "dark" : "light") ? DesktopStyle.accent : DesktopStyle.line))
        }
    }
}

// MARK: - Ícone de Ações de Conta (Exclamação em Círculo Azul +3px)

struct AccountActionIcon: View {
    // Renderizado diretamente via NSImage não-template para impedir que o AppKit/Menu
    // sobreponha ou apague a cor azul na renderização de botões/menus do macOS.
    private static let blueImage: NSImage = {
        let blue = NSColor(srgbRed: 0.12, green: 0.53, blue: 1.0, alpha: 1.0)
        let config = NSImage.SymbolConfiguration(pointSize: 19, weight: .semibold)
        guard let symbol = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: "Ações da conta")?.withSymbolConfiguration(config) else {
            return NSImage()
        }
        let size = symbol.size
        let img = NSImage(size: size, flipped: false) { rect in
            blue.set()
            symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            rect.fill(using: .sourceIn)
            return true
        }
        img.isTemplate = false
        return img
    }()

    var body: some View {
        Image(nsImage: Self.blueImage)
            .renderingMode(.original)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
    }
}

// MARK: - Configuração de Voz Natural (Mulher / Homem)

struct VoiceSettingsSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var workspace: Workspace
    @ObservedObject var voice: VoiceController
    var showTitle: Bool = true
    @State private var showVoiceCatalog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showTitle {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Voz e Áudio")
                        .font(.system(size: 17, weight: .medium))
                    Text("Escolha entre voz feminina ou masculina com prosódia natural em português.")
                        .font(.system(size: 13))
                        .foregroundStyle(DesktopStyle.muted)
                }
            } else {
                Text("Configure timbre natural (Mulher ou Homem), velocidade e motor de síntese das respostas faladas.")
                    .font(.system(size: 13))
                    .foregroundStyle(DesktopStyle.muted)
            }

            VStack(alignment: .leading, spacing: 14) {
                Toggle("Ler respostas em voz alta", isOn: $workspace.speakReplies)
                    .toggleStyle(.switch)

                Rectangle()
                    .fill(WisdTheme.divider(colorScheme))
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Identidade e Voz do Agente")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text(voice.activeVoiceSummary)
                            .font(.system(size: 11.5))
                            .foregroundStyle(WisdTheme.muted(colorScheme))
                            .lineLimit(1)
                    }

                    HStack(spacing: 10) {
                        ForEach(AgentVoiceGender.allCases) { gender in
                            VoiceGenderCard(
                                gender: gender,
                                selected: voice.voiceGender == gender
                            ) {
                                voice.selectedVoiceID = "auto"
                                voice.voiceGender = gender
                            }
                        }
                    }

                    // Identidades vocais WisdAI (JARVIS, Atlas, Aurora, Aria) -> fonte única VoiceIdentityManager
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(WisdVoicePersona.allCases) { persona in
                                let isCurrent = voice.orchestrator.identityManager.config.identityId == persona
                                Button {
                                    voice.orchestrator.identityManager.selectPersona(persona)
                                } label: {
                                    Text(persona.shortName)
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(isCurrent ? Color.white : WisdTheme.ink(colorScheme))
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 5)
                                        .background(
                                            Capsule().fill(isCurrent ? WisdTheme.accent : WisdTheme.elevated(colorScheme))
                                        )
                                }
                                .buttonStyle(.plain)
                                .help(persona.subtitle)
                            }
                        }
                    }
                    .padding(.top, 2)

                    if let alert = voice.orchestrator.identityManager.divergenceAlert {
                        Label(alert, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }
                }

                Rectangle()
                    .fill(WisdTheme.divider(colorScheme))
                    .frame(height: 1)

                // Paleta Horizon Orb & preferências Codex
                VStack(alignment: .leading, spacing: 10) {
                    Text("Orbe Horizon & Experiência Codex")
                        .font(.system(size: 13, weight: .semibold))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(CodexOrbPalette.allCases) { palette in
                                let selected = voice.orbPalette == palette
                                Button {
                                    voice.orbPalette = palette
                                } label: {
                                    HStack(spacing: 6) {
                                        CodexHorizonOrbView(
                                            phase: .active,
                                            activity: .listening,
                                            levels: CodexOrbAudioLevels(overall: 0.3, low: 0.3, mid: 0.4, high: 0.25, micLevel: 0.35),
                                            palette: palette,
                                            isMuted: false,
                                            size: 18
                                        )
                                        Text(palette.displayName)
                                            .font(.system(size: 11.5, weight: .medium))
                                            .foregroundStyle(selected ? Color.white : WisdTheme.ink(colorScheme))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule().fill(selected ? WisdTheme.accent : WisdTheme.elevated(colorScheme))
                                    )
                                    .overlay(
                                        Capsule().stroke(selected ? WisdTheme.accent : WisdTheme.border(colorScheme), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Toggle("Sinais sonoros do assistente e ditado", isOn: $voice.voiceSoundsEnabled)
                        .toggleStyle(.switch)
                    Toggle("Saudação automática ao iniciar conversa por voz", isOn: $voice.autoGreetingEnabled)
                        .toggleStyle(.switch)
                    Toggle("Memória contínua de voz (realtime-voice-continuity)", isOn: $voice.voiceContinuityEnabled)
                        .toggleStyle(.switch)
                }

                Rectangle()
                    .fill(WisdTheme.divider(colorScheme))
                    .frame(height: 1)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Voz ativa do assistente")
                            .font(.system(size: 13, weight: .medium))
                        Text(voice.activeVoiceSummary)
                            .font(.system(size: 11.5))
                            .foregroundStyle(WisdTheme.muted(colorScheme))
                            .lineLimit(1)
                    }
                    Spacer()
                    WisdSecondaryButton("Selecionar voz", icon: "chevron.up.chevron.down") {
                        showVoiceCatalog.toggle()
                    }
                    .popover(isPresented: $showVoiceCatalog, arrowEdge: .top) {
                        VoiceSelectorPopoverView(voice: voice)
                            .presentationBackground(.clear)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Cadência da fala")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text(String(format: "%.2f×", voice.speechSpeed))
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(WisdTheme.softAccentText)
                    }
                    HStack(spacing: 8) {
                        ForEach([("Lenta", 0.90), ("Natural", 1.00), ("Fluida", 1.08), ("Ágil", 1.18)], id: \.0) { preset in
                            let isCurrent = abs(voice.speechSpeed - preset.1) < 0.03
                            Button(preset.0) {
                                voice.speechSpeed = preset.1
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(isCurrent ? .white : WisdTheme.ink(colorScheme))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(isCurrent ? WisdTheme.accent : WisdTheme.elevated(colorScheme))
                            )
                        }
                        Slider(value: $voice.speechSpeed, in: 0.80...1.25, step: 0.02)
                            .tint(WisdTheme.accent)
                    }
                }

                Toggle("Priorizar voz neural em nuvem (OpenAI HD quando disponível)", isOn: $voice.preferCloudNeuralTTS)
                    .toggleStyle(.switch)

                Rectangle()
                    .fill(WisdTheme.divider(colorScheme))
                    .frame(height: 1)

                // Controles acústicos salvos por voz
                VStack(alignment: .leading, spacing: 8) {
                    let idMgr = voice.orchestrator.identityManager
                    let cfg = idMgr.config
                    HStack {
                        Text("Ajustes Acústicos Individuais (\(cfg.identityId.shortName))")
                            .font(.system(size: 12.5, weight: .semibold))
                        Spacer()
                        Button("Restaurar padrão") {
                            idMgr.resetPreferences(for: cfg.identityId)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WisdTheme.softAccentText)
                    }

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tom: \(String(format: "%+.1f st", cfg.design.toneSemitones))")
                                .font(.system(size: 11))
                            Slider(value: Binding(
                                get: { cfg.design.toneSemitones },
                                set: { v in idMgr.updateConfig { $0.design.toneSemitones = (v * 10.0).rounded() / 10.0 } }
                            ), in: -4.0...4.0, step: 0.2)
                            .tint(WisdTheme.accent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Intensidade metálica: \(Int((cfg.design.metallicIntensity * 100).rounded()))%")
                                .font(.system(size: 11))
                            Slider(value: Binding(
                                get: { cfg.design.metallicIntensity },
                                set: { v in idMgr.updateConfig { $0.design.metallicIntensity = v } }
                            ), in: 0.0...1.0, step: 0.02)
                            .tint(WisdTheme.accent)
                        }
                    }

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ressonância: \(Int((cfg.design.resonance * 100).rounded()))%")
                                .font(.system(size: 11))
                            Slider(value: Binding(
                                get: { cfg.design.resonance },
                                set: { v in idMgr.updateConfig { $0.design.resonance = v } }
                            ), in: 0.0...1.0, step: 0.02)
                            .tint(WisdTheme.accent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Expressividade: \(Int((cfg.design.expressivityAmount * 100).rounded()))%")
                                .font(.system(size: 11))
                            Slider(value: Binding(
                                get: { cfg.design.expressivityAmount },
                                set: { v in
                                    idMgr.updateConfig { next in
                                        next.design.expressivityAmount = v
                                        next.design.expressivity = v < 0.30 ? .subtle : (v > 0.70 ? .warmAndDynamic : .balanced)
                                    }
                                }
                            ), in: 0.0...1.0, step: 0.05)
                            .tint(WisdTheme.accent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Volume: \(Int((cfg.design.outputVolume * 100).rounded()))%")
                                .font(.system(size: 11))
                            Slider(value: Binding(
                                get: { cfg.design.outputVolume },
                                set: { v in idMgr.updateConfig { $0.design.outputVolume = v } }
                            ), in: 0.25...1.50, step: 0.05)
                            .tint(WisdTheme.accent)
                        }
                    }
                }

                Rectangle()
                    .fill(WisdTheme.divider(colorScheme))
                    .frame(height: 1)

                HStack(spacing: 10) {
                    WisdPrimaryButton(
                        voice.isSpeaking ? "Parar prévia" : "Testar voz (\(voice.orchestrator.identityManager.config.identityId.shortName))",
                        icon: voice.isSpeaking ? "stop.fill" : "play.fill"
                    ) {
                        if voice.isSpeaking {
                            voice.stopSpeaking()
                        } else {
                            voice.previewVoice()
                        }
                    }

                    WisdSecondaryButton("Vozes do macOS…", icon: "waveform.badge.plus") {
                        openMacOSSpeechSettings()
                    }
                    Spacer()
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesktopStyle.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(DesktopStyle.line))

            WisdEnterpriseVoiceSettingsCard(workspace: workspace, orchestrator: voice.orchestrator)
        }
    }
}

struct VoiceGenderCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let gender: AgentVoiceGender
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: gender.iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(selected ? WisdTheme.softAccentText : WisdTheme.muted(colorScheme))
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(selected ? WisdTheme.accent.opacity(0.22) : WisdTheme.elevated(colorScheme))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(gender.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WisdTheme.ink(colorScheme))
                    Text(gender == .female ? "Feminina · Marin / Coral" : "Masculina · Cedar / Cove")
                        .font(.system(size: 10.5))
                        .foregroundStyle(WisdTheme.muted(colorScheme))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selected ? WisdTheme.softAccentText : WisdTheme.muted(colorScheme).opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? WisdTheme.accent.opacity(0.15) : (hovered ? WisdTheme.elevated(colorScheme) : WisdTheme.elevated(colorScheme).opacity(0.65)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selected ? WisdTheme.accent.opacity(0.50) : WisdTheme.border(colorScheme), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

struct VoiceSelectorPopoverView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var voice: VoiceController

    var body: some View {
        WisdPopoverShell(
            title: "Voz Natural do Agente",
            subtitle: voice.activeVoiceSummary,
            statusColor: voice.isSpeaking ? Color.blue : WisdTheme.iconAccent,
            width: 360
        ) {
            VStack(alignment: .leading, spacing: 0) {
                WisdPopoverSection("Escolher Gênero") {
                    HStack(spacing: 8) {
                        ForEach(AgentVoiceGender.allCases) { gender in
                            VoiceGenderCard(
                                gender: gender,
                                selected: voice.voiceGender == gender
                            ) {
                                voice.selectedVoiceID = "auto"
                                voice.voiceGender = gender
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
                }

                Rectangle().fill(WisdTheme.divider(colorScheme)).frame(height: 1)

                WisdPopoverSection("Ritmo da Fala") {
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            ForEach([("Lenta", 0.90), ("Natural", 1.00), ("Fluida", 1.08), ("Ágil", 1.18)], id: \.0) { preset in
                                let isCurrent = abs(voice.speechSpeed - preset.1) < 0.03
                                Button(preset.0) {
                                    voice.speechSpeed = preset.1
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(isCurrent ? .white : WisdTheme.ink(colorScheme))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(isCurrent ? WisdTheme.accent : WisdTheme.elevated(colorScheme))
                                )
                            }
                            Spacer()
                            Text(String(format: "%.2f×", voice.speechSpeed))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(WisdTheme.muted(colorScheme))
                        }
                        Slider(value: $voice.speechSpeed, in: 0.80...1.25, step: 0.02)
                            .tint(WisdTheme.accent)
                    }
                    .padding(.horizontal, 14)
                }

                Rectangle().fill(WisdTheme.divider(colorScheme)).frame(height: 1)

                WisdPopoverSection("Identidades & Speakers Neurais") {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(WisdVoicePersona.allCases) { persona in
                                let selected = voice.orchestrator.identityManager.config.identityId == persona && voice.selectedVoiceID == "auto"
                                WisdSelectableRow(
                                    icon: persona.recommendedTimbre == .male ? "person.wave.2" : "person.wave.2.fill",
                                    iconColor: WisdTheme.softAccentText,
                                    title: persona.displayName,
                                    subtitle: persona.subtitle,
                                    selected: selected,
                                    badge: persona.recommendedTimbre == .male ? "Masculina" : "Feminina",
                                    badgeColor: WisdTheme.accent
                                ) {
                                    voice.selectedVoiceID = "auto"
                                    voice.orchestrator.identityManager.selectPersona(persona)
                                }
                            }

                            if voice.orchestrator.supertonicTTS.isReadyOnDisk {
                                Text("Speakers Supertonic-3 (44.1 kHz)")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(WisdTheme.muted(colorScheme))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.top, 8)
                                    .padding(.bottom, 2)

                                ForEach(SupertonicVoicePreset.allCases) { st in
                                    let cfg = voice.orchestrator.identityManager.config
                                    let isSelected = cfg.engineId == .supertonic3 && cfg.speakerId == st.rawValue
                                    WisdSelectableRow(
                                        icon: st.timbre == .male ? "person.wave.2" : "person.wave.2.fill",
                                        iconColor: WisdTheme.softAccentText,
                                        title: st.displayName,
                                        subtitle: "Supertonic-3 ONNX · Flow Matching 44.1kHz",
                                        selected: isSelected,
                                        badge: st.timbre == .male ? "Homem" : "Mulher",
                                        badgeColor: WisdTheme.accent
                                    ) {
                                        voice.selectedVoiceID = "auto"
                                        voice.orchestrator.identityManager.selectSpeaker(st.rawValue)
                                    }
                                }
                            }

                            if voice.orchestrator.kokoroTTS.isReadyOnDisk {
                                Text("Speakers Kokoro-82M (24 kHz)")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(WisdTheme.muted(colorScheme))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.top, 8)
                                    .padding(.bottom, 2)

                                ForEach(KokoroVoicePreset.allCases) { kok in
                                    let cfg = voice.orchestrator.identityManager.config
                                    let isSelected = (cfg.engineId == .kokoro82M || cfg.engineId == .autoLocal) && cfg.speakerId == kok.rawValue
                                    WisdSelectableRow(
                                        icon: kok.timbre == .male ? "person.wave.2" : "person.wave.2.fill",
                                        iconColor: WisdTheme.softAccentText,
                                        title: kok.displayName,
                                        subtitle: "Kokoro-82M ONNX · \(kok.supportedLanguage.shortCode)",
                                        selected: isSelected,
                                        badge: kok.timbre == .male ? "Homem" : "Mulher",
                                        badgeColor: WisdTheme.accent
                                    ) {
                                        voice.selectedVoiceID = "auto"
                                        voice.orchestrator.identityManager.selectSpeaker(kok.rawValue)
                                    }
                                }
                            }

                            if !voice.availablePortugueseVoices.isEmpty {
                                Text("Vozes Apple instaladas neste Mac")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(WisdTheme.muted(colorScheme))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.top, 8)
                                    .padding(.bottom, 2)

                                ForEach(voice.availablePortugueseVoices) { option in
                                    WisdSelectableRow(
                                        icon: option.gender.iconName,
                                        iconColor: option.isEloquence ? WisdTheme.muted(colorScheme) : WisdTheme.softAccentText,
                                        title: option.name,
                                        subtitle: "\(option.gender.displayName) · \(option.language)",
                                        selected: voice.selectedVoiceID == option.id,
                                        badge: option.qualityBadge,
                                        badgeColor: option.isEloquence ? Color.gray : WisdTheme.accent
                                    ) {
                                        voice.selectedVoiceID = option.id
                                        voice.voiceGender = option.gender
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                    }
                    .frame(maxHeight: 245)
                }

                Rectangle().fill(WisdTheme.divider(colorScheme)).frame(height: 1)

                VStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Orbe Horizon")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(WisdTheme.muted(colorScheme))
                        HStack(spacing: 6) {
                            ForEach(CodexOrbPalette.allCases) { palette in
                                let isSel = voice.orbPalette == palette
                                Button {
                                    voice.orbPalette = palette
                                } label: {
                                    CodexHorizonOrbView(
                                        phase: .active,
                                        activity: .listening,
                                        levels: CodexOrbAudioLevels(overall: 0.3, low: 0.3, mid: 0.35, high: 0.25, micLevel: 0.3),
                                        palette: palette,
                                        isMuted: false,
                                        size: 20
                                    )
                                    .padding(3)
                                    .background(Circle().fill(isSel ? WisdTheme.accent.opacity(0.28) : Color.clear))
                                    .overlay(Circle().stroke(isSel ? WisdTheme.accent : Color.clear, lineWidth: 1.5))
                                }
                                .buttonStyle(.plain)
                                .help(palette.displayName)
                            }
                            Spacer()
                        }
                    }

                    Toggle("Sinais sonoros de voz", isOn: $voice.voiceSoundsEnabled)
                        .toggleStyle(.switch)
                        .font(.system(size: 12))

                    Toggle("Voz neural OpenAI HD (se chave conectada)", isOn: $voice.preferCloudNeuralTTS)
                        .toggleStyle(.switch)
                        .font(.system(size: 12))

                    HStack(spacing: 8) {
                        WisdSecondaryButton("Vozes macOS…", icon: "gear") {
                            openMacOSSpeechSettings()
                        }
                        Spacer()
                        WisdPrimaryButton(
                            voice.isSpeaking ? "Parar" : "Testar voz",
                            icon: voice.isSpeaking ? "stop.fill" : "play.fill"
                        ) {
                            if voice.isSpeaking {
                                voice.stopSpeaking()
                            } else {
                                voice.previewVoice()
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
    }
}

private func openMacOSSpeechSettings() {
    let urls = [
        "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?SpokenContent",
        "x-apple.systempreferences:com.apple.preference.universalaccess?Seeing_VoiceOver"
    ]
    for raw in urls {
        if let url = URL(string: raw), NSWorkspace.shared.open(url) {
            return
        }
    }
}

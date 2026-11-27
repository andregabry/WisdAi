import Foundation

@main
struct StateSmoke {
    @MainActor static func main() throws {
        // This executable has its own defaults domain, separate from the desktop app.
        let domain = ProcessInfo.processInfo.processName
        precondition(domain == "WisdAIStateSmoke")
        UserDefaults.standard.removePersistentDomain(forName: domain)
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let local = DesktopLocalData()
        local.aiAccounts = []
        let first = AIAccount(name: "Personal", provider: .claude, cliInstalled: false)
        let second = AIAccount(name: "Work", provider: .claude, cliInstalled: false)
        local.addAccount(first); local.addAccount(second)
        precondition(local.aiAccounts.count == 2)
        var renamed = first; renamed.name = "Renamed"
        local.addAccount(renamed)
        precondition(local.aiAccounts.count == 2 && local.aiAccounts[0].name == "Renamed")
        precondition(local.aiAccounts.allSatisfy { !$0.supportsExecution && $0.models.isEmpty })
        let sessions = [AccountChoice(id: "session-1", label: "personal", active: true, workspaceID: "workspace-1"),
                        AccountChoice(id: "session-2", label: "work", active: false, workspaceID: "workspace-2")]
        local.syncSessions(sessions)
        let active = local.aiAccounts.first { $0.sessionID == "session-1" }!
        local.syncModels(accountID: active.id, models: ["account-1-model"], source: "fixture")
        precondition(local.aiAccounts.first { $0.sessionID == "session-2" }!.models.isEmpty)
        local.syncSessions(Array(sessions.dropFirst()))
        precondition(local.aiAccounts.first { $0.id == active.id }!.supportsExecution == false)
        precondition(local.aiAccounts.first { $0.id == active.id }!.models.isEmpty)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("preserve.txt")
        try "keep".write(to: file, atomically: true, encoding: .utf8)
        var project = ProjectItem(name: "Before", path: folder.path, additionalPaths: [folder.appendingPathComponent("extra").path])
        local.addOrUpdateProject(project)
        project.name = "After"; local.addOrUpdateProject(project)
        precondition(local.projects.filter { $0.id == project.id }.count == 1)
        local.deleteProject(project)
        let preserved = try String(contentsOf: file, encoding: .utf8)
        precondition(preserved == "keep")
        let restored = DesktopLocalData()
        precondition(restored.aiAccounts.filter { $0.provider == .claude }.count == 2)
        precondition(!restored.projects.contains { $0.id == project.id })
        let legacy = AIAccount(name: "Legacy", provider: .deepseek, apiKeyOrToken: "fixture-not-a-real-key")
        do { _ = try JSONEncoder().encode(legacy); preconditionFailure("Plaintext credential was serialized") }
        catch is EncodingError { }
        let clean = try JSONEncoder().encode(first)
        precondition(!String(decoding: clean, as: UTF8.self).contains("apiKeyOrToken"))
        let catalog = try ProviderCatalogClient.parse(Data(#"{"data":[{"id":"b"},{"id":"a"},{"id":"a"}]}"#.utf8))
        precondition(catalog == ["a", "b"])
        let cliCatalog = try ProviderCatalogClient.parseAntigravity(Data("id\tName\ngemini-fixture\tFixture\nAuthentication required\nhttps://example.invalid/secret\tInvalid\n".utf8))
        precondition(cliCatalog == ["gemini-fixture"])
        do { _ = try ProviderCatalogClient.parse(Data("{}".utf8)); preconditionFailure("Invalid catalog accepted") }
        catch CatalogError.invalid { }
        let endpoint = try ProviderCatalogClient.endpoint(for: .nvidia)
        precondition(endpoint.host == "integrate.api.nvidia.com")
        do { _ = try ProviderCatalogClient.endpoint(for: .claude); preconditionFailure("Unsupported endpoint allowed") }
        catch CatalogError.unsupported { }
        let credentialID = UUID()
        try AccountKeychain.save("fixture-not-a-real-credential", accountID: credentialID)
        defer { try? AccountKeychain.delete(accountID: credentialID) }
        let savedKey = try AccountKeychain.read(accountID: credentialID)
        precondition(savedKey == "fixture-not-a-real-credential")
        let redirectURL = URL(string: "https://example.invalid/redirect")!
        let response = HTTPURLResponse(url: endpoint, statusCode: 302, httpVersion: nil, headerFields: nil)!
        var redirectRejected = false
        let task = URLSession.shared.dataTask(with: endpoint)
        ProviderCatalogClient().urlSession(.shared, task: task, willPerformHTTPRedirection: response,
                                          newRequest: URLRequest(url: redirectURL)) { redirectRejected = $0 == nil }
        task.cancel()
        precondition(redirectRejected)

        // In-memory quota store & pre-flight smart routing checks
        let quotaStore = UsageQuotaStore()
        var accGemini = AIAccount(name: "Gemini Main", provider: .gemini, models: ["gemini-4-hydrogen-xhigh", "gemini-3.8-flash-high"], isActive: true)
        var accClaude = AIAccount(name: "Claude Backup", provider: .claude, models: ["claude-sonnet-4-6"], isActive: false)
        quotaStore.markModelLimited(accountID: accGemini.id, modelID: "gemini-4-hydrogen-xhigh", until: Date().addingTimeInterval(300), reason: "Rate limit 429")
        let sameAccountRoute = quotaStore.selectBestRoute(preferredAccount: accGemini, preferredModel: "gemini-4-hydrogen-xhigh", allAccounts: [accGemini, accClaude])
        precondition(sameAccountRoute?.account.id == accGemini.id && sameAccountRoute?.model == "gemini-3.8-flash-high" && sameAccountRoute?.switchedReason != nil)

        quotaStore.markAccountLimited(accountID: accGemini.id, models: accGemini.models, until: Date().addingTimeInterval(600), reason: "Account quota exhausted")
        quotaStore.updateFromHTTPHeaders(accountID: accClaude.id, models: accClaude.models, statusCode: 200, headers: ["x-ratelimit-remaining-requests": "80", "x-ratelimit-limit-requests": "100"], source: "Test")
        let crossAccountRoute = quotaStore.selectBestRoute(preferredAccount: accGemini, preferredModel: "gemini-3.8-flash-high", allAccounts: [accGemini, accClaude])
        precondition(crossAccountRoute?.account.id == accClaude.id && crossAccountRoute?.model == "claude-sonnet-4-6" && crossAccountRoute?.switchedReason != nil)
        precondition(quotaStore.remainingPercent(accountID: accClaude.id, modelID: "claude-sonnet-4-6") == 80)

        var testAccounts = [accGemini, accClaude]
        quotaStore.markAccountLimited(accountID: accGemini.id, models: accGemini.models, until: Date().addingTimeInterval(-5), reason: "Expired")
        let recovered = quotaStore.reconcileExpiredLimits(now: Date(), accounts: &testAccounts)
        precondition(recovered > 0 && quotaStore.availability(accountID: accGemini.id, modelID: "gemini-3.8-flash-high") != .exhausted)
        accGemini = testAccounts[0]
        accClaude = testAccounts[1]
        _ = (accGemini, accClaude)

        // Internal SQLite chat database persistence checks
        let db = ChatStorage(inMemory: true)
        let conv1 = Conversation(id: "sqlite-thread-1", title: "Primeira conversa", cwd: "/tmp/proj1", agyConversationId: "agy-1")
        let conv2 = Conversation(id: "sqlite-thread-2", title: "Segunda conversa", cwd: "/tmp/proj2", agyConversationId: nil)
        db.upsertConversation(conv1)
        db.upsertConversation(conv2)
        db.setLastSelectedThreadId("sqlite-thread-1")
        precondition(db.getLastSelectedThreadId() == "sqlite-thread-1")

        let msgs1 = [
            Message(author: "Você", text: "Olá banco SQLite"),
            Message(author: "WisdAI", text: "Pensamento intermediário", kind: .reasoning, status: "concluído", turnId: "t1", durationSeconds: 1.4, subKind: "thought"),
            Message(author: "WisdAI", text: "Etapas", kind: .plan, status: "concluído", turnId: "t1", steps: [PlanStep(title: "Analisar schema", status: "done")]),
            Message(author: "WisdAI", text: "Tudo salvo com sucesso no banco interno!", kind: .text, turnId: "t1")
        ]
        db.saveMessages(msgs1, for: "sqlite-thread-1")
        db.saveMessages([Message(author: "Você", text: "Mensagem isolada 2")], for: "sqlite-thread-2")

        let loadedConvs = db.loadConversations()
        precondition(loadedConvs.count == 2)
        precondition(loadedConvs.first(where: { $0.id == "sqlite-thread-1" })?.agyConversationId == "agy-1")
        let loaded1 = db.loadMessages(for: "sqlite-thread-1")
        precondition(loaded1.count == 4)
        precondition(loaded1[0].author == "Você" && loaded1[0].text == "Olá banco SQLite")
        precondition(loaded1[1].kind == .reasoning && loaded1[1].durationSeconds == 1.4)
        precondition(loaded1[2].kind == .plan && loaded1[2].steps?.first?.title == "Analisar schema")
        precondition(loaded1[3].text == "Tudo salvo com sucesso no banco interno!")

        db.deleteThread("sqlite-thread-1")
        precondition(db.loadConversations().count == 1)
        precondition(db.loadMessages(for: "sqlite-thread-1").isEmpty)
        precondition(db.loadMessages(for: "sqlite-thread-2").count == 1)

        // Ensure reasoning effort selection is independent from model switching
        let ws = Workspace()
        ws.reasoningLevel = .ultra
        ws.selectedModel = "claude-sonnet-4-6"
        precondition(ws.reasoningLevel == .ultra && ws.selectedEffort == "ultra")

        // Cross-provider model compatibility & dead-CLI fallback checks
        var accOpenAI = AIAccount(name: "ChatGPT", provider: .openai, models: ["gpt-6-astra", "gpt-5.6-sol"], isActive: true)
        accOpenAI.sessionID = "session-openai"
        let accDeadClaude = AIAccount(name: "Claude Missing CLI", provider: .claude, cliInstalled: false, models: ["claude-3-7-sonnet"], isActive: true)
        precondition(!UsageQuotaStore.isModelCompatible("claude-3-7-sonnet", with: accOpenAI))
        precondition(UsageQuotaStore.isModelCompatible("gpt-5.6-sol", with: accOpenAI))

        // Case 1: Active OpenAI account with stale claude-3-7-sonnet must normalize to OpenAI's own model
        let sanitizedOpenAI = quotaStore.selectBestRoute(
            preferredAccount: accOpenAI,
            preferredModel: "claude-3-7-sonnet",
            allAccounts: [accOpenAI, accGemini]
        )
        precondition(sanitizedOpenAI?.account.id == accOpenAI.id && sanitizedOpenAI?.model == "gpt-6-astra")

        // Case 2: Non-executable Claude account must route to next executable account with tokens
        let reroutedFromDeadClaude = quotaStore.selectBestRoute(
            preferredAccount: accDeadClaude,
            preferredModel: "claude-3-7-sonnet",
            allAccounts: [accDeadClaude, accGemini, accOpenAI],
            canExecuteAccount: { $0.id != accDeadClaude.id && $0.supportsExecution }
        )
        precondition(reroutedFromDeadClaude != nil && reroutedFromDeadClaude?.account.id != accDeadClaude.id)
        precondition(UsageQuotaStore.isModelCompatible(reroutedFromDeadClaude!.model, with: reroutedFromDeadClaude!.account))
        _ = accDeadClaude

        // CLI model vs --effort conflict resolution & strict provider model scoping
        precondition(AIProvider.gemini.ownsModel("gemini-3.8-flash-high"))
        precondition(!AIProvider.gemini.ownsModel("claude-opus-4-6-thinking"))
        precondition(!AIProvider.gemini.ownsModel("claude-sonnet-4-6"))
        precondition(!AIProvider.gemini.ownsModel("gpt-oss-120b-medium"))

        let scopedLocal = DesktopLocalData()
        var gAcc = AIAccount(name: "Gemini Scoped", provider: .gemini, isActive: true)
        scopedLocal.addAccount(gAcc)
        scopedLocal.syncModels(accountID: gAcc.id, models: ["claude-opus-4-6-thinking", "claude-sonnet-4-6", "gemini-3.8-flash-high", "gpt-oss-120b-medium"], source: "fixture")
        gAcc = scopedLocal.aiAccounts.first(where: { $0.id == gAcc.id })!
        precondition(gAcc.models == ["gemini-3.8-flash-high"])

        let agyCatalog = ["gemini-3.8-flash-high", "gemini-3.8-flash-medium", "gemini-3.8-flash-low"]
        let tierDefault = Workspace.resolveAgyModelAndEffort(requestedModel: "gemini-3.8-flash-high", accountModels: agyCatalog, selectedEffort: "default", level: .medio)
        precondition(tierDefault.model == "gemini-3.8-flash-high" && tierDefault.effortArg == nil)
        let tierDowngrade = Workspace.resolveAgyModelAndEffort(requestedModel: "gemini-3.8-flash-high", accountModels: agyCatalog, selectedEffort: "low", level: .leve)
        precondition(tierDowngrade.model == "gemini-3.8-flash-low" && tierDowngrade.effortArg == nil)
        let claudeNoEffort = Workspace.resolveAgyModelAndEffort(requestedModel: "claude-opus-4-6-thinking", accountModels: ["claude-opus-4-6-thinking"], selectedEffort: "ultra", level: .ultra)
        precondition(claudeNoEffort.model == "claude-opus-4-6-thinking" && claudeNoEffort.effortArg == nil)
        let autoEffort = Workspace.resolveAgyModelAndEffort(requestedModel: "auto", accountModels: agyCatalog, selectedEffort: "high", level: .alto)
        precondition(autoEffort.model == "auto" && autoEffort.effortArg == "high")

        // Natural voice synthesis helpers & Mulher/Homem gender options
        precondition(AgentVoiceGender.female.displayName == "Mulher" && AgentVoiceGender.female.openAIVoiceName == "nova")
        precondition(AgentVoiceGender.male.displayName == "Homem" && AgentVoiceGender.male.openAIVoiceName == "onyx")

        let cleanedSpeech = VoiceController.cleanForSpeech("""
        ✨ **Pronto!** Veja [notes.md](file:///Users/andregabry/Project/notes.md) e acesse https://example.com/docs.
        ```swift
        let x = 1
        ```
        Tudo compilado em `WisdAI`.
        """)
        precondition(!cleanedSpeech.contains("https://") && !cleanedSpeech.contains("file://") && !cleanedSpeech.contains("let x = 1") && !cleanedSpeech.contains("**"))
        precondition(cleanedSpeech.contains("notes.md") && cleanedSpeech.contains("WisdAI"))

        let longReply = "Primeiro analisamos os arquivos do projeto com calma. Em seguida aplicamos a correção no módulo de voz para soar mais humano! Por fim compilamos tudo sem erros."
        let chunks = VoiceController.splitIntoNaturalSentences(longReply)
        precondition(chunks.count == 3)

        let backupGender = UserDefaults.standard.string(forKey: "wisdcode.voice.gender")
        let backupCodexVoice = UserDefaults.standard.string(forKey: "wisdcode.voice.codexVoice")
        defer {
            if let backupGender {
                UserDefaults.standard.set(backupGender, forKey: "wisdcode.voice.gender")
            } else {
                UserDefaults.standard.removeObject(forKey: "wisdcode.voice.gender")
            }
            if let backupCodexVoice {
                UserDefaults.standard.set(backupCodexVoice, forKey: "wisdcode.voice.codexVoice")
            } else {
                UserDefaults.standard.removeObject(forKey: "wisdcode.voice.codexVoice")
            }
        }
        let voiceCtrl = VoiceController()
        voiceCtrl.voiceGender = .male
        precondition(voiceCtrl.voiceGender == .male && voiceCtrl.activeCodexVoice.id == "cedar")
        voiceCtrl.selectedCodexVoiceID = "coral"
        precondition(voiceCtrl.voiceGender == .female && voiceCtrl.activeCodexVoice.id == "coral")

        let conversationalInstr = Workspace.wrapConversationalVoiceInstruction("oi, me explica esse arquivo", projectName: "WisdAI")
        precondition(conversationalInstr.contains("Assistente de Voz no Chat") && conversationalInstr.contains("oi, me explica esse arquivo"))
        let codexPrompt = Workspace.codexVoiceSystemPrompt(projectName: "WisdAI")
        precondition(codexPrompt.contains("Codex") && !codexPrompt.contains("Siri"))

        // Garante ausência de rótulos Siri no catálogo de vozes exibido ao usuário
        for opt in VoiceController.discoverPortugueseVoices() {
            precondition(!opt.qualityBadge.localizedCaseInsensitiveContains("siri"))
            precondition(!opt.name.localizedCaseInsensitiveContains("siri"))
        }

        // Edição de mensagem já enviada: trunca histórico e mantém apenas contexto até a mensagem editada
        let m1 = Message(author: "Você", text: "Primeira pergunta", turnId: "t1")
        let m2 = Message(author: "WisdAI", text: "Primeira resposta", turnId: "t1")
        let m3 = Message(author: "Você", text: "Segunda pergunta antiga", turnId: "t2")
        let m4 = Message(author: "WisdAI", text: "Segunda resposta antiga", turnId: "t2")
        let m5 = Message(author: "Você", text: "Terceira pergunta", turnId: "t3")
        let history = [m1, m2, m3, m4, m5]

        let editCtx = Workspace.prepareContextForEditedMessage(in: history, messageID: m3.id, newText: "Segunda pergunta corrigida")
        precondition(editCtx != nil)
        precondition(editCtx!.truncatedMessages.count == 2)
        precondition(editCtx!.truncatedMessages.map(\.id) == [m1.id, m2.id])
        precondition(editCtx!.beforeTurnId == "t2")
        precondition(editCtx!.editedTitle == nil)

        let editPrompt = Workspace.buildPriorConversationContextPrompt(priorMessages: editCtx!.priorTextMessages, currentTask: "Segunda pergunta corrigida")
        precondition(editPrompt.contains("Primeira pergunta") && editPrompt.contains("Primeira resposta"))
        precondition(!editPrompt.contains("Segunda resposta antiga") && !editPrompt.contains("Terceira pergunta"))
        precondition(editPrompt.contains("Segunda pergunta corrigida"))

        let firstEditCtx = Workspace.prepareContextForEditedMessage(in: history, messageID: m1.id, newText: "Nova primeira pergunta")
        precondition(firstEditCtx != nil && firstEditCtx!.truncatedMessages.isEmpty && firstEditCtx!.editedTitle == "Nova primeira pergunta")

        // Regra de silêncio sensível ao contexto para evitar cortes prematuros no meio da frase
        precondition(VoiceController.recommendedSilenceDelay(for: "Eu quero que você") == 2.9)
        precondition(VoiceController.recommendedSilenceDelay(for: "Oi, tudo bem?") == 1.65)
        precondition(VoiceController.recommendedSilenceDelay(for: "Analise os arquivos agora") == 2.15)
        precondition(VoiceController.recommendedSilenceDelay(for: "") == 2.5)

        // Paridade 1:1 Codex Voice: prompts, saudação, continuidade JSON, catálogo e estado inicial
        let catalogIds = Set(CodexVoicePreset.catalog.map(\.id))
        precondition(Set(["marin", "coral", "juniper", "breeze", "cedar", "cove", "arbor", "spruce"]).isSubset(of: catalogIds))
        precondition(CodexRealtimePromptCatalog.backendPrompt(userFirstName: "André Gabry", projectName: "WisdAI").contains("You are Codex"))
        precondition(CodexRealtimePromptCatalog.startInstructions.contains("Realtime conversation started"))
        precondition(CodexRealtimePromptCatalog.endInstructions.contains("Realtime conversation ended"))
        precondition(CodexRealtimePromptCatalog.greetingDeveloperMessage(userFirstName: "André").contains("André"))

        let continuityTemp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wisdai-continuity-smoke-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: continuityTemp) }
        let continuityStore = CodexRealtimeContinuityStore(fileURL: continuityTemp)
        continuityStore.recordItem(threadId: "thread-smoke-1", role: "user", text: "Olá Codex")
        continuityStore.recordItem(threadId: "thread-smoke-1", role: "assistant", text: "Oi! Tudo pronto.")
        let reloadedContinuity = continuityStore.loadItems(for: "thread-smoke-1")
        precondition(reloadedContinuity.count == 2)
        precondition(reloadedContinuity[0].role == "user" && reloadedContinuity[0].text == "Olá Codex")
        precondition(reloadedContinuity[1].role == "assistant" && reloadedContinuity[1].text == "Oi! Tudo pronto.")
        let wavHeaderCheck = CodexVoiceAudioCues.makeWAVContainer(pcm16Mono: Data(repeating: 0, count: 64), sampleRate: 16_000, channels: 1)
        precondition(wavHeaderCheck.count == 44 + 64 && String(data: wavHeaderCheck.prefix(4), encoding: .ascii) == "RIFF")
        precondition(voiceCtrl.voicePhase == .inactive && voiceCtrl.voiceActivity == .idle && voiceCtrl.dictationPhase == .idle)

        // Avisos naturais de espera longa e transição na conclusão
        let toolWaitMsg = Workspace.longTaskWaitNoticeText(isToolExecution: true)
        precondition(toolWaitMsg.contains("tempo") && toolWaitMsg.contains("aviso"))
        let thinkWaitMsg = Workspace.longTaskWaitNoticeText(isToolExecution: false)
        precondition(thinkWaitMsg.contains("tempo") && thinkWaitMsg.contains("concluída"))
        let prefReply = Workspace.formatCompletedReplyForSpeech("Arquivo atualizado.", hadWaitNotice: true)
        precondition(prefReply.hasPrefix("Pronto, a tarefa foi concluída.") && prefReply.contains("Arquivo atualizado."))
        let alreadyPrefReply = Workspace.formatCompletedReplyForSpeech("Pronto, terminei tudo.", hadWaitNotice: true)
        precondition(alreadyPrefReply == "Pronto, terminei tudo.")
        let directReply = Workspace.formatCompletedReplyForSpeech("Oi, tudo bem!", hadWaitNotice: false)
        precondition(directReply == "Oi, tudo bem!")

        // Saudação automática inicial e seleção rápida de modelo conversacional em modo voz
        let greetNew = Workspace.buildVoiceActivationGreeting(userFullName: "André Gabry", hasExistingMessages: false, projectName: "WisdAI")
        precondition(greetNew.contains("André") && greetNew.contains("WisdAI"))
        let greetExisting = Workspace.buildVoiceActivationGreeting(userFullName: "André Gabry", hasExistingMessages: true, projectName: nil)
        precondition(greetExisting.contains("André"))
        let gemAcc = AIAccount(
            name: "Gemini",
            provider: .gemini,
            emailOrIdentity: "a@b.com",
            cliInstalled: true,
            models: ["gemini-4-hydrogen-high", "gemini-3.8-flash-low"]
        )
        precondition(Workspace.resolveFastVoiceModelIfConversational(chosenModel: "gemini-4-hydrogen-high", task: "Oi, tudo bem com você?", account: gemAcc) == "gemini-3.8-flash-low")
        precondition(Workspace.resolveFastVoiceModelIfConversational(chosenModel: "gemini-4-hydrogen-high", task: "Analise os arquivos do projeto", account: gemAcc) == "gemini-4-hydrogen-high")

        print("PASS: project edits/removal preserve files; same-provider accounts persist; catalogs stay scoped; revoked sessions blocked; plaintext credentials rejected; catalog parsing validated; real-time in-memory quota routing verified; internal SQLite chat persistence verified; reasoning effort decoupled from model switching; cross-provider model routing & fallback verified; Codex-style Mulher/Homem voice assistant & prosody verified; message editing & truncated context verified; voice silence detection verified; Codex 1:1 WebRTC continuity, prompts & WAV framing verified; minimal orb + chat wait/completion voice flow verified; natural voice greeting + fast conversational routing verified")
    }
}

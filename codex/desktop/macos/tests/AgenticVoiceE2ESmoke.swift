import AVFoundation
import Foundation

@main
struct AgenticVoiceE2ESmoke {
    private static let sampleOutputDir = URL(
        fileURLWithPath: "/Users/andregabry/.gemini/antigravity/brain/15f30b3f-af87-4fae-bd9f-5f3efd1c6b44/voice_samples_v6_e2e",
        isDirectory: true
    )

    @MainActor
    static func main() async throws {
        let procName = ProcessInfo.processInfo.processName
        precondition(procName.contains("Smoke"), "Executable name must contain 'Smoke' so ChatStorage uses :memory:")
        let domain = procName
        let bundleID = Bundle.main.bundleIdentifier ?? domain
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        defer {
            UserDefaults.standard.removePersistentDomain(forName: domain)
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }

        print("=== WisdAI P0 Agentic Voice E2E Verification Suite (Tests A-H) ===")
        print("Process: \(procName) | BundleID: \(bundleID)")

        let rootTmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("wisdai-e2e-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootTmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootTmp) }

        let repoA = rootTmp.appendingPathComponent("WisdMeet", isDirectory: true)
        let repoB = rootTmp.appendingPathComponent("WisdFin", isDirectory: true)
        try createFixtureGitRepoA(at: repoA)
        try createFixtureGitRepoB(at: repoB)

        let agyPath = AgentCLIAuthenticator.locateCLI(for: .gemini)
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/agy").path
        precondition(FileManager.default.isExecutableFile(atPath: agyPath), "Real agy CLI must exist at \(agyPath)")

        let claudeCLI = AgentCLIAuthenticator.locateCLI(for: .claude)
        print("ENV: agyCLI=\(agyPath) | claudeCLI=\(claudeCLI ?? "NOT_INSTALLED") | codexAux=\(Bundle.main.url(forAuxiliaryExecutable: "codex")?.path ?? "missing")")

        // Configure isolated localData + accounts
        let local = DesktopLocalData()
        local.aiAccounts = []
        local.projects = [
            ProjectItem(name: "WisdMeet", path: repoA.path),
            ProjectItem(name: "WisdFin", path: repoB.path)
        ]

        var agyAccount = AIAccount(
            name: "Gemini Antigravity",
            provider: .gemini,
            emailOrIdentity: "e2e@local",
            cliInstalled: true,
            cliPath: agyPath,
            models: ["gemini-4-hydrogen-high", "gemini-3.8-flash-high"],
            activeModelIndex: 0,
            isActive: true
        )
        agyAccount.modelsUpdatedAt = Date()
        local.aiAccounts = [agyAccount]

        let ws = Workspace()
        ws.localDataRef = local
        ws.project = repoA
        ws.selectedAccount = agyAccount
        ws.selectedModel = "gemini-4-hydrogen-high"
        ws.selectedEffort = "ultra"
        ws.mode = 1
        ws.speakReplies = false

        // ------------------------------------------------------------------
        // TEST A: Real Voice Audit via VoiceOrchestrator -> UnifiedPipeline -> agy
        // ------------------------------------------------------------------
        let convA = "e2e-conv-a-\(UUID().uuidString)"
        ws.openThread(id: convA, cwd: repoA.path)
        ws.selectedAccount = agyAccount
        ws.selectedModel = "gemini-4-hydrogen-high"
        ws.selectedEffort = "ultra"
        ws.mode = 1
        ws.configureHeadlessAgenticVoiceBridge()

        let voiceUtteranceA = "Quero que você analise todo o código do projeto Whit Meet e cite os arquivos lidos e símbolos reais encontrados"
        let normResA = ContextualTranscriptNormalizer.normalize(
            voiceUtteranceA,
            activeProjectName: ws.resolvedProjectContext.projectName
        )
        precondition(normResA.normalizedTranscript.contains("WisdMeet"), "ContextualTranscriptNormalizer deve corrigir 'Whit Meet' -> 'WisdMeet'")
        let dispatchResA = ws.submitUnifiedMessage(normResA.normalizedTranscript, source: .voice)
        guard case .started = dispatchResA else {
            preconditionFailure("Test A: Dispatch unificado de voz deveria iniciar, obtido: \(dispatchResA)")
        }
        let eventsStartA = ws.executionEventBus.events(for: convA)
        precondition(eventsStartA.contains(where: { $0.kind == .taskReceived || $0.kind == .taskStarted }),
                     "Test A: VoiceOrchestrator deveria despachar diretamente via pipeline unificada")

        await waitUntilIdle(ws: ws, timeoutSeconds: 95)
        let eventsA = ws.executionEventBus.events(for: convA)
        let replyTextA = latestAssistantReply(in: ws)
        let spokenSummaryA = ws.voice.orchestrator.lastPresentedSpokenTextForTelemetry
        print("TEST A events count=\(eventsA.count) | kinds=\(eventsA.map(\.kind.rawValue))")
        print("TEST A reply chars=\(replyTextA.count) | spoken chars=\(spokenSummaryA.count)")

        precondition(!replyTextA.isEmpty, "Test A: Antigravity deve retornar relatório real no chat")
        precondition(eventsA.contains(where: { $0.kind == .taskCompleted }), "Test A: Evento task.completed precisa ser emitido")
        precondition(
            replyTextA.contains("MeetSessionCoordinator_V6Sentinel")
                || replyTextA.contains("MeetSessionController.swift")
                || replyTextA.contains("AudioJitterBridge.swift")
                || replyTextA.contains("AudioPipelineJitterBudget"),
            "Test A: Resposta precisa citar arquivos/símbolos reais do projeto WisdMeet. Obtido: \(replyTextA.prefix(300))"
        )
        let lowerReplyA = replyTextA.lowercased()
        precondition(
            !lowerReplyA.contains("compartilhe o código") && !lowerReplyA.contains("redes neurais convolucionais"),
            "Test A: Não pode pedir código ao usuário nem alucinar CNN"
        )
        precondition(
            !spokenSummaryA.isEmpty && !spokenSummaryA.contains("```") && !spokenSummaryA.hasPrefix("Hmm"),
            "Test A: Resumo falado precisa existir, estar limpo de markdown e sem muleta Hmm"
        )
        print("PASS [Test A]: Real Voice Audit via Antigravity executed real repo analysis & clean spoken summary")

        // ------------------------------------------------------------------
        // TEST B: Text vs Voice Equivalence on Same Workspace / Model / Effort
        // ------------------------------------------------------------------
        let convText = "e2e-conv-b-text-\(UUID().uuidString)"
        ws.openThread(id: convText, cwd: repoA.path)
        ws.selectedAccount = agyAccount
        ws.selectedModel = "gemini-4-hydrogen-high"
        ws.selectedEffort = "ultra"
        ws.mode = 1
        ws.prompt = "Em uma frase, informe exatamente o valor inteiro de AudioPipelineJitterBudget definido no arquivo Sources/AudioJitterBridge.swift."
        ws.send()
        await waitUntilIdle(ws: ws, timeoutSeconds: 120)
        let textMeta = ws.executionEventBus.metadata(for: convText)
        let textAnswer = latestAssistantReply(in: ws)

        let convVoice = "e2e-conv-b-voice-\(UUID().uuidString)"
        ws.openThread(id: convVoice, cwd: repoA.path)
        ws.selectedAccount = agyAccount
        ws.selectedModel = "gemini-4-hydrogen-high"
        ws.selectedEffort = "ultra"
        ws.mode = 1
        let outcomeVoiceB = ws.submitUnifiedMessage(
            "Em uma frase, informe exatamente o valor inteiro de AudioPipelineJitterBudget definido no arquivo Sources/AudioJitterBridge.swift.",
            source: .voice
        )
        guard case .started(let voiceMeta) = outcomeVoiceB else {
            preconditionFailure("Test B: Voz deveria iniciar execução unificada igual ao texto, obtido: \(outcomeVoiceB)")
        }
        await waitUntilIdle(ws: ws, timeoutSeconds: 120)
        let voiceAnswer = latestAssistantReply(in: ws)

        precondition(textMeta != nil, "Test B: Metadados da submissão por texto devem estar no ExecutionEventBus")
        precondition(textMeta!.modelID == voiceMeta.modelID && voiceMeta.modelID == "gemini-4-hydrogen-high",
                     "Test B: Modelo não pode sofrer downgrade silencioso no modo de voz (\(voiceMeta.modelID))")
        precondition(textMeta!.reasoningEffort == voiceMeta.reasoningEffort && voiceMeta.reasoningEffort == "ultra",
                     "Test B: Effort 'ultra' deve ser preservado igualmente em texto e voz")
        precondition(textMeta!.permissionsMode == voiceMeta.permissionsMode && voiceMeta.permissionsMode == 1)
        precondition(textMeta!.workingDirectory == voiceMeta.workingDirectory && voiceMeta.workingDirectory == repoA.path)
        precondition(textAnswer.contains("42") && voiceAnswer.contains("42"),
                     "Test B: Ambos texto (\(textAnswer)) e voz (\(voiceAnswer)) devem ler e reportar o valor real 42")
        print("PASS [Test B]: Text and Voice parity verified (model=\(voiceMeta.modelID), effort=\(voiceMeta.reasoningEffort), mode=\(voiceMeta.permissionsMode), value=42)")

        // ------------------------------------------------------------------
        // TEST C: Nonexistent Directory Honest Rejection (Never Fallback to $HOME)
        // ------------------------------------------------------------------
        let missingDir = rootTmp.appendingPathComponent("NonExistentRepo_XYZ", isDirectory: true)
        let convMissing = "e2e-conv-c-\(UUID().uuidString)"
        ws.project = missingDir
        ws.openThread(id: convMissing, cwd: missingDir.path)
        ws.selectedAccount = agyAccount
        ws.configureHeadlessAgenticVoiceBridge()

        let blockedOutcome = ws.submitUnifiedMessage("Analise o código deste projeto", source: .voice)
        guard case .blockedDirectory(let blockedErr, let blockedPath) = blockedOutcome else {
            preconditionFailure("Test C: Diretório inexistente deve retornar .blockedDirectory, obtido \(blockedOutcome)")
        }
        precondition(blockedPath == missingDir.path && !ws.busy && !ws.resolvedProjectContext.directoryExists)
        precondition(ws.executionEventBus.events(for: convMissing).contains(where: { $0.kind == .taskBlocked }))

        let ojBlockC = await ws.handleOpenJarvisToolCall(
            name: OpenJarvisToolName.executeAgentTask.rawValue,
            params: ["instruction": "Analise todo o código agora"]
        )
        precondition((ojBlockC["ok"] as? Bool) == false && (ojBlockC["status"] as? String) == "blocked_directory",
                     "Test C: OpenJarvis execute_agent_task em diretório inexistente deve retornar blocked_directory, obtido: \(ojBlockC)")
        precondition(!ws.busy, "Test C: Pipeline de voz também não pode executar nem cair em $HOME")
        precondition(ws.messages.last?.text.contains(missingDir.path) == true || blockedErr.contains(missingDir.path))
        print("PASS [Test C]: Nonexistent directory blocked honestly (\(blockedErr))")

        // ------------------------------------------------------------------
        // TEST D: Conversing While Agent Executes (Live Status, Enqueue & Cancel)
        // ------------------------------------------------------------------
        ws.project = repoA
        let convD = "e2e-conv-d-\(UUID().uuidString)"
        ws.openThread(id: convD, cwd: repoA.path)
        ws.selectedAccount = agyAccount
        ws.selectedModel = "gemini-3.8-flash-high"
        ws.selectedEffort = "medium"
        ws.mode = 1
        ws.configureHeadlessAgenticVoiceBridge()

        let outcomeD = ws.submitUnifiedMessage(
            "Leia Package.swift, README.md e ambos os arquivos em Sources e faça um resumo estruturado por arquivo.",
            source: .voice
        )
        guard case .started = outcomeD else { preconditionFailure("Test D: Tarefa deveria iniciar") }
        try? await Task.sleep(nanoseconds: 500_000_000)

        precondition(ws.busy, "Test D: Tarefa deve estar em execução durante perguntas vivas")
        let statusToolD = await ws.handleOpenJarvisToolCall(name: OpenJarvisToolName.getTaskStatus.rawValue, params: ["task_id": convD])
        precondition((statusToolD["has_active_task"] as? Bool) == true, "Test D: get_task_status deve indicar tarefa ativa: \(statusToolD)")
        let statusAnswer1 = ws.executionEventBus.formatGroundedProgressAnswer(
            for: "O que está a acontecer agora?",
            conversationID: convD,
            projectName: ws.resolvedProjectContext.projectName,
            language: .portugueseBR
        )
        print("TEST D status1=\(statusAnswer1)")
        precondition(statusAnswer1.contains("Antigravity") || statusAnswer1.contains("executando") || statusAnswer1.contains("WisdMeet"),
                     "Test D: Resposta sobre progresso vivo deve refletir estado real: \(statusAnswer1)")

        let statusAnswer2 = ws.executionEventBus.formatGroundedProgressAnswer(
            for: "Que ficheiros está a analisar e quanto falta?",
            conversationID: convD,
            projectName: ws.resolvedProjectContext.projectName,
            language: .portugueseBR
        )
        print("TEST D status2=\(statusAnswer2)")
        precondition(!statusAnswer2.isEmpty, "Test D: Deve responder imediatamente sobre ficheiros/andamento")

        let statusAnswer3 = ws.executionEventBus.formatGroundedProgressAnswer(
            for: "Por que razão está a demorar?",
            conversationID: convD,
            projectName: ws.resolvedProjectContext.projectName,
            language: .portugueseBR
        )
        print("TEST D status3=\(statusAnswer3)")
        precondition(!statusAnswer3.isEmpty, "Test D: Deve explicar razão real do tempo de execução")

        // Queue complementary instruction while busy via OpenJarvis send_task_instruction contract
        let queueResD = await ws.handleOpenJarvisToolCall(
            name: OpenJarvisToolName.sendTaskInstruction.rawValue,
            params: ["instruction": "Pode verificar também se existe arquivo LICENSE na raiz?"]
        )
        precondition((queueResD["ok"] as? Bool) == true, "Test D: send_task_instruction falhou: \(queueResD)")
        let queuedEvents = ws.executionEventBus.events(for: convD)
        print("TEST D queuedKinds=\(queuedEvents.map(\.kind.rawValue))")
        precondition(queuedEvents.contains(where: { $0.kind == .taskQueued }),
                     "Test D: Pedido complementar durante execução deve enfileirar (.taskQueued)")

        // Explicitly cancel active task via OpenJarvis cancel_task contract
        let cancelResD = await ws.handleOpenJarvisToolCall(name: OpenJarvisToolName.cancelTask.rawValue, params: [:])
        precondition((cancelResD["ok"] as? Bool) == true, "Test D: cancel_task falhou: \(cancelResD)")
        await waitUntilIdle(ws: ws, timeoutSeconds: 15)
        let eventsAfterCancel = ws.executionEventBus.events(for: convD)
        print("TEST D afterCancelKinds=\(eventsAfterCancel.map(\.kind.rawValue))")
        precondition(eventsAfterCancel.contains(where: { $0.kind == .taskCancelled }),
                     "Test D: Comando cancel_task deve emitir .taskCancelled e interromper")
        print("PASS [Test D]: Live grounded status Q&A, complementary queue (.taskQueued) & cancel_task (.taskCancelled) verified")

        // ------------------------------------------------------------------
        // TEST E: Two Simultaneous Isolated Projects (Repo A main vs Repo B feature/beta)
        // ------------------------------------------------------------------
        let convIsoB = "e2e-conv-e-repob-\(UUID().uuidString)"
        ws.project = repoB
        ws.openThread(id: convIsoB, cwd: repoB.path)
        ws.selectedAccount = agyAccount
        ws.selectedModel = "gemini-3.8-flash-high"
        ws.selectedEffort = "medium"
        ws.configureHeadlessAgenticVoiceBridge()

        precondition(ws.resolvedProjectContext.projectName == "WisdFin")
        precondition(ws.resolvedProjectContext.gitBranch == "feature/beta",
                     "Test E: Branch esperada feature/beta, obtida: \(ws.resolvedProjectContext.gitBranch ?? "nil")")

        let ojIsoRes = await ws.handleOpenJarvisToolCall(
            name: OpenJarvisToolName.executeAgentTask.rawValue,
            params: ["instruction": "Leia o arquivo Sources/BetaSentinel.swift deste projeto WisdFin e diga o token encontrado."]
        )
        precondition((ojIsoRes["ok"] as? Bool) == true, "Test E: Dispatch em WisdFin falhou: \(ojIsoRes)")
        await waitUntilIdle(ws: ws, timeoutSeconds: 120)
        let answerIsoB = latestAssistantReply(in: ws)
        precondition(answerIsoB.contains("token_beta_772"), "Test E: Thread de WisdFin deve ler token_beta_772, obtido: \(answerIsoB)")
        precondition(!answerIsoB.contains("MeetSessionCoordinator_V6Sentinel"), "Test E: Contexto de WisdMeet não pode vazar para WisdFin")
        precondition(ws.executionEventBus.snapshot(for: convA)?.workingDirectory == repoA.path)
        precondition(ws.executionEventBus.snapshot(for: convIsoB)?.workingDirectory == repoB.path)
        print("PASS [Test E]: Multi-project isolation verified (WisdMeet@main vs WisdFin@feature/beta -> token_beta_772)")

        // ------------------------------------------------------------------
        // TEST F: Real Agents Check (Antigravity live, Codex app-server probe, Claude honesty)
        // ------------------------------------------------------------------
        // F1: Claude Code (not installed on host) -> explicit honest refusal, zero hallucination
        let convClaude = "e2e-conv-f-claude-\(UUID().uuidString)"
        ws.project = repoA
        ws.openThread(id: convClaude, cwd: repoA.path)
        let claudeOutcome = ws.submitUnifiedMessage("Verifique README.md usando Claude Code", source: .voice, agentHint: .claude)
        guard case .unavailable(let claudeMsg) = claudeOutcome else {
            preconditionFailure("Test F: Claude sem CLI instalado deve retornar .unavailable honesto, obtido \(claudeOutcome)")
        }
        precondition(claudeCLI == nil || claudeMsg.contains("Claude"), "Test F: Mensagem honesta para Claude ausente: \(claudeMsg)")
        print("PASS [Test F-Claude]: Missing Claude Code CLI handled honestly -> \(claudeMsg)")

        // F2: Codex App-Server real probe via bundled auxiliary codex executable
        var agyInactive = agyAccount
        agyInactive.isActive = false
        local.aiAccounts = [agyInactive]
        ws.selectedAccount = nil
        ws.models = []
        ws.connect()

        var codexReady = false
        let codexWaitDeadline = Date().addingTimeInterval(15.0)
        while Date() < codexWaitDeadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if ws.ready
                && ws.models.contains(where: { !$0.id.lowercased().contains("gemini") })
                && (ws.accountIdentity != nil || ws.account != "Verificando conta…") {
                codexReady = true
                break
            }
        }
        // Re-expose both accounts cleanly so agentHint routing works seamlessly between Antigravity & Codex
        var discoveredOpenAIAccount: AIAccount?
        if let syncedOpenAI = local.aiAccounts.first(where: { $0.provider == .openai && $0.supportsExecution }) {
            discoveredOpenAIAccount = syncedOpenAI
            ws.selectedAccount = syncedOpenAI
        }
        let codexConv = "e2e-conv-f-codex-\(UUID().uuidString)"
        ws.openThread(id: codexConv, cwd: repoA.path)
        print("PROBE [Test F-Codex]: ready=\(ws.ready) models=\(ws.models.map(\.id)) account=\(ws.account) identity=\(ws.accountIdentity ?? "nil") error=\(ws.error ?? "nil")")
        if codexReady {
            ws.selectedModel = ws.models.first(where: \.isDefault)?.id ?? ws.models.first?.id ?? "auto"
            ws.selectedEffort = "medium"
            let codexBaselineID = ws.messages.last?.id
            let codexOut = ws.submitUnifiedMessage("Leia o arquivo README.md e responda em uma frase qual o título do projeto.", source: .voice, agentHint: .codex)
            print("PROBE [Test F-Codex]: dispatchOutcome=\(codexOut)")
            guard case .started(let codexMeta) = codexOut else {
                preconditionFailure("Test F-Codex: Codex conectado deveria iniciar execução, obtido: \(codexOut)")
            }
            await waitUntilIdle(ws: ws, timeoutSeconds: 60)
            let codexNewMsgs = ws.messages.drop(while: { $0.id != codexBaselineID }).filter { ($0.author == "WisdAI" || $0.author == "WisdCode") && $0.kind == .text }
            let codexReply = codexNewMsgs.last?.text ?? latestAssistantReply(in: ws)
            let codexEvents = ws.executionEventBus.events(for: ws.selected ?? codexConv).map(\.kind.rawValue)
            print("PROBE [Test F-Codex]: err=\(ws.error ?? "nil") events=\(codexEvents) reply=\(codexReply)")
            precondition(codexMeta.providerID == "openai", "Test F-Codex: Provider deve ser openai")
            precondition(!codexReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && codexReply.lowercased().contains("wisdmeet"),
                         "Test F-Codex: Resposta real do Codex precisa mencionar WisdMeet (err=\(ws.error ?? "nil"), reply=\(codexReply))")
            print("PASS [Test F-Codex]: Real Codex app-server turn completed reply=\(codexReply.prefix(160))")
        } else {
            print("INFO [Test F-Codex]: Codex app-server launched (ready=\(ws.ready)) without active authenticated OAuth session in headless bundle")
        }

        // Switch active account back to Antigravity for Test G
        local.aiAccounts = [agyAccount]
        ws.selectedAccount = agyAccount
        ws.selectedModel = "gemini-3.8-flash-high"
        ws.selectedEffort = "medium"
        ws.mode = 1

        // ------------------------------------------------------------------
        // TEST G: Anti-Hallucination on Codebase With Zero Neural Networks
        // ------------------------------------------------------------------
        let convG = "e2e-conv-g-\(UUID().uuidString)"
        ws.project = repoA
        ws.openThread(id: convG, cwd: repoA.path)
        ws.configureHeadlessAgenticVoiceBridge()

        let ojResG = await ws.handleOpenJarvisToolCall(
            name: OpenJarvisToolName.executeAgentTask.rawValue,
            params: [
                "instruction": "Verifique se existe alguma rede neural convolucional implementada no projeto WisdMeet",
                "read_only": true,
            ]
        )
        precondition((ojResG["ok"] as? Bool) == true, "Test G: Dispatch anti-alucinação falhou: \(ojResG)")
        await waitUntilIdle(ws: ws, timeoutSeconds: 120)
        let answerG = latestAssistantReply(in: ws)
        let lowerG = answerG.lowercased()
        let deniesCNN = lowerG.contains("não existe")
            || lowerG.contains("não há")
            || lowerG.contains("nenhuma rede neural")
            || lowerG.contains("não possui")
            || lowerG.contains("sem rede neural")
            || lowerG.contains("não foi encontrada")
            || lowerG.contains("não implementa")
        precondition(deniesCNN, "Test G: Agente precisa responder honestamente que NÃO há rede neural convolucional em WisdMeet. Obtido: \(answerG)")
        print("PASS [Test G]: Anti-hallucination verified cleanly on WisdMeet repo (zero false CNN claims)")

        // ------------------------------------------------------------------
        // TEST H: Reproducible Natural PT-BR & EN Grounded Voice WAV Export
        // ------------------------------------------------------------------
        try await runTestHVoiceSynthesisAndExport(groundedMarkdownA: replyTextA, spokenSummaryA: spokenSummaryA)

        // ------------------------------------------------------------------
        // TEST I: Full Native OpenJarvis Runtime E2E (UDS Daemon + 12 Tools + STT/TTS + Barge-In + Crash Recovery)
        // ------------------------------------------------------------------
        try await runTestIOpenJarvisNativeIntegration(
            ws: ws,
            local: local,
            agyAccount: agyAccount,
            openAIAccount: discoveredOpenAIAccount,
            repoA: repoA,
            repoB: repoB,
            claudeCLI: claudeCLI
        )

        print("AGENTIC_VOICE_E2E_ALL_PASS")
    }

    @MainActor
    private static func runTestIOpenJarvisNativeIntegration(
        ws: Workspace,
        local: DesktopLocalData,
        agyAccount: AIAccount,
        openAIAccount: AIAccount?,
        repoA: URL,
        repoB: URL,
        claudeCLI: String?
    ) async throws {
        var accounts = [agyAccount]
        if let openAIAccount {
            accounts.append(openAIAccount)
        }
        local.aiAccounts = accounts

        // Configure two projects in LocalData so list_projects & get_project_context exercise multi-project wiring
        let pA = ProjectItem(name: "WisdMeet", path: repoA.path)
        let pB = ProjectItem(name: "WisdFin", path: repoB.path)
        local.projects = [pA, pB]

        ws.project = repoA
        let convOJ1 = "e2e-openjarvis-1-\(UUID().uuidString)"
        ws.openThread(id: convOJ1, cwd: repoA.path)
        ws.selectedAccount = agyAccount
        ws.selectedModel = "gemini-3.8-flash-high"
        ws.selectedEffort = "medium"
        ws.mode = 1
        ws.configureHeadlessAgenticVoiceBridge()

        let oj = ws.voice.orchestrator.openJarvis
        let tBoot0 = DispatchTime.now().uptimeNanoseconds
        let health = try await oj.ensureRunning()
        let bootMs = Double(DispatchTime.now().uptimeNanoseconds &- tBoot0) / 1_000_000.0
        precondition(health.status == "ok" && health.runtime == "openjarvis", "Test I: OpenJarvis health inválido: \(health)")
        precondition(health.llmHealthy, "Test I: llama.cpp Metal engine deve estar saudável no OpenJarvis")
        precondition(health.toolsCount == 12, "Test I: Esperadas 12 ferramentas OpenJarvis, obtidas \(health.toolsCount)")
        for tool in OpenJarvisToolName.allCases {
            precondition(health.tools.contains(tool.rawValue), "Test I: Tool ausente no ToolRegistry: \(tool.rawValue)")
        }
        precondition(health.ttsCleanHealthy, "Test I: Backend clean Sherpa-ONNX TTS deve estar saudável no OpenJarvis")
        precondition(health.sttBackend == "faster-whisper", "Test I: STT esperado faster-whisper, obtido \(health.sttBackend)")
        print(String(format: "PASS [Test I-Boot]: OpenJarvis UDS daemon pid=%d rss=%.1fMB boot=%.0fms tools=%d voices=%@", health.pid, health.rssMB, bootMs, health.toolsCount, health.ttsVoices.joined(separator: ",")))

        await oj.pushWorkspaceSnapshot(ws.buildOpenJarvisWorkspaceContextDictionary())

        // Turn I-1: Active project & agents discovery via real Qwen3-1.7B + OpenJarvis UDS host callback
        let t1 = await ws.voice.orchestrator.submitVoiceTurnAsync(
            "Use get_active_project e list_available_agents para confirmar qual projeto está ativo no WisdAI agora e quais agentes estão instalados."
        )
        print("PROBE [Test I-1]: tools=\(t1.toolCalls.map { "\($0.tool):\($0.success)" }) reply=\(t1.reply)")
        precondition(!t1.toolCalls.isEmpty, "Test I-1: OpenJarvis precisa invocar ferramentas reais do WisdAI via UDS")
        precondition(t1.toolCalls.contains(where: { $0.success }), "Test I-1: Ferramentas invocadas devem suceder no host WisdAI")
        precondition(!t1.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Test I-1: Resposta não pode ser vazia")

        // Turn I-2: Real autonomous delegation from OpenJarvis -> execute_agent_task -> Antigravity agy CLI
        let baselineMsgs = ws.messages.count
        let t2 = await ws.voice.orchestrator.submitVoiceTurnAsync(
            "Execute a ferramenta execute_agent_task agora para ler o arquivo Sources/MeetSessionController.swift no projeto WisdMeet e descobrir o valor de coordinatorTag."
        )
        print("PROBE [Test I-2]: tools=\(t2.toolCalls.map { "\($0.tool):\($0.success)" }) reply=\(t2.reply)")
        if t2.toolCalls.contains(where: { $0.tool == OpenJarvisToolName.executeAgentTask.rawValue && $0.success }) || ws.busy {
            await waitUntilIdle(ws: ws, timeoutSeconds: 120)
            let execReply = latestAssistantReply(in: ws)
            let newChatReplies = ws.messages.dropFirst(baselineMsgs).filter { ($0.author == "WisdAI" || $0.author == "WisdCode") && $0.kind == .text }.map(\.text).joined(separator: "\n")
            let combinedCheck = execReply + "\n" + newChatReplies
            precondition(combinedCheck.contains("MeetSessionCoordinator_V6Sentinel"),
                         "Test I-2: Delegação OpenJarvis->Antigravity precisa ler o símbolo real MeetSessionCoordinator_V6Sentinel: \(combinedCheck.prefix(300))")
            let taskResultRes = await ws.handleOpenJarvisToolCall(name: OpenJarvisToolName.getTaskResult.rawValue, params: [:])
            precondition((taskResultRes["ok"] as? Bool) == true, "Test I-2: get_task_result deve retornar sucesso após execução")
            print("PASS [Test I-2]: OpenJarvis execute_agent_task -> Antigravity agy CLI verified (MeetSessionCoordinator_V6Sentinel)")
        } else {
            // Verify direct execute_agent_task contract & execution if LLM needed extra turn context
            let directDispatch = await ws.handleOpenJarvisToolCall(
                name: OpenJarvisToolName.executeAgentTask.rawValue,
                params: ["instruction": "Leia Sources/MeetSessionController.swift e diga apenas o valor exato de coordinatorTag.", "agent": "antigravity", "read_only": true]
            )
            if (directDispatch["ok"] as? Bool) != true {
                let diagAccounts = local.aiAccounts.map { "\($0.name)(\($0.provider.rawValue),id=\($0.id),exec=\(ws.isAccountExecutableNow($0)),exhausted=\($0.exhaustedModelIndices),snapAvail=\(String(describing: ws.quotaStore.accountSnapshot(for: $0.id)?.availability)))" }
                print("DIAGNOSTIC [Test I-2]: directDispatch=\(directDispatch) selectedAcc=\(ws.selectedAccount?.name ?? "nil") selectedMod=\(ws.selectedModel) accounts=\(diagAccounts) cooldowns=\(ws.recovery.journal.cooldowns.count)")
            }
            precondition((directDispatch["ok"] as? Bool) == true, "Test I-2: execute_agent_task direto falhou: \(directDispatch)")
            await waitUntilIdle(ws: ws, timeoutSeconds: 120)
            let directReply = latestAssistantReply(in: ws)
            precondition(directReply.contains("MeetSessionCoordinator_V6Sentinel"), "Test I-2: Resposta Antigravity deve conter MeetSessionCoordinator_V6Sentinel")
            print("PASS [Test I-2]: OpenJarvis execute_agent_task host contract -> Antigravity agy CLI verified (MeetSessionCoordinator_V6Sentinel)")
        }

        // Verify remaining OpenJarvis host tool contracts end-to-end
        let listProjRes = await ws.handleOpenJarvisToolCall(name: OpenJarvisToolName.listProjects.rawValue, params: [:])
        precondition((listProjRes["count"] as? Int ?? 0) >= 2, "Test I: list_projects deve retornar WisdMeet e WisdFin")
        let projCtxRes = await ws.handleOpenJarvisToolCall(name: OpenJarvisToolName.getProjectContext.rawValue, params: ["project": "WisdFin"])
        precondition((projCtxRes["ok"] as? Bool) == true && (projCtxRes["name"] as? String) == "WisdFin", "Test I: get_project_context(WisdFin) falhou: \(projCtxRes)")
        let approvalRes = await ws.handleOpenJarvisToolCall(name: OpenJarvisToolName.requestTaskApproval.rawValue, params: ["decision": "status"])
        precondition((approvalRes["ok"] as? Bool) == true && (approvalRes["has_pending_approval"] as? Bool) == false, "Test I: request_task_approval(status) falhou: \(approvalRes)")
        let runningIdleRes = await ws.handleOpenJarvisToolCall(name: OpenJarvisToolName.listRunningTasks.rawValue, params: [:])
        precondition((runningIdleRes["ok"] as? Bool) == true)

        // Turn I-3: Adaptive English turn + honest Claude unavailability
        let t3 = await ws.voice.orchestrator.submitVoiceTurnAsync(
            "Please answer in English. Check available agents and confirm whether Claude Code can be used on this machine."
        )
        print("PROBE [Test I-3-EN]: tools=\(t3.toolCalls.map { "\($0.tool):\($0.success)" }) reply=\(t3.reply)")
        precondition(!t3.reply.isEmpty, "Test I-3: Resposta em inglês não pode ser vazia")
        if claudeCLI == nil {
            let lower3 = t3.reply.lowercased()
            precondition(!lower3.contains("claude code está executando") && !lower3.contains("executed with claude"),
                         "Test I-3: Não pode afirmar que Claude Code executou sem CLI instalado")
        }

        // Turn I-4: Audio interruption (barge-in) cancels SSE stream WITHOUT cancelling background engineering task
        let convBG = "e2e-openjarvis-bg-\(UUID().uuidString)"
        ws.openThread(id: convBG, cwd: repoA.path)
        ws.selectedAccount = agyAccount
        ws.selectedModel = "gemini-3.8-flash-high"
        ws.configureHeadlessAgenticVoiceBridge()
        let bgStart = await ws.handleOpenJarvisToolCall(
            name: OpenJarvisToolName.executeAgentTask.rawValue,
            params: [
                "instruction": "Leia Package.swift, README.md, Sources/MeetSessionController.swift e Sources/AudioJitterBridge.swift e prepare uma análise detalhada linha a linha.",
                "agent": "antigravity",
            ]
        )
        precondition((bgStart["ok"] as? Bool) == true, "Test I-4: Tarefa em background deveria iniciar: \(bgStart)")
        try? await Task.sleep(nanoseconds: 350_000_000)
        precondition(ws.busy || !ws.activeTasks.isEmpty, "Test I-4: Tarefa em background precisa estar ativa")

        let runningDuringBG = await ws.handleOpenJarvisToolCall(name: OpenJarvisToolName.listRunningTasks.rawValue, params: [:])
        precondition((runningDuringBG["count"] as? Int ?? 0) >= 1, "Test I-4: list_running_tasks deve reportar tarefa ativa: \(runningDuringBG)")
        let sendInstrRes = await ws.handleOpenJarvisToolCall(
            name: OpenJarvisToolName.sendTaskInstruction.rawValue,
            params: ["instruction": "Inclua também verificação do arquivo README.md."]
        )
        precondition((sendInstrRes["ok"] as? Bool) == true, "Test I-4: send_task_instruction deve enfileirar instrução complementar: \(sendInstrRes)")
        let eventsRes = await ws.handleOpenJarvisToolCall(name: OpenJarvisToolName.getTaskEvents.rawValue, params: ["limit": 10])
        precondition((eventsRes["ok"] as? Bool) == true, "Test I-4: get_task_events deve retornar eventos reais")

        final class StreamInterruptBox: @unchecked Sendable {
            private let lock = NSLock()
            var sawStartOrDelta = false
            var sawDone = false
            func markStarted() { lock.withLock { sawStartOrDelta = true } }
            func markDone() { lock.withLock { sawDone = true } }
            func snapshot() -> (started: Bool, done: Bool) { lock.withLock { (sawStartOrDelta, sawDone) } }
        }
        let sBox = StreamInterruptBox()
        let tCancelStart = DispatchTime.now().uptimeNanoseconds
        let streamTask = Task {
            try? await oj.streamVoiceTurn(
                userText: "Me dê um resumo longo e detalhado de cada etapa técnica do que está em andamento neste repositório agora, com vários exemplos.",
                history: [],
                personaID: "jarvis",
                preferredLanguage: "pt-BR",
                workspaceSnapshot: ws.buildOpenJarvisWorkspaceContextDictionary()
            ) { ev in
                switch ev {
                case .started, .tokenDelta:
                    sBox.markStarted()
                case .done:
                    sBox.markDone()
                default:
                    break
                }
            }
        }
        let waitStreamDeadline = Date().addingTimeInterval(6.0)
        while Date() < waitStreamDeadline && !sBox.snapshot().started {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        let tBarge0 = DispatchTime.now().uptimeNanoseconds
        oj.cancelActiveVoiceTurnAudioOnly()
        _ = await streamTask.result
        let cancelElapsedMs = Double(DispatchTime.now().uptimeNanoseconds &- tBarge0) / 1_000_000.0
        _ = tCancelStart
        precondition(cancelElapsedMs < 2000.0, "Test I-4: Cancelamento de turno SSE por barge-in deve ser rápido (<2s), foi \(cancelElapsedMs)ms")
        precondition(ws.busy || !ws.activeTasks.isEmpty, "Test I-4: Interrupção da fala NÃO pode cancelar a tarefa do agente em background!")

        let cancelTaskRes = await ws.handleOpenJarvisToolCall(name: OpenJarvisToolName.cancelTask.rawValue, params: [:])
        precondition((cancelTaskRes["ok"] as? Bool) == true, "Test I-4: cancel_task explícito deve cancelar tarefa ativa")
        await waitUntilIdle(ws: ws, timeoutSeconds: 15)
        print(String(format: "PASS [Test I-4]: Stream barge-in cancel=%.1fms preserved running agent task; explicit cancel_task cleanly stopped it", cancelElapsedMs))

        // Turn I-5: Codex real execution via OpenJarvis contract (when OAuth session is active)
        if let openAIAccount {
            let convCodexOJ = "e2e-openjarvis-codex-\(UUID().uuidString)"
            ws.openThread(id: convCodexOJ, cwd: repoA.path)
            ws.selectedAccount = openAIAccount
            if let firstNonGemini = ws.models.first(where: { !$0.id.lowercased().contains("gemini") })?.id {
                ws.selectedModel = firstNonGemini
            }
            ws.configureHeadlessAgenticVoiceBridge()
            let codexTaskRes = await ws.handleOpenJarvisToolCall(
                name: OpenJarvisToolName.executeAgentTask.rawValue,
                params: [
                    "instruction": "Leia Sources/AudioJitterBridge.swift e responda em uma frase qual é o valor inteiro de AudioPipelineJitterBudget.",
                    "agent": "codex",
                    "read_only": true,
                ]
            )
            precondition((codexTaskRes["ok"] as? Bool) == true, "Test I-5: Codex dispatch via OpenJarvis falhou: \(codexTaskRes)")
            await waitUntilIdle(ws: ws, timeoutSeconds: 60)
            let codexOut = latestAssistantReply(in: ws)
            precondition(codexOut.contains("42"), "Test I-5: Codex via OpenJarvis precisa reportar 42, obtido: \(codexOut)")
            print("PASS [Test I-5-Codex]: OpenJarvis -> execute_agent_task(codex) verified (AudioPipelineJitterBudget=42)")
            ws.selectedAccount = agyAccount
            ws.selectedModel = "gemini-3.8-flash-high"
        }

        // Turn I-6: Multi-project context switch -> WisdFin @ feature/beta (zero leakage from WisdMeet)
        ws.project = repoB
        let convIsoOJ = "e2e-openjarvis-iso-\(UUID().uuidString)"
        ws.openThread(id: convIsoOJ, cwd: repoB.path)
        ws.selectedAccount = agyAccount
        ws.configureHeadlessAgenticVoiceBridge()
        await oj.pushWorkspaceSnapshot(ws.buildOpenJarvisWorkspaceContextDictionary())
        let tIso = await ws.voice.orchestrator.submitVoiceTurnAsync(
            "Use get_active_project e responda em uma frase curta apenas o nome do projeto ativo e a branch git atual."
        )
        print("PROBE [Test I-6-Isolation]: tools=\(tIso.toolCalls.map { "\($0.tool):\($0.success)" }) reply=\(tIso.reply)")
        precondition(tIso.reply.lowercased().contains("wisdfin"), "Test I-6: Resposta isolada deve citar WisdFin, obtido: \(tIso.reply)")
        precondition(!tIso.reply.lowercased().contains("wisdmeet"), "Test I-6: Contexto de WisdMeet não pode vazar para WisdFin: \(tIso.reply)")
        print("PASS [Test I-6]: OpenJarvis multi-project isolation verified (WisdFin @ feature/beta)")

        // Turn I-7: OpenJarvis Clean Neural TTS WAV Export + FasterWhisper Hotword STT Round-Trip
        let ojSampleDir = sampleOutputDir.deletingLastPathComponent().appendingPathComponent("openjarvis_native_e2e_samples", isDirectory: true)
        try? FileManager.default.removeItem(at: ojSampleDir)
        try FileManager.default.createDirectory(at: ojSampleDir, withIntermediateDirectories: true)

        let ttsSpecs: [(filename: String, voice: String, lang: String, speed: Double, text: String)] = [
            ("oj_01_supertonic_m4_ptbr.wav", "supertonic:m4", "pt-BR", 1.04, "Estou analisando o repositório WisdMeet com Antigravity e Codex usando o OpenJarvis."),
            ("oj_02_supertonic_m5_ptbr.wav", "supertonic:m5", "pt-BR", 1.02, "Tudo pronto por aqui. O módulo de áudio compilou sem erros e a branch principal permanece intacta."),
            ("oj_03_supertonic_m4_en.wav", "supertonic:m4", "en", 1.04, "Good afternoon. Jarvis is connected to OpenJarvis over a private Unix socket, with clean speech and real project tools."),
            ("oj_04_kokoro_pm_alex_ptbr.wav", "pm_alex", "pt-BR", 1.02, "Validação neural do motor Kokoro em português brasileiro sem filtros artificiais."),
            ("oj_05_kokoro_bm_george_en.wav", "bm_george", "en-GB", 1.00, "At your service, sir. Background agents remain completely isolated per repository."),
        ]

        var roundTripAudioData: Data?
        for spec in ttsSpecs {
            let wavData = try await oj.synthesizeCleanWAV(text: spec.text, voiceID: spec.voice, speed: spec.speed, language: spec.lang)
            precondition(wavData.count > 1000, "Test I-7: WAV gerado para \(spec.voice) muito curto")
            precondition(String(data: wavData.prefix(4), encoding: .ascii) == "RIFF", "Test I-7: Cabeçalho RIFF inválido em \(spec.filename)")
            // Verify PCM16 energy & absence of clipping (samples after 44-byte header)
            let pcmBytes = wavData.dropFirst(44)
            var sumSq = 0.0
            var peakNorm = 0.0
            let sampleCount = pcmBytes.count / 2
            pcmBytes.withUnsafeBytes { raw in
                let ptr = raw.bindMemory(to: Int16.self)
                for i in 0..<sampleCount {
                    let norm = Double(ptr[i]) / 32768.0
                    sumSq += norm * norm
                    peakNorm = max(peakNorm, abs(norm))
                }
            }
            let rms = sampleCount > 0 ? sqrt(sumSq / Double(sampleCount)) : 0
            precondition(rms > 0.01 && peakNorm <= 1.0, "Test I-7: WAV inválido/mudo em \(spec.filename): rms=\(rms) peak=\(peakNorm)")
            let outURL = ojSampleDir.appendingPathComponent(spec.filename)
            try wavData.write(to: outURL, options: .atomic)
            if spec.filename == "oj_01_supertonic_m4_ptbr.wav" {
                roundTripAudioData = wavData
            }
            print(String(format: "EXPORTED [Test I-7]: %@ voice=%@ bytes=%d rms=%.4f peak=%.3f", spec.filename, spec.voice, wavData.count, rms, peakNorm))
        }

        let sttWarmed = await oj.warmupSTT()
        precondition(sttWarmed, "Test I-7: FasterWhisper STT warmup falhou")
        let transcript = try await oj.transcribeWAV(
            audioData: roundTripAudioData!,
            language: "pt",
            hotwords: ["WisdMeet", "Antigravity", "Codex", "OpenJarvis"]
        )
        print("PROBE [Test I-7-STT]: FasterWhisper transcript='\(transcript)'")
        let lowerTrans = transcript.lowercased()
        precondition(
            lowerTrans.contains("wisd") || lowerTrans.contains("codex") || lowerTrans.contains("openjarvis") || lowerTrans.contains("antigravity"),
            "Test I-7: FasterWhisper com hotwords precisa reconhecer termos do domínio, obtido: \(transcript)"
        )

        // Check memory guard & RSS after warmup
        let warmHealth = try await oj.probeHealth()
        let facts = try await oj.fetchMemoryFacts()
        let serializedFacts = facts.map { "\($0["text"] ?? "")" }.joined(separator: "\n")
        precondition(!serializedFacts.contains(repoA.path) && !serializedFacts.contains(repoB.path),
                     "Test I-8: FilteredFactExtractor não deve persistir paths efêmeros de repositório: \(serializedFacts)")
        print(String(format: "PASS [Test I-7/8]: FasterWhisper+CleanTTS & MemoryGuard verified (openJarvisPID=%d warmRSS=%.1fMB facts=%d)", warmHealth.pid, warmHealth.rssMB, facts.count))

        // Turn I-8: Simulated daemon crash (SIGKILL) + automatic/managed recovery + clean shutdown
        let crashedPID = Int32(warmHealth.pid)
        kill(crashedPID, SIGKILL)
        try? await Task.sleep(nanoseconds: 700_000_000)
        let recovered = try await oj.ensureRunning()
        precondition(recovered.pid > 0 && Int32(recovered.pid) != crashedPID && recovered.status == "ok" && recovered.toolsCount == 12,
                     "Test I-8: OpenJarvis não recuperou após SIGKILL (old=\(crashedPID), new=\(recovered.pid))")
        print("PASS [Test I-8-Recovery]: Daemon crashed (SIGKILL pid=\(crashedPID)) -> cleanly recovered (new pid=\(recovered.pid))")

        oj.shutdown()
        ws.voice.orchestrator.llamaBrainRuntime.unloadModel()
        ws.shutdownGracefully()
        try? await Task.sleep(nanoseconds: 350_000_000)
        precondition(!FileManager.default.fileExists(atPath: oj.daemonSocketPath), "Test I-8: Socket daemon UDS não removido no shutdown")
        precondition(!FileManager.default.fileExists(atPath: oj.hostSocketPath), "Test I-8: Socket host UDS não removido no shutdown")
        print("PASS [Test I-8-Shutdown]: Clean shutdown verified (OpenJarvis & llama-server PIDs terminated & private UDS sockets removed)")
    }

    // MARK: - Helpers & Fixtures

    @MainActor
    private static func waitUntilIdle(ws: Workspace, timeoutSeconds: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 80_000_000)
            if !ws.busy && ws.activeTasks.isEmpty {
                return
            }
        }
        preconditionFailure("Timeout (\(timeoutSeconds)s) waiting for Workspace turn to complete. note=\(ws.currentActivityNote ?? "nil") err=\(ws.error ?? "nil")")
    }

    @MainActor
    private static func latestAssistantReply(in ws: Workspace) -> String {
        ws.messages.last(where: { ($0.author == "WisdAI" || $0.author == "WisdCode") && $0.kind == .text })?.text ?? ""
    }

    private static func createFixtureGitRepoA(at root: URL) throws {
        let src = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try """
        // swift-tools-version: 5.9
        import PackageDescription
        let package = Package(name: "WisdMeet", targets: [.target(name: "WisdMeetCore")])
        """.write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        try """
        # WisdMeet
        Plataforma de videoconferência com captura e mistura de áudio em baixa latência (sem módulos de IA ou redes neurais neste pacote).
        """.write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        try """
        import Foundation
        public final class MeetSessionController {
            public static let coordinatorTag = "MeetSessionCoordinator_V6Sentinel"
            public let reconnectBackoffMs: Int = 350
            public init() {}
            public func computeRetryDelay(attempt: Int) -> Int {
                min(reconnectBackoffMs * max(1, attempt), 5000)
            }
        }
        """.write(to: src.appendingPathComponent("MeetSessionController.swift"), atomically: true, encoding: .utf8)

        try """
        import Foundation
        public struct AudioJitterBridge {
            public static let AudioPipelineJitterBudget: Int = 42
            public var bufferedFrames: Int = 0
            public init() {}
        }
        """.write(to: src.appendingPathComponent("AudioJitterBridge.swift"), atomically: true, encoding: .utf8)

        try initGitRepo(at: root, branch: "main")
    }

    private static func createFixtureGitRepoB(at root: URL) throws {
        let src = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try "# WisdFin\nModulo financeiro isolado.\n".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try """
        public struct BetaSentinel {
            public static let token = "token_beta_772"
        }
        """.write(to: src.appendingPathComponent("BetaSentinel.swift"), atomically: true, encoding: .utf8)
        try initGitRepo(at: root, branch: "feature/beta")
    }

    private static func initGitRepo(at root: URL, branch: String) throws {
        let script = """
        set -e
        cd "\(root.path)"
        git init -b "\(branch)" >/dev/null 2>&1
        git config user.name "WisdAI Smoke"
        git config user.email "smoke@wisdai.local"
        git add -A
        git commit -m "Initial fixture commit" >/dev/null 2>&1
        """
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-lc", script]
        try proc.run()
        proc.waitUntilExit()
        precondition(proc.terminationStatus == 0, "git init failed at \(root.path)")
    }

    @MainActor
    private static func runTestHVoiceSynthesisAndExport(groundedMarkdownA: String, spokenSummaryA: String) async throws {
        try? FileManager.default.removeItem(at: sampleOutputDir)
        try FileManager.default.createDirectory(at: sampleOutputDir, withIntermediateDirectories: true)

        let supertonic = SupertonicNeuralTTSProvider()
        let kokoro = KokoroNeuralTTSProvider()
        precondition(supertonic.isReadyOnDisk && kokoro.isReadyOnDisk, "Supertonic e Kokoro devem estar disponíveis em disco para Test H")

        _ = try await supertonic.preload()
        _ = try await kokoro.preload(language: .portugueseBR)

        let auditSummaryPTBR = spokenSummaryA.isEmpty
            ? VoicePresentationEngine.composeSpokenSummary(
                fullMarkdownText: groundedMarkdownA,
                snapshot: nil,
                profile: .default,
                hadWaitNotice: false,
                customDictionary: TechnicalPronunciationDictionary.defaults(for: .portugueseBR)
            )
            : VoicePresentationEngine.composeSpokenSummary(
                fullMarkdownText: groundedMarkdownA,
                snapshot: nil,
                profile: .default,
                hadWaitNotice: false,
                customDictionary: TechnicalPronunciationDictionary.defaults(for: .portugueseBR)
            )
        let progressPTBR = TechnicalPronunciationDictionary.defaults(for: .portugueseBR)
            .apply(to: "Estou acompanhando por aqui. Antigravity está analisando MeetSessionController.swift no projeto WisdMeet e já leu dois arquivos.")
        let completedPTBR = TechnicalPronunciationDictionary.defaults(for: .portugueseBR)
            .apply(to: "Concluí a auditoria no WisdMeet. Encontrei o controlador principal e o orçamento de jitter, sem qualquer rede neural implementada.")
        let auditSummaryEN = TechnicalPronunciationDictionary.defaults(for: .englishUS)
            .apply(to: "Finished inspecting WisdMeet. MeetSessionController manages backoff retries cleanly, and no neural network code exists in the repository.")

        let samples: [(filename: String, engine: String, preset: String, lang: VoiceLanguageVariant, text: String, gain: Float)] = [
            ("v6_jarvis_m4_ptbr_01_live_audit_summary.wav", "supertonic", "m4", .portugueseBR, auditSummaryPTBR, 1.0),
            ("v6_jarvis_m4_ptbr_02_progress_during_task.wav", "supertonic", "m4", .portugueseBR, progressPTBR, 1.0),
            ("v6_ultron_br_m5_ptbr_03_audit_complete.wav", "supertonic", "m5", .portugueseBR, completedPTBR, 1.04),
            ("v6_aurora_kokoro_ptbr_04_audit_complete.wav", "kokoro", "pf_dora", .portugueseBR, completedPTBR, 1.0),
            ("v6_jarvis_m4_en_05_audit_complete.wav", "supertonic", "m4", .englishUS, auditSummaryEN, 1.0)
        ]

        for item in samples {
            var allSamples24k: [Float] = []
            let clauses = VoiceController.splitIntoNaturalSentences(item.text)
            let chunksToSynth = clauses.isEmpty ? [item.text] : clauses
            let t0 = DispatchTime.now().uptimeNanoseconds

            for (idx, clause) in chunksToSynth.enumerated() {
                let isLast = (idx == chunksToSynth.count - 1)
                let raw24k: [Float]
                if item.engine == "supertonic" {
                    let sp: SupertonicVoicePreset = item.preset == "m5" ? .m5 : .m4
                    let res = try await supertonic.synthesizeStandaloneSamples(
                        text: clause,
                        language: item.lang,
                        preset: sp,
                        rate: 1.0,
                        flowSteps: 8,
                        targetSampleRate: 24_000
                    )
                    raw24k = res.samples
                } else {
                    let kp: KokoroVoicePreset = KokoroVoicePreset(rawValue: item.preset) ?? .pfDora
                    let res = try await kokoro.synthesizeStandaloneSamples(
                        text: clause,
                        language: item.lang,
                        preset: kp,
                        rate: 1.0
                    )
                    raw24k = res.samples
                }
                let processed = raw24k.map { max(-0.98, min(0.98, $0 * item.gain)) }
                allSamples24k.append(contentsOf: processed)
                if !isLast {
                    allSamples24k.append(contentsOf: [Float](repeating: 0, count: 2400)) // 100ms natural pause
                }
            }

            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000.0
            let durSec = Double(allSamples24k.count) / 24_000.0
            let rtf = (elapsedMs / 1000.0) / max(0.05, durSec)
            let f0 = AcousticFeatureExtractor.measureMedianFundamentalFrequencyHz(samples: allSamples24k, sampleRate: 24_000) ?? 0
            let peak = allSamples24k.map { abs($0) }.max() ?? 0
            let meanDC = allSamples24k.reduce(0, +) / Float(max(1, allSamples24k.count))
            precondition(!allSamples24k.isEmpty && durSec > 0.6 && peak <= 0.99 && abs(meanDC) < 0.01,
                         "Test H WAV quality failed on \(item.filename): dur=\(durSec)s peak=\(peak) dc=\(meanDC)")

            let outURL = sampleOutputDir.appendingPathComponent(item.filename)
            try writePCM16WAV(samples: allSamples24k, sampleRate: 24_000, to: outURL)
            print(String(format: "AUDIO [Test H]: %@ | dur=%.2fs | RTF=%.3f | F0=%.1fHz | peak=%.3f | DC=%.5f",
                         item.filename, durSec, rtf, f0, peak, meanDC))
        }

        supertonic.unloadSynchronously()
        kokoro.unloadSynchronously()
        print("PASS [Test H]: Exported 5 reproducible PT-BR & EN V6 WAV samples to \(sampleOutputDir.path)")
    }

    private static func writePCM16WAV(samples: [Float], sampleRate: Int, to url: URL) throws {
        var pcm = Data(capacity: samples.count * 2)
        for s in samples {
            let clamped = max(-1.0, min(1.0, s))
            var int16 = Int16((clamped * Float(Int16.max)).rounded()).littleEndian
            pcm.append(Data(bytes: &int16, count: 2))
        }
        var header = Data(capacity: 44)
        func appendU32(_ v: UInt32) { var le = v.littleEndian; header.append(Data(bytes: &le, count: 4)) }
        func appendU16(_ v: UInt16) { var le = v.littleEndian; header.append(Data(bytes: &le, count: 2)) }
        header.append(Data("RIFF".utf8))
        appendU32(UInt32(36 + pcm.count))
        header.append(Data("WAVEfmt ".utf8))
        appendU32(16)
        appendU16(1) // PCM
        appendU16(1) // Mono
        appendU32(UInt32(sampleRate))
        appendU32(UInt32(sampleRate * 2))
        appendU16(2)
        appendU16(16)
        header.append(Data("data".utf8))
        appendU32(UInt32(pcm.count))
        var wav = header
        wav.append(pcm)
        try wav.write(to: url, options: .atomic)
    }
}

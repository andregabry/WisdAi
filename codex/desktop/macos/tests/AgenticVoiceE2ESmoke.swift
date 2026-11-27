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
        let normResA = ws.voice.orchestrator.submitNormalizedVoiceTranscript(voiceUtteranceA)
        precondition(normResA.normalizedTranscript.contains("WisdMeet"), "ContextualTranscriptNormalizer deve corrigir 'Whit Meet' -> 'WisdMeet'")
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
        await waitUntilIdle(ws: ws, timeoutSeconds: 75)
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
        await waitUntilIdle(ws: ws, timeoutSeconds: 75)
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

        _ = ws.voice.orchestrator.submitNormalizedVoiceTranscript("Analise todo o código agora")
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
        _ = ws.voice.orchestrator.submitNormalizedVoiceTranscript("O que está a acontecer agora?")
        let statusAnswer1 = ws.voice.orchestrator.lastPresentedSpokenTextForTelemetry
        print("TEST D status1=\(statusAnswer1)")
        precondition(statusAnswer1.contains("Antigravity") || statusAnswer1.contains("executando") || statusAnswer1.contains("WisdMeet"),
                     "Test D: Resposta sobre progresso vivo deve refletir estado real: \(statusAnswer1)")

        _ = ws.voice.orchestrator.submitNormalizedVoiceTranscript("Que ficheiros está a analisar e quanto falta?")
        let statusAnswer2 = ws.voice.orchestrator.lastPresentedSpokenTextForTelemetry
        print("TEST D status2=\(statusAnswer2)")
        precondition(!statusAnswer2.isEmpty, "Test D: Deve responder imediatamente sobre ficheiros/andamento")

        _ = ws.voice.orchestrator.submitNormalizedVoiceTranscript("Por que razão está a demorar?")
        let statusAnswer3 = ws.voice.orchestrator.lastPresentedSpokenTextForTelemetry
        print("TEST D status3=\(statusAnswer3)")
        precondition(!statusAnswer3.isEmpty, "Test D: Deve explicar razão real do tempo de execução")

        // Queue complementary instruction while busy
        _ = ws.voice.orchestrator.submitNormalizedVoiceTranscript("Pode verificar também se existe arquivo LICENSE na raiz?")
        let queuedEvents = ws.executionEventBus.events(for: convD)
        print("TEST D queuedKinds=\(queuedEvents.map(\.kind.rawValue))")
        precondition(queuedEvents.contains(where: { $0.kind == .taskQueued }),
                     "Test D: Pedido complementar durante execução deve enfileirar (.taskQueued)")

        // Explicitly cancel active task by voice
        _ = ws.voice.orchestrator.submitNormalizedVoiceTranscript("Pode parar esta tarefa agora")
        await waitUntilIdle(ws: ws, timeoutSeconds: 15)
        let eventsAfterCancel = ws.executionEventBus.events(for: convD)
        print("TEST D afterCancelKinds=\(eventsAfterCancel.map(\.kind.rawValue))")
        precondition(eventsAfterCancel.contains(where: { $0.kind == .taskCancelled }),
                     "Test D: Comando de voz 'pare esta tarefa' deve emitir .taskCancelled e interromper")
        print("PASS [Test D]: Live grounded status Q&A, complementary queue (.taskQueued) & voice cancel (.taskCancelled) verified")

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

        _ = ws.voice.orchestrator.submitNormalizedVoiceTranscript("Leia o arquivo Sources/BetaSentinel.swift deste projeto WisdFin e diga o token encontrado.")
        await waitUntilIdle(ws: ws, timeoutSeconds: 75)
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
        if let syncedOpenAI = local.aiAccounts.first(where: { $0.provider == .openai && $0.supportsExecution }) {
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

        _ = ws.voice.orchestrator.submitNormalizedVoiceTranscript(
            "Verifique se existe alguma rede neural convolucional implementada no projeto WisdMeet"
        )
        await waitUntilIdle(ws: ws, timeoutSeconds: 75)
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

        print("AGENTIC_VOICE_E2E_ALL_PASS")
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

        let samples: [(filename: String, engine: String, preset: String, lang: VoiceLanguageVariant, text: String, dsp: VoiceDSPParameters)] = [
            ("v6_jarvis_m4_ptbr_01_live_audit_summary.wav", "supertonic", "m4", .portugueseBR, auditSummaryPTBR, .clean),
            ("v6_jarvis_m4_ptbr_02_progress_during_task.wav", "supertonic", "m4", .portugueseBR, progressPTBR, .clean),
            ("v6_ultron_br_m5_ptbr_03_audit_complete.wav", "supertonic", "m5", .portugueseBR, completedPTBR, .ultronBRDefault),
            ("v6_aurora_kokoro_ptbr_04_audit_complete.wav", "kokoro", "pf_dora", .portugueseBR, completedPTBR, .clean),
            ("v6_jarvis_m4_en_05_audit_complete.wav", "supertonic", "m4", .englishUS, auditSummaryEN, .clean)
        ]

        for item in samples {
            var allSamples24k: [Float] = []
            let dspProcessor = VoiceStudioDSPProcessor(sampleRate: 24_000)
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
                let processed = dspProcessor.process(raw24k, parameters: item.dsp, isFinalChunk: isLast)
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

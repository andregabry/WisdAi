import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Risk Tiers & Tool Classification (Adapted from OpenJarvis Apache-2.0 Patterns)

public enum VoiceActionRiskTier: String, Codable, Sendable {
    case trivial   // Conversational / read-only status summary
    case low       // Safe analysis / file reading
    case medium    // Project edits inside workspace bounds
    case high      // Shell commands / destructive actions (always requires WisdAI policy approval)
}

public enum VoiceControlAction: Equatable, Sendable {
    case muteMicrophone
    case unmuteMicrophone
    case stopVoiceSession
    case interruptSpeech
    case switchLanguage(VoiceLanguageVariant)
}

public enum VoiceSpecialistAgentHint: String, Equatable, Codable, Sendable {
    case autoActive
    case codex
    case antigravity
    case claude
}

public struct VoiceTaskSummarySnapshot: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let title: String
    public let agentName: String
    public let modelName: String
    public let status: String
    public let progressNote: String

    public init(id: String, title: String, agentName: String, modelName: String, status: String, progressNote: String) {
        self.id = id
        self.title = title
        self.agentName = agentName
        self.modelName = modelName
        self.status = status
        self.progressNote = progressNote
    }
}

public enum VoiceIntentDecision: Equatable, Sendable {
    case voiceControl(VoiceControlAction)
    case queryTaskStatus(projectHint: String?)
    case handleLocally(complexityScore: Double, languageDetected: VoiceLanguageVariant?)
    case delegateToSpecialist(agentHint: VoiceSpecialistAgentHint, prompt: String, riskTier: VoiceActionRiskTier, parallelFriendly: Bool)
}

public enum VoiceDelegationDispatchResult: Equatable, Sendable {
    case dispatched(agentDisplayName: String)
    case awaitingUserApproval(reason: String)
    case unavailable(reason: String)
}

// MARK: - Deterministic Query Complexity & Intent Router

/// Adapted conceptually from OpenJarvis ``learning/routing/complexity.py`` (Apache-2.0, Copyright 2025 The OpenJarvis Authors).
public enum LocalQueryComplexityAnalyzer {
    private static let agentKeywordsCodex = ["codex", "openai"]
    private static let agentKeywordsAgy = ["antigravity", "agy", "gemini"]
    private static let agentKeywordsClaude = ["claude"]

    private static let statusPatterns = [
        "como está o desenvolvimento", "como estao as tarefas", "como estão as tarefas",
        "status do projeto", "status das tarefas", "o que está rodando", "o que esta rodando",
        "o agente terminou", "alguma tarefa em andamento", "progress of", "running tasks"
    ]

    private static let directDelegatePhrases = [
        "pede ao ", "pede para o ", "pede pro ", "pede pra ",
        "peça ao ", "peça para o ", "peça pro ", "peça pra ",
        "manda o ", "mande o ", "chama o ", "chame o ",
        "fala pro ", "fala com o ", "diga ao ", "solicite ao ",
        "delegue ao ", "passa pro ",
        "ask claude", "ask codex", "ask antigravity", "tell codex", "tell claude"
    ]

    private static let workspaceActionPatterns = [
        "edite ", "edita ", "editar ", "altere ", "altera ", "alterar ", "refatore ", "refatora ",
        "corrija ", "corrige ", "corrigir ", "implemente ", "implementa ", "crie um arquivo",
        "rode os testes", "execute o", "executa o", "rode o", "compile o", "build ",
        "analise o código", "analise o repositório", "analisar o projeto", "analisar a autenticação",
        "verifique o arquivo", "pesquise no código", "revise o código", "check the code",
        "edit the file", "run tests", "fix the bug"
    ]

    private static let conceptualQuestionPrefixes = [
        "o que é ", "o que e ", "o que significa ", "como funciona ", "qual a diferença ",
        "qual é a diferença ", "explique o que ", "por que ", "porque ", "você acha ",
        "vale a pena ", "what is ", "how does ", "why does ", "explain "
    ]

    private static let complexReasoningKeywords = [
        "arquitetura", "architecture", "concorrência", "concorrencia", "deadlock", "race condition",
        "latência", "latencia", "trade-off", "tradeoff", "compare", "comparar", "diferença",
        "autenticação", "autenticacao", "segurança", "seguranca", "memória", "memoria", "memory",
        "duplex", "echo", "eco", "vad", "streaming", "quantiza", "benchmark", "algoritmo",
        "cqrs", "event-driven", "mutex", "actor", "sqlite", "fts5"
    ]

    private static let destructivePatterns = [
        "apague tudo", "delete all", "rm -rf", "drop database", "reset --hard", "force push"
    ]

    public static func detectLanguage(from utterance: String, fallback: VoiceLanguageVariant) -> VoiceLanguageVariant {
        let lower = " " + utterance.lowercased() + " "
        let enMarkers = [" the ", " let's ", " switch to english", " speak english", " how are you", " can you ", " please ", " actually,"]
        let esMarkers = [" hola ", " en español", " por favor ", " cómo estás", " puedes "]
        let ptMarkers = [" você ", " está ", " projeto ", " tudo bem", " não ", " para ", " quero ", " preciso ", " como "]

        let enScore = enMarkers.filter { lower.contains($0) }.count
        let esScore = esMarkers.filter { lower.contains($0) }.count
        let ptScore = ptMarkers.filter { lower.contains($0) }.count

        if enScore > ptScore && enScore >= 1 { return .englishUS }
        if esScore > ptScore && esScore >= 1 { return .spanishES }
        return fallback
    }

    /// Evaluates semantic complexity independent of raw word count ("Por que deadlock?" can still be high-complexity).
    public static func computeSemanticComplexityScore(utterance: String) -> Double {
        let lower = utterance.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return 0.0 }
        let words = lower.split(whereSeparator: { $0.isWhitespace })
        var score = min(0.38, Double(words.count) / 48.0)
        let conceptHits = complexReasoningKeywords.filter { lower.contains($0) }.count
        if conceptHits > 0 {
            score = max(score, 0.58 + min(0.32, Double(conceptHits) * 0.14))
        }
        if lower.contains("por que") || lower.contains("compare") || lower.contains("como evitar") || lower.contains("explain why") {
            score = max(score, 0.65)
        }
        if lower.contains("?") {
            score = max(score, 0.35)
        }
        return min(1.0, score)
    }

    public static func route(
        utterance: String,
        currentLanguage: VoiceLanguageVariant
    ) -> VoiceIntentDecision {
        let trimmed = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // 1. Voice self-controls
        if lower == "pare" || lower == "para" || lower == "stop" || lower.contains("silenciar microfone") || lower.contains("mutar microfone") {
            return .voiceControl(.muteMicrophone)
        }
        if lower.contains("encerrar voz") || lower.contains("desligar voz") || lower.contains("fechar assistente") {
            return .voiceControl(.stopVoiceSession)
        }
        if lower.contains("fala em inglês") || lower.contains("switch to english") || lower.contains("em inglês") {
            return .voiceControl(.switchLanguage(.englishUS))
        }
        if lower.contains("em português de portugal") || lower.contains("português europeu") {
            return .voiceControl(.switchLanguage(.portuguesePT))
        }
        if lower.contains("em português") && !lower.contains("portugal") {
            return .voiceControl(.switchLanguage(.portugueseBR))
        }
        if lower.contains("en español") || lower.contains("em espanhol") {
            return .voiceControl(.switchLanguage(.spanishES))
        }

        // 2. Task / project status inspection (never invent states; reads live orchestrator snapshot!)
        if statusPatterns.contains(where: { lower.contains($0) }) {
            return .queryTaskStatus(projectHint: extractProjectMention(from: trimmed))
        }

        // 3. Explicit agent delegation or explicit actionable workspace request (never accidental on mere agent name mention or conceptual chat)
        let agentHint = detectAgentHint(in: lower)
        let hasDirectDelegateVerb = directDelegatePhrases.contains(where: { lower.contains($0) })
        let isPureConceptualQuestion = conceptualQuestionPrefixes.contains(where: { lower.hasPrefix($0) }) && !hasDirectDelegateVerb
        let hasWorkspaceAction = !isPureConceptualQuestion && workspaceActionPatterns.contains(where: { lower.contains($0) })
        let isHighRisk = destructivePatterns.contains(where: { lower.contains($0) })

        if hasDirectDelegateVerb || hasWorkspaceAction || isHighRisk {
            let isWriteVerb = lower.contains("edite") || lower.contains("edita") || lower.contains("altere")
                || lower.contains("corrija") || lower.contains("corrige") || lower.contains("implemente")
                || lower.contains("crie um arquivo") || lower.contains("rode os testes")
            let risk: VoiceActionRiskTier = isHighRisk ? .high : (isWriteVerb ? .medium : .low)
            let parallel = lower.contains("continua conversando") || lower.contains("continue conversando")
                || lower.contains("enquanto") || lower.contains("em paralelo") || lower.contains("em segundo plano")
                || lower.contains("continue talking") || agentHint != nil
            return .delegateToSpecialist(
                agentHint: agentHint ?? .autoActive,
                prompt: trimmed,
                riskTier: risk,
                parallelFriendly: parallel
            )
        }

        // 4. Local conversational brain handles greetings, reasoning, memory questions, conceptual questions & brainstorming
        let detected = detectLanguage(from: trimmed, fallback: currentLanguage)
        let score = computeSemanticComplexityScore(utterance: trimmed)
        return .handleLocally(complexityScore: score, languageDetected: detected)
    }

    private static func detectAgentHint(in lower: String) -> VoiceSpecialistAgentHint? {
        if agentKeywordsClaude.contains(where: { lower.contains($0) }) { return .claude }
        if agentKeywordsAgy.contains(where: { lower.contains($0) }) { return .antigravity }
        if agentKeywordsCodex.contains(where: { lower.contains($0) }) { return .codex }
        return nil
    }

    private static func extractProjectMention(from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "(?:do\\s+projeto|no\\s+projeto|sobre\\s+o\\s+projeto|projeto|do|no|sobre\\s+o)\\s+([A-Za-z0-9_.-]+)", options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        if let match = regex.firstMatch(in: text, range: range),
           match.numberOfRanges >= 2,
           let swiftRange = Range(match.range(at: 1), in: text) {
            return String(text[swiftRange])
        }
        return nil
    }
}

// MARK: - Interchangeable Conversational Brain Abstraction (Phase 3)

public enum VoiceBrainEngineKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case adaptiveAuto = "auto"
    case appleFoundationModels = "apple_foundation_models"
    case localLlamaCppMetal = "llama_cpp_metal"
    case localMLXServer = "mlx_compat_server"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .adaptiveAuto: return "Automático (Melhor Motor Local)"
        case .appleFoundationModels: return "Apple FoundationModels (ANE Nativo)"
        case .localLlamaCppMetal: return "llama.cpp Metal (Qwen / Gemma / Llama / Phi)"
        case .localMLXServer: return "MLX Local Server (127.0.0.1)"
        }
    }
}

public enum LocalBrainBackendStatus: String, Sendable {
    case appleFoundationModelsReady = "Apple FoundationModels (On-Device ANE)"
    case llamaCppMetalReady = "llama.cpp Metal Local (GGUF)"
    case mlxLocalServerReady = "MLX Local Compat Server"
    case compactHeuristicFallback = "Modelo conversacional indisponível"
}

@MainActor
public final class LocalConversationalBrain: ObservableObject {
    @Published public private(set) var backendStatus: LocalBrainBackendStatus = .compactHeuristicFallback
    @Published public private(set) var isPrewarmed: Bool = false
    @Published public private(set) var lastErrorDetail: String? = nil
    @Published public var preferredEngineKind: VoiceBrainEngineKind = VoiceBrainEngineKind(rawValue: UserDefaults.standard.string(forKey: "wisdai.voice.brainEngineKind") ?? "") ?? .adaptiveAuto {
        didSet {
            UserDefaults.standard.set(preferredEngineKind.rawValue, forKey: "wisdai.voice.brainEngineKind")
        }
    }

    public var externalLocalChatHandler: ((_ systemPrompt: String, _ recentHistory: [(role: String, text: String)], _ userText: String, _ language: VoiceLanguageVariant, _ onDelta: @escaping @MainActor (String) -> Void) async throws -> String)?
    public var externalLocalReadyProvider: (() -> (ready: Bool, label: String))?

    #if canImport(FoundationModels)
    // Type-erased storage keeps deployment target compatibility cleanly across macOS 14..27.
    private var fmSessionBox: Any?
    #endif
    private var lastAppliedInstructionsDigest: Int = 0
    private var approximateSessionTokens: Int = 0
    private let maxSafeTokenBudget = 3200 // Reserve margin cleanly below Apple FM 4,096 context cap
    private var recentAssistantOpenings: [String] = []

    public init() {
        refreshBackendAvailability()
    }

    public func refreshBackendAvailability() {
        if preferredEngineKind == .localLlamaCppMetal || preferredEngineKind == .localMLXServer {
            if let ext = externalLocalReadyProvider?(), ext.ready {
                backendStatus = (preferredEngineKind == .localMLXServer) ? .mlxLocalServerReady : .llamaCppMetalReady
            } else {
                backendStatus = .compactHeuristicFallback
            }
            return
        }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                backendStatus = .appleFoundationModelsReady
                return
            }
        }
        #endif
        if let ext = externalLocalReadyProvider?(), ext.ready {
            backendStatus = .llamaCppMetalReady
        } else {
            backendStatus = .compactHeuristicFallback
        }
    }

    public func prewarm(instructions: String) {
        if (preferredEngineKind == .localLlamaCppMetal || preferredEngineKind == .localMLXServer),
           let ext = externalLocalReadyProvider?(), ext.ready {
            backendStatus = (preferredEngineKind == .localMLXServer) ? .mlxLocalServerReady : .llamaCppMetalReady
            lastAppliedInstructionsDigest = instructions.hashValue
            isPrewarmed = true
            return
        }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *),
           preferredEngineKind != .localLlamaCppMetal,
           preferredEngineKind != .localMLXServer,
           case .available = SystemLanguageModel.default.availability {
            backendStatus = .appleFoundationModelsReady
            let session = LanguageModelSession(instructions: instructions)
            session.prewarm()
            self.fmSessionBox = session
            self.lastAppliedInstructionsDigest = instructions.hashValue
            self.approximateSessionTokens = max(64, instructions.count / 4)
            self.isPrewarmed = true
            self.lastErrorDetail = nil
            return
        }
        #endif
        refreshBackendAvailability()
        isPrewarmed = true
    }

    public func resetSession(instructions: String) {
        approximateSessionTokens = 0
        lastAppliedInstructionsDigest = 0
        recentAssistantOpenings.removeAll(keepingCapacity: false)
        #if canImport(FoundationModels)
        fmSessionBox = nil
        #endif
        prewarm(instructions: instructions)
    }

    public func streamReply(
        userText: String,
        systemInstructions: String,
        portableContextSummary: String,
        recentTurns: [(role: String, text: String)] = [],
        language: VoiceLanguageVariant,
        onDelta: @escaping @MainActor (String) -> Void
    ) async -> String {
        lastErrorDetail = nil
        var enrichedInstructions = systemInstructions
        if !portableContextSummary.isEmpty {
            enrichedInstructions += "\n\n<portable_context_reference>\n\(String(portableContextSummary.prefix(1200)))\n</portable_context_reference>"
        }
        if !recentAssistantOpenings.isEmpty {
            let openingsHint = recentAssistantOpenings.suffix(3).joined(separator: " | ")
            enrichedInstructions += "\nEvite repetir as mesmas aberturas usadas recentemente (\(openingsHint)); varie naturalmente como em diálogo humano."
        }

        // Route to external local runtime (llama.cpp Metal / MLX Server) if explicitly selected or when Apple FM unavailable
        let useExternalFirst: Bool = {
            if preferredEngineKind == .localLlamaCppMetal || preferredEngineKind == .localMLXServer {
                return externalLocalChatHandler != nil && (externalLocalReadyProvider?().ready ?? false)
            }
            if preferredEngineKind == .adaptiveAuto,
               let ext = externalLocalReadyProvider?(), ext.ready,
               externalLocalChatHandler != nil {
                // Prefer loaded GGUF model in Adaptive mode only when user intentionally loaded one; otherwise Apple FM runs with 0 heap load.
                return true
            }
            return false
        }()

        if useExternalFirst, let handler = externalLocalChatHandler {
            do {
                backendStatus = (preferredEngineKind == .localMLXServer) ? .mlxLocalServerReady : .llamaCppMetalReady
                let reply = try await handler(enrichedInstructions, recentTurns, userText, language, onDelta)
                let clean = reply.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty && !Task.isCancelled {
                    recordOpening(from: clean)
                    return clean
                }
            } catch {
                if Task.isCancelled { return "" }
                lastErrorDetail = "Motor local selecionado falhou: \(error.localizedDescription)"
                if preferredEngineKind != .adaptiveAuto {
                    refreshBackendAvailability()
                    return emitUnavailableNotice(language: language, detail: lastErrorDetail, onDelta: onDelta)
                }
            }
        }

        let userTokens = max(8, userText.count / 4)
        if approximateSessionTokens + userTokens > maxSafeTokenBudget {
            resetSession(instructions: enrichedInstructions)
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *),
           preferredEngineKind != .localLlamaCppMetal,
           preferredEngineKind != .localMLXServer,
           case .available = SystemLanguageModel.default.availability {
            backendStatus = .appleFoundationModelsReady

            for attempt in 0..<2 {
                if Task.isCancelled { return "" }
                let activeSession: LanguageModelSession
                if attempt == 0,
                   let existing = fmSessionBox as? LanguageModelSession,
                   (lastAppliedInstructionsDigest == 0 || !portableContextSummary.isEmpty || lastAppliedInstructionsDigest == enrichedInstructions.hashValue) {
                    activeSession = existing
                } else {
                    let s = LanguageModelSession(instructions: enrichedInstructions)
                    s.prewarm()
                    fmSessionBox = s
                    lastAppliedInstructionsDigest = enrichedInstructions.hashValue
                    approximateSessionTokens = max(64, enrichedInstructions.count / 4)
                    activeSession = s
                }

                var emittedPrefixLen = 0
                var fullReply = ""
                do {
                    for try await partial in activeSession.streamResponse(to: userText) {
                        if Task.isCancelled { return "" }
                        let current = partial.content
                        if current.count > emittedPrefixLen {
                            let startIdx = current.index(current.startIndex, offsetBy: emittedPrefixLen)
                            let delta = String(current[startIdx...])
                            emittedPrefixLen = current.count
                            fullReply = current
                            onDelta(delta)
                        }
                    }
                    let finalClean = fullReply.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !finalClean.isEmpty {
                        approximateSessionTokens += userTokens + max(16, finalClean.count / 4)
                        recordOpening(from: finalClean)
                        return finalClean
                    }
                } catch {
                    if Task.isCancelled { return "" }
                    lastErrorDetail = error.localizedDescription
                    #if DEBUG
                    #endif
                    fmSessionBox = nil
                    // Never fabricate or append text onto a partial response already heard by user
                    if !fullReply.isEmpty { return fullReply }
                    if attempt == 0 {
                        approximateSessionTokens = 0
                        continue
                    }
                }
            }
        }
        #endif

        guard !Task.isCancelled else { return "" }
        backendStatus = .compactHeuristicFallback
        return emitUnavailableNotice(language: language, detail: lastErrorDetail, onDelta: onDelta)
    }

    private func emitUnavailableNotice(
        language: VoiceLanguageVariant,
        detail: String?,
        onDelta: @escaping @MainActor (String) -> Void
    ) -> String {
        let fallback = deterministicNaturalFallback(for: "", language: language, errorDetail: detail)
        onDelta(fallback)
        return fallback
    }

    private func recordOpening(from reply: String) {
        let prefix = String(reply.prefix(24)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prefix.isEmpty else { return }
        recentAssistantOpenings.append(prefix)
        if recentAssistantOpenings.count > 4 {
            recentAssistantOpenings.removeFirst(recentAssistantOpenings.count - 4)
        }
    }

    public static func formatTaskStatusReply(
        tasks: [VoiceTaskSummarySnapshot],
        projectName: String?,
        language: VoiceLanguageVariant
    ) -> String {
        if tasks.isEmpty {
            let projLabel = projectName.map { " no projeto \($0)" } ?? ""
            return language.bcp47LanguagePrefix == "en"
                ? "There are no background agent tasks running right now. Whenever you want to analyze or change code, just let me know."
                : "Não há nenhuma tarefa de agente em execução no momento\(projLabel). Quando quiser que eu acione algum agente ou revise algo no projeto, é só pedir."
        }
        let descriptions = tasks.prefix(3).map { task in
            "\(task.agentName) está trabalhando em \(task.title) (\(task.progressNote))"
        }.joined(separator: "; ")
        if tasks.count == 1 {
            return "Tem uma tarefa ativa agora: \(descriptions)."
        }
        return "Existem \(tasks.count) tarefas em execução: \(descriptions)."
    }

    private func deterministicNaturalFallback(for input: String, language: VoiceLanguageVariant, errorDetail: String? = nil) -> String {
        switch language {
        case .englishUS:
            return "The local conversation model is unavailable right now. Please try again or explicitly ask me to consult an agent."
        case .spanishES:
            return "El modelo de conversación local no está disponible ahora mismo. Inténtalo de nuevo o pide que consulte a un agente."
        case .portuguesePT:
            return "O modelo de conversação local está indisponível neste momento. Tenta novamente ou pede-me para consultar um agente."
        case .portugueseBR:
            return "O modelo de conversação local está indisponível no momento. Tente novamente ou peça explicitamente para eu consultar um agente."
        }
    }
}

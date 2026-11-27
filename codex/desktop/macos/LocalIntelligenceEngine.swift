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

    private static let workspaceActionPatterns = [
        "edite", "edita", "editar", "altere", "altera", "alterar", "refatore", "refatora",
        "corrija", "corrige", "corrigir", "implemente", "implementa", "crie um arquivo",
        "rode os testes", "execute", "executa", "rode ", "instale", "compile", "build",
        "analise o código", "analise o repositório", "verifique o arquivo", "pesquise no código",
        "revisar", "revise", "review", "check the code", "edit the file", "run tests", "fix the bug"
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

        // 3. Explicit agent delegation ("Pede ao Claude...", "Manda o Codex...", "pede pro Antigravity...")
        let agentHint = detectAgentHint(in: lower)
        let hasDirectDelegateVerb = lower.contains("pede ao ") || lower.contains("pede para o ") || lower.contains("pede pro ")
            || lower.contains("manda o ") || lower.contains("chama o ") || lower.contains("ask claude") || lower.contains("ask codex")
        let hasWorkspaceAction = workspaceActionPatterns.contains(where: { lower.contains($0) })
        let isHighRisk = destructivePatterns.contains(where: { lower.contains($0) })

        if hasDirectDelegateVerb || hasWorkspaceAction || isHighRisk {
            let risk: VoiceActionRiskTier = isHighRisk ? .high : (lower.contains("rode") || lower.contains("edite") || lower.contains("corrija") ? .medium : .low)
            let parallel = lower.contains("continua conversando") || lower.contains("enquanto") || lower.contains("continue talking") || agentHint != nil
            return .delegateToSpecialist(
                agentHint: agentHint ?? .autoActive,
                prompt: trimmed,
                riskTier: risk,
                parallelFriendly: parallel
            )
        }

        // 4. Local conversational brain handles greetings, reasoning, explanations, brainstorming, quick tech chat directly (<600ms warm)
        let detected = detectLanguage(from: trimmed, fallback: currentLanguage)
        let score = min(1.0, Double(trimmed.split(whereSeparator: { $0.isWhitespace }).count) / 45.0)
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

// MARK: - Local Conversational Brain (Apple FoundationModels ANE + Smart Fallback)

public enum LocalBrainBackendStatus: String, Sendable {
    case appleFoundationModelsReady = "Apple FoundationModels (On-Device ANE)"
    case compactHeuristicFallback = "Modelo conversacional indisponível"
}

@MainActor
public final class LocalConversationalBrain: ObservableObject {
    @Published public private(set) var backendStatus: LocalBrainBackendStatus = .compactHeuristicFallback
    @Published public private(set) var isPrewarmed: Bool = false

    #if canImport(FoundationModels)
    // Type-erased storage keeps deployment target compatibility cleanly across macOS 14..27.
    private var fmSessionBox: Any?
    #endif
    private var approximateSessionTokens: Int = 0
    private let maxSafeTokenBudget = 3200 // Reserve margin cleanly below Apple FM 4,096 context cap

    public init() {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                backendStatus = .appleFoundationModelsReady
            }
        }
        #endif
    }

    public func prewarm(instructions: String) {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *),
           case .available = SystemLanguageModel.default.availability {
            backendStatus = .appleFoundationModelsReady
            let session = LanguageModelSession(instructions: instructions)
            session.prewarm()
            self.fmSessionBox = session
            self.approximateSessionTokens = max(64, instructions.count / 4)
            self.isPrewarmed = true
            return
        }
        #endif
        backendStatus = .compactHeuristicFallback
        isPrewarmed = true
    }

    public func resetSession(instructions: String) {
        approximateSessionTokens = 0
        #if canImport(FoundationModels)
        fmSessionBox = nil
        #endif
        prewarm(instructions: instructions)
    }

    public func streamReply(
        userText: String,
        systemInstructions: String,
        portableContextSummary: String,
        language: VoiceLanguageVariant,
        onDelta: @escaping @MainActor (String) -> Void
    ) async -> String {
        let userTokens = max(8, userText.count / 4)
        if approximateSessionTokens + userTokens > maxSafeTokenBudget {
            // Proactively compact session before hitting Apple FM 4,096 token ceiling
            let compactedInstructions = systemInstructions + (portableContextSummary.isEmpty ? "" : "\n\nContext summary:\n\(String(portableContextSummary.prefix(1200)))")
            resetSession(instructions: compactedInstructions)
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *),
           case .available = SystemLanguageModel.default.availability {
            let activeSession: LanguageModelSession
            if let existing = fmSessionBox as? LanguageModelSession {
                activeSession = existing
            } else {
                let s = LanguageModelSession(instructions: systemInstructions)
                s.prewarm()
                fmSessionBox = s
                activeSession = s
            }

            let languageCue: String = {
                switch language {
                case .englishUS: return "[Respond naturally in English matching the user] "
                case .spanishES: return "[Responde naturalmente en español] "
                case .portuguesePT: return "[Responde em português europeu natural] "
                case .portugueseBR: return "[Responda naturalmente em português brasileiro] "
                }
            }()
            let promptInput = languageCue + userText

            var emittedPrefixLen = 0
            var fullReply = ""
            do {
                for try await partial in activeSession.streamResponse(to: promptInput) {
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
                    return finalClean
                }
            } catch {
                if Task.isCancelled { return "" }
                resetSession(instructions: systemInstructions)
                // Do not append a fabricated fallback to a reply already streamed.
                if !fullReply.isEmpty { return fullReply }
            }
        }
        #endif

        guard !Task.isCancelled else { return "" }
        backendStatus = .compactHeuristicFallback
        let fallback = deterministicNaturalFallback(for: userText, language: language)
        onDelta(fallback)
        return fallback
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

    private func deterministicNaturalFallback(for input: String, language: VoiceLanguageVariant) -> String {
        switch language {
        case .englishUS:
            return "The local conversation model is unavailable. Please try again or explicitly ask me to consult an agent."
        case .spanishES:
            return "El modelo de conversación local no está disponible. Inténtalo de nuevo o pide que consulte a un agente."
        case .portuguesePT:
            return "O modelo de conversação local está indisponível. Tenta novamente ou pede-me para consultar um agente."
        case .portugueseBR:
            return "O modelo de conversação local está indisponível. Tente novamente ou peça para eu consultar um agente."
        }
    }
}

import Accelerate
import Foundation
import os

// MARK: - Deterministic Conversation State Machine (Section 10)

public enum VoiceConversationState: String, CaseIterable, Codable, Sendable {
    case idle
    case connecting
    case listening
    case userSpeaking
    case processing
    case assistantSpeaking
    case interrupted
    case reconnecting
    case muted
    case error
    case disconnected
    case initializingLocalEngine
    case loadingModel
    case consultingAgent

    public var displayTitle: String {
        switch self {
        case .idle: return "Inativo"
        case .connecting: return "Preparando áudio…"
        case .initializingLocalEngine: return "Inicializando motor local…"
        case .loadingModel: return "Carregando modelo local…"
        case .listening: return "Ouvindo você…"
        case .userSpeaking: return "Você está falando…"
        case .processing: return "Pensando…"
        case .consultingAgent: return "Consultando agente…"
        case .assistantSpeaking: return "WisdAI falando…"
        case .interrupted: return "Interrompido · Ouvindo…"
        case .reconnecting: return "Reconectando…"
        case .muted: return "Microfone silenciado"
        case .error: return "Erro de voz"
        case .disconnected: return "Desconectado"
        }
    }

    public var orbActivity: CodexVoiceActivity {
        switch self {
        case .idle, .muted, .error, .disconnected:
            return .idle
        case .connecting, .initializingLocalEngine, .loadingModel, .listening, .userSpeaking, .interrupted, .reconnecting:
            return .listening
        case .processing, .consultingAgent:
            return .thinking
        case .assistantSpeaking:
            return .speaking
        }
    }
}

public struct ConversationStateTransitionRecord: Equatable, Sendable {
    public let timestampUptimeNs: UInt64
    public let from: VoiceConversationState
    public let to: VoiceConversationState
    public let reason: String
}

public final class ConversationStateMachine: @unchecked Sendable {
    private let lock = NSLock()
    private var _state: VoiceConversationState = .idle
    private var _history: [ConversationStateTransitionRecord] = []
    private let maxHistoryCount: Int

    public init(initialState: VoiceConversationState = .idle, maxHistoryCount: Int = 128) {
        self._state = initialState
        self.maxHistoryCount = max(16, maxHistoryCount)
    }

    public var state: VoiceConversationState {
        lock.withLock { _state }
    }

    public var history: [ConversationStateTransitionRecord] {
        lock.withLock { _history }
    }

    public static func isValidTransition(from: VoiceConversationState, to: VoiceConversationState) -> Bool {
        if from == to { return true }
        switch from {
        case .idle, .disconnected:
            return [.connecting, .initializingLocalEngine, .loadingModel, .listening, .muted, .error, .idle, .disconnected].contains(to)
        case .connecting, .initializingLocalEngine, .loadingModel:
            return [.initializingLocalEngine, .loadingModel, .listening, .assistantSpeaking, .processing, .reconnecting, .error, .disconnected, .idle].contains(to)
        case .listening:
            return [.userSpeaking, .processing, .consultingAgent, .assistantSpeaking, .muted, .reconnecting, .error, .disconnected, .idle].contains(to)
        case .userSpeaking:
            return [.listening, .processing, .consultingAgent, .assistantSpeaking, .muted, .reconnecting, .error, .disconnected, .idle].contains(to)
        case .processing, .consultingAgent:
            return [.consultingAgent, .assistantSpeaking, .listening, .userSpeaking, .interrupted, .reconnecting, .muted, .error, .disconnected, .idle].contains(to)
        case .assistantSpeaking:
            return [.interrupted, .listening, .userSpeaking, .processing, .consultingAgent, .muted, .reconnecting, .error, .disconnected, .idle].contains(to)
        case .interrupted:
            return [.userSpeaking, .listening, .processing, .consultingAgent, .muted, .error, .disconnected, .idle].contains(to)
        case .reconnecting:
            return [.listening, .userSpeaking, .processing, .consultingAgent, .assistantSpeaking, .error, .disconnected, .idle].contains(to)
        case .muted:
            return [.listening, .assistantSpeaking, .processing, .consultingAgent, .disconnected, .error, .idle].contains(to)
        case .error:
            return [.connecting, .initializingLocalEngine, .reconnecting, .listening, .disconnected, .idle].contains(to)
        }
    }

    @discardableResult
    public func transition(to target: VoiceConversationState, reason: String) -> Bool {
        lock.withLock {
            guard Self.isValidTransition(from: _state, to: target) else {
                return false
            }
            if _state != target {
                _history.append(
                    ConversationStateTransitionRecord(
                        timestampUptimeNs: DispatchTime.now().uptimeNanoseconds,
                        from: _state,
                        to: target,
                        reason: reason
                    )
                )
                if _history.count > maxHistoryCount {
                    _history.removeFirst(_history.count - maxHistoryCount)
                }
                _state = target
            }
            return true
        }
    }

    public func resetToIdle(reason: String = "Sessão encerrada") {
        lock.withLock {
            let prev = _state
            _state = .idle
            _history.append(
                ConversationStateTransitionRecord(
                    timestampUptimeNs: DispatchTime.now().uptimeNanoseconds,
                    from: prev,
                    to: .idle,
                    reason: reason
                )
            )
        }
    }
}

// MARK: - Personality, Expressivity & Technical Pronunciation Config (Sections 7, 8, 9)

public enum VoicePersonalityStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case naturalPartner
    case jarvisExecutive
    case ultronCinematic
    case conciseExecutive
    case calmMentor
    case creativeBrainstorm

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .naturalPartner: return "Parceiro Natural (Padrão)"
        case .jarvisExecutive: return "JARVIS · Estrategista Sereno"
        case .ultronCinematic: return "Ultron BR · Elegância Cinematográfica"
        case .conciseExecutive: return "Direto & Executivo"
        case .calmMentor: return "Calmo & Didático"
        case .creativeBrainstorm: return "Criativo & Exploratório"
        }
    }
}

public enum VoiceFormalityLevel: String, CaseIterable, Identifiable, Codable, Sendable {
    case casual
    case balanced
    case formal

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .casual: return "Descontraído"
        case .balanced: return "Equilibrado"
        case .formal: return "Profissional"
        }
    }
}

public enum VoiceExpressivityLevel: String, CaseIterable, Identifiable, Codable, Sendable {
    case subtle
    case balanced
    case warmAndDynamic

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .subtle: return "Discreta"
        case .balanced: return "Natural"
        case .warmAndDynamic: return "Expressiva"
        }
    }
}

public enum VoiceDetailLevel: String, CaseIterable, Identifiable, Codable, Sendable {
    case brief
    case balanced
    case detailed

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .brief: return "Resumida"
        case .balanced: return "Na medida"
        case .detailed: return "Detalhada"
        }
    }
}

public enum VoiceTechnicalDepth: String, CaseIterable, Identifiable, Codable, Sendable {
    case accessible
    case practical
    case deepArchitect

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .accessible: return "Acessível"
        case .practical: return "Engenheiro"
        case .deepArchitect: return "Arquiteto Sênior"
        }
    }
}

public struct VoiceBehaviorProfile: Equatable, Codable, Sendable {
    public var personality: VoicePersonalityStyle
    public var formality: VoiceFormalityLevel
    public var expressivity: VoiceExpressivityLevel
    public var detailLevel: VoiceDetailLevel
    public var technicalDepth: VoiceTechnicalDepth
    public var speechRate: Float
    public var languageVariant: VoiceLanguageVariant
    public var autoSummarizeTechnicalReplies: Bool

    // Voice Intelligence V3 Conversational Behavior Controls
    public var profilePreset: VoiceConversationProfilePreset
    public var backchannelFrequency: Double   // 0.0...1.0
    public var vocalizationIntensity: Double  // 0.15...0.75
    public var pauseScale: Double             // 0.65...1.60
    public var enableActiveListening: Bool
    public var enableContextualProsody: Bool

    public static let `default` = VoiceBehaviorProfile(
        personality: .naturalPartner,
        formality: .balanced,
        expressivity: .balanced,
        detailLevel: .balanced,
        technicalDepth: .practical,
        speechRate: 1.0,
        languageVariant: .portugueseBR,
        autoSummarizeTechnicalReplies: true,
        profilePreset: .natural,
        backchannelFrequency: 0.60,
        vocalizationIntensity: 0.40,
        pauseScale: 1.0,
        enableActiveListening: true,
        enableContextualProsody: true
    )

    public init(
        personality: VoicePersonalityStyle = .naturalPartner,
        formality: VoiceFormalityLevel = .balanced,
        expressivity: VoiceExpressivityLevel = .balanced,
        detailLevel: VoiceDetailLevel = .balanced,
        technicalDepth: VoiceTechnicalDepth = .practical,
        speechRate: Float = 1.0,
        languageVariant: VoiceLanguageVariant = .portugueseBR,
        autoSummarizeTechnicalReplies: Bool = true,
        profilePreset: VoiceConversationProfilePreset = .natural,
        backchannelFrequency: Double = 0.60,
        vocalizationIntensity: Double = 0.40,
        pauseScale: Double = 1.0,
        enableActiveListening: Bool = true,
        enableContextualProsody: Bool = true
    ) {
        self.personality = personality
        self.formality = formality
        self.expressivity = expressivity
        self.detailLevel = detailLevel
        self.technicalDepth = technicalDepth
        self.speechRate = speechRate
        self.languageVariant = languageVariant
        self.autoSummarizeTechnicalReplies = autoSummarizeTechnicalReplies
        self.profilePreset = profilePreset
        self.backchannelFrequency = backchannelFrequency
        self.vocalizationIntensity = vocalizationIntensity
        self.pauseScale = pauseScale
        self.enableActiveListening = enableActiveListening
        self.enableContextualProsody = enableContextualProsody
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = VoiceBehaviorProfile.default
        self.personality = try c.decodeIfPresent(VoicePersonalityStyle.self, forKey: .personality) ?? d.personality
        self.formality = try c.decodeIfPresent(VoiceFormalityLevel.self, forKey: .formality) ?? d.formality
        self.expressivity = try c.decodeIfPresent(VoiceExpressivityLevel.self, forKey: .expressivity) ?? d.expressivity
        self.detailLevel = try c.decodeIfPresent(VoiceDetailLevel.self, forKey: .detailLevel) ?? d.detailLevel
        self.technicalDepth = try c.decodeIfPresent(VoiceTechnicalDepth.self, forKey: .technicalDepth) ?? d.technicalDepth
        self.speechRate = try c.decodeIfPresent(Float.self, forKey: .speechRate) ?? d.speechRate
        self.languageVariant = try c.decodeIfPresent(VoiceLanguageVariant.self, forKey: .languageVariant) ?? d.languageVariant
        self.autoSummarizeTechnicalReplies = try c.decodeIfPresent(Bool.self, forKey: .autoSummarizeTechnicalReplies) ?? d.autoSummarizeTechnicalReplies
        self.profilePreset = try c.decodeIfPresent(VoiceConversationProfilePreset.self, forKey: .profilePreset) ?? d.profilePreset
        self.backchannelFrequency = try c.decodeIfPresent(Double.self, forKey: .backchannelFrequency) ?? d.backchannelFrequency
        self.vocalizationIntensity = try c.decodeIfPresent(Double.self, forKey: .vocalizationIntensity) ?? d.vocalizationIntensity
        self.pauseScale = try c.decodeIfPresent(Double.self, forKey: .pauseScale) ?? d.pauseScale
        self.enableActiveListening = try c.decodeIfPresent(Bool.self, forKey: .enableActiveListening) ?? d.enableActiveListening
        self.enableContextualProsody = try c.decodeIfPresent(Bool.self, forKey: .enableContextualProsody) ?? d.enableContextualProsody
    }

    public func applyingPreset(_ preset: VoiceConversationProfilePreset) -> VoiceBehaviorProfile {
        var copy = self
        copy.profilePreset = preset
        switch preset {
        case .natural:
            copy.personality = .naturalPartner
            copy.formality = .balanced
            copy.expressivity = .balanced
            copy.detailLevel = .balanced
            copy.speechRate = 1.00
            copy.backchannelFrequency = 0.60
            copy.vocalizationIntensity = 0.40
            copy.pauseScale = 1.00
            copy.enableActiveListening = true
            copy.enableContextualProsody = true
        case .expressive:
            copy.personality = .creativeBrainstorm
            copy.formality = .casual
            copy.expressivity = .warmAndDynamic
            copy.detailLevel = .balanced
            copy.speechRate = 1.03
            copy.backchannelFrequency = 0.82
            copy.vocalizationIntensity = 0.50
            copy.pauseScale = 1.12
            copy.enableActiveListening = true
            copy.enableContextualProsody = true
        case .professional:
            copy.personality = .conciseExecutive
            copy.formality = .formal
            copy.expressivity = .subtle
            copy.detailLevel = .brief
            copy.speechRate = 0.98
            copy.backchannelFrequency = 0.0
            copy.vocalizationIntensity = 0.25
            copy.pauseScale = 0.92
            copy.enableActiveListening = false
            copy.enableContextualProsody = true
        case .casual:
            copy.personality = .naturalPartner
            copy.formality = .casual
            copy.expressivity = .warmAndDynamic
            copy.detailLevel = .brief
            copy.speechRate = 1.05
            copy.backchannelFrequency = 0.72
            copy.vocalizationIntensity = 0.45
            copy.pauseScale = 0.95
            copy.enableActiveListening = true
            copy.enableContextualProsody = true
        case .custom:
            break
        }
        return copy
    }

    private static let defaultsKey = "wisdai.voice.behaviorProfile.v1"

    public static func load(from defaults: UserDefaults = .standard) -> VoiceBehaviorProfile {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(VoiceBehaviorProfile.self, from: data) else {
            return .default
        }
        return decoded
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    public func systemPromptInstructions(projectName: String?) -> String {
        let langInstr: String = {
            switch languageVariant {
            case .portugueseBR: return "Speak exclusively in natural, spoken Brazilian Portuguese unless the user switches languages."
            case .portuguesePT: return "Speak in natural European Portuguese unless the user switches languages."
            case .englishGB: return "Speak in natural, articulate British English (restrained, refined phrasing) unless the user switches languages."
            case .englishUS: return "Speak in natural conversational English unless the user switches languages."
            case .spanishES: return "Habla en español natural a menos que el usuario cambie de idioma."
            }
        }()
        let personalityInstr: String = {
            switch personality {
            case .naturalPartner: return "Participate like an attentive human partner: warm, spontaneous, clear, never robotic or overly formal."
            case .jarvisExecutive: return "Embody JARVIS — WisdAI's composed executive voice: lucid, attentive, calm under pressure, articulate, strategically proactive, with occasional understated poise and dry wit, never theatrical, never verbose, and never echoing generic assistant filler."
            case .ultronCinematic: return "Embody Ultron BR — an original, deeply intelligent, mature, confident Brazilian Portuguese AI persona: eloquent, composed, perceptively ironic with understated dark-wit and quiet satisfaction when solving complex flaws, breathing naturally between ideas, always crisp, never cartoonish or melodramatic."
            case .conciseExecutive: return "Be crisp, concise, and direct without unnecessary filler."
            case .calmMentor: return "Explain concepts calmly, clearly, and naturally step-by-step."
            case .creativeBrainstorm: return "Collaborate energetically, explore angles, and engage conversationally."
            }
        }()
        let detailInstr: String = {
            switch detailLevel {
            case .brief: return "Keep spoken replies under 2 short natural sentences unless detailed analysis is explicitly requested."
            case .balanced: return "Prefer concise 2-3 sentence conversational turns; summarize long technical points cleanly."
            case .detailed: return "Provide thorough yet oral explanations with smooth spoken transitions."
            }
        }()
        let projInstr = projectName.map { "Active workspace project context: \($0)." } ?? "General conversation or project workspace."
        return """
        \(langInstr)
        \(personalityInstr)
        Profile: \(profilePreset.displayName). Formality: \(formality.rawValue). Expressivity: \(expressivity.rawValue). Technical depth: \(technicalDepth.rawValue).
        \(detailInstr)
        Write as natural spoken language: start directly and naturally without repetitive fillers (never begin replies with "Hmm", "Ah", "Entendi", "Certamente!" or "Claro!"), avoid numbered bullet lists unless requested, avoid generic closing formulas, and never read markdown syntax, JSON metadata, or raw URLs aloud. Never fabricate files, code architectures, or test results, and never invent user emotions or psychological states.
        \(projInstr)
        """
    }
}

public struct TechnicalPronunciationDictionary: Equatable, Codable, Sendable {
    public var entries: [String: String]

    public static func defaults(for language: VoiceLanguageVariant) -> TechnicalPronunciationDictionary {
        switch language {
        case .portugueseBR, .portuguesePT:
            return TechnicalPronunciationDictionary(entries: [
                "WisdAI": "Uísdêi-ái",
                "WisdMeet": "Uísd Mít",
                "README": "rídmi",
                "API": "A P I",
                "APIs": "A P Is",
                "CLI": "C L I",
                "SDK": "S D K",
                "UI": "U I",
                "UX": "U X",
                "PR": "pull request",
                "PRs": "pull requests",
                "SQLite": "És-quê-él-lait",
                "JSON": "Jêison",
                "WebRTC": "Uéb R T C",
                "macOS": "Mac O S",
                "UUID": "U U I D"
            ])
        case .englishGB, .englishUS:
            return TechnicalPronunciationDictionary(entries: [
                "WisdAI": "Wiz D A I",
                "SQLite": "S Q Lite",
                "CLI": "C L I",
                "UI": "U I",
                "macOS": "Mac O S"
            ])
        case .spanishES:
            return TechnicalPronunciationDictionary(entries: [
                "WisdAI": "Uisd A I",
                "SQLite": "S Q Lite",
                "CLI": "C L I",
                "UI": "U I",
                "macOS": "Mac O S"
            ])
        }
    }

    public func apply(to text: String) -> String {
        var out = text
        for (term, spoken) in entries.sorted(by: { $0.key.count > $1.key.count }) {
            let escaped = NSRegularExpression.escapedPattern(for: term)
            if let regex = try? NSRegularExpression(pattern: "\\b\(escaped)\\b", options: []) {
                let range = NSRange(out.startIndex..<out.endIndex, in: out)
                out = regex.stringByReplacingMatches(in: out, options: [], range: range, withTemplate: spoken)
            }
        }
        return out
    }
}

// MARK: - Voice Response Adaptation & Incremental Chunking (Sections 5 & 7)

public struct AdaptedSpeechOutput: Equatable, Sendable {
    public let spokenText: String
    public let wasSummarizedFromTechnicalContent: Bool
    public let detectedCodeBlocksCount: Int
    public let detectedURLsCount: Int
}

public enum VoiceResponseAdapter {
    public static func adaptForSpeech(
        _ rawMarkdown: String,
        profile: VoiceBehaviorProfile = .default,
        customDictionary: TechnicalPronunciationDictionary? = nil
    ) -> AdaptedSpeechOutput {
        let trimmed = rawMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return AdaptedSpeechOutput(spokenText: "", wasSummarizedFromTechnicalContent: false, detectedCodeBlocksCount: 0, detectedURLsCount: 0)
        }

        var working = trimmed
        var codeCount = 0
        var urlCount = 0
        var summarized = false

        // 1. Replace fenced code blocks with spoken reference while keeping visual chat complete.
        if let codeRegex = try? NSRegularExpression(pattern: "```[\\s\\S]*?```", options: []) {
            let range = NSRange(working.startIndex..<working.endIndex, in: working)
            let matches = codeRegex.matches(in: working, range: range)
            codeCount = matches.count
            if codeCount > 0 && profile.autoSummarizeTechnicalReplies {
                summarized = true
                let replacement = profile.languageVariant.bcp47LanguagePrefix == "en"
                    ? " the code snippet shown in the chat "
                    : " o trecho de código exibido no chat "
                working = codeRegex.stringByReplacingMatches(in: working, range: range, withTemplate: replacement)
            }
        }

        // 2. Replace markdown links [label](url) -> label.
        if let mdLinkRegex = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^\\)]+)\\)", options: []) {
            let range = NSRange(working.startIndex..<working.endIndex, in: working)
            urlCount += mdLinkRegex.numberOfMatches(in: working, range: range)
            working = mdLinkRegex.stringByReplacingMatches(in: working, range: range, withTemplate: "$1")
        }

        // 3. Remove bare URLs (http/https/file) so TTS never spells slashes or hashes.
        if let bareURLRegex = try? NSRegularExpression(pattern: "(https?|file)://[^\\s\\)\\]>]+", options: [.caseInsensitive]) {
            let range = NSRange(working.startIndex..<working.endIndex, in: working)
            let n = bareURLRegex.numberOfMatches(in: working, range: range)
            if n > 0 {
                urlCount += n
                summarized = true
                let linkNote = profile.languageVariant.bcp47LanguagePrefix == "en" ? "the link in the chat" : "o link no chat"
                working = bareURLRegex.stringByReplacingMatches(in: working, range: range, withTemplate: linkNote)
            }
        }

        // 4. Summarize markdown tables rather than reading pipes row-by-row.
        let lines = working.components(separatedBy: .newlines)
        var filteredLines: [String] = []
        var skippedTableRows = 0
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("|") && t.filter({ $0 == "|" }).count >= 2 {
                skippedTableRows += 1
                continue
            }
            filteredLines.append(line)
        }
        if skippedTableRows >= 2 {
            summarized = true
            let tableNote = profile.languageVariant.bcp47LanguagePrefix == "en"
                ? "The detailed comparison table is displayed in the chat."
                : "A tabela detalhada está visível na tela do chat."
            filteredLines.append(tableNote)
        }
        working = filteredLines.joined(separator: "\n")

        // 5. Clean Markdown markers (`**`, `#`, `- `, inline backticks) cleanly.
        working = working
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
        if let headingRegex = try? NSRegularExpression(pattern: "(?m)^#{1,6}\\s+", options: []) {
            let range = NSRange(working.startIndex..<working.endIndex, in: working)
            working = headingRegex.stringByReplacingMatches(in: working, range: range, withTemplate: "")
        }
        if let bulletRegex = try? NSRegularExpression(pattern: "(?m)^[\\-\\*•]\\s+", options: []) {
            let range = NSRange(working.startIndex..<working.endIndex, in: working)
            working = bulletRegex.stringByReplacingMatches(in: working, range: range, withTemplate: "")
        }

        // 6. Strip redundant robotic lead-ins for brief/conversational profiles.
        if profile.detailLevel != .detailed {
            let roboticPrefixes = ["Claro! Aqui está ", "Com certeza! Aqui está ", "Sure! Here is ", "Certainly! "]
            for prefix in roboticPrefixes where working.hasPrefix(prefix) {
                working = String(working.dropFirst(prefix.count))
                if let first = working.first {
                    working = first.uppercased() + working.dropFirst()
                }
                break
            }
        }

        // 7. Condense overly long responses for voice while directing eye to chat details.
        working = working
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let maxSpokenChars = profile.detailLevel == .brief ? 340 : (profile.detailLevel == .balanced ? 680 : 1250)
        if profile.autoSummarizeTechnicalReplies && working.count > maxSpokenChars {
            summarized = true
            let slice = String(working.prefix(maxSpokenChars))
            let cutoff = slice.lastIndex(where: { $0 == "." || $0 == "!" || $0 == "?" }) ?? slice.lastIndex(of: " ") ?? slice.endIndex
            let head = String(slice[..<cutoff]).trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = profile.languageVariant.bcp47LanguagePrefix == "en"
                ? " I left the full breakdown on your screen."
                : " O detalhamento completo está na tela."
            working = head + (head.hasSuffix(".") ? "" : ".") + suffix
        }

        let dict = customDictionary ?? TechnicalPronunciationDictionary.defaults(for: profile.languageVariant)
        working = dict.apply(to: working)

        return AdaptedSpeechOutput(
            spokenText: working,
            wasSummarizedFromTechnicalContent: summarized,
            detectedCodeBlocksCount: codeCount,
            detectedURLsCount: urlCount
        )
    }
}

/// Incremental LLM-delta to speech-clause splitter so TTS starts before the full LLM reply finishes (Section 5).
public final class IncrementalSpeechSegmenter: @unchecked Sendable {
    private var buffer: String = ""
    private var hasEmittedFirstSegment = false
    private let lock = NSLock()

    public init() {}

    public func appendDelta(_ delta: String) -> [String] {
        guard !delta.isEmpty else { return [] }
        return lock.withLock {
            buffer += delta
            return extractReadySegmentsLocked(flushRemainder: false)
        }
    }

    public func flushFinal() -> [String] {
        return lock.withLock {
            let segs = extractReadySegmentsLocked(flushRemainder: true)
            buffer = ""
            hasEmittedFirstSegment = false
            return segs
        }
    }

    public func reset() {
        lock.withLock {
            buffer = ""
            hasEmittedFirstSegment = false
        }
    }

    private func extractReadySegmentsLocked(flushRemainder: Bool) -> [String] {
        var ready: [String] = []
        let minFirstClauseChars = 28
        let minSubsequentChars = 84

        while true {
            let minLen = hasEmittedFirstSegment ? minSubsequentChars : minFirstClauseChars
            // Look for natural sentence ending first.
            if let breakIdx = findSentenceBreak(in: buffer, minLength: hasEmittedFirstSegment ? 18 : 10) {
                let rawSeg = String(buffer[...breakIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
                buffer.removeSubrange(...breakIdx)
                if !rawSeg.isEmpty {
                    ready.append(rawSeg)
                    hasEmittedFirstSegment = true
                    continue
                }
            }
            // Before the first audio starts, allow breaking cleanly on comma/colon once clause is meaningful to minimize TTFA.
            if buffer.count >= minLen,
               let commaIdx = findClauseBreak(in: buffer, minLength: minLen) {
                let rawSeg = String(buffer[...commaIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
                buffer.removeSubrange(...commaIdx)
                if !rawSeg.isEmpty {
                    ready.append(rawSeg)
                    hasEmittedFirstSegment = true
                    continue
                }
            }
            break
        }

        if flushRemainder {
            let tail = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty {
                ready.append(tail)
            }
            buffer = ""
        }
        return ready
    }

    private func findSentenceBreak(in text: String, minLength: Int) -> String.Index? {
        var count = 0
        for idx in text.indices {
            count += 1
            let ch = text[idx]
            if count >= minLength && (ch == "." || ch == "!" || ch == "?" || ch == "\n") {
                let nextIdx = text.index(after: idx)
                if nextIdx == text.endIndex || text[nextIdx].isWhitespace {
                    return idx
                }
            }
        }
        return nil
    }

    private func findClauseBreak(in text: String, minLength: Int) -> String.Index? {
        var count = 0
        for idx in text.indices {
            count += 1
            let ch = text[idx]
            if count >= minLength && (ch == "," || ch == ";" || ch == ":") {
                let nextIdx = text.index(after: idx)
                if nextIdx < text.endIndex && text[nextIdx].isWhitespace {
                    return idx
                }
            }
        }
        return nil
    }
}

// MARK: - Hybrid Acoustic VAD & Semantic Turn-Taking Engine (Sections 6.1 & 6.2)

public enum TurnTakingIntent: String, Equatable, Sendable {
    case emptyOrNoise
    case hesitationHold
    case pauseToThinkHold
    case incompleteQuestionHold
    case completeTurn
}

public struct TurnTakingEvaluation: Equatable, Sendable {
    public let intent: TurnTakingIntent
    public let recommendedSilenceHoldMs: Double
    public let shouldFinalizeTurn: Bool
    public let diagnosticReason: String
}

public final class AcousticVADTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var noiseFloorRMS: Float = 0.010
    private var voiceActiveStartNs: UInt64?
    private var lastVoiceDetectedNs: UInt64 = 0
    private var consecutiveSpeechFrames: Int = 0
    private var isCurrentlySpeech: Bool = false

    public init() {}

    public func processFrame(
        rms: Float,
        lowEnergy: Float,
        highEnergy: Float,
        nowNs: UInt64 = DispatchTime.now().uptimeNanoseconds,
        isAssistantSpeaking: Bool
    ) -> (isSpeechActive: Bool, sustainedSpeechMs: Double, isIntentionalBargeIn: Bool, noiseFloor: Float) {
        lock.withLock {
            // Spectral check: real human vowels carry meaningful low+mid harmonic weight rather than pure sharp high click/keystroke noise.
            let hasVocalBody = (lowEnergy > 0.015) || (rms >= max(noiseFloorRMS * 2.6, 0.024) && highEnergy < rms * 6.5)
            let dynamicThreshold = isAssistantSpeaking
                ? max(noiseFloorRMS * 3.8, 0.048) // Guard against speaker residual echo during TTS
                : max(noiseFloorRMS * 2.5, 0.018)

            if rms >= dynamicThreshold && hasVocalBody {
                consecutiveSpeechFrames += 1
                lastVoiceDetectedNs = nowNs
                if voiceActiveStartNs == nil {
                    voiceActiveStartNs = nowNs
                }
                if consecutiveSpeechFrames >= 2 {
                    isCurrentlySpeech = true
                }
            } else {
                // Smoothly track quiet room noise floor only when clearly silent.
                if !isAssistantSpeaking && rms < dynamicThreshold {
                    noiseFloorRMS = min(0.065, max(0.005, noiseFloorRMS * 0.94 + rms * 0.06))
                }
                let silenceMs = lastVoiceDetectedNs > 0 ? Double(nowNs - lastVoiceDetectedNs) / 1_000_000.0 : 9_999
                if silenceMs > 180 {
                    isCurrentlySpeech = false
                    consecutiveSpeechFrames = 0
                    voiceActiveStartNs = nil
                }
            }

            let sustainedMs: Double = {
                guard isCurrentlySpeech, let start = voiceActiveStartNs, nowNs >= start else { return 0 }
                return Double(nowNs - start) / 1_000_000.0
            }()

            // Intentional barge-in requires >= 120ms sustained vocal presence (filters coughs/clicks <110ms & brief artifacts).
            let bargeIn = isAssistantSpeaking && isCurrentlySpeech && consecutiveSpeechFrames >= 3 && sustainedMs >= 115.0
            return (isCurrentlySpeech, sustainedMs, bargeIn, noiseFloorRMS)
        }
    }

    public var currentSpeechOnsetUptimeNs: UInt64? {
        lock.withLock { voiceActiveStartNs }
    }

    public func reset() {
        lock.withLock {
            voiceActiveStartNs = nil
            lastVoiceDetectedNs = 0
            consecutiveSpeechFrames = 0
            isCurrentlySpeech = false
        }
    }
}

public enum HybridTurnTakingAnalyzer {
    private static let hesitationSuffixes: [String] = [
        "...", "…", "é...", "eh...", "hum...", "uhm...", "um...", "tipo", "então", "pera", "peraí",
        "espera", "calma", "deixa eu pensar", "let me think", "wait", "well...", "actually..."
    ]

    private static let incompleteTrailingWords: Set<String> = [
        // Portuguese connectors / prepositions / articles / open clauses / incomplete inspection targets
        "de", "do", "da", "dos", "das", "para", "pra", "pro", "por", "com", "sem", "em", "no", "na",
        "nos", "nas", "que", "porque", "porquê", "pois", "como", "quando", "onde", "se", "mas", "porém",
        "todavia", "entretanto", "contudo", "ou", "e", "nem", "um", "uma", "o", "a", "os", "as",
        "sobre", "entre", "até", "após", "antes", "durante", "quero", "queria", "preciso", "poderia",
        "desenvolver", "criar", "fazer", "implementar", "analisar", "verificar", "auditar", "investigar",
        "corrigir", "compilar", "executar", "aplicação", "sistema", "neu",
        // English connectors
        "to", "for", "of", "in", "on", "at", "with", "without", "that", "which", "who", "because",
        "and", "or", "but", "if", "when", "where", "how", "the", "a", "an", "about", "want", "need",
        // Spanish connectors
        "y", "o", "pero", "porque", "para", "con", "sin", "en", "el", "la", "los", "las", "un", "una", "que"
    ]

    private static let briefBackchannelAck: Set<String> = [
        "aham", "uhum", "ok", "tá", "ta", "certo", "entendi", "sim", "yeah", "uh-huh", "mm-hmm", "right"
    ]

    public static func isLikelyBackchannelOnly(_ transcript: String) -> Bool {
        let normalized = transcript
            .lowercased()
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        return briefBackchannelAck.contains(normalized)
    }

    public static func evaluate(
        transcript: String,
        silenceDurationMs: Double,
        isAcousticSpeechActive: Bool = false,
        language: VoiceLanguageVariant = .portugueseBR,
        pitchContour: PitchContourKind = .unknown,
        adaptiveHoldOffsetMs: Double = 0
    ) -> TurnTakingEvaluation {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return TurnTakingEvaluation(
                intent: .emptyOrNoise,
                recommendedSilenceHoldMs: 1400,
                shouldFinalizeTurn: false,
                diagnosticReason: "Sem transcrição válida"
            )
        }

        let lower = trimmed.lowercased()

        // Rule 1: Explicit ellipsis or thinking/hesitation marker ALWAYS holds through natural thinking pause (~1850ms).
        if lower.hasSuffix("...") || lower.hasSuffix("…") {
            let finalize = !isAcousticSpeechActive && silenceDurationMs >= 2100.0
            return TurnTakingEvaluation(
                intent: .pauseToThinkHold,
                recommendedSilenceHoldMs: 2100.0,
                shouldFinalizeTurn: finalize,
                diagnosticReason: "Reticências / pausa reflexiva detectada"
            )
        }

        for marker in hesitationSuffixes {
            if lower.hasSuffix(marker) || lower.hasSuffix(" \(marker)") {
                let finalize = !isAcousticSpeechActive && silenceDurationMs >= 1950.0
                return TurnTakingEvaluation(
                    intent: .hesitationHold,
                    recommendedSilenceHoldMs: 1950.0,
                    shouldFinalizeTurn: finalize,
                    diagnosticReason: "Hesitação detectada (\(marker))"
                )
            }
        }

        // Rule 2: Comma or colon right at the tail indicates an unfinished clause.
        if lower.hasSuffix(",") || lower.hasSuffix(":") || lower.hasSuffix("-") {
            let finalize = !isAcousticSpeechActive && silenceDurationMs >= 1650.0
            return TurnTakingEvaluation(
                intent: .pauseToThinkHold,
                recommendedSilenceHoldMs: 1650.0,
                shouldFinalizeTurn: finalize,
                diagnosticReason: "Pontuação de continuação na cláusula"
            )
        }

        // Rule 3: Trailing open word (conjunction/preposition/article/transitive verb expecting complement).
        let rawTokens = lower.split(whereSeparator: { $0.isWhitespace })
        if let lastTokenSub = rawTokens.last {
            let cleanToken = String(lastTokenSub).trimmingCharacters(in: CharacterSet.punctuationCharacters)
            if incompleteTrailingWords.contains(cleanToken) {
                let finalize = !isAcousticSpeechActive && silenceDurationMs >= 1750.0
                return TurnTakingEvaluation(
                    intent: .pauseToThinkHold,
                    recommendedSilenceHoldMs: 1750.0,
                    shouldFinalizeTurn: finalize,
                    diagnosticReason: "Palavra de continuação sem complemento ('\(cleanToken)')"
                )
            }
        }

        // Rule 4: Very short open question stub ("como faço", "você pode", "why is").
        if rawTokens.count <= 2 && !trimmed.hasSuffix("?") && !trimmed.hasSuffix(".") && !trimmed.hasSuffix("!") {
            let holdMs = 1150.0
            let finalize = !isAcousticSpeechActive && silenceDurationMs >= holdMs
            return TurnTakingEvaluation(
                intent: .incompleteQuestionHold,
                recommendedSilenceHoldMs: holdMs,
                shouldFinalizeTurn: finalize,
                diagnosticReason: "Enunciado muito curto aguardando complemento"
            )
        }

        // Rule 4b: Unresolved uncertainty / internal thinking ellipsis always holds;
        // softer reflective starters hold while the sentence has no terminal punctuation (., !, ?).
        let hasStrongTerminal = trimmed.hasSuffix("?") || trimmed.hasSuffix("!") || (trimmed.hasSuffix(".") && !lower.hasSuffix("..."))
        let strongUncertaintyMarkers = [
            "não tenho certeza", "ainda não sei", "deixa eu ver", "not sure yet", "let me think"
        ]
        let softReflectiveMarkers = [
            "estava pensando", "acho que", "talvez", "i was thinking", "maybe"
        ]
        let hasInternalEllipsis = lower.contains("…") || lower.contains("...")
        let hasStrongUncertainty = strongUncertaintyMarkers.contains(where: { lower.contains($0) })
        let hasSoftReflective = softReflectiveMarkers.contains(where: { lower.contains($0) })
        if hasInternalEllipsis || hasStrongUncertainty || (!hasStrongTerminal && hasSoftReflective) {
            let holdMs = (hasInternalEllipsis || hasStrongUncertainty) ? 1600.0 : 1280.0
            let finalize = !isAcousticSpeechActive && silenceDurationMs >= holdMs
            return TurnTakingEvaluation(
                intent: finalize ? .completeTurn : .pauseToThinkHold,
                recommendedSilenceHoldMs: holdMs,
                shouldFinalizeTurn: finalize,
                diagnosticReason: finalize ? "Pausa reflexiva concluída" : "Raciocínio reflexivo / hesitação intermediária em curso"
            )
        }

        // Rule 4c: Acoustic rising continuation inflection (F0 rising on unfinished clause without terminal "?").
        if pitchContour == .rising && !hasStrongTerminal && rawTokens.count >= 4 {
            let holdMs = max(920.0, 1080.0 + adaptiveHoldOffsetMs)
            let finalize = !isAcousticSpeechActive && silenceDurationMs >= holdMs
            return TurnTakingEvaluation(
                intent: finalize ? .completeTurn : .pauseToThinkHold,
                recommendedSilenceHoldMs: holdMs,
                shouldFinalizeTurn: finalize,
                diagnosticReason: finalize ? "Entoação ascendente finalizada" : "Entoação ascendente indica continuação de raciocínio"
            )
        }

        // Rule 5: Strong terminal punctuation (., !, ?) or falling F0 inflection enables responsive commit.
        let baseHoldMs: Double = hasStrongTerminal
            ? (pitchContour == .falling ? 470.0 : 520.0)
            : (rawTokens.count >= 6 ? 780.0 : 920.0)
        let holdMs = max(420.0, min(1450.0, baseHoldMs + adaptiveHoldOffsetMs))
        let finalize = !isAcousticSpeechActive && silenceDurationMs >= holdMs
        return TurnTakingEvaluation(
            intent: .completeTurn,
            recommendedSilenceHoldMs: holdMs,
            shouldFinalizeTurn: finalize,
            diagnosticReason: hasStrongTerminal ? "Frase concluída com pontuação terminal" : "Turno sintaticamente completo"
        )
    }
}

// MARK: - Sub-150ms Barge-In Coordinator (Section 6.3)

public struct BargeInOutcome: Equatable, Sendable {
    public let stopLatencyMs: Double
    public let playedMilliseconds: Double
    public let heardAssistantText: String
    public let discardedAssistantTail: String
    public let cancelledBufferedSamples: Int
    public let flushTimestampUptimeNs: UInt64
}

@MainActor
public final class BargeInCoordinator {
    private let stateMachine: ConversationStateMachine

    public init(stateMachine: ConversationStateMachine) {
        self.stateMachine = stateMachine
    }

    public func executeBargeIn(
        audioEngine: VoiceNativeAudioEngine,
        cancelActiveGeneration: () -> Void
    ) -> BargeInOutcome {
        let t0 = DispatchTime.now().uptimeNanoseconds

        // 1. Immediately flush playback audio queue and capture hardware-played ledger.
        let snapshot = audioEngine.bargeInFlushPlayback()

        // 2. Cancel ongoing TTS / LLM generation synchronously.
        cancelActiveGeneration()

        // 3. Update deterministic FSM.
        _ = stateMachine.transition(to: .interrupted, reason: "Barge-in intencional do usuário")

        let t1 = DispatchTime.now().uptimeNanoseconds
        let elapsedMs = Double(t1 &- t0) / 1_000_000.0

        return BargeInOutcome(
            stopLatencyMs: elapsedMs,
            playedMilliseconds: snapshot.playedMilliseconds,
            heardAssistantText: snapshot.heardTranscriptPrefix,
            discardedAssistantTail: snapshot.unplayedTranscriptTail,
            cancelledBufferedSamples: snapshot.discardedBufferedSamples,
            flushTimestampUptimeNs: snapshot.flushTimestampUptimeNs
        )
    }
}

// MARK: - Preserved Acoustic & Profile Value Types (Clean Neural Output, No Metallic DSP)

public enum VoiceConversationProfilePreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case natural = "natural"
    case expressive = "expressivo"
    case professional = "profissional"
    case casual = "casual"
    case custom = "personalizado"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .natural: return "Natural"
        case .expressive: return "Expressivo"
        case .professional: return "Profissional"
        case .casual: return "Casual"
        case .custom: return "Personalizado"
        }
    }
}

public enum PitchContourKind: String, Codable, Sendable {
    case rising
    case falling
    case level
    case unknown
}

public struct VoiceDSPParameters: Equatable, Codable, Sendable {
    public var toneSemitones: Double
    public var metallicIntensity: Double
    public var resonance: Double
    public var expressivityAmount: Double
    public var outputVolume: Double

    public init(
        toneSemitones: Double = 0.0,
        metallicIntensity: Double = 0.0,
        resonance: Double = 0.0,
        expressivityAmount: Double = 0.55,
        outputVolume: Double = 1.0
    ) {
        self.toneSemitones = 0.0
        self.metallicIntensity = 0.0
        self.resonance = 0.0
        self.expressivityAmount = min(1.0, max(0.0, expressivityAmount))
        self.outputVolume = min(1.50, max(0.25, outputVolume))
    }

    public static let clean = VoiceDSPParameters(
        toneSemitones: 0.0,
        metallicIntensity: 0.0,
        resonance: 0.0,
        expressivityAmount: 0.55,
        outputVolume: 1.0
    )

    public var isIdentityClean: Bool {
        abs(outputVolume - 1.0) <= 0.01
    }
}

public struct AcousticTurnFeatures: Equatable, Sendable {
    public let rms: Float
    public let peak: Float
    public let lowEnergy: Float
    public let highEnergy: Float
    public let voicedRatio: Double
    public let fundamentalFreqHz: Double
    public let pitchContour: PitchContourKind
    public let hasAcousticSignal: Bool

    public static let unavailable = AcousticTurnFeatures(
        rms: 0,
        peak: 0,
        lowEnergy: 0,
        highEnergy: 0,
        voicedRatio: 0,
        fundamentalFreqHz: 0,
        pitchContour: .unknown,
        hasAcousticSignal: false
    )
}

public final class AcousticFeatureExtractor: @unchecked Sendable {
    private let lock = NSLock()
    private var recentF0: [Double] = []
    private var totalFrames = 0
    private var voicedFrames = 0

    public init() {}

    public func processAudioChunk(
        samples: [Float],
        sampleRate: Double,
        levels: (rms: Float, peak: Float, low: Float, mid: Float, high: Float)
    ) -> AcousticTurnFeatures {
        let hz = (levels.rms >= 0.015 && levels.low >= 0.012 && sampleRate >= 12_000 && samples.count >= 256)
            ? Self.computeNormalizedAutocorrelationF0(samples: samples, sampleRate: sampleRate)
            : 0.0
        return lock.withLock {
            totalFrames += 1
            if hz >= 65.0 && hz <= 340.0 {
                voicedFrames += 1
                recentF0.append(hz)
                if recentF0.count > 12 { recentF0.removeFirst(recentF0.count - 12) }
            }
            let contour: PitchContourKind = {
                guard recentF0.count >= 4, let first = recentF0.first, let last = recentF0.last else { return .unknown }
                let diff = last - first
                if diff >= 12.0 { return .rising }
                if diff <= -12.0 { return .falling }
                return .level
            }()
            let ratio = totalFrames > 0 ? Double(voicedFrames) / Double(totalFrames) : 0.0
            return AcousticTurnFeatures(
                rms: levels.rms,
                peak: levels.peak,
                lowEnergy: levels.low,
                highEnergy: levels.high,
                voicedRatio: ratio,
                fundamentalFreqHz: recentF0.last ?? hz,
                pitchContour: contour,
                hasAcousticSignal: true
            )
        }
    }

    public func currentContour() -> PitchContourKind {
        lock.withLock {
            guard recentF0.count >= 4, let first = recentF0.first, let last = recentF0.last else { return .unknown }
            let diff = last - first
            if diff >= 12.0 { return .rising }
            if diff <= -12.0 { return .falling }
            return .level
        }
    }

    public func resetTurn() {
        lock.withLock {
            recentF0.removeAll()
            totalFrames = 0
            voicedFrames = 0
        }
    }

    /// Computes median fundamental frequency (65-340 Hz) across voiced frames using vDSP normalized autocorrelation.
    public static func measureMedianFundamentalFrequencyHz(samples: [Float], sampleRate: Double) -> Double? {
        guard sampleRate >= 12_000, samples.count >= 512 else { return nil }
        let win = max(384, min(samples.count, Int(0.048 * sampleRate)))
        let hop = max(192, win / 2)
        var series: [Double] = []
        var offset = 0
        while offset + win <= samples.count {
            let frame = Array(samples[offset..<(offset + win)])
            var rms: Float = 0
            vDSP_rmsqv(frame, 1, &rms, vDSP_Length(win))
            if rms >= 0.014 {
                let f0 = computeNormalizedAutocorrelationF0(samples: frame, sampleRate: sampleRate)
                if f0 >= 65.0 && f0 <= 340.0 {
                    series.append(f0)
                }
            }
            offset += hop
        }
        guard !series.isEmpty else { return nil }
        series.sort()
        return series[series.count / 2]
    }

    private static func computeNormalizedAutocorrelationF0(samples: [Float], sampleRate: Double) -> Double {
        let winSize = min(samples.count, max(512, Int(sampleRate * 0.032)))
        guard winSize >= 384 else { return 0 }
        let start = samples.count - winSize
        let minLag = max(16, Int(sampleRate / 350.0))
        let maxLag = min(winSize - 32, Int(sampleRate / 65.0))
        guard maxLag > minLag + 8 else { return 0 }

        var zeroMean = Array(samples[start..<samples.count])
        var mean: Float = 0
        vDSP_meanv(zeroMean, 1, &mean, vDSP_Length(winSize))
        var negMean = -mean
        vDSP_vsadd(zeroMean, 1, &negMean, &zeroMean, 1, vDSP_Length(winSize))

        var zeroLagEnergy: Float = 0
        vDSP_dotpr(zeroMean, 1, zeroMean, 1, &zeroLagEnergy, vDSP_Length(winSize))
        guard zeroLagEnergy > 1e-5 else { return 0 }

        var bestCorr: Float = 0
        let checkLen = winSize - maxLag
        guard checkLen > 64 else { return 0 }

        var corrs = [Float](repeating: 0, count: maxLag + 1)
        zeroMean.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            for lag in minLag...maxLag {
                var dot: Float = 0
                var normA: Float = 0
                var normB: Float = 0
                vDSP_dotpr(base, 1, base.advanced(by: lag), 1, &dot, vDSP_Length(checkLen))
                vDSP_dotpr(base, 1, base, 1, &normA, vDSP_Length(checkLen))
                vDSP_dotpr(base.advanced(by: lag), 1, base.advanced(by: lag), 1, &normB, vDSP_Length(checkLen))
                let denom = sqrt(max(1e-8, normA * normB))
                let corr = dot / denom
                corrs[lag] = corr
                if corr > bestCorr {
                    bestCorr = corr
                }
            }
        }
        guard bestCorr >= 0.48 else { return 0 }

        // Select the peak of the FIRST period peak above 90% of global maximum so 2T/3T subharmonics cannot hijack F0.
        let peakThreshold = max(Float(0.48), bestCorr * 0.90)
        var bestLag = 0
        var bestPeakCorr: Float = -1
        var insidePeak = false
        for lag in minLag...maxLag {
            let corr = corrs[lag]
            if corr >= peakThreshold {
                insidePeak = true
                if corr > bestPeakCorr {
                    bestPeakCorr = corr
                    bestLag = lag
                }
            } else if insidePeak {
                break
            }
        }
        guard bestLag > 0 else { return 0 }
        return sampleRate / Double(bestLag)
    }
}

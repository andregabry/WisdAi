import Accelerate
import Foundation

// MARK: - Section 12: Evolved Voice Personality Engine (Aurora, Atlas, Aria)

public struct VoicePersonalityProfile: Equatable, Codable, Sendable {
    public let persona: WisdVoicePersona
    public let conversationalWarmth: Double   // 0.0...1.0
    public let formality: VoiceFormalityLevel
    public let energy: Double                 // 0.0...1.0
    public let cadenceRate: Float             // 0.85...1.15
    public let backchannelFrequency: Double   // 0.0...1.0
    public let expressivity: VoiceExpressivityLevel
    public let directness: Double             // 0.0...1.0 (objectivity)
    public let interactionStyle: String

    public static func profile(for persona: WisdVoicePersona) -> VoicePersonalityProfile {
        switch persona {
        case .aurora:
            return VoicePersonalityProfile(
                persona: .aurora,
                conversationalWarmth: 0.84,
                formality: .balanced,
                energy: 0.68,
                cadenceRate: 1.00,
                backchannelFrequency: 0.62,
                expressivity: .balanced,
                directness: 0.72,
                interactionStyle: "Parceira conversacional acolhedora, fluida e atenta ao ritmo de quem fala."
            )
        case .atlas:
            return VoicePersonalityProfile(
                persona: .atlas,
                conversationalWarmth: 0.62,
                formality: .formal,
                energy: 0.50,
                cadenceRate: 0.96,
                backchannelFrequency: 0.42,
                expressivity: .subtle,
                directness: 0.88,
                interactionStyle: "Interlocutor calmo, firme e técnico; escuta pacientemente antes de sintetizar."
            )
        case .aria:
            return VoicePersonalityProfile(
                persona: .aria,
                conversationalWarmth: 0.80,
                formality: .casual,
                energy: 0.84,
                cadenceRate: 1.06,
                backchannelFrequency: 0.78,
                expressivity: .warmAndDynamic,
                directness: 0.68,
                interactionStyle: "Colaboradora energética e espontânea, ótima para explorar ideias e prototipar."
            )
        }
    }
}

// MARK: - Section 13: Conversation Behavior Profiles (Natural, Expressivo, Profissional, Casual, Personalizado)

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

    public var subtitle: String {
        switch self {
        case .natural: return "Conversação equilibrada, fluida e contextual"
        case .expressive: return "Maior variedade de entoação e feedback vocal"
        case .professional: return "Comunicação técnica, clara e objetiva"
        case .casual: return "Comunicação descontraída e espontânea"
        case .custom: return "Ajuste manual de escuta ativa, ritmo e expressividade"
        }
    }
}

// MARK: - Section 9: Contextual Acoustic Intelligence (Lightweight 8 GB Safe DSP)

public enum PitchContourKind: String, Codable, Sendable {
    case rising
    case falling
    case level
    case unknown
}

public struct AcousticTurnFeatures: Equatable, Sendable {
    public let rms: Float
    public let peak: Float
    public let lowEnergy: Float
    public let highEnergy: Float
    public let voicedRatio: Double
    public let fundamentalFreqHz: Double
    public let f0SlopeHzPerSec: Double
    public let pitchContour: PitchContourKind
    public let estimatedTempoWPM: Double
    public let energyDecaySlope: Double
    public let pauseDurationMs: Double
    public let hasAcousticSignal: Bool

    public static let unavailable = AcousticTurnFeatures(
        rms: 0,
        peak: 0,
        lowEnergy: 0,
        highEnergy: 0,
        voicedRatio: 0,
        fundamentalFreqHz: 0,
        f0SlopeHzPerSec: 0,
        pitchContour: .unknown,
        estimatedTempoWPM: 135.0,
        energyDecaySlope: 0,
        pauseDurationMs: 0,
        hasAcousticSignal: false
    )
}

public final class AcousticFeatureExtractor: @unchecked Sendable {
    private struct PitchPoint {
        let timeSec: Double
        let f0Hz: Double
        let rms: Float
    }

    private let lock = NSLock()
    private var recentPoints: [PitchPoint] = []
    private var totalFramesInTurn: Int = 0
    private var voicedFramesInTurn: Int = 0
    private var turnSpeechStartNs: UInt64 = 0
    private var lastTranscriptWords: Int = 0
    private var currentTempoWPM: Double = 135.0

    public init() {}

    public func processAudioChunk(
        samples: [Float],
        sampleRate: Double,
        levels: (rms: Float, peak: Float, low: Float, mid: Float, high: Float),
        nowNs: UInt64 = DispatchTime.now().uptimeNanoseconds,
        pauseDurationMs: Double = 0
    ) -> AcousticTurnFeatures {
        let estimatedHz: Double = (levels.rms >= 0.015 && levels.low >= 0.012 && sampleRate >= 12_000 && samples.count >= 256)
            ? estimateFundamentalFrequencyHz(samples: samples, sampleRate: sampleRate)
            : 0.0

        return lock.withLock {
            totalFramesInTurn += 1
            if turnSpeechStartNs == 0 && levels.rms >= 0.014 {
                turnSpeechStartNs = nowNs
            }
            if estimatedHz > 0 {
                voicedFramesInTurn += 1
                let tSec = turnSpeechStartNs > 0 && nowNs >= turnSpeechStartNs
                    ? Double(nowNs &- turnSpeechStartNs) / 1_000_000_000.0
                    : 0.0
                recentPoints.append(PitchPoint(timeSec: tSec, f0Hz: estimatedHz, rms: levels.rms))
                if recentPoints.count > 12 {
                    recentPoints.removeFirst(recentPoints.count - 12)
                }
            }

            let slope = computePitchSlopeLocked()
            let energySlope = computeEnergySlopeLocked()
            let contour: PitchContourKind = {
                guard recentPoints.count >= 3 else { return .unknown }
                if slope >= 18.0 { return .rising }
                if slope <= -18.0 { return .falling }
                return .level
            }()
            let ratio = totalFramesInTurn > 0 ? Double(voicedFramesInTurn) / Double(totalFramesInTurn) : 0.0
            let latestF0 = recentPoints.last?.f0Hz ?? estimatedHz

            return AcousticTurnFeatures(
                rms: levels.rms,
                peak: levels.peak,
                lowEnergy: levels.low,
                highEnergy: levels.high,
                voicedRatio: ratio,
                fundamentalFreqHz: latestF0,
                f0SlopeHzPerSec: slope,
                pitchContour: contour,
                estimatedTempoWPM: currentTempoWPM,
                energyDecaySlope: energySlope,
                pauseDurationMs: pauseDurationMs,
                hasAcousticSignal: true
            )
        }
    }

    public func updateTranscriptTempo(wordCount: Int, nowNs: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        lock.withLock {
            guard wordCount > lastTranscriptWords else { return }
            lastTranscriptWords = wordCount
            if turnSpeechStartNs == 0 {
                turnSpeechStartNs = nowNs
                return
            }
            let elapsedMin = max(0.025, Double(nowNs &- turnSpeechStartNs) / 60_000_000_000.0)
            let rawWPM = Double(wordCount) / elapsedMin
            let bounded = min(230.0, max(75.0, rawWPM))
            currentTempoWPM = currentTempoWPM * 0.65 + bounded * 0.35
        }
    }

    public func currentSnapshot(pauseDurationMs: Double = 0) -> AcousticTurnFeatures {
        lock.withLock {
            guard totalFramesInTurn > 0 else { return .unavailable }
            let slope = computePitchSlopeLocked()
            let energySlope = computeEnergySlopeLocked()
            let contour: PitchContourKind = {
                guard recentPoints.count >= 3 else { return .unknown }
                if slope >= 18.0 { return .rising }
                if slope <= -18.0 { return .falling }
                return .level
            }()
            let ratio = Double(voicedFramesInTurn) / Double(totalFramesInTurn)
            return AcousticTurnFeatures(
                rms: recentPoints.last?.rms ?? 0,
                peak: recentPoints.last?.rms ?? 0,
                lowEnergy: 0,
                highEnergy: 0,
                voicedRatio: ratio,
                fundamentalFreqHz: recentPoints.last?.f0Hz ?? 0,
                f0SlopeHzPerSec: slope,
                pitchContour: contour,
                estimatedTempoWPM: currentTempoWPM,
                energyDecaySlope: energySlope,
                pauseDurationMs: pauseDurationMs,
                hasAcousticSignal: true
            )
        }
    }

    public func resetTurn() {
        lock.withLock {
            recentPoints.removeAll(keepingCapacity: true)
            totalFramesInTurn = 0
            voicedFramesInTurn = 0
            turnSpeechStartNs = 0
            lastTranscriptWords = 0
        }
    }

    private func computePitchSlopeLocked() -> Double {
        guard recentPoints.count >= 3,
              let first = recentPoints.first,
              let last = recentPoints.last else { return 0 }
        let dt = last.timeSec - first.timeSec
        guard dt >= 0.08 else { return 0 }
        let half = recentPoints.count / 2
        let headAvg = recentPoints.prefix(half).map(\.f0Hz).reduce(0, +) / Double(max(1, half))
        let tailSlice = recentPoints.suffix(recentPoints.count - half)
        let tailAvg = tailSlice.map(\.f0Hz).reduce(0, +) / Double(max(1, tailSlice.count))
        return (tailAvg - headAvg) / dt
    }

    private func computeEnergySlopeLocked() -> Double {
        guard recentPoints.count >= 3,
              let first = recentPoints.first,
              let last = recentPoints.last else { return 0 }
        let dt = max(0.08, last.timeSec - first.timeSec)
        return Double(last.rms - first.rms) / dt
    }

    /// Lightweight time-domain normalized autocorrelation F0 detector (75–350 Hz) using vDSP.
    private func estimateFundamentalFrequencyHz(samples: [Float], sampleRate: Double) -> Double {
        let winSize = min(samples.count, max(512, Int(sampleRate * 0.032)))
        guard winSize >= 384 else { return 0 }
        let start = samples.count - winSize
        let minLag = max(16, Int(sampleRate / 350.0))
        let maxLag = min(winSize - 32, Int(sampleRate / 75.0))
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
        var bestLag = 0
        let checkLen = winSize - maxLag
        guard checkLen > 64 else { return 0 }

        zeroMean.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            var lag = minLag
            while lag <= maxLag {
                var dot: Float = 0
                var normA: Float = 0
                var normB: Float = 0
                vDSP_dotpr(base, 1, base.advanced(by: lag), 1, &dot, vDSP_Length(checkLen))
                vDSP_dotpr(base, 1, base, 1, &normA, vDSP_Length(checkLen))
                vDSP_dotpr(base.advanced(by: lag), 1, base.advanced(by: lag), 1, &normB, vDSP_Length(checkLen))
                let denom = sqrt(max(1e-9, normA * normB))
                let ncorr = dot / denom
                if ncorr > bestCorr {
                    bestCorr = ncorr
                    bestLag = lag
                }
                lag += 2 // Coarse stride 2 (~0.04ms cost on M2) refined immediately below
            }
        }

        guard bestCorr >= 0.56, bestLag > minLag else { return 0 }
        // Fine +/-1 sample local polish
        let lowRefine = max(minLag, bestLag - 1)
        let highRefine = min(maxLag, bestLag + 1)
        var refinedLag = bestLag
        var refinedCorr = bestCorr
        zeroMean.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            for lag in lowRefine...highRefine where lag != bestLag {
                var dot: Float = 0
                var normA: Float = 0
                var normB: Float = 0
                vDSP_dotpr(base, 1, base.advanced(by: lag), 1, &dot, vDSP_Length(checkLen))
                vDSP_dotpr(base, 1, base, 1, &normA, vDSP_Length(checkLen))
                vDSP_dotpr(base.advanced(by: lag), 1, base.advanced(by: lag), 1, &normB, vDSP_Length(checkLen))
                let ncorr = dot / sqrt(max(1e-9, normA * normB))
                if ncorr > refinedCorr {
                    refinedCorr = ncorr
                    refinedLag = lag
                }
            }
        }
        guard refinedLag > 0 else { return 0 }
        let hz = sampleRate / Double(refinedLag)
        return (hz >= 75.0 && hz <= 350.0) ? hz : 0
    }
}

/// Adapts assistant cadence subtly to the user's speaking rhythm across turns,
/// explicitly without asserting or storing emotional states as psychological facts.
public final class UserConversationalStyleAdapter: @unchecked Sendable {
    private let lock = NSLock()
    private var rollingUserTempoWPM: Double = 135.0
    private var rollingPauseMs: Double = 620.0
    private var observedTurnsCount: Int = 0

    public init() {}

    public func observeTurn(acoustic: AcousticTurnFeatures, turnDurationSec: Double) {
        guard turnDurationSec >= 0.6 else { return }
        lock.withLock {
            observedTurnsCount += 1
            if acoustic.hasAcousticSignal && acoustic.estimatedTempoWPM >= 75 && acoustic.estimatedTempoWPM <= 230 {
                rollingUserTempoWPM = rollingUserTempoWPM * 0.70 + acoustic.estimatedTempoWPM * 0.30
            }
            if acoustic.pauseDurationMs > 120 && acoustic.pauseDurationMs < 2400 {
                rollingPauseMs = rollingPauseMs * 0.72 + acoustic.pauseDurationMs * 0.28
            }
        }
    }

    public func adaptiveCadenceMultiplier() -> Float {
        lock.withLock {
            guard observedTurnsCount >= 2 else { return 1.0 }
            if rollingUserTempoWPM >= 165 { return 1.04 }
            if rollingUserTempoWPM <= 105 { return 0.96 }
            return 1.0
        }
    }

    public func recommendedTurnHoldAdjustmentMs() -> Double {
        lock.withLock {
            guard observedTurnsCount >= 2 else { return 0 }
            if rollingPauseMs >= 950 { return 140.0 }
            if rollingPauseMs <= 420 { return -60.0 }
            return 0
        }
    }

    public func snapshotSummary() -> String {
        lock.withLock {
            String(format: "Ritmo %.0f pal/min · Pausa média %.0f ms (%d turnos)", rollingUserTempoWPM, rollingPauseMs, observedTurnsCount)
        }
    }

    public func reset() {
        lock.withLock {
            rollingUserTempoWPM = 135.0
            rollingPauseMs = 620.0
            observedTurnsCount = 0
        }
    }
}

// MARK: - Section 6: Conversational Behavior Planner & Vocalization Vocabulary

public enum VocalizationKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case uhum
    case aham
    case hmm
    case sei
    case entendi
    case certo
    case ahSim = "ah_sim"
    case interessante
    case olha
    case boaPergunta = "boa_pergunta"

    public var id: String { rawValue }

    public var isBackchannelCandidate: Bool {
        switch self {
        case .uhum, .aham, .hmm, .sei, .entendi, .certo, .ahSim, .interessante:
            return true
        case .olha, .boaPergunta:
            return false
        }
    }

    public var isTurnLeadCandidate: Bool {
        switch self {
        case .hmm, .olha, .boaPergunta, .certo, .entendi, .ahSim, .interessante:
            return true
        case .uhum, .aham, .sei:
            return false
        }
    }

    public func spokenText(for language: VoiceLanguageVariant) -> String {
        switch language {
        case .englishUS:
            switch self {
            case .uhum: return "Uh-huh."
            case .aham: return "Mhm!"
            case .hmm: return "Hmm…"
            case .sei: return "I see…"
            case .entendi: return "Got it…"
            case .certo: return "Right…"
            case .ahSim: return "Oh, right!"
            case .interessante: return "Interesting…"
            case .olha: return "Look,"
            case .boaPergunta: return "Good question."
            }
        case .spanishES:
            switch self {
            case .uhum: return "Ajá…"
            case .aham: return "Mm-hm!"
            case .hmm: return "Hmm…"
            case .sei: return "Ya…"
            case .entendi: return "Entiendo…"
            case .certo: return "Claro…"
            case .ahSim: return "¡Ah, sí!"
            case .interessante: return "Interesante…"
            case .olha: return "Mira,"
            case .boaPergunta: return "Buena pregunta."
            }
        case .portugueseBR, .portuguesePT:
            switch self {
            case .uhum: return "Uhum…"
            case .aham: return "Aham!"
            case .hmm: return "Hmm…"
            case .sei: return "Sei…"
            case .entendi: return "Entendi…"
            case .certo: return "Certo…"
            case .ahSim: return "Ah, sim!"
            case .interessante: return "Interessante…"
            case .olha: return "Olha,"
            case .boaPergunta: return "Boa pergunta."
            }
        }
    }

    public var communicativeIntent: String {
        switch self {
        case .uhum, .aham: return "continuidade_ativa"
        case .hmm: return "reflexao"
        case .sei, .entendi: return "compreensao"
        case .certo: return "confirmacao_leve"
        case .ahSim: return "revelacao"
        case .interessante: return "engajamento_curioso"
        case .olha: return "transicao_oral"
        case .boaPergunta: return "gancho_pensamento"
        }
    }
}

public enum ConversationalIntentKind: String, Codable, Sendable {
    case acknowledgment
    case directAnswer = "direct_answer"
    case reflection
    case enthusiasm
    case uncertainty
    case reassurance
    case technicalExplanation = "technical_explanation"
    case collaborativePlanning = "collaborative_planning"
}

public enum ConversationalBehaviorAction: String, Codable, Sendable {
    case activeListening = "active_listening"
    case speakDirectly = "speak_directly"
    case thinkThenSpeak = "think_then_speak"
    case briefConfirmation = "brief_confirmation"
    case collaborativeGuide = "collaborative_guide"
}

public enum ConversationalExpressionKind: String, Codable, Sendable {
    case interested
    case warm
    case thoughtful
    case surprised
    case enthusiastic
    case uncertain
    case calm
    case direct
}

public struct ConversationalBehaviorPlan: Codable, Equatable, Sendable {
    public let intent: ConversationalIntentKind
    public let behavior: ConversationalBehaviorAction
    public let expression: ConversationalExpressionKind
    public let vocalization: VocalizationKind?
    public let intensity: Double
    public let allowUserSpeech: Bool
    public let rateMultiplier: Float
    public let pauseScale: Double
    public let formality: VoiceFormalityLevel
    public let reason: String

    public func prettyJSONSummary() -> String {
        var obj: [String: Any] = [
            "intent": intent.rawValue,
            "behavior": behavior.rawValue,
            "expression": expression.rawValue,
            "intensity": (intensity * 100).rounded() / 100.0,
            "allowUserSpeech": allowUserSpeech,
            "formality": formality.rawValue
        ]
        if let vocalization {
            obj["vocalization"] = vocalization.rawValue
        }
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
              let txt = String(data: data, encoding: .utf8) else {
            return "\(intent.rawValue)/\(expression.rawValue)"
        }
        return txt
    }

    public static func stripBehaviorMetadataFromSpeech(_ text: String) -> String {
        var out = text
        // Remove JSON behavior-plan snippets or hidden bracket tags if a small local model echoes them.
        if let jsonRx = try? NSRegularExpression(pattern: "\\{\\s*\"intent\"\\s*:[^\\}]*\\}", options: [.caseInsensitive]) {
            let range = NSRange(out.startIndex..<out.endIndex, in: out)
            out = jsonRx.stringByReplacingMatches(in: out, range: range, withTemplate: "")
        }
        if let tagRx = try? NSRegularExpression(pattern: "\\[(?:BEHAVIOR|PROSODY|EXPRESSION|INTENT|PAUSA|VOCALIZACAO)[^\\]]*\\]", options: [.caseInsensitive]) {
            let range = NSRange(out.startIndex..<out.endIndex, in: out)
            out = tagRx.stringByReplacingMatches(in: out, range: range, withTemplate: "")
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public final class ConversationalBehaviorPlanner: @unchecked Sendable {
    private let lock = NSLock()
    private var recentLeadVocalizations: [VocalizationKind] = []
    private var turnsSinceLastLeadVocalization: Int = 2

    public init() {}

    public func planTurnResponse(
        userUtterance: String,
        complexityScore: Double,
        acousticFeatures: AcousticTurnFeatures?,
        styleAdapter: UserConversationalStyleAdapter,
        persona: WisdVoicePersona,
        profile: VoiceBehaviorProfile,
        isSpecialistRunning: Bool
    ) -> ConversationalBehaviorPlan {
        let lower = userUtterance.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let personality = VoicePersonalityProfile.profile(for: persona)
        let adaptiveCadence = styleAdapter.adaptiveCadenceMultiplier()

        let hasDiscoveryCue = lower.contains("descobri") || lower.contains("consegui") || lower.contains("funcionou")
            || lower.contains("ideia") || lower.contains("olha só") || lower.contains("resolved") || lower.contains("figured out")
        let hasUncertaintyOrDilemma = lower.contains("dúvida") || lower.contains("duvida") || lower.contains("não sei")
            || lower.contains("nao sei") || lower.contains("comparar") || lower.contains("trade-off")
            || lower.contains("tradeoff") || lower.contains("será que") || lower.contains("qual melhor")
            || lower.contains("should i") || lower.contains("not sure")
        let hasTechnicalDepthCue = complexityScore >= 0.56 || lower.contains("arquitetura") || lower.contains("protocolo")
            || lower.contains("thread") || lower.contains("latência") || lower.contains("deadlock")
        let isQuickGreetingOrCheck = lower.split(whereSeparator: { $0.isWhitespace }).count <= 5 && !hasTechnicalDepthCue && !hasUncertaintyOrDilemma

        let (intent, behaviorAction, expression): (ConversationalIntentKind, ConversationalBehaviorAction, ConversationalExpressionKind) = {
            if isQuickGreetingOrCheck && !hasDiscoveryCue {
                return (.reassurance, .briefConfirmation, personality.energy >= 0.72 ? .warm : .calm)
            }
            if hasDiscoveryCue {
                return (.enthusiasm, .collaborativeGuide, .enthusiastic)
            }
            if hasUncertaintyOrDilemma || complexityScore >= 0.70 {
                return (.reflection, .thinkThenSpeak, .thoughtful)
            }
            if hasTechnicalDepthCue {
                return (
                    .technicalExplanation,
                    profile.formality == .formal ? .speakDirectly : .collaborativeGuide,
                    personality.formality == .formal ? .direct : .interested
                )
            }
            if isSpecialistRunning {
                return (.reassurance, .speakDirectly, .warm)
            }
            return (.directAnswer, .speakDirectly, personality.conversationalWarmth >= 0.75 ? .warm : .calm)
        }()

        let leadVocalization: VocalizationKind? = lock.withLock {
            turnsSinceLastLeadVocalization += 1
            guard profile.enableContextualProsody,
                  profile.expressivity != .subtle,
                  profile.profilePreset != .professional else {
                return nil
            }
            // Never insert lead-ins on consecutive turns so speech never sounds scripted or repetitive.
            let minGapTurns = profile.profilePreset == .expressive ? 2 : 3
            guard turnsSinceLastLeadVocalization >= minGapTurns else { return nil }

            let candidate: VocalizationKind? = {
                switch intent {
                case .reflection where complexityScore >= 0.68 || hasUncertaintyOrDilemma:
                    return lower.contains("?") ? .boaPergunta : .hmm
                case .enthusiasm:
                    return .interessante
                case .technicalExplanation where profile.profilePreset == .casual || profile.profilePreset == .expressive:
                    return .olha
                default:
                    return nil
                }
            }()

            guard let chosen = candidate, !recentLeadVocalizations.contains(chosen) else {
                return nil
            }
            recentLeadVocalizations.append(chosen)
            if recentLeadVocalizations.count > 3 {
                recentLeadVocalizations.removeFirst()
            }
            turnsSinceLastLeadVocalization = 0
            return chosen
        }

        let baseIntensity = max(0.15, min(0.90, (profile.vocalizationIntensity + personality.conversationalWarmth) * 0.5))
        let tempoAdjust: Float = {
            if intent == .reflection { return 0.96 }
            if intent == .enthusiasm && profile.expressivity != .subtle { return 1.03 }
            return 1.0
        }()
        let finalRate = min(1.25, max(0.82, profile.speechRate * personality.cadenceRate * adaptiveCadence * tempoAdjust))
        let pauseMult = max(0.65, min(1.60, profile.pauseScale * (intent == .reflection ? 1.15 : 1.0)))

        let diagnostic: String = {
            let contourNote = acousticFeatures?.pitchContour.rawValue ?? "none"
            return "intent=\(intent.rawValue) expr=\(expression.rawValue) contour=\(contourNote) lead=\(leadVocalization?.rawValue ?? "none")"
        }()

        return ConversationalBehaviorPlan(
            intent: intent,
            behavior: behaviorAction,
            expression: expression,
            vocalization: leadVocalization,
            intensity: baseIntensity,
            allowUserSpeech: true,
            rateMultiplier: finalRate,
            pauseScale: pauseMult,
            formality: profile.formality,
            reason: diagnostic
        )
    }

    public func resetSession() {
        lock.withLock {
            recentLeadVocalizations.removeAll()
            turnsSinceLastLeadVocalization = 2
        }
    }
}

// MARK: - Section 4: Active Listening & Backchanneling Engine

public struct BackchannelDecision: Equatable, Sendable {
    public let shouldEmit: Bool
    public let vocalization: VocalizationKind?
    public let intensity: Float
    public let continuationProbability: Double
    public let reason: String

    public static func suppressed(_ reason: String, probability: Double = 0.0) -> BackchannelDecision {
        BackchannelDecision(shouldEmit: false, vocalization: nil, intensity: 0, continuationProbability: probability, reason: reason)
    }
}

public final class ActiveListeningBackchannelEngine: @unchecked Sendable {
    private let lock = NSLock()
    private var backchannelsInCurrentTurn: Int = 0
    private var lastBackchannelEmitNs: UInt64 = 0
    private var recentBackchannels: [VocalizationKind] = []
    private var emittedForWordCountWatermark: Int = 0

    public init() {}

    public func evaluateDuringUserSpeech(
        partialTranscript: String,
        turnElapsedSeconds: Double,
        pauseDurationMs: Double,
        isAcousticSpeechActive: Bool,
        isAssistantSpeaking: Bool,
        isAuxiliaryPlaying: Bool,
        isEchoHangoverActive: Bool,
        acoustic: AcousticTurnFeatures,
        profile: VoiceBehaviorProfile,
        persona: WisdVoicePersona,
        nowNs: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) -> BackchannelDecision {
        guard profile.enableActiveListening else {
            return .suppressed("Escuta ativa desativada no perfil")
        }
        let personality = VoicePersonalityProfile.profile(for: persona)
        let effectiveFreq = max(0.0, min(1.0, (profile.backchannelFrequency * 0.72) + (personality.backchannelFrequency * 0.28)))
        guard effectiveFreq > 0.08, profile.profilePreset != .professional else {
            return .suppressed("Frequência de feedback baixa/desativada")
        }
        guard !isAssistantSpeaking else {
            return .suppressed("Assistente já falando")
        }
        guard !isAuxiliaryPlaying else {
            return .suppressed("Vocalização auxiliar já em reprodução")
        }
        guard !isEchoHangoverActive else {
            return .suppressed("Janela de eco ativa")
        }
        guard !isAcousticSpeechActive else {
            return .suppressed("Usuário articulando som ativo neste instante")
        }

        // Never emit in total prolonged silence or outside genuine conversational pause (290ms...860ms).
        guard pauseDurationMs >= 290.0 && pauseDurationMs <= 860.0 else {
            return .suppressed("Fora da janela natural de micro-pausa (\(Int(pauseDurationMs))ms)")
        }

        let clean = partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty,
              !HybridTurnTakingAnalyzer.isLikelyBackchannelOnly(clean) else {
            return .suppressed("Transcrição curta ou mero ack")
        }

        let words = clean.split(whereSeparator: { $0.isWhitespace })
        let wordCount = words.count
        guard turnElapsedSeconds >= 3.0 || wordCount >= 9 else {
            return .suppressed("Início de turno ainda muito curto (\(wordCount) palavras)")
        }

        // Compute probability that user intends to KEEP talking vs waiting for complete reply.
        let lower = clean.lowercased()
        var continuationProb = 0.20
        if turnElapsedSeconds >= 4.0 && wordCount >= 10 { continuationProb += 0.22 }
        if wordCount >= 18 { continuationProb += 0.16 }
        if lower.hasSuffix(",") || lower.hasSuffix("...") || lower.hasSuffix("…") {
            continuationProb += 0.26
        }
        if let lastWord = words.last.map({ String($0).lowercased().trimmingCharacters(in: .punctuationCharacters) }),
           ["e", "mas", "então", "porque", "pois", "aí", "tipo", "como", "quando", "que", "se", "para", "de", "and", "but", "so", "because", "when", "if", "that"].contains(lastWord) {
            continuationProb += 0.28
        }
        if acoustic.hasAcousticSignal {
            if acoustic.pitchContour == .level || acoustic.pitchContour == .rising {
                continuationProb += 0.12
            } else if acoustic.pitchContour == .falling && (clean.hasSuffix("?") || clean.hasSuffix("!")) {
                continuationProb -= 0.45
            }
        }
        if clean.hasSuffix("?") {
            continuationProb -= 0.50 // User asked a complete question — don't talk over the pause!
        }

        continuationProb = max(0.0, min(1.0, continuationProb))
        guard continuationProb >= 0.62 else {
            return .suppressed("Baixa probabilidade de continuação longa (\(String(format: "%.2f", continuationProb)))", probability: continuationProb)
        }

        return lock.withLock {
            let maxPerTurn = effectiveFreq >= 0.72 ? 3 : 2
            guard backchannelsInCurrentTurn < maxPerTurn else {
                return .suppressed("Limite de backchannels por turno atingido (\(maxPerTurn))", probability: continuationProb)
            }
            guard wordCount >= emittedForWordCountWatermark + 7 else {
                return .suppressed("Poucas novas palavras desde o último feedback", probability: continuationProb)
            }

            let minCooldownSec = 10.5 - (effectiveFreq * 5.2) // 5.3s (expressive) -> 8.0s (natural)
            if lastBackchannelEmitNs > 0 {
                let elapsedSinceLastSec = Double(nowNs &- lastBackchannelEmitNs) / 1_000_000_000.0
                if elapsedSinceLastSec < minCooldownSec {
                    return .suppressed("Cooldown ativo (\(String(format: "%.1fs", elapsedSinceLastSec)))", probability: continuationProb)
                }
            }

            let chosen = selectContextualVocalizationLocked(lowerTranscript: lower, acoustic: acoustic, turnCount: wordCount)
            backchannelsInCurrentTurn += 1
            lastBackchannelEmitNs = nowNs
            emittedForWordCountWatermark = wordCount
            recentBackchannels.append(chosen)
            if recentBackchannels.count > 4 {
                recentBackchannels.removeFirst()
            }

            let subtleIntensity = Float(max(0.18, min(0.55, profile.vocalizationIntensity)))
            return BackchannelDecision(
                shouldEmit: true,
                vocalization: chosen,
                intensity: subtleIntensity,
                continuationProbability: continuationProb,
                reason: "Pausa \(Int(pauseDurationMs))ms · cont=\(String(format: "%.2f", continuationProb)) · palavras=\(wordCount)"
            )
        }
    }

    public func beginNewUserTurn() {
        lock.withLock {
            backchannelsInCurrentTurn = 0
            emittedForWordCountWatermark = 0
        }
    }

    public func resetSession() {
        lock.withLock {
            backchannelsInCurrentTurn = 0
            lastBackchannelEmitNs = 0
            emittedForWordCountWatermark = 0
            recentBackchannels.removeAll()
        }
    }

    private func selectContextualVocalizationLocked(
        lowerTranscript: String,
        acoustic: AcousticTurnFeatures,
        turnCount: Int
    ) -> VocalizationKind {
        let pool: [VocalizationKind]
        if lowerTranscript.contains("descobri") || lowerTranscript.contains("incrível") || lowerTranscript.contains("percebi") || lowerTranscript.contains("ideia") {
            pool = [.ahSim, .interessante, .aham]
        } else if lowerTranscript.contains("então") || lowerTranscript.contains("porque") || lowerTranscript.contains("funciona") || turnCount >= 18 {
            pool = [.entendi, .certo, .uhum, .sei]
        } else if acoustic.pitchContour == .rising {
            pool = [.aham, .certo, .uhum]
        } else {
            pool = [.uhum, .sei, .aham, .entendi]
        }
        if let fresh = pool.first(where: { !recentBackchannels.contains($0) }) {
            return fresh
        }
        if let notLast = pool.first(where: { $0 != recentBackchannels.last }) {
            return notLast
        }
        return pool.first ?? .uhum
    }
}

// MARK: - Section 7: Contextual Prosody Planner

public struct EngineProsodyCapabilities: Equatable, Sendable {
    public let supportsRateControl: Bool
    public let supportsDynamicSilenceScale: Bool
    public let supportsPitchModulation: Bool
    public let supportsNativeAudioTags: Bool

    public static func forEngine(_ engine: VoiceTTSEngineKind, isKokoroActive: Bool) -> EngineProsodyCapabilities {
        if isKokoroActive || engine == .kokoro82M {
            return EngineProsodyCapabilities(
                supportsRateControl: true,
                supportsDynamicSilenceScale: true,
                supportsPitchModulation: false, // Honest: Kokoro has no direct pitch knob
                supportsNativeAudioTags: false
            )
        }
        switch engine {
        case .appleNaturalPCM, .autoLocal:
            return EngineProsodyCapabilities(
                supportsRateControl: true,
                supportsDynamicSilenceScale: false,
                supportsPitchModulation: true, // Subtle AVSpeechUtterance.pitchMultiplier
                supportsNativeAudioTags: false
            )
        case .sherpaPiperVits:
            return EngineProsodyCapabilities(
                supportsRateControl: true,
                supportsDynamicSilenceScale: true,
                supportsPitchModulation: false,
                supportsNativeAudioTags: false
            )
        case .cosyVoice2, .chatterbox:
            return EngineProsodyCapabilities(
                supportsRateControl: true,
                supportsDynamicSilenceScale: false,
                supportsPitchModulation: false,
                supportsNativeAudioTags: true
            )
        default:
            return EngineProsodyCapabilities(
                supportsRateControl: false,
                supportsDynamicSilenceScale: false,
                supportsPitchModulation: false,
                supportsNativeAudioTags: false
            )
        }
    }
}

public struct ProsodyDirective: Equatable, Sendable {
    public let expression: ConversationalExpressionKind
    public let rateMultiplier: Float
    public let silenceScale: Float
    public let pitchMultiplier: Float
    public let gainScale: Float
    public let prePauseMs: Int
    public let postPauseMs: Int
}

public enum VoiceProsodyPlanner {
    public static func directive(
        for clauseText: String,
        clauseIndex: Int,
        plan: ConversationalBehaviorPlan,
        capabilities: EngineProsodyCapabilities
    ) -> ProsodyDirective {
        let trimmed = clauseText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        let isQuestion = trimmed.hasSuffix("?")
        let isExclamation = trimmed.hasSuffix("!")
        let isReflective = lower.hasPrefix("hmm") || lower.hasPrefix("olha") || lower.contains("talvez") || lower.contains("não tenho certeza") || trimmed.contains("…")

        var rateMod: Float = 1.0
        var silenceScale: Float = 0.20
        var pitchMod: Float = 1.0
        var gainMod: Float = 1.0
        var prePauseMs = 0
        var postPauseMs = 0

        switch plan.expression {
        case .thoughtful:
            rateMod = 0.94
            silenceScale = 0.28
            pitchMod = 0.98
            prePauseMs = clauseIndex == 0 ? 45 : 75
        case .surprised, .enthusiastic:
            rateMod = 1.03
            silenceScale = 0.17
            pitchMod = 1.04
            gainMod = 1.04
        case .uncertain:
            rateMod = 0.93
            silenceScale = 0.30
            pitchMod = 0.99
            prePauseMs = 60
        case .warm, .interested:
            rateMod = 0.99
            silenceScale = 0.22
            pitchMod = 1.01
        case .calm, .direct:
            rateMod = 0.98
            silenceScale = 0.20
            pitchMod = 1.0
        }

        if isQuestion {
            pitchMod = min(1.05, pitchMod + 0.025)
            postPauseMs = 80
        } else if isExclamation {
            pitchMod = min(1.05, pitchMod + 0.015)
            postPauseMs = 55
        } else if isReflective {
            rateMod = min(rateMod, 0.93)
            silenceScale = max(silenceScale, 0.28)
            postPauseMs = 95
        } else {
            postPauseMs = 40
        }

        let effectiveRate = capabilities.supportsRateControl
            ? min(1.30, max(0.75, plan.rateMultiplier * rateMod))
            : 1.0
        let effectiveSilence = capabilities.supportsDynamicSilenceScale
            ? Float(min(0.45, max(0.12, Double(silenceScale) * plan.pauseScale)))
            : 0.20
        let effectivePitch = capabilities.supportsPitchModulation
            ? min(1.06, max(0.95, pitchMod))
            : 1.0

        return ProsodyDirective(
            expression: plan.expression,
            rateMultiplier: effectiveRate,
            silenceScale: effectiveSilence,
            pitchMultiplier: effectivePitch,
            gainScale: gainMod,
            prePauseMs: Int(Double(prePauseMs) * plan.pauseScale),
            postPauseMs: Int(Double(postPauseMs) * plan.pauseScale)
        )
    }
}

// MARK: - Section 8: Natural Speech Composer (Evolving VoiceResponseAdapter)

public enum NaturalSpeechComposer {
    private static let roboticSignOffRegexPatterns: [String] = [
        "\\s*Se precisar de (?:mais )?(?:alguma )?coisa[^.!?]*[.!]?$",
        "\\s*Estou à disposição[^.!?]*[.!]?$",
        "\\s*Qualquer dúvida[^.!?]*[.!]?$",
        "\\s*Espero que (?:isso )?ajude[^.!?]*[.!]?$",
        "\\s*Let me know if you need anything else[^.!?]*[.!]?$",
        "\\s*Feel free to ask if you have more questions[^.!?]*[.!]?$"
    ]

    private static let stiffOpeners: [String] = [
        "Certamente!", "Certamente,", "Excelente pergunta!", "Ótima pergunta!",
        "Para responder à sua pergunta,", "Com certeza!", "Com certeza,",
        "Aqui está a resposta:", "Aqui está o resumo:", "Aqui está:",
        "Certainly!", "Great question!", "Sure thing!", "Here is the answer:"
    ]

    public static func compose(
        _ rawMarkdown: String,
        plan: ConversationalBehaviorPlan?,
        profile: VoiceBehaviorProfile,
        capabilities: EngineProsodyCapabilities,
        customDictionary: TechnicalPronunciationDictionary? = nil
    ) -> AdaptedSpeechOutput {
        // 1. Strip any leaked behavior/prosody metadata BEFORE speech adaptation.
        var working = ConversationalBehaviorPlan.stripBehaviorMetadataFromSpeech(rawMarkdown)

        // 2. Strip overly stiff lead-ins & repetitive boilerplate sign-offs unless user explicitly chose formal/detailed.
        if profile.profilePreset != .professional || profile.detailLevel != .detailed {
            var matchedOpener = true
            while matchedOpener {
                matchedOpener = false
                for opener in stiffOpeners where working.lowercased().hasPrefix(opener.lowercased()) {
                    working = String(working.dropFirst(opener.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if let first = working.first {
                        working = first.uppercased() + working.dropFirst()
                    }
                    matchedOpener = true
                    break
                }
            }
            for pattern in roboticSignOffRegexPatterns {
                if let rx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                    let range = NSRange(working.startIndex..<working.endIndex, in: working)
                    working = rx.stringByReplacingMatches(in: working, options: [], range: range, withTemplate: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        // 3. Turn numbered bullet patterns ("1. Item\n2. Outro") into flowing oral prose.
        working = smoothSpokenEnumerations(in: working, language: profile.languageVariant)

        // 4. Delegate markdown/URL/table/code cleaning & length balancing to tested V2 VoiceResponseAdapter.
        let adapted = VoiceResponseAdapter.adaptForSpeech(
            working,
            profile: profile,
            customDictionary: customDictionary
        )

        var spoken = adapted.spokenText
        // 5. Gentle natural spoken rhythm contractions for casual/natural PT-BR (preserving technical symbols intact).
        if profile.languageVariant == .portugueseBR && (profile.profilePreset == .casual || profile.profilePreset == .natural) {
            spoken = applyGentlePTBRContractions(spoken)
        }

        // 6. When engine genuinely supports native paralinguistic tags, map subtle contextual cue cleanly;
        //    otherwise keep natural punctuation ("Hmm…", "Ah!") without fake tags.
        if capabilities.supportsNativeAudioTags, let expr = plan?.expression {
            if expr == .enthusiastic && spoken.count > 24 && !spoken.contains("[") {
                spoken = spoken.replacingOccurrences(of: "!", with: "! ")
            }
        }

        return AdaptedSpeechOutput(
            spokenText: spoken.trimmingCharacters(in: .whitespacesAndNewlines),
            wasSummarizedFromTechnicalContent: adapted.wasSummarizedFromTechnicalContent,
            detectedCodeBlocksCount: adapted.detectedCodeBlocksCount,
            detectedURLsCount: adapted.detectedURLsCount
        )
    }

    private static func smoothSpokenEnumerations(in text: String, language: VoiceLanguageVariant) -> String {
        let lines = text.components(separatedBy: .newlines)
        var out: [String] = []
        var numberHitCount = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let range = trimmed.range(of: "^([1-5])[\\.\\)]\\s+", options: .regularExpression) {
                let digit = String(trimmed[range]).trimmingCharacters(in: CharacterSet.decimalDigits.inverted)
                let body = String(trimmed[range.upperBound...])
                numberHitCount += 1
                let lead: String = {
                    if language.bcp47LanguagePrefix == "en" {
                        switch digit {
                        case "1": return "First, "
                        case "2": return "Second, "
                        default: return "Also, "
                        }
                    }
                    switch digit {
                    case "1": return "Primeiro, "
                    case "2": return "Depois, "
                    case "3": return "Além disso, "
                    default: return "Por fim, "
                    }
                }()
                let lowerBody = body.first.map { $0.lowercased() + body.dropFirst() } ?? body
                out.append(lead + lowerBody)
            } else {
                out.append(line)
            }
        }
        return numberHitCount >= 2 ? out.joined(separator: " ") : text
    }

    private static func applyGentlePTBRContractions(_ text: String) -> String {
        // Only apply conversational prepositions where safe around lowercase words (avoids altering code/identifiers).
        var out = text
        let replacements: [(String, String)] = [
            ("\\bpara a ([a-zçáéíóúãõâêô]+)\\b", "pra $1"),
            ("\\bpara o ([a-zçáéíóúãõâêô]+)\\b", "pro $1"),
            ("\\bpara você\\b", "pra você")
        ]
        for (pattern, template) in replacements {
            if let rx = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(out.startIndex..<out.endIndex, in: out)
                out = rx.stringByReplacingMatches(in: out, range: range, withTemplate: template)
            }
        }
        return out
    }
}

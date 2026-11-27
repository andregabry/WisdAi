import AppKit
import AVFoundation
import Combine
import Foundation
import Speech

// MARK: - Seleção de Gênero e Vozes Codex / Naturais

public enum AgentVoiceGender: String, CaseIterable, Identifiable, Codable {
    case female
    case male

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .female: return "Mulher"
        case .male: return "Homem"
        }
    }

    public var shortLabel: String {
        switch self {
        case .female: return "Feminina"
        case .male: return "Masculina"
        }
    }

    public var iconName: String {
        switch self {
        case .female: return "person.wave.2.fill"
        case .male: return "person.wave.2"
        }
    }

    public var openAIVoiceName: String {
        switch self {
        case .female: return "nova"
        case .male: return "onyx"
        }
    }

    public var defaultCodexVoiceID: String {
        switch self {
        case .female: return "marin"
        case .male: return "cedar"
        }
    }
}

public struct CodexVoicePreset: Identifiable, Hashable {
    public let id: String
    public let displayName: String
    public let gender: AgentVoiceGender
    public let subtitle: String
    public let openAISpeechVoice: String

    public static let catalog: [CodexVoicePreset] = [
        CodexVoicePreset(id: "marin", displayName: "Marin", gender: .female, subtitle: "Voz feminina padrão do Codex v2/v3", openAISpeechVoice: "nova"),
        CodexVoicePreset(id: "coral", displayName: "Coral", gender: .female, subtitle: "Clara, acolhedora e expressiva", openAISpeechVoice: "coral"),
        CodexVoicePreset(id: "juniper", displayName: "Juniper", gender: .female, subtitle: "Voz Codex calorosa e equilibrada", openAISpeechVoice: "nova"),
        CodexVoicePreset(id: "breeze", displayName: "Breeze", gender: .female, subtitle: "Voz Codex leve e conversacional", openAISpeechVoice: "shimmer"),
        CodexVoicePreset(id: "maple", displayName: "Maple", gender: .female, subtitle: "Voz Codex amigável e fluida", openAISpeechVoice: "alloy"),
        CodexVoicePreset(id: "vale", displayName: "Vale", gender: .female, subtitle: "Voz Codex serena e precisa", openAISpeechVoice: "sage"),
        CodexVoicePreset(id: "sol", displayName: "Sol", gender: .female, subtitle: "Voz Codex luminosa e natural", openAISpeechVoice: "coral"),
        CodexVoicePreset(id: "shimmer", displayName: "Shimmer", gender: .female, subtitle: "Suave, articulada e calma", openAISpeechVoice: "shimmer"),
        CodexVoicePreset(id: "sage", displayName: "Sage", gender: .female, subtitle: "Natural e reflexiva", openAISpeechVoice: "sage"),
        CodexVoicePreset(id: "cedar", displayName: "Cedar", gender: .male, subtitle: "Voz masculina natural do Codex", openAISpeechVoice: "onyx"),
        CodexVoicePreset(id: "cove", displayName: "Cove", gender: .male, subtitle: "Voz masculina clássica do Codex", openAISpeechVoice: "onyx"),
        CodexVoicePreset(id: "arbor", displayName: "Arbor", gender: .male, subtitle: "Voz Codex firme e envolvente", openAISpeechVoice: "ash"),
        CodexVoicePreset(id: "spruce", displayName: "Spruce", gender: .male, subtitle: "Voz Codex equilibrada e objetiva", openAISpeechVoice: "echo"),
        CodexVoicePreset(id: "ember", displayName: "Ember", gender: .male, subtitle: "Voz Codex expressiva e direta", openAISpeechVoice: "onyx"),
        CodexVoicePreset(id: "ash", displayName: "Ash", gender: .male, subtitle: "Firme, clara e natural", openAISpeechVoice: "ash"),
        CodexVoicePreset(id: "ballad", displayName: "Ballad", gender: .male, subtitle: "Harmônica e cadenciada", openAISpeechVoice: "onyx"),
        CodexVoicePreset(id: "echo", displayName: "Echo", gender: .male, subtitle: "Calma e bem articulada", openAISpeechVoice: "echo"),
        CodexVoicePreset(id: "verse", displayName: "Verse", gender: .male, subtitle: "Dinâmica e conversacional", openAISpeechVoice: "onyx")
    ]
}

public struct NaturalVoiceOption: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let language: String
    public let gender: AgentVoiceGender
    public let qualityScore: Int
    public let qualityBadge: String
    public let isEloquence: Bool
}

// MARK: - Assistente de Voz Conversacional (Codex WebRTC Realtime 1:1 + Voz Natural no Chat)

@MainActor
final class VoiceController: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    @Published var isListening: Bool = false
    @Published var isSpeaking: Bool = false
    @Published var isProcessing: Bool = false
    @Published var isConnecting: Bool = false
    @Published var isMuted: Bool = false
    @Published var isOutputMuted: Bool = false
    @Published var realtimeSessionActive: Bool = false
    @Published var realtimeThreadId: String? = nil

    @Published var voicePhase: CodexVoicePhase = .inactive
    @Published var voiceActivity: CodexVoiceActivity = .idle
    @Published var orbLevels: CodexOrbAudioLevels = .zero
    @Published var dictationPhase: CodexDictationPhase = .idle
    @Published var dictationWaveformHistory: [Float] = Array(repeating: 0, count: 96)
    @Published var recordingDurationMs: Int = 0
    @Published var dictationRecovery: CodexDictationRecovery? = nil

    @Published var liveTranscribedText: String = ""
    @Published var liveAssistantTranscript: String = ""
    @Published var audioLevel: Float = 0.0
    @Published var speakerLevel: Float = 0.0
    @Published var micHistory: [Float] = Array(repeating: 0, count: 10)
    @Published var speakerHistory: [Float] = Array(repeating: 0, count: 10)
    @Published var voiceFeedbackStatus: String? = nil
    @Published var voiceErrorMessage: String? = nil
    @Published var continuousConversation: Bool = true
    @Published var isVoiceModeActive: Bool = false

    public let orchestrator = WisdVoiceOrchestrator()
    private var orchestratorCancellables: Set<AnyCancellable> = []

    @Published var voiceGender: AgentVoiceGender {
        didSet {
            UserDefaults.standard.set(voiceGender.rawValue, forKey: "wisdcode.voice.gender")
            let currentPreset = CodexVoicePreset.catalog.first(where: { $0.id == selectedCodexVoiceID })
            if currentPreset?.gender != voiceGender {
                selectedCodexVoiceID = voiceGender.defaultCodexVoiceID
            }
            if selectedVoiceID != "auto" {
                selectedVoiceID = "auto"
            }
        }
    }

    @Published var selectedCodexVoiceID: String {
        didSet {
            UserDefaults.standard.set(selectedCodexVoiceID, forKey: "wisdcode.voice.codexVoice")
            if let preset = CodexVoicePreset.catalog.first(where: { $0.id == selectedCodexVoiceID }),
               preset.gender != voiceGender {
                voiceGender = preset.gender
            }
        }
    }

    @Published var selectedVoiceID: String {
        didSet { UserDefaults.standard.set(selectedVoiceID, forKey: "wisdcode.voice.identifier") }
    }

    @Published var speechSpeed: Double {
        didSet { UserDefaults.standard.set(speechSpeed, forKey: "wisdcode.voice.speed") }
    }

    @Published var preferCloudNeuralTTS: Bool {
        didSet { UserDefaults.standard.set(preferCloudNeuralTTS, forKey: "wisdcode.voice.cloudNeural") }
    }

    @Published var orbPalette: CodexOrbPalette {
        didSet { UserDefaults.standard.set(orbPalette.rawValue, forKey: "wisdcode.voice.orbPalette") }
    }

    @Published var voiceSoundsEnabled: Bool {
        didSet { UserDefaults.standard.set(voiceSoundsEnabled, forKey: "wisdcode.voice.soundsEnabled") }
    }

    @Published var autoGreetingEnabled: Bool {
        didSet { UserDefaults.standard.set(autoGreetingEnabled, forKey: "wisdcode.voice.greetingEnabled") }
    }

    @Published var voiceContinuityEnabled: Bool {
        didSet { UserDefaults.standard.set(voiceContinuityEnabled, forKey: "wisdcode.voice.continuityEnabled") }
    }

    let webrtcBridge = CodexRealtimeWebRTCBridge()
    private(set) var isUsingWebRTCTransport: Bool = false

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "pt-BR")) ?? SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer()!
    private let recognitionLock = NSLock()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionToken = UUID()
    private var isStartingListening = false
    private var onTranscriptionCallback: ((String) -> Void)?
    private var restartTaskWorkItem: DispatchWorkItem?
    private var dictationEngine: AVAudioEngine?
    private let synthesizer = AVSpeechSynthesizer()

    // Gravação PCM16 opcional para transcrever via Codex /transcribe ou Whisper ao finalizar ditado
    private var isDictationMode: Bool = false
    private var dictationAudioLock = NSLock()
    private var dictationCapturedPCM16 = Data()
    private var dictationDurationTimer: Timer?
    private var dictationStartedAt: Date?
    private var dictationFinalCallback: ((String) -> Void)?

    // Pipeline de reprodução local (barítono) e áudio HD OpenAI
    private var playbackEngine: AVAudioEngine?
    private var playbackPlayerNode: AVAudioPlayerNode?
    private var playbackTimePitch: AVAudioUnitTimePitch?
    private var audioPlayer: AVAudioPlayer?
    private var cloudTTSTask: Task<Void, Never>?
    private var cloudTTSCooldownUntil: Date = .distantPast

    // Pipeline de streaming duplex PCM16 para Codex Realtime (`thread/realtime/*` legado)
    private var realtimeCaptureEngine: AVAudioEngine?
    private var realtimePCMChunkAccumulator = Data()
    private var realtimeAudioSendCallback: ((String, Int, Int, Int) -> Void)?
    private var realtimePlaybackEngine: AVAudioEngine?
    private var realtimePlayerNode: AVAudioPlayerNode?
    private var realtimePlaybackFormat: AVAudioFormat?
    private var realtimePendingBuffers: Int = 0
    private var speakerMeterDecayTimer: Timer?

    private var speechToken = UUID()
    private var pendingSentences: [String] = []
    private var pendingCloudChunks: [String] = []
    private var prefetchedCloudAudioData: Data? = nil
    private var activeNativeVoice: AVSpeechSynthesisVoice?
    private var activeUseBaritoneShift: Bool = false
    private weak var activeSpeechUtterance: AVSpeechUtterance?
    private var directSpeakDidStart: Bool = false
    private var directSpeakWatchdog: DispatchWorkItem?
    private var baritoneWriteWatchdog: DispatchWorkItem?
    private var accumulatedTranscriptPrefix: String = ""
    private var completionHandler: (() -> Void)?
    private var isSpeakingIntermediateNotice: Bool = false
    private var queuedFinalSpeechText: String? = nil
    private var silenceTimer: Timer?
    var onSpeechFinalized: ((String) -> Void)?
    var onStopRequested: (() -> Void)?

    override init() {
        let savedGenderRaw = UserDefaults.standard.string(forKey: "wisdcode.voice.gender") ?? AgentVoiceGender.female.rawValue
        let initialGender = AgentVoiceGender(rawValue: savedGenderRaw) ?? .female
        self.voiceGender = initialGender
        let savedCodexVoice = UserDefaults.standard.string(forKey: "wisdcode.voice.codexVoice")
        if let savedCodexVoice,
           CodexVoicePreset.catalog.contains(where: { $0.id == savedCodexVoice }) {
            self.selectedCodexVoiceID = savedCodexVoice
        } else {
            self.selectedCodexVoiceID = initialGender.defaultCodexVoiceID
        }
        self.selectedVoiceID = UserDefaults.standard.string(forKey: "wisdcode.voice.identifier") ?? "auto"
        let savedSpeed = UserDefaults.standard.object(forKey: "wisdcode.voice.speed") as? Double ?? 1.0
        self.speechSpeed = min(1.25, max(0.80, savedSpeed))
        self.preferCloudNeuralTTS = UserDefaults.standard.object(forKey: "wisdcode.voice.cloudNeural") as? Bool ?? true
        let savedPalette = UserDefaults.standard.string(forKey: "wisdcode.voice.orbPalette") ?? CodexOrbPalette.blue.rawValue
        self.orbPalette = CodexOrbPalette(rawValue: savedPalette) ?? .blue
        self.voiceSoundsEnabled = UserDefaults.standard.object(forKey: "wisdcode.voice.soundsEnabled") as? Bool ?? true
        self.autoGreetingEnabled = UserDefaults.standard.object(forKey: "wisdcode.voice.greetingEnabled") as? Bool ?? true
        self.voiceContinuityEnabled = UserDefaults.standard.object(forKey: "wisdcode.voice.continuityEnabled") as? Bool ?? true
        super.init()
        synthesizer.delegate = self
        bindOrchestratorState()
    }

    private func bindOrchestratorState() {
        orchestrator.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                guard let self, self.orchestrator.isVoiceSessionActive else { return }
                self.voiceActivity = newState.orbActivity
                self.voiceFeedbackStatus = newState.displayTitle
                self.isListening = (newState == .listening || newState == .userSpeaking)
                self.isSpeaking = (newState == .assistantSpeaking)
                self.isProcessing = (newState == .processing || newState == .consultingAgent)
                self.isConnecting = (newState == .connecting || newState == .initializingLocalEngine || newState == .loadingModel || newState == .reconnecting)
                self.voicePhase = (newState == .idle || newState == .disconnected) ? .inactive : .active
                if newState == .error {
                    self.voiceErrorMessage = self.orchestrator.lastErrorSummary
                        ?? self.orchestrator.activeBannerNotice
                        ?? "Falha ao inicializar componente do motor de voz."
                } else if newState == .listening {
                    self.voiceErrorMessage = nil
                }
            }
            .store(in: &orchestratorCancellables)

        orchestrator.$activeBannerNotice
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notice in
                guard let self else { return }
                if self.orchestrator.state == .error {
                    self.voiceErrorMessage = notice ?? self.orchestrator.lastErrorSummary
                }
            }
            .store(in: &orchestratorCancellables)

        orchestrator.$lastErrorSummary
            .receive(on: DispatchQueue.main)
            .sink { [weak self] summary in
                guard let self else { return }
                if self.orchestrator.state == .error, let summary, !summary.isEmpty {
                    self.voiceErrorMessage = summary
                }
            }
            .store(in: &orchestratorCancellables)

        orchestrator.audioEngine.$liveLevels
            .receive(on: DispatchQueue.main)
            .sink { [weak self] levels in
                guard let self, self.orchestrator.isVoiceSessionActive else { return }
                self.orbLevels = levels
                self.audioLevel = levels.micLevel
                self.speakerLevel = levels.overall
            }
            .store(in: &orchestratorCancellables)

        orchestrator.$liveUserTranscript
            .receive(on: DispatchQueue.main)
            .sink { [weak self] txt in
                guard let self, self.orchestrator.isVoiceSessionActive else { return }
                self.liveTranscribedText = txt
            }
            .store(in: &orchestratorCancellables)

        orchestrator.$liveAssistantTranscript
            .receive(on: DispatchQueue.main)
            .sink { [weak self] txt in
                guard let self, self.orchestrator.isVoiceSessionActive else { return }
                self.liveAssistantTranscript = txt
            }
            .store(in: &orchestratorCancellables)

        orchestrator.$isMuted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] muted in
                guard let self, self.orchestrator.isVoiceSessionActive else { return }
                self.isMuted = muted
            }
            .store(in: &orchestratorCancellables)

        orchestrator.$isOutputMuted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] outMuted in
                guard let self, self.orchestrator.isVoiceSessionActive else { return }
                self.isOutputMuted = outMuted
            }
            .store(in: &orchestratorCancellables)
    }

    // MARK: - Catálogo de Vozes Codex e do Sistema

    var activeCodexVoice: CodexVoicePreset {
        if let match = CodexVoicePreset.catalog.first(where: { $0.id == selectedCodexVoiceID }) {
            return match
        }
        return CodexVoicePreset.catalog.first(where: { $0.id == voiceGender.defaultCodexVoiceID }) ?? CodexVoicePreset.catalog[0]
    }

    var availableCodexVoices: [CodexVoicePreset] {
        CodexVoicePreset.catalog
    }

    var availablePortugueseVoices: [NaturalVoiceOption] {
        Self.discoverPortugueseVoices()
    }

    var activeVoiceSummary: String {
        if orchestrator.isVoiceSessionActive {
            return "Motor Autônomo WisdAI · \(orchestrator.voiceIdentity.persona.displayName) · \(orchestrator.brainStatus.rawValue)"
        }
        if isVoiceModeActive && isConnecting {
            return "Inicializando Motor WisdAI · \(orchestrator.voiceIdentity.persona.displayName)"
        }
        return "Voz WisdAI · \(orchestrator.voiceIdentity.persona.displayName)"
    }

    static func discoverPortugueseVoices() -> [NaturalVoiceOption] {
        let maleHints = ["felipe", "henrique", "cristiano", "tiago", "gabriel", "daniel", "eddy", "reed", "rocko", "grandpa", "voz 1"]
        let raw = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.lowercased().hasPrefix("pt") }
        var seen = Set<String>()
        var options: [NaturalVoiceOption] = []

        for v in raw where seen.insert(v.identifier).inserted {
            let lowerID = v.identifier.lowercased()
            let lowerName = v.name.lowercased()
            let isEloquence = lowerID.contains(".eloquence.")
            let isSystemNeural = lowerID.contains(".siri.") || lowerName.contains("voz ")

            let inferredGender: AgentVoiceGender = {
                switch v.gender {
                case .male: return .male
                case .female: return .female
                default:
                    return maleHints.contains(where: { lowerName.contains($0) || lowerID.contains($0) }) ? .male : .female
                }
            }()

            var score = 0
            if isEloquence { score -= 500 }
            if isSystemNeural { score += 260 }
            if v.quality == .premium { score += 320 }
            else if v.quality == .enhanced { score += 220 }
            else { score += 60 }
            if v.language.caseInsensitiveCompare("pt-BR") == .orderedSame { score += 50 }
            if lowerID.contains("super-compact") { score -= 15 }

            let badge: String = {
                if isEloquence { return "Clássica" }
                if isSystemNeural { return "Neural" }
                if v.quality == .premium { return "Premium" }
                if v.quality == .enhanced { return "Aprimorada" }
                return "Padrão"
            }()

            let cleanName = lowerName.hasPrefix("voz ")
                ? "Voz Natural (\(inferredGender.displayName))"
                : v.name

            options.append(NaturalVoiceOption(
                id: v.identifier,
                name: cleanName,
                language: v.language,
                gender: inferredGender,
                qualityScore: score,
                qualityBadge: badge,
                isEloquence: isEloquence
            ))
        }

        return options.sorted {
            if $0.qualityScore != $1.qualityScore { return $0.qualityScore > $1.qualityScore }
            return $0.name < $1.name
        }
    }

    static func resolveBestVoice(
        for gender: AgentVoiceGender,
        explicitID: String = "auto"
    ) -> (voice: AVSpeechSynthesisVoice?, useBaritoneShift: Bool) {
        let catalog = discoverPortugueseVoices()
        if explicitID != "auto",
           let customVoice = AVSpeechSynthesisVoice(identifier: explicitID) {
            return (customVoice, false)
        }

        let nonEloquence = catalog.filter { !$0.isEloquence }
        let pool = nonEloquence.isEmpty ? catalog : nonEloquence

        if let exactMatch = pool.first(where: { $0.gender == gender }) {
            return (AVSpeechSynthesisVoice(identifier: exactMatch.id), false)
        }

        if let bestNatural = pool.first, let av = AVSpeechSynthesisVoice(identifier: bestNatural.id) {
            // Evita pitch-shift artificial agressivo sobre voz neural feminina quando não há voz masculina nativa
            return (av, false)
        }

        let fallback = AVSpeechSynthesisVoice(language: "pt-BR") ?? AVSpeechSynthesisVoice(language: Locale.current.identifier)
        return (fallback, false)
    }

    static func hasOpenAIAPIKey() -> Bool {
        if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envKey.isEmpty {
            return true
        }
        if let key = AccountKeychain.readProviderKey(provider: .openai)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !key.isEmpty {
            return true
        }
        return false
    }

    // MARK: - Ciclo do Assistente de Voz (Codex WebRTC Realtime 1:1 & Chat Conversacional)

    func prepareWebRTCRealtimeSession(
        onOffer: @escaping (Result<String, Error>) -> Void,
        onDataChannelEvent: @escaping ([String: Any]) -> Void,
        onError: @escaping (String) -> Void
    ) {
        stopDictation(cancel: true)
        stopListening()
        stopSpeaking()
        stopRealtimeAudioCapture()
        stopRealtimeAudioPlayback()
        isUsingWebRTCTransport = true
        isVoiceModeActive = true
        voicePhase = .starting
        voiceActivity = .idle
        isConnecting = true
        isMuted = false
        isOutputMuted = false
        realtimeSessionActive = false
        realtimeThreadId = nil
        continuousConversation = true
        liveTranscribedText = ""
        liveAssistantTranscript = ""
        voiceErrorMessage = nil
        voiceFeedbackStatus = "Conectando assistente Codex…"

        webrtcBridge.prepareOffer(
            preferredDeviceId: nil,
            initialMicMuted: false,
            initialOutputMuted: false,
            onDataChannelEvent: onDataChannelEvent,
            onLevels: { [weak self] levels in
                guard let self, self.isVoiceModeActive, self.isUsingWebRTCTransport else { return }
                self.orbLevels = levels
                if !self.isMuted {
                    self.pushMicLevel(levels.micLevel)
                }
                if self.isSpeaking {
                    self.pushSpeakerLevel(levels.overall)
                }
            },
            onConnectionStateChange: { [weak self] state in
                guard let self, self.isVoiceModeActive, self.isUsingWebRTCTransport else { return }
                if state == "failed" || state == "disconnected" {
                    if self.voicePhase == .starting {
                        onError("Falha na conexão WebRTC de áudio.")
                    }
                }
            },
            onRemoteAudioState: { [weak self] remoteSpeaking in
                guard let self, self.isVoiceModeActive, self.isUsingWebRTCTransport else { return }
                if self.isOutputMuted {
                    self.isSpeaking = false
                    self.voiceActivity = self.isProcessing ? .thinking : (self.isMuted ? .idle : .listening)
                    return
                }
                self.isSpeaking = remoteSpeaking
                if remoteSpeaking {
                    self.voiceActivity = .speaking
                    self.voiceFeedbackStatus = "WisdAI respondendo…"
                } else if self.voicePhase == .active {
                    self.voiceActivity = self.isMuted ? .idle : .listening
                    self.voiceFeedbackStatus = self.isMuted ? "Microfone silenciado" : "Ouvindo você…"
                }
            },
            onError: onError,
            completion: onOffer
        )
    }

    func activateWebRTCRealtimeSession(threadId: String, onStop: @escaping () -> Void) {
        guard isVoiceModeActive else { return }
        isUsingWebRTCTransport = true
        isConnecting = false
        realtimeSessionActive = true
        realtimeThreadId = threadId
        voicePhase = .active
        voiceActivity = isMuted ? .idle : .listening
        isListening = !isMuted
        voiceErrorMessage = nil
        voiceFeedbackStatus = isMuted ? "Microfone silenciado" : "Ouvindo você…"
        onStopRequested = onStop
        webrtcBridge.releaseBufferedAudio()
        CodexVoiceAudioCues.shared.play(.realtimeStart, enabled: voiceSoundsEnabled)
    }

    func beginCodexRealtimeSession(
        threadId: String,
        sendAudioChunk: @escaping (_ base64PCM16: String, _ sampleRate: Int, _ channels: Int, _ samplesPerChannel: Int) -> Void,
        onStop: @escaping () -> Void
    ) {
        if isUsingWebRTCTransport {
            activateWebRTCRealtimeSession(threadId: threadId, onStop: onStop)
            return
        }
        stopDictation(cancel: true)
        stopListening()
        stopSpeaking()
        isVoiceModeActive = true
        voicePhase = .active
        voiceActivity = .listening
        isConnecting = false
        isMuted = false
        isOutputMuted = false
        realtimeSessionActive = true
        realtimeThreadId = threadId
        continuousConversation = true
        liveTranscribedText = ""
        liveAssistantTranscript = ""
        voiceErrorMessage = nil
        voiceFeedbackStatus = "Ouvindo você…"
        onStopRequested = onStop
        CodexVoiceAudioCues.shared.play(.realtimeStart, enabled: voiceSoundsEnabled)
        startRealtimeAudioCapture(sendChunk: sendAudioChunk)
    }

    func startConversationalChatMode(greeting: String? = nil, onSpeech: @escaping (String) -> Void) {
        startConversationalChatMode(
            workspaceContext: .empty,
            continuityMessages: [],
            hasCodexAppServer: false,
            greeting: greeting,
            onSpeech: onSpeech
        )
    }

    func startConversationalChatMode(
        workspaceContext: VoiceWorkspaceContextSnapshot,
        continuityMessages: [CodexContinuityItem],
        hasCodexAppServer: Bool,
        activeTasksProvider: (() -> [VoiceTaskSummarySnapshot])? = nil,
        onDelegateTaskToAgent: ((VoiceSpecialistAgentHint, String, VoiceActionRiskTier) -> Void)? = nil,
        onRecordLocalExchangeToChat: ((String, String) -> Void)? = nil,
        greeting: String? = nil,
        onSpeech: @escaping (String) -> Void
    ) {
        webrtcBridge.close()
        isUsingWebRTCTransport = false
        stopRealtimeAudioCapture()
        stopRealtimeAudioPlayback()
        stopDictation(cancel: true)
        realtimeSessionActive = false
        realtimeThreadId = nil
        isConnecting = true
        isMuted = false
        isOutputMuted = false
        isVoiceModeActive = true
        voicePhase = .starting
        continuousConversation = true
        liveTranscribedText = ""
        liveAssistantTranscript = ""
        voiceErrorMessage = nil
        self.onTranscriptionCallback = nil
        self.onSpeechFinalized = onSpeech
        CodexVoiceAudioCues.shared.play(.realtimeStart, enabled: voiceSoundsEnabled)

        orchestrator.selectedVoiceIdentifier = (selectedVoiceID != "auto") ? selectedVoiceID : "auto"
        orchestrator.behavior.speechRate = Float(speechSpeed)
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.orchestrator.startSessionWithContinuity(
                workspaceContext: workspaceContext,
                continuityItems: continuityMessages,
                greetingText: greeting,
                hasCodexAppServer: hasCodexAppServer,
                activeTasksProvider: activeTasksProvider,
                onDelegateTaskToAgent: onDelegateTaskToAgent,
                onRecordLocalExchangeToChat: onRecordLocalExchangeToChat,
                onCommitUserUtterance: onSpeech
            )
            self.voicePhase = self.orchestrator.isVoiceSessionActive ? .active : .inactive
            self.isConnecting = false
        }
    }

    func stopVoiceConversation() {
        let shouldPlayEndCue = (voicePhase == .active || voicePhase == .starting)
        let stopCallback = onStopRequested
        onStopRequested = nil
        queuedFinalSpeechText = nil
        isSpeakingIntermediateNotice = false
        isProcessing = false
        if shouldPlayEndCue {
            voicePhase = .stopping
        }
        orchestrator.stopSession()
        webrtcBridge.close()
        isUsingWebRTCTransport = false
        isVoiceModeActive = false
        isConnecting = false
        isMuted = false
        isOutputMuted = false
        realtimeSessionActive = false
        realtimeThreadId = nil
        voiceActivity = .idle
        silenceTimer?.invalidate()
        silenceTimer = nil
        stopRealtimeAudioCapture()
        stopRealtimeAudioPlayback()
        stopListening()
        stopSpeaking()
        voicePhase = .inactive
        voiceFeedbackStatus = nil
        voiceErrorMessage = nil
        liveTranscribedText = ""
        liveAssistantTranscript = ""
        resetMeters()
        if shouldPlayEndCue {
            CodexVoiceAudioCues.shared.play(.realtimeEnd, enabled: voiceSoundsEnabled)
        }
        stopCallback?()
    }

    func toggleMute() {
        if orchestrator.isVoiceSessionActive {
            orchestrator.toggleMute()
            isMuted = orchestrator.isMuted
            CodexVoiceAudioCues.shared.play(isMuted ? .mute : .unmute, enabled: voiceSoundsEnabled)
            return
        }
        isMuted.toggle()
        CodexVoiceAudioCues.shared.play(isMuted ? .mute : .unmute, enabled: voiceSoundsEnabled)
        if isUsingWebRTCTransport {
            webrtcBridge.setMicMuted(isMuted)
            isListening = !isMuted && voicePhase == .active
            if !isSpeaking {
                voiceActivity = isMuted ? .idle : (isProcessing ? .thinking : .listening)
            }
            voiceFeedbackStatus = isMuted ? "Microfone silenciado" : (isSpeaking ? "WisdAI respondendo…" : "Ouvindo você…")
            if isMuted { audioLevel = 0 }
        } else if realtimeSessionActive {
            realtimePCMChunkAccumulator.removeAll(keepingCapacity: false)
            voiceActivity = isMuted ? .idle : (isSpeaking ? .speaking : .listening)
            voiceFeedbackStatus = isMuted ? "Microfone silenciado" : "Ouvindo você…"
            if isMuted { audioLevel = 0 }
        } else if isVoiceModeActive {
            if isMuted {
                stopListening()
                voiceActivity = isSpeaking ? .speaking : .idle
                voiceFeedbackStatus = "Microfone silenciado"
            } else {
                voiceFeedbackStatus = "Ouvindo você…"
                voiceActivity = .listening
                startListening(onTranscription: onTranscriptionCallback)
            }
        }
    }

    func toggleOutputMute() {
        if orchestrator.isVoiceSessionActive {
            orchestrator.toggleOutputMute()
            isOutputMuted = orchestrator.isOutputMuted
            CodexVoiceAudioCues.shared.play(isOutputMuted ? .mute : .unmute, enabled: voiceSoundsEnabled)
            return
        }
        isOutputMuted.toggle()
        CodexVoiceAudioCues.shared.play(isOutputMuted ? .mute : .unmute, enabled: voiceSoundsEnabled)
        if isUsingWebRTCTransport {
            webrtcBridge.setOutputMuted(isOutputMuted)
        }
        if isOutputMuted {
            stopRealtimeAudioPlayback()
            if !isUsingWebRTCTransport {
                stopSpeaking()
            } else {
                isSpeaking = false
                if voicePhase == .active && !isMuted {
                    voiceActivity = isProcessing ? .thinking : .listening
                    voiceFeedbackStatus = "Áudio silenciado · lendo no chat"
                }
            }
        } else if voicePhase == .active {
            voiceFeedbackStatus = isMuted ? "Microfone silenciado" : "Ouvindo você…"
        }
    }

    func interruptAndListen() {
        if orchestrator.isVoiceSessionActive {
            orchestrator.performManualOrVADBarageIn(reason: "Interrupção manual do usuário")
            return
        }
        if isUsingWebRTCTransport {
            webrtcBridge.sendDataChannelEvent(["type": "response.cancel"])
            webrtcBridge.sendDataChannelEvent(["type": "output_audio_buffer.clear"])
            isSpeaking = false
            if isMuted {
                isMuted = false
                webrtcBridge.setMicMuted(false)
            }
            voiceActivity = .listening
            voiceFeedbackStatus = "Ouvindo você…"
            return
        }
        if realtimeSessionActive {
            interruptRealtimeOutputAudio()
            if isMuted { isMuted = false }
            voiceActivity = .listening
            voiceFeedbackStatus = "Ouvindo você…"
            return
        }
        stopSpeaking()
        if isMuted { isMuted = false }
        voiceActivity = .listening
        startListening(onTranscription: onTranscriptionCallback)
    }

    func finalizeSpeech() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        let prompt = stopListening()
        guard !prompt.isEmpty else { return }
        liveTranscribedText = ""
        voiceActivity = .thinking
        voiceFeedbackStatus = "Pensando…"
        onSpeechFinalized?(prompt)
    }

    func resumeListeningIfVoiceActive() {
        guard isVoiceModeActive, continuousConversation, !isSpeaking, !isMuted, !realtimeSessionActive else {
            if isVoiceModeActive && !isSpeaking {
                voiceActivity = isMuted ? .idle : .listening
            }
            return
        }
        isProcessing = false
        voiceActivity = .listening
        voiceFeedbackStatus = "Ouvindo você…"
        if !isListening {
            startListening(onTranscription: onTranscriptionCallback)
        }
    }

    func previewVoice() {
        let sample = voiceGender == .male
            ? "Oi! Aqui é o assistente de voz do WisdAI no estilo Codex. Pode conversar comigo que eu respondo direto por aqui."
            : "Oi! Aqui é a assistente de voz do WisdAI no estilo Codex. Pode conversar comigo que eu respondo direto por aqui."
        speak(sample)
    }

    func openPrivacySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition",
            "x-apple.systempreferences:com.apple.preference.security"
        ]
        for raw in urls {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    // MARK: - Ditado Inline Estilo Codex (Forma de Onda + Transcrição / Recuperação)

    func startDictation(
        onLiveUpdate: @escaping (String) -> Void,
        onFinalResult: @escaping (String) -> Void
    ) {
        if isVoiceModeActive {
            stopVoiceConversation()
        }
        stopSpeaking()
        dictationRecovery = nil
        dictationPhase = .starting
        isDictationMode = true
        dictationFinalCallback = onFinalResult
        dictationAudioLock.lock()
        dictationCapturedPCM16.removeAll(keepingCapacity: true)
        dictationAudioLock.unlock()
        dictationWaveformHistory = Array(repeating: 0, count: 96)
        recordingDurationMs = 0
        dictationStartedAt = Date()
        CodexVoiceAudioCues.shared.play(.dictationStart, enabled: voiceSoundsEnabled)
        startListening(onTranscription: onLiveUpdate)
    }

    func stopDictation(cancel: Bool = false, onFinal: ((String) -> Void)? = nil) {
        dictationDurationTimer?.invalidate()
        dictationDurationTimer = nil

        if let onFinal {
            dictationFinalCallback = onFinal
        }

        guard isDictationMode || dictationPhase == .starting || dictationPhase == .recording || dictationPhase == .processing else {
            return
        }

        let liveFallback = stopListening()
        let finalDurationMs = recordingDurationMs
        let callback = dictationFinalCallback

        dictationAudioLock.lock()
        let capturedPCM = dictationCapturedPCM16
        dictationCapturedPCM16.removeAll(keepingCapacity: false)
        dictationAudioLock.unlock()

        isDictationMode = false
        dictationStartedAt = nil

        if cancel {
            dictationPhase = .idle
            dictationRecovery = nil
            dictationFinalCallback = nil
            liveTranscribedText = ""
            CodexVoiceAudioCues.shared.play(.dictationStop, enabled: voiceSoundsEnabled)
            return
        }

        CodexVoiceAudioCues.shared.play(.dictationStop, enabled: voiceSoundsEnabled)

        if finalDurationMs < 240 && liveFallback.isEmpty {
            dictationPhase = .idle
            dictationFinalCallback = nil
            dictationRecovery = CodexDictationRecovery(
                reason: "Gravação muito curta para transcrever.",
                recoveredText: "",
                canRetry: true
            )
            return
        }

        let policy = orchestrator.policy
        let canUseOfficialCloudWhisper = policy.allowPaidVoiceAPIs && policy.externalAudioConsentGranted && Self.hasOpenAIAPIKey()

        if !liveFallback.isEmpty && !capturedPCM.isEmpty && !canUseOfficialCloudWhisper {
            dictationPhase = .completed
            dictationFinalCallback = nil
            callback?(liveFallback)
            dictationPhase = .idle
            return
        }

        if capturedPCM.count >= 6400 && canUseOfficialCloudWhisper {
            dictationPhase = .processing
            let apiKey = (AccountKeychain.readProviderKey(provider: .openai) ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"])?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let wav = CodexVoiceAudioCues.makeWAVContainer(pcm16Mono: capturedPCM, sampleRate: 16_000, channels: 1)
            Task { @MainActor [weak self] in
                guard let self else { return }
                let cloudText = await Self.transcribeWithOfficialOpenAIAPI(wavData: wav, apiKey: apiKey)
                let chosen = (cloudText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                    ? cloudText!
                    : liveFallback
                self.dictationFinalCallback = nil
                if chosen.isEmpty {
                    self.dictationPhase = .idle
                    self.dictationRecovery = CodexDictationRecovery(
                        reason: "Não foi possível transcrever o áudio gravado.",
                        recoveredText: liveFallback,
                        canRetry: true
                    )
                } else {
                    self.dictationPhase = .completed
                    callback?(chosen)
                    self.dictationPhase = .idle
                }
            }
            return
        }

        dictationFinalCallback = nil
        if liveFallback.isEmpty {
            dictationPhase = .idle
            dictationRecovery = CodexDictationRecovery(
                reason: "Nenhuma fala reconhecida. Fale mais perto do microfone ou tente novamente.",
                recoveredText: "",
                canRetry: true
            )
        } else {
            dictationPhase = .completed
            callback?(liveFallback)
            dictationPhase = .idle
        }
    }

    func dismissDictationRecovery() {
        dictationRecovery = nil
    }

    // MARK: - Captura e Reprodução PCM16 Duplex (Codex Realtime)

    private func startRealtimeAudioCapture(
        sendChunk: @escaping (_ base64PCM16: String, _ sampleRate: Int, _ channels: Int, _ samplesPerChannel: Int) -> Void
    ) {
        stopRealtimeAudioCapture()
        self.realtimeAudioSendCallback = sendChunk

        AVCaptureDevice.requestAccess(for: .audio) { [weak self] allowed in
            Task { @MainActor [weak self] in
                guard let self, self.isVoiceModeActive, self.realtimeSessionActive else { return }
                guard allowed else {
                    self.voiceErrorMessage = "Permita o acesso ao Microfone nos Ajustes do Sistema para conversar por voz."
                    self.voiceFeedbackStatus = "Microfone não autorizado"
                    return
                }

                let engine = AVAudioEngine()
                let inputNode = engine.inputNode
                try? inputNode.setVoiceProcessingEnabled(true)

                let inputFormat = inputNode.outputFormat(forBus: 0)
                guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
                      let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true),
                      let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
                    self.voiceErrorMessage = "Formato de microfone indisponível neste dispositivo."
                    return
                }

                self.realtimeCaptureEngine = engine
                self.realtimePCMChunkAccumulator.removeAll(keepingCapacity: true)

                inputNode.removeTap(onBus: 0)
                inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
                    guard let self else { return }

                    var rmsLevel: Float = 0
                    if let chData = buffer.floatChannelData?[0], buffer.frameLength > 0 {
                        let n = Int(buffer.frameLength)
                        var sum: Float = 0
                        for i in 0..<n {
                            let s = chData[i]
                            sum += s * s
                        }
                        rmsLevel = min(max(sqrt(sum / Float(n)) * 11.0, 0.0), 1.0)
                    }

                    let ratio = 24_000.0 / max(inputFormat.sampleRate, 1.0)
                    let outCapacity = AVAudioFrameCount(max(64, Int(Double(buffer.frameLength) * ratio) + 32))
                    guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else { return }

                    var didProvideInput = false
                    var convError: NSError?
                    let status = converter.convert(to: convertedBuffer, error: &convError) { _, outStatus in
                        if didProvideInput {
                            outStatus.pointee = .noDataNow
                            return nil
                        }
                        didProvideInput = true
                        outStatus.pointee = .haveData
                        return buffer
                    }

                    guard status != .error,
                          convertedBuffer.frameLength > 0,
                          let int16Ptr = convertedBuffer.int16ChannelData?[0] else { return }

                    let byteCount = Int(convertedBuffer.frameLength) * MemoryLayout<Int16>.size
                    let chunkData = Data(bytes: int16Ptr, count: byteCount)

                    Task { @MainActor [weak self] in
                        guard let self, self.isVoiceModeActive, self.realtimeSessionActive else { return }
                        if self.isMuted {
                            self.audioLevel = 0
                            return
                        }
                        self.pushMicLevel(rmsLevel)
                        self.realtimePCMChunkAccumulator.append(chunkData)
                        let targetFrameBytes = 2400
                        while self.realtimePCMChunkAccumulator.count >= targetFrameBytes {
                            let slice = self.realtimePCMChunkAccumulator.prefix(targetFrameBytes)
                            self.realtimePCMChunkAccumulator.removeFirst(targetFrameBytes)
                            let b64 = Data(slice).base64EncodedString()
                            self.realtimeAudioSendCallback?(b64, 24_000, 1, targetFrameBytes / 2)
                        }
                    }
                }

                do {
                    engine.prepare()
                    try engine.start()
                    self.isListening = true
                    self.voiceFeedbackStatus = "Ouvindo você…"
                } catch {
                    self.voiceErrorMessage = "Não foi possível iniciar o áudio em tempo real: \(error.localizedDescription)"
                    self.stopRealtimeAudioCapture()
                }
            }
        }
    }

    private func stopRealtimeAudioCapture() {
        realtimeAudioSendCallback = nil
        realtimePCMChunkAccumulator.removeAll(keepingCapacity: false)
        if let engine = realtimeCaptureEngine {
            if engine.isRunning {
                engine.stop()
            }
            engine.inputNode.removeTap(onBus: 0)
        }
        realtimeCaptureEngine = nil
        isListening = false
    }

    func enqueueRealtimePCMOutput(base64Data: String, sampleRate: Int, numChannels: Int) {
        guard isVoiceModeActive, realtimeSessionActive,
              let rawData = Data(base64Encoded: base64Data),
              rawData.count >= 2 else { return }

        let safeRate = Double(max(8000, sampleRate))
        let safeChannels = AVAudioChannelCount(max(1, min(numChannels, 2)))
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: safeRate, channels: safeChannels, interleaved: false) else {
            return
        }

        if realtimePlaybackEngine == nil || realtimePlaybackFormat != format {
            stopRealtimeAudioPlayback()
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            do {
                try engine.start()
                player.play()
                self.realtimePlaybackEngine = engine
                self.realtimePlayerNode = player
                self.realtimePlaybackFormat = format
            } catch {
                return
            }
        }

        let totalSamples = rawData.count / MemoryLayout<Int16>.size
        let frameCount = totalSamples / Int(safeChannels)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        var rmsSum: Float = 0
        rawData.withUnsafeBytes { rawPtr in
            let int16Samples = rawPtr.bindMemory(to: Int16.self)
            for ch in 0..<Int(safeChannels) {
                guard let dst = buffer.floatChannelData?[ch] else { continue }
                for frame in 0..<frameCount {
                    let idx = frame * Int(safeChannels) + ch
                    let sample = Float(Int16(littleEndian: int16Samples[idx])) / 32768.0
                    dst[frame] = sample
                    if ch == 0 {
                        rmsSum += sample * sample
                    }
                }
            }
        }

        let level = min(max(sqrt(rmsSum / Float(max(frameCount, 1))) * 3.2, 0.0), 1.0)
        pushSpeakerLevel(level)
        isSpeaking = true
        voiceFeedbackStatus = "WisdAI falando…"

        realtimePendingBuffers += 1
        realtimePlayerNode?.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.realtimePendingBuffers = max(0, self.realtimePendingBuffers - 1)
                if self.realtimePendingBuffers == 0 {
                    self.isSpeaking = false
                    self.pushSpeakerLevel(0)
                    if self.isVoiceModeActive && !self.isMuted {
                        self.voiceFeedbackStatus = "Ouvindo você…"
                    }
                }
            }
        }
    }

    func interruptRealtimeOutputAudio() {
        realtimePendingBuffers = 0
        realtimePlayerNode?.stop()
        if let player = realtimePlayerNode, realtimePlaybackEngine?.isRunning == true {
            player.play()
        }
        isSpeaking = false
        pushSpeakerLevel(0)
        if isVoiceModeActive && !isMuted {
            voiceFeedbackStatus = "Ouvindo você…"
        }
    }

    private func stopRealtimeAudioPlayback() {
        realtimePendingBuffers = 0
        realtimePlayerNode?.stop()
        realtimePlaybackEngine?.stop()
        realtimePlayerNode = nil
        realtimePlaybackEngine = nil
        realtimePlaybackFormat = nil
        isSpeaking = false
    }

    // MARK: - Reconhecimento de Fala ao Vivo (Modo Chat Conversacional / Ditado)

    func startListening(onTranscription: ((String) -> Void)? = nil) {
        if let onTranscription {
            self.onTranscriptionCallback = onTranscription
        } else if !isVoiceModeActive {
            self.onTranscriptionCallback = nil
        }
        guard !isListening, !isStartingListening else { return }
        isStartingListening = true
        stopSpeaking()
        liveTranscribedText = ""
        accumulatedTranscriptPrefix = ""
        voiceFeedbackStatus = "Ouvindo você…"
        voiceErrorMessage = nil

        let startSessionToken = UUID()
        self.recognitionToken = startSessionToken

        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.recognitionToken == startSessionToken else {
                    self.isStartingListening = false
                    return
                }
                guard authStatus == .authorized else {
                    self.isStartingListening = false
                    let errMsg = "Permita o Reconhecimento de Fala para o WisdAI nos Ajustes do Sistema (Privacidade e Segurança)."
                    self.voiceErrorMessage = errMsg
                    self.voiceFeedbackStatus = "Reconhecimento não autorizado"
                    if self.isDictationMode {
                        self.isDictationMode = false
                        self.dictationPhase = .idle
                        self.dictationFinalCallback = nil
                        self.dictationRecovery = CodexDictationRecovery(reason: errMsg, recoveredText: "", canRetry: true)
                    }
                    return
                }

                AVCaptureDevice.requestAccess(for: .audio) { [weak self] micAllowed in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.isStartingListening = false
                        guard self.recognitionToken == startSessionToken else { return }
                        guard micAllowed else {
                            let errMsg = "Permita o acesso ao Microfone para o WisdAI nos Ajustes do Sistema."
                            self.voiceErrorMessage = errMsg
                            self.voiceFeedbackStatus = "Microfone não autorizado"
                            if self.isDictationMode {
                                self.isDictationMode = false
                                self.dictationPhase = .idle
                                self.dictationFinalCallback = nil
                                self.dictationRecovery = CodexDictationRecovery(reason: errMsg, recoveredText: "", canRetry: true)
                            }
                            return
                        }
                        self.beginAudioEngineRecording()
                    }
                }
            }
        }
    }

    private func beginAudioEngineRecording() {
        restartTaskWorkItem?.cancel()
        restartTaskWorkItem = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        if let existingEngine = dictationEngine {
            if existingEngine.isRunning {
                existingEngine.stop()
            }
            existingEngine.inputNode.removeTap(onBus: 0)
            dictationEngine = nil
        }

        let engine = AVAudioEngine()
        self.dictationEngine = engine

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            voiceErrorMessage = "Nenhum microfone disponível foi encontrado."
            stopListening()
            return
        }

        let tempRequest = SFSpeechAudioBufferRecognitionRequest()
        let recognizerFormat = tempRequest.nativeAudioFormat
        let audioConverter: AVAudioConverter? = {
            if recordingFormat.channelCount == recognizerFormat.channelCount &&
                recordingFormat.sampleRate == recognizerFormat.sampleRate &&
                recordingFormat.commonFormat == recognizerFormat.commonFormat {
                return nil
            }
            return AVAudioConverter(from: recordingFormat, to: recognizerFormat)
        }()

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] (buffer, _) in
            guard let self else { return }

            self.recognitionLock.lock()
            let activeReq = self.recognitionRequest
            self.recognitionLock.unlock()

            if let activeReq {
                if let audioConverter {
                    let ratio = recognizerFormat.sampleRate / max(recordingFormat.sampleRate, 1.0)
                    let outCapacity = AVAudioFrameCount(max(64, Int(Double(buffer.frameLength) * ratio) + 32))
                    if let converted = AVAudioPCMBuffer(pcmFormat: recognizerFormat, frameCapacity: outCapacity) {
                        var provided = false
                        var convErr: NSError?
                        let status = audioConverter.convert(to: converted, error: &convErr) { _, outStatus in
                            if provided {
                                outStatus.pointee = .noDataNow
                                return nil
                            }
                            provided = true
                            outStatus.pointee = .haveData
                            return buffer
                        }
                        if status != .error && converted.frameLength > 0 {
                            activeReq.append(converted)
                        }
                    }
                } else {
                    activeReq.append(buffer)
                }
            }

            // Captura PCM16 16kHz mono para transcrição oficial opt-in (/v1/audio/transcriptions) durante ditado
            if self.isDictationMode,
               let dictFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true),
               let dictConverter = AVAudioConverter(from: recordingFormat, to: dictFormat) {
                let ratio = 16_000.0 / max(recordingFormat.sampleRate, 1.0)
                let cap = AVAudioFrameCount(max(64, Int(Double(buffer.frameLength) * ratio) + 32))
                if let pcmBuf = AVAudioPCMBuffer(pcmFormat: dictFormat, frameCapacity: cap) {
                    var didProvide = false
                    var convErr: NSError?
                    let st = dictConverter.convert(to: pcmBuf, error: &convErr) { _, outStatus in
                        if didProvide {
                            outStatus.pointee = .noDataNow
                            return nil
                        }
                        didProvide = true
                        outStatus.pointee = .haveData
                        return buffer
                    }
                    if st != .error, pcmBuf.frameLength > 0, let ptr = pcmBuf.int16ChannelData?[0] {
                        let bytes = Data(bytes: ptr, count: Int(pcmBuf.frameLength) * 2)
                        self.dictationAudioLock.lock()
                        if self.dictationCapturedPCM16.count < 16_000 * 2 * 300 {
                            self.dictationCapturedPCM16.append(bytes)
                        }
                        self.dictationAudioLock.unlock()
                    }
                }
            }

            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frameLength {
                let sample = channelData[i]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(max(frameLength, 1)))
            let normalized = min(max(rms * 11.0, 0.0), 1.0)
            DispatchQueue.main.async {
                self.pushMicLevel(normalized)
            }
        }

        do {
            engine.prepare()
            try engine.start()
            isListening = true
            if isDictationMode {
                dictationPhase = .recording
                dictationStartedAt = Date()
                dictationDurationTimer?.invalidate()
                dictationDurationTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, let started = self.dictationStartedAt, self.isDictationMode else { return }
                        self.recordingDurationMs = max(0, Int(Date().timeIntervalSince(started) * 1000))
                    }
                }
            } else if isVoiceModeActive && !isSpeaking && !isProcessing {
                voiceActivity = .listening
            }
            voiceFeedbackStatus = "Ouvindo você…"
        } catch {
            voiceErrorMessage = "Não foi possível iniciar o microfone: \(error.localizedDescription)"
            if isDictationMode {
                dictationRecovery = CodexDictationRecovery(reason: error.localizedDescription, recoveredText: "", canRetry: true)
                dictationPhase = .idle
                isDictationMode = false
            }
            stopListening()
            return
        }

        startRecognitionTaskOnActiveEngine()
    }

    private func startRecognitionTaskOnActiveEngine() {
        guard isListening, dictationEngine?.isRunning == true else { return }
        guard speechRecognizer.isAvailable else {
            voiceErrorMessage = "Reconhecimento de fala indisponível no momento neste Mac."
            stopListening()
            return
        }

        recognitionTask?.cancel()
        recognitionTask = nil

        let taskToken = UUID()
        self.recognitionToken = taskToken

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Deixa o macOS escolher livremente reconhecimento online/local para maior fluidez em PT-BR
        request.requiresOnDeviceRecognition = false
        recognitionLock.lock()
        self.recognitionRequest = request
        recognitionLock.unlock()

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, self.recognitionToken == taskToken, self.isListening else { return }

                if let result {
                    let segment = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    let combined: String = {
                        if self.accumulatedTranscriptPrefix.isEmpty { return segment }
                        if segment.isEmpty { return self.accumulatedTranscriptPrefix }
                        return self.accumulatedTranscriptPrefix + " " + segment
                    }()

                    if !combined.isEmpty {
                        self.liveTranscribedText = combined
                        self.onTranscriptionCallback?(combined)
                    }

                    if self.isVoiceModeActive && !self.realtimeSessionActive && !combined.isEmpty {
                        let delay = Self.recommendedSilenceDelay(for: combined)
                        self.silenceTimer?.invalidate()
                        self.silenceTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                            Task { @MainActor in
                                guard let self, self.isListening else { return }
                                self.finalizeSpeech()
                            }
                        }
                    }

                    if result.isFinal {
                        if !combined.isEmpty {
                            self.accumulatedTranscriptPrefix = combined
                        }
                        if self.isListening && !self.isMuted {
                            self.scheduleRecognitionTaskRestart(after: 0.08)
                        }
                        return
                    }
                }

                if let error {
                    let nsErr = error as NSError
                    // O SFSpeechRecognizer encerra periodicamente por silêncio inicial (1110),
                    // retry de sessão (203) ou limite de segmento (216/301): acumula e continua ouvindo.
                    let recoverableCodes: Set<Int> = [1110, 203, 216, 301]
                    if recoverableCodes.contains(nsErr.code) {
                        let buffered = self.liveTranscribedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !buffered.isEmpty {
                            self.accumulatedTranscriptPrefix = buffered
                        }
                        if self.isListening && !self.isMuted {
                            self.scheduleRecognitionTaskRestart(after: 0.10)
                        }
                    } else {
                        self.voiceErrorMessage = "Erro no reconhecimento de fala: \(nsErr.localizedDescription)"
                        self.stopListening()
                    }
                }
            }
        }
    }

    private func scheduleRecognitionTaskRestart(after delay: TimeInterval) {
        restartTaskWorkItem?.cancel()
        recognitionLock.lock()
        let prevReq = recognitionRequest
        recognitionRequest = nil
        recognitionLock.unlock()
        prevReq?.endAudio()

        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isListening, !self.isMuted, self.dictationEngine?.isRunning == true else { return }
                self.startRecognitionTaskOnActiveEngine()
            }
        }
        restartTaskWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    @discardableResult
    func stopListening() -> String {
        isStartingListening = false
        recognitionToken = UUID()
        restartTaskWorkItem?.cancel()
        restartTaskWorkItem = nil
        silenceTimer?.invalidate()
        silenceTimer = nil

        let finalPrompt = liveTranscribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        accumulatedTranscriptPrefix = ""
        if let engine = dictationEngine {
            if engine.isRunning {
                engine.stop()
            }
            engine.inputNode.removeTap(onBus: 0)
            dictationEngine = nil
        }

        recognitionLock.lock()
        let prevReq = recognitionRequest
        recognitionRequest = nil
        recognitionLock.unlock()
        prevReq?.endAudio()

        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false
        audioLevel = 0.0
        return finalPrompt
    }

    func cancelListening() {
        _ = stopListening()
        liveTranscribedText = ""
        voiceFeedbackStatus = "Ouvindo você…"
    }

    // MARK: - Detecção Inteligente de Pausa de Fala

    nonisolated static func recommendedSilenceDelay(for text: String) -> TimeInterval {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 2.5 }
        if trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?") {
            return 1.65
        }
        let words = trimmed.split(whereSeparator: { $0.isWhitespace }).map { $0.lowercased() }
        let danglingEndings: Set<String> = [
            "que", "você", "vc", "eu", "ele", "ela", "nós", "para", "pra", "com",
            "de", "da", "do", "das", "dos", "em", "na", "no", "nas", "nos",
            "e", "ou", "mas", "porque", "por", "como", "quando", "se", "a", "o",
            "as", "os", "um", "uma", "uns", "umas", "esse", "essa", "este", "esta",
            "quero", "preciso", "gostaria", "poderia", "pode", "vai", "fazer"
        ]
        if let last = words.last, danglingEndings.contains(last) || words.count < 4 {
            return 2.9
        }
        return 2.15
    }

    // MARK: - Síntese Neural e Conversa Natural por Voz

    func speak(
        _ rawText: String,
        preserveProcessingState: Bool = false,
        queueIfSpeakingIntermediate: Bool = false,
        onFinished: (() -> Void)? = nil
    ) {
        let text = Self.cleanForSpeech(rawText)
        guard !text.isEmpty else { return }

        if queueIfSpeakingIntermediate && isSpeaking && isSpeakingIntermediateNotice {
            queuedFinalSpeechText = rawText
            return
        }

        if !realtimeSessionActive {
            stopListening()
        }
        queuedFinalSpeechText = nil
        stopSpeakingInternal(clearHandler: false)

        if isOutputMuted {
            liveAssistantTranscript = text
            isSpeaking = false
            isSpeakingIntermediateNotice = false
            isProcessing = preserveProcessingState
            voiceActivity = preserveProcessingState ? .thinking : (isMuted ? .idle : .listening)
            voiceFeedbackStatus = isMuted ? "Áudio e microfone silenciados" : "Áudio silenciado · lendo no chat"
            onFinished?()
            if isVoiceModeActive && continuousConversation && !isProcessing && !isMuted && !realtimeSessionActive {
                startListening(onTranscription: onTranscriptionCallback)
            }
            return
        }

        let token = UUID()
        self.speechToken = token
        self.completionHandler = onFinished
        self.isSpeaking = true
        self.isSpeakingIntermediateNotice = preserveProcessingState
        self.isProcessing = preserveProcessingState
        self.voiceActivity = .speaking
        self.voiceFeedbackStatus = preserveProcessingState ? "Executando tarefa…" : "WisdAI respondendo…"
        startSpeakerPulseAnimation()

        let sentences = Self.splitIntoNaturalSentences(text)
        guard !sentences.isEmpty else {
            finishSpeakingSession(token: token)
            return
        }

        let policy = orchestrator.policy
        if preferCloudNeuralTTS,
           policy.allowPaidVoiceAPIs,
           policy.externalAudioConsentGranted,
           Date() >= cloudTTSCooldownUntil,
           let apiKey = (AccountKeychain.readProviderKey(provider: .openai) ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"])?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !apiKey.isEmpty {
            let voiceName = activeCodexVoice.openAISpeechVoice
            let speed = min(1.25, max(0.75, speechSpeed))
            cloudTTSTask = Task { @MainActor [weak self] in
                guard let self, self.speechToken == token else { return }
                let (audioData, statusCode) = await Self.fetchOpenAISpeech(text: text, voice: voiceName, speed: speed, apiKey: apiKey)
                guard self.speechToken == token else { return }
                if let audioData, self.playStudioAudioData(audioData, token: token) {
                    return
                }
                if let statusCode, (statusCode == 401 || statusCode == 403 || statusCode == 429) {
                    self.cloudTTSCooldownUntil = Date().addingTimeInterval(300)
                }
                self.startLocalNaturalSpeech(sentences: sentences, token: token)
            }
            return
        }

        startLocalNaturalSpeech(sentences: sentences, token: token)
    }

    private static func transcribeWithOfficialOpenAIAPI(wavData: Data, apiKey: String?) async -> String? {
        guard wavData.count > 1600,
              let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty,
              let url = URL(string: "https://api.openai.com/v1/audio/transcriptions") else {
            return nil
        }
        let boundary = "----WisdAIOpenAITranscribe\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var body = Data()
        body.append(contentsOf: "--\(boundary)\r\n".utf8)
        body.append(contentsOf: "Content-Disposition: form-data; name=\"file\"; filename=\"dictation.wav\"\r\n".utf8)
        body.append(contentsOf: "Content-Type: audio/wav\r\n\r\n".utf8)
        body.append(wavData)
        body.append(contentsOf: "\r\n--\(boundary)\r\n".utf8)
        body.append(contentsOf: "Content-Disposition: form-data; name=\"model\"\r\n\r\ngpt-4o-mini-transcribe\r\n".utf8)
        body.append(contentsOf: "--\(boundary)\r\n".utf8)
        body.append(contentsOf: "Content-Disposition: form-data; name=\"language\"\r\n\r\npt\r\n".utf8)
        body.append(contentsOf: "--\(boundary)--\r\n".utf8)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 14.0
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpCookieStorage = nil
        cfg.urlCredentialStorage = nil
        let session = URLSession(configuration: cfg)
        defer { session.invalidateAndCancel() }
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = (json["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return text
    }

    func stopSpeaking() {
        queuedFinalSpeechText = nil
        isSpeakingIntermediateNotice = false
        stopSpeakingInternal(clearHandler: true)
    }

    private func stopSpeakingInternal(clearHandler: Bool) {
        speechToken = UUID()
        pendingSentences = []
        pendingCloudChunks = []
        prefetchedCloudAudioData = nil
        activeSpeechUtterance = nil
        directSpeakDidStart = false
        directSpeakWatchdog?.cancel()
        directSpeakWatchdog = nil
        baritoneWriteWatchdog?.cancel()
        baritoneWriteWatchdog = nil
        cloudTTSTask?.cancel()
        cloudTTSTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
        teardownPlaybackEngine()
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        speakerMeterDecayTimer?.invalidate()
        speakerMeterDecayTimer = nil
        isSpeaking = false
        speakerLevel = 0
        if clearHandler {
            completionHandler = nil
        }
    }

    private func teardownPlaybackEngine() {
        playbackPlayerNode?.stop()
        playbackEngine?.stop()
        playbackPlayerNode = nil
        playbackTimePitch = nil
        playbackEngine = nil
    }

    private func startLocalNaturalSpeech(sentences: [String], token: UUID) {
        guard speechToken == token else { return }
        let resolution = Self.resolveBestVoice(for: voiceGender, explicitID: selectedVoiceID)
        self.activeNativeVoice = resolution.voice
        self.activeUseBaritoneShift = resolution.useBaritoneShift
        self.pendingSentences = sentences
        playNextLocalSentence(token: token)
    }

    private func playNextLocalSentence(token: UUID) {
        guard speechToken == token else { return }
        guard !pendingSentences.isEmpty else {
            finishSpeakingSession(token: token)
            return
        }
        let sentence = pendingSentences.removeFirst()

        let utterance = AVSpeechUtterance(string: sentence)
        utterance.voice = activeNativeVoice
        let baseRate = Float(0.50 * speechSpeed)
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, baseRate))
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.01
        utterance.postUtteranceDelay = pendingSentences.isEmpty ? 0.03 : 0.10

        if activeUseBaritoneShift {
            // Crítico: synthesizer.write() dispara didFinish ao terminar de escrever PCM na memória,
            // muito antes do som terminar no AVAudioPlayerNode; activeSpeechUtterance deve ficar nil aqui.
            self.activeSpeechUtterance = nil
            utterance.pitchMultiplier = 1.0
            synthesizeAndPlayWithBaritoneTimbre(utterance: utterance, token: token)
        } else {
            utterance.pitchMultiplier = 1.0
            speakDirectUtteranceWithWatchdog(utterance, token: token)
        }
    }

    private func speakDirectUtteranceWithWatchdog(_ utterance: AVSpeechUtterance, token: UUID) {
        directSpeakWatchdog?.cancel()
        directSpeakDidStart = false
        self.activeSpeechUtterance = utterance
        synthesizer.speak(utterance)

        let watchdog = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.speechToken == token,
                      self.activeSpeechUtterance === utterance,
                      !self.directSpeakDidStart else { return }
                let fallbackVoice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.compact.pt-BR.Luciana")
                    ?? AVSpeechSynthesisVoice(language: "pt-BR")
                guard let fallbackVoice, fallbackVoice.identifier != utterance.voice?.identifier else { return }
                self.synthesizer.stopSpeaking(at: .immediate)
                let fallback = AVSpeechUtterance(string: utterance.speechString)
                fallback.voice = fallbackVoice
                fallback.rate = utterance.rate
                fallback.volume = 1.0
                fallback.pitchMultiplier = self.voiceGender == .male ? 0.82 : 1.0
                self.activeSpeechUtterance = fallback
                self.synthesizer.speak(fallback)
            }
        }
        directSpeakWatchdog = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: watchdog)
    }

    private nonisolated static func cloneAsFloat32PCMBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let frameCount = buffer.frameLength
        guard frameCount > 0 else { return nil }

        let targetFormat: AVAudioFormat
        if buffer.format.commonFormat == .pcmFormatFloat32, !buffer.format.isInterleaved {
            targetFormat = buffer.format
        } else if let floatFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: buffer.format.sampleRate, channels: buffer.format.channelCount, interleaved: false) {
            targetFormat = floatFmt
        } else {
            return nil
        }

        guard let copy = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return nil }
        copy.frameLength = frameCount

        if buffer.format.commonFormat == .pcmFormatFloat32,
           let src = buffer.floatChannelData,
           let dst = copy.floatChannelData {
            let channels = Int(buffer.format.channelCount)
            let count = Int(frameCount)
            for ch in 0..<channels {
                dst[ch].update(from: src[ch], count: count)
            }
            return copy
        }

        guard let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else { return nil }
        var didProvide = false
        var convError: NSError?
        let status = converter.convert(to: copy, error: &convError) { _, outStatus in
            if didProvide {
                outStatus.pointee = .noDataNow
                return nil
            }
            didProvide = true
            outStatus.pointee = .haveData
            return buffer
        }
        return (status != .error && copy.frameLength > 0) ? copy : nil
    }

    private func synthesizeAndPlayWithBaritoneTimbre(utterance: AVSpeechUtterance, token: UUID) {
        teardownPlaybackEngine()
        baritoneWriteWatchdog?.cancel()

        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        timePitch.pitch = -290
        timePitch.rate = 1.0
        timePitch.overlap = 12.0

        engine.attach(playerNode)
        engine.attach(timePitch)
        engine.mainMixerNode.outputVolume = 1.0
        playerNode.volume = 1.0
        self.playbackEngine = engine
        self.playbackPlayerNode = playerNode
        self.playbackTimePitch = timePitch

        var engineConfigured = false
        var scheduledCount = 0
        var lastFormat: AVAudioFormat?

        let watchdog = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.speechToken == token, self.playbackEngine === engine else { return }
                if self.playbackPlayerNode?.isPlaying != true && self.pendingSentences.isEmpty && self.activeSpeechUtterance == nil {
                    self.teardownPlaybackEngine()
                    let fallback = AVSpeechUtterance(string: utterance.speechString)
                    fallback.voice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.compact.pt-BR.Luciana") ?? utterance.voice
                    fallback.rate = utterance.rate
                    fallback.volume = 1.0
                    fallback.pitchMultiplier = 0.82
                    self.speakDirectUtteranceWithWatchdog(fallback, token: token)
                }
            }
        }
        baritoneWriteWatchdog = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: watchdog)

        synthesizer.write(utterance) { [weak self] audioBuffer in
            guard let pcm = audioBuffer as? AVAudioPCMBuffer else { return }
            let isEndMarker = (pcm.frameLength == 0)
            let cloned = isEndMarker ? nil : Self.cloneAsFloat32PCMBuffer(pcm)

            DispatchQueue.main.async { [weak self] in
                guard let self, self.speechToken == token, self.playbackEngine === engine else { return }

                if isEndMarker {
                    self.baritoneWriteWatchdog?.cancel()
                    self.baritoneWriteWatchdog = nil
                    if scheduledCount == 0 {
                        self.teardownPlaybackEngine()
                        let fallback = AVSpeechUtterance(string: utterance.speechString)
                        fallback.voice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.compact.pt-BR.Luciana") ?? utterance.voice
                        fallback.rate = utterance.rate
                        fallback.volume = 1.0
                        fallback.pitchMultiplier = 0.82
                        self.speakDirectUtteranceWithWatchdog(fallback, token: token)
                        return
                    }
                    if let fmt = lastFormat,
                       let marker = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 1) {
                        marker.frameLength = 1
                        marker.floatChannelData?[0][0] = 0
                        playerNode.scheduleBuffer(marker, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                            Task { @MainActor [weak self] in
                                self?.playNextLocalSentence(token: token)
                            }
                        }
                    } else {
                        self.playNextLocalSentence(token: token)
                    }
                    return
                }

                guard let safePCM = cloned else { return }

                if !engineConfigured {
                    self.baritoneWriteWatchdog?.cancel()
                    self.baritoneWriteWatchdog = nil
                    engine.connect(playerNode, to: timePitch, format: safePCM.format)
                    engine.connect(timePitch, to: engine.mainMixerNode, format: safePCM.format)
                    do {
                        try engine.start()
                        playerNode.play()
                        engineConfigured = true
                        lastFormat = safePCM.format
                    } catch {
                        self.teardownPlaybackEngine()
                        let fallback = AVSpeechUtterance(string: utterance.speechString)
                        fallback.voice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.compact.pt-BR.Luciana") ?? utterance.voice
                        fallback.rate = utterance.rate
                        fallback.volume = 1.0
                        fallback.pitchMultiplier = 0.82
                        self.speakDirectUtteranceWithWatchdog(fallback, token: token)
                        return
                    }
                }

                lastFormat = safePCM.format
                scheduledCount += 1
                playerNode.scheduleBuffer(safePCM, completionHandler: nil)
            }
        }
    }

    private func playStudioAudioData(_ data: Data, token: UUID) -> Bool {
        guard speechToken == token else { return false }
        do {
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            player.isMeteringEnabled = true
            player.enableRate = true
            player.rate = Float(min(1.28, max(0.82, speechSpeed)))
            player.volume = 1.0
            player.prepareToPlay()
            self.audioPlayer = player
            return player.play()
        } catch {
            return false
        }
    }

    private static func fetchOpenAISpeech(text: String, voice: String, speed: Double, apiKey: String) async -> (Data?, Int?) {
        guard let url = URL(string: "https://api.openai.com/v1/audio/speech") else { return (nil, nil) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 3.2
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "tts-1-hd",
            "input": text,
            "voice": voice,
            "response_format": "mp3",
            "speed": speed
        ]
        guard let encoded = try? JSONSerialization.data(withJSONObject: body) else { return (nil, nil) }
        request.httpBody = encoded

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return (nil, nil) }
            guard (200..<300).contains(http.statusCode), !data.isEmpty else {
                return (nil, http.statusCode)
            }
            return (data, http.statusCode)
        } catch {
            return (nil, nil)
        }
    }

    private func finishSpeakingSession(token: UUID) {
        guard speechToken == token else { return }
        activeSpeechUtterance = nil
        teardownPlaybackEngine()
        audioPlayer = nil
        speakerMeterDecayTimer?.invalidate()
        speakerMeterDecayTimer = nil
        let wasIntermediate = isSpeakingIntermediateNotice
        isSpeakingIntermediateNotice = false
        isSpeaking = false
        pushSpeakerLevel(0)
        let handler = completionHandler
        completionHandler = nil
        handler?()

        if let queued = queuedFinalSpeechText {
            queuedFinalSpeechText = nil
            isProcessing = false
            speak(queued, preserveProcessingState: false, queueIfSpeakingIntermediate: false)
            return
        }

        if wasIntermediate && isProcessing {
            voiceActivity = .thinking
            voiceFeedbackStatus = "Executando tarefa…"
            return
        }

        if isVoiceModeActive && continuousConversation && !isProcessing && !isMuted && !realtimeSessionActive {
            voiceActivity = .listening
            voiceFeedbackStatus = "Ouvindo você…"
            let restartToken = speechToken
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                guard let self,
                      self.speechToken == restartToken,
                      self.isVoiceModeActive,
                      self.continuousConversation,
                      !self.isProcessing,
                      !self.isSpeaking,
                      !self.isMuted,
                      !self.realtimeSessionActive else { return }
                self.startListening(onTranscription: self.onTranscriptionCallback)
            }
        } else if !isProcessing {
            voiceActivity = isMuted ? .idle : .listening
            voiceFeedbackStatus = isMuted ? "Microfone silenciado" : "Ouvindo você…"
        }
    }

    // MARK: - Medidores de Amplitude e Orbe Horizon (Estilo Codex)

    private func pushMicLevel(_ level: Float) {
        audioLevel = level
        var next = micHistory
        if !next.isEmpty { next.removeFirst() }
        next.append(level)
        micHistory = next

        if isDictationMode {
            var wf = dictationWaveformHistory
            if !wf.isEmpty { wf.removeFirst() }
            wf.append(level)
            dictationWaveformHistory = wf
        }

        if !isUsingWebRTCTransport {
            let overall = isSpeaking ? orbLevels.overall : level * 0.45
            orbLevels = CodexOrbAudioLevels(
                overall: overall,
                low: orbLevels.low,
                mid: isSpeaking ? orbLevels.mid : level * 0.55,
                high: orbLevels.high,
                micLevel: level
            )
            if isVoiceModeActive && !isSpeaking && !isProcessing && !isMuted {
                voiceActivity = .listening
            }
        }
    }

    private func pushSpeakerLevel(_ level: Float) {
        speakerLevel = level
        var next = speakerHistory
        if !next.isEmpty { next.removeFirst() }
        next.append(level)
        speakerHistory = next

        if !isUsingWebRTCTransport {
            orbLevels = CodexOrbAudioLevels(
                overall: level,
                low: min(1.0, level * 0.95),
                mid: min(1.0, level * 1.05),
                high: min(1.0, level * 0.72),
                micLevel: audioLevel
            )
            if isVoiceModeActive && level > 0.02 && !isOutputMuted {
                voiceActivity = .speaking
            }
        }
    }

    private func resetMeters() {
        audioLevel = 0
        speakerLevel = 0
        orbLevels = .zero
        micHistory = Array(repeating: 0, count: 10)
        speakerHistory = Array(repeating: 0, count: 10)
        dictationWaveformHistory = Array(repeating: 0, count: 96)
    }

    private func startSpeakerPulseAnimation() {
        speakerMeterDecayTimer?.invalidate()
        var phase: Double = 0
        speakerMeterDecayTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
            phase += 0.24
            let smoothHarmonic = Float(0.40 + 0.22 * sin(phase) + 0.14 * sin(phase * 2.17 + 0.6))
            Task { @MainActor [weak self] in
                guard let self, self.isSpeaking else { return }
                if let player = self.audioPlayer, player.isPlaying {
                    player.updateMeters()
                    let power = player.averagePower(forChannel: 0)
                    let norm = min(max((power + 45.0) / 45.0, 0.1), 1.0)
                    let blended = self.speakerLevel * 0.55 + norm * 0.45
                    self.pushSpeakerLevel(blended)
                } else {
                    self.pushSpeakerLevel(min(max(smoothHarmonic, 0.15), 0.90))
                }
            }
        }
    }

    // MARK: - Limpeza e Segmentação Natural para Fala em Português

    nonisolated static func splitIntoNaturalSentences(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var sentences: [String] = []
        var current = ""
        for char in trimmed {
            current.append(char)
            if (char == "." || char == "!" || char == "?" || char == "\n"), current.count >= 22 {
                let candidate = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty {
                    sentences.append(candidate)
                }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            if let last = sentences.last, tail.count < 16 {
                sentences[sentences.count - 1] = last + " " + tail
            } else {
                sentences.append(tail)
            }
        }
        return sentences
    }

    nonisolated static func cleanForSpeech(_ raw: String) -> String {
        var text = raw
        let codeBlockRegex = try? NSRegularExpression(pattern: "```[\\s\\S]*?```", options: [])
        text = codeBlockRegex?.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count), withTemplate: ", código exibido no chat. ") ?? text
        let linkRegex = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\([^\\)]+\\)", options: [])
        text = linkRegex?.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count), withTemplate: "$1") ?? text
        let urlRegex = try? NSRegularExpression(pattern: "(?:https?|file)://\\S+", options: [])
        text = urlRegex?.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count), withTemplate: "") ?? text
        text = text.replacingOccurrences(of: "`", with: "")
        text = text.replacingOccurrences(of: "**", with: "")
        text = text.replacingOccurrences(of: "*", with: "")
        text = text.replacingOccurrences(of: "__", with: "")
        text = text.replacingOccurrences(of: "|", with: ", ")
        let headerRegex = try? NSRegularExpression(pattern: "^#{1,6}\\s*", options: [.anchorsMatchLines])
        text = headerRegex?.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count), withTemplate: "") ?? text
        let bulletRegex = try? NSRegularExpression(pattern: "^\\s*[-•·⚡⚠️✅✓⏳]+\\s*", options: [.anchorsMatchLines])
        text = bulletRegex?.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count), withTemplate: "") ?? text

        let cleanedScalars = text.unicodeScalars.filter { scalar in
            if scalar.properties.isEmojiPresentation || scalar.properties.isEmoji && !scalar.isASCII {
                return false
            }
            return true
        }
        text = String(String.UnicodeScalarView(cleanedScalars))
        text = text.replacingOccurrences(of: "·", with: ", ")
        text = text.replacingOccurrences(of: "—", with: ", ")
        text = text.replacingOccurrences(of: "…", with: ".")

        let multiNewline = try? NSRegularExpression(pattern: "\\s*\\n+\\s*", options: [])
        text = multiNewline?.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count), withTemplate: ". ") ?? text
        let multiSpace = try? NSRegularExpression(pattern: "\\s{2,}", options: [])
        text = multiSpace?.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count), withTemplate: " ") ?? text

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 1200 {
            let index = trimmed.index(trimmed.startIndex, offsetBy: 1200)
            let prefix = String(trimmed[..<index])
            return prefix + ". Veja os demais detalhes no chat."
        }
        return trimmed
    }

    func cleanForSpeech(_ raw: String) -> String {
        Self.cleanForSpeech(raw)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard utterance === self.activeSpeechUtterance else { return }
            self.directSpeakDidStart = true
            self.directSpeakWatchdog?.cancel()
            self.directSpeakWatchdog = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard utterance === self.activeSpeechUtterance else { return }
            self.activeSpeechUtterance = nil
            let token = self.speechToken
            self.playNextLocalSentence(token: token)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard utterance === self.activeSpeechUtterance else { return }
            self.activeSpeechUtterance = nil
            if self.pendingSentences.isEmpty && self.playbackEngine == nil {
                self.isSpeaking = false
                self.completionHandler = nil
            }
        }
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard player === self.audioPlayer else { return }
            let token = self.speechToken
            self.finishSpeakingSession(token: token)
        }
    }
}

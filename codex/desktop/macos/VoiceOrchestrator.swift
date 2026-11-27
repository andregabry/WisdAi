import AVFoundation
import Combine
import Foundation
import Speech
import SwiftUI

// MARK: - WisdAI Brand Chromatic Voice Orb Palette (Section 16)

public enum WisdVoiceOrbPalette: String, CaseIterable, Identifiable, Codable, Sendable {
    case wisdAIBrand     // Deep Blue, Luminous Blue, Turquoise, Gold, Silver
    case oceanDepths     // Deep Blue, Luminous Blue, Turquoise
    case solarSilver     // Luminous Blue, Gold, Silver

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .wisdAIBrand: return "WisdAI Signature (Azul · Turquesa · Ouro · Prata)"
        case .oceanDepths: return "WisdAI Oceano (Azul Profundo · Turquesa)"
        case .solarSilver: return "WisdAI Aurora (Azul Luminoso · Ouro · Prata)"
        }
    }

    public var deepBlue: Color { Color(red: 0.043, green: 0.165, blue: 0.435) }      // #0B2A6F
    public var luminousBlue: Color { Color(red: 0.118, green: 0.420, blue: 1.000) }  // #1E6BFF
    public var turquoise: Color { Color(red: 0.078, green: 0.784, blue: 0.784) }     // #14C8C8
    public var gold: Color { Color(red: 0.898, green: 0.722, blue: 0.294) }          // #E5B84B
    public var silver: Color { Color(red: 0.788, green: 0.831, blue: 0.894) }        // #C9D4E4

    public var gradientColors: [Color] {
        switch self {
        case .wisdAIBrand:
            return [deepBlue, luminousBlue, turquoise, gold, silver]
        case .oceanDepths:
            return [deepBlue, luminousBlue, turquoise, Color(red: 0.42, green: 0.88, blue: 0.94), silver]
        case .solarSilver:
            return [deepBlue, luminousBlue, gold, silver, turquoise]
        }
    }
}

// MARK: - Voice Presentation Mode & Role Decoupling Config (Sections 11 & 16)

public enum VoicePresentationMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case floatingOverlay
    case compactWindow
    case expandedWindow

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .floatingOverlay: return "Overlay sobre o Chat"
        case .compactWindow: return "Janela Compacta de Voz"
        case .expandedWindow: return "Janela Expandida com Transcrição"
        }
    }
}

public struct VoiceRoleRoutingConfig: Equatable, Codable, Sendable {
    public var requestedTransportProvider: VoiceGatewayProviderKind
    public var preferredConversationModelID: String
    public var preferredExecutionAgentAccountID: UUID?

    public static let `default` = VoiceRoleRoutingConfig(
        requestedTransportProvider: .autoBestCompliant,
        preferredConversationModelID: "",
        preferredExecutionAgentAccountID: nil
    )

    private static let defaultsKey = "wisdai.voice.roleRouting.v1"

    public static func load(from defaults: UserDefaults = .standard) -> VoiceRoleRoutingConfig {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(VoiceRoleRoutingConfig.self, from: data) else {
            return .default
        }
        return decoded
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}

// MARK: - Orchestrator Coordinating Engine + Gateway + Intelligence + Memory

@MainActor
public final class WisdVoiceOrchestrator: ObservableObject {
    @Published public private(set) var state: VoiceConversationState = .idle
    @Published public var policy: VoicePolicyPreferences {
        didSet {
            policy.save()
            memoryStore.loadPersistentIfPermitted(policy: policy)
            refreshResolvedPipeline()
        }
    }
    @Published public var behavior: VoiceBehaviorProfile {
        didSet {
            behavior.save()
            customPronunciation = TechnicalPronunciationDictionary.defaults(for: behavior.languageVariant)
        }
    }
    @Published public var routing: VoiceRoleRoutingConfig {
        didSet {
            routing.save()
            refreshResolvedPipeline()
        }
    }
    @Published public var presentationMode: VoicePresentationMode {
        didSet {
            UserDefaults.standard.set(presentationMode.rawValue, forKey: "wisdai.voice.presentationMode")
        }
    }
    @Published public var orbPalette: WisdVoiceOrbPalette {
        didSet {
            UserDefaults.standard.set(orbPalette.rawValue, forKey: "wisdai.voice.orbPalette")
        }
    }

    @Published public private(set) var resolvedPipeline: ResolvedVoicePipeline
    @Published public private(set) var liveUserTranscript: String = ""
    @Published public private(set) var liveAssistantTranscript: String = ""
    @Published public private(set) var liveAssistantMarkdownText: String = ""
    @Published public private(set) var lastTurnEvaluation: TurnTakingEvaluation?
    @Published public private(set) var isMuted: Bool = false
    @Published public private(set) var isOutputMuted: Bool = false
    @Published public private(set) var isVoiceSessionActive: Bool = false
    @Published public var showVoiceHUDWindow: Bool = false
    @Published public var showConsentDialog: Bool = false
    @Published public private(set) var activeBannerNotice: String?
    @Published public var selectedVoiceIdentifier: String = UserDefaults.standard.string(forKey: "wisdai.voice.preferredVoiceID") ?? "auto" {
        didSet {
            UserDefaults.standard.set(selectedVoiceIdentifier, forKey: "wisdai.voice.preferredVoiceID")
        }
    }
    @Published public var voiceIdentity: VoiceIdentityDescriptor {
        didSet {
            if let data = try? JSONEncoder().encode(voiceIdentity) {
                UserDefaults.standard.set(data, forKey: "wisdai.voice.identity.v1")
            }
            VoiceTTSWarmupCoordinator.warmupInBackground(
                provider: appleTTS,
                language: behavior.languageVariant,
                voicePreference: effectiveTTSVoicePreference()
            )
        }
    }
    @Published public private(set) var brainStatus: LocalBrainBackendStatus = .compactHeuristicFallback
    @Published public private(set) var hasLocalTTSWarmedUp: Bool = false
    @Published public private(set) var activeTasksSnapshot: [VoiceTaskSummarySnapshot] = []
    @Published public private(set) var componentStatuses: [VoiceComponentKind: VoiceComponentStatusSnapshot] = {
        var dict: [VoiceComponentKind: VoiceComponentStatusSnapshot] = [:]
        for kind in VoiceComponentKind.allCases {
            dict[kind] = VoiceComponentStatusSnapshot(kind: kind)
        }
        return dict
    }()
    @Published public private(set) var lastStartupDurationMs: Double = 0
    @Published public private(set) var lastErrorSummary: String? = nil
    @Published public private(set) var installedPTVoicesCount: Int = 0
    @Published public private(set) var installedSpeechLocales: [String] = []
    @Published public var customPronunciation: TechnicalPronunciationDictionary

    public let audioEngine: VoiceNativeAudioEngine
    public let stateMachine: ConversationStateMachine
    public let vadTracker: AcousticVADTracker
    public let memoryStore: VoiceMemoryStore
    public let telemetry: VoiceTelemetryRecorder
    public let bargeInCoordinator: BargeInCoordinator
    public let speechSegmenter: IncrementalSpeechSegmenter

    // Autonomous WisdAI Intelligence, On-Device Understanding & Local Asset Components
    public let localBrain: LocalConversationalBrain
    public let localSTT: UnifiedLocalSTTCoordinator
    public let echoSuppressor: AcousticEchoSuppressor
    public let knowledgeStore: VoiceSQLiteKnowledgeStore
    public let modelAssetManager: VoiceModelAssetManager
    public var memoryPressureWatcher: VoiceMemoryPressureWatcher?

    public let appleSTT: AppleSpeechStreamingSTTProvider
    public let deepgramSTT: DeepgramStreamingSTTProvider
    public let appleTTS: AppleNaturalPCMStreamingTTSProvider
    public let openAITTS: OpenAIStreamingTTSProvider
    public let elevenLabsTTS: ElevenLabsStreamingTTSProvider
    public let openAIRealtime: OpenAIRealtimeWebSocketTransport
    public let geminiLive: GeminiLiveWebSocketTransport

    private var activeS2STransport: RealtimeSpeechToSpeechTransport?
    private var activeSTTProvider: StreamingSpeechToTextProvider?
    private var ttsQueueTask: Task<Void, Never>?
    private var localBrainGenerationTask: Task<Void, Never>?
    private var startupWatchdogTask: Task<Void, Never>?
    private var queuedSpeechChunks: [(text: String, originalIndex: Int)] = []
    private var isTTSWorkerRunning = false
    private var turnEvalTimer: DispatchSourceTimer?
    private var resourceTimer: DispatchSourceTimer?
    private var sessionGenerationID: UInt64 = 0
    private var activeTurnGenerationID: UInt64 = 0
    private var activePlaybackEpoch: UInt64 = 0
    private var lastAcousticSpeechTimestampNs: UInt64 = 0
    private var lastMicNonSilenceTimestampNs: UInt64 = 0
    private var lastSTTResultTimestampNs: UInt64 = 0
    private var lastFrameClearedEchoGate: Bool = false
    private var userSpeechStartedAtNs: UInt64 = 0
    private var turnSubmittedAtNs: UInt64 = 0
    private var lastCommittedNormalizedUtterance: String = ""
    private var lastCommittedUtteranceAtNs: UInt64 = 0
    private var firstLLMDeltaRecorded = false
    private var firstAudioChunkRecorded = false
    private var activeS2SAssistantItemID: String = ""
    private var geminiResumptionHandle: String?
    private var onCommitUserUtterance: ((String) -> Void)?
    private var onTranscriptDeltaUI: ((String, String) -> Void)?
    private var activeTasksProvider: (() -> [VoiceTaskSummarySnapshot])?
    private var onDelegateTaskToAgent: ((VoiceSpecialistAgentHint, String, VoiceActionRiskTier) -> VoiceDelegationDispatchResult)?
    private var onRecordLocalExchangeToChat: ((String, String) -> Void)?
    private var hasCodexAppServerConnected: Bool = false

    private var cancellables: Set<AnyCancellable> = []

    public init() {
        let initialPolicy = VoicePolicyPreferences.load()
        let initialBehavior = VoiceBehaviorProfile.load()
        let initialRouting = VoiceRoleRoutingConfig.load()
        let profile = HardwareMemoryProfile.detect()
        let initialIdentity: VoiceIdentityDescriptor = {
            if let data = UserDefaults.standard.data(forKey: "wisdai.voice.identity.v1"),
               let decoded = try? JSONDecoder().decode(VoiceIdentityDescriptor.self, from: data) {
                return decoded
            }
            return .wisdAIDefault
        }()

        self.policy = initialPolicy
        self.behavior = initialBehavior
        self.routing = initialRouting
        self.voiceIdentity = initialIdentity
        self.presentationMode = VoicePresentationMode(rawValue: UserDefaults.standard.string(forKey: "wisdai.voice.presentationMode") ?? "") ?? .floatingOverlay
        self.orbPalette = WisdVoiceOrbPalette(rawValue: UserDefaults.standard.string(forKey: "wisdai.voice.orbPalette") ?? "") ?? .wisdAIBrand
        self.customPronunciation = TechnicalPronunciationDictionary.defaults(for: initialBehavior.languageVariant)

        self.audioEngine = VoiceNativeAudioEngine(memoryProfile: profile)
        self.stateMachine = ConversationStateMachine()
        self.vadTracker = AcousticVADTracker()
        self.memoryStore = VoiceMemoryStore(hardwareProfile: profile)
        self.telemetry = VoiceTelemetryRecorder()
        self.bargeInCoordinator = BargeInCoordinator(stateMachine: self.stateMachine)
        self.speechSegmenter = IncrementalSpeechSegmenter()

        self.localBrain = LocalConversationalBrain()
        self.localSTT = UnifiedLocalSTTCoordinator()
        self.echoSuppressor = AcousticEchoSuppressor()
        self.knowledgeStore = VoiceSQLiteKnowledgeStore()
        self.modelAssetManager = VoiceModelAssetManager()

        self.appleSTT = AppleSpeechStreamingSTTProvider()
        self.deepgramSTT = DeepgramStreamingSTTProvider()
        self.appleTTS = AppleNaturalPCMStreamingTTSProvider()
        self.openAITTS = OpenAIStreamingTTSProvider()
        self.elevenLabsTTS = ElevenLabsStreamingTTSProvider()
        self.openAIRealtime = OpenAIRealtimeWebSocketTransport()
        self.geminiLive = GeminiLiveWebSocketTransport()

        self.resolvedPipeline = Self.computePipeline(
            requested: initialRouting.requestedTransportProvider,
            policy: initialPolicy,
            hasCodexAppServer: false
        )
        self.telemetry.setActiveProviderLabel("\(self.resolvedPipeline.activeSTTName) → \(self.resolvedPipeline.activeTTSName)")

        self.memoryPressureWatcher = VoiceMemoryPressureWatcher { [weak self] level in
            guard let self, level != .normal else { return }
            self.memoryStore.compactIfNeeded()
            self.telemetry.log(category: "MemoryPressure", message: "Pressão de memória (\(level.rawValue)): compactação automática aplicada.")
        }

        wireAudioEngineCallbacks()
        refreshDependencyInventory()
    }

    public func refreshDependencyInventory() {
        let ptVoices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.lowercased().hasPrefix("pt")
        }
        installedPTVoicesCount = ptVoices.count
        if #available(macOS 26.0, *) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let locales = await SpeechTranscriber.installedLocales
                self.installedSpeechLocales = locales.map(\.identifier).sorted()
            }
        }
        updateComponentStatus(
            .agentOrchestrator,
            state: hasCodexAppServerConnected ? .ready : .idle,
            engineOrModel: hasCodexAppServerConnected ? "Orquestrador Conectado" : "Independente (Agentes Off-line)",
            lastError: nil,
            dependencyHint: hasCodexAppServerConnected ? nil : "Motor de voz funciona normalmente mesmo sem agentes externos."
        )
    }

    private func updateComponentStatus(
        _ kind: VoiceComponentKind,
        state: VoiceComponentHealthState,
        engineOrModel: String,
        latencyMs: Double? = nil,
        lastError: String? = nil,
        dependencyHint: String? = nil
    ) {
        componentStatuses[kind] = VoiceComponentStatusSnapshot(
            kind: kind,
            state: state,
            activeEngineOrModel: engineOrModel,
            latencyMs: latencyMs,
            lastError: lastError,
            dependencyHint: dependencyHint,
            updatedAt: Date()
        )
        if state == .error || state == .unavailable, let lastError, !lastError.isEmpty {
            lastErrorSummary = "[\(kind.displayName)] \(lastError)"
        }
    }

    public func refreshResolvedPipeline(hasCodexAppServer: Bool? = nil) {
        if let hasCodexAppServer {
            self.hasCodexAppServerConnected = hasCodexAppServer
        }
        let next = Self.computePipeline(
            requested: routing.requestedTransportProvider,
            policy: policy,
            hasCodexAppServer: self.hasCodexAppServerConnected
        )
        resolvedPipeline = next
        activeBannerNotice = next.advisoryBanner
        telemetry.setActiveProviderLabel("\(next.activeSTTName) → \(next.activeTTSName)")
        updateComponentStatus(
            .agentOrchestrator,
            state: self.hasCodexAppServerConnected ? .ready : .idle,
            engineOrModel: self.hasCodexAppServerConnected ? "Agentes Ativos" : "Independente (Zero Dependência Externa)",
            dependencyHint: self.hasCodexAppServerConnected ? nil : "Sem agentes externos ativos; conversação local pronta."
        )
    }

    private static func computePipeline(
        requested: VoiceGatewayProviderKind,
        policy: VoicePolicyPreferences,
        hasCodexAppServer: Bool
    ) -> ResolvedVoicePipeline {
        if !policy.allowPaidVoiceAPIs && (requested == .autoBestCompliant || requested == .appleLocalHybrid) {
            return VoicePipelineResolver.resolve(
                requested: requested,
                policy: policy,
                hasOpenAIKey: false,
                hasGeminiKey: false,
                hasDeepgramKey: false,
                hasElevenLabsKey: false,
                hasCodexAppServer: false
            )
        }
        let hasOpenAI = !(AccountKeychain.readProviderKey(provider: .openai)?.isEmpty ?? true)
        let hasGemini = !(AccountKeychain.readProviderKey(provider: .gemini)?.isEmpty ?? true)
        let hasDeepgram = !(VoiceKeychainStore.readKey(for: .deepgram)?.isEmpty ?? true)
        let hasEleven = !(VoiceKeychainStore.readKey(for: .elevenLabs)?.isEmpty ?? true)
        return VoicePipelineResolver.resolve(
            requested: requested,
            policy: policy,
            hasOpenAIKey: hasOpenAI,
            hasGeminiKey: hasGemini,
            hasDeepgramKey: hasDeepgram,
            hasElevenLabsKey: hasEleven,
            hasCodexAppServer: hasCodexAppServer
        )
    }

    // MARK: - Session Lifecycle

    public func effectiveTTSVoicePreference() -> String {
        if selectedVoiceIdentifier != "auto", !selectedVoiceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return selectedVoiceIdentifier
        }
        return "persona:\(voiceIdentity.persona.rawValue)"
    }

    public func effectiveSpeechRate() -> Float {
        min(1.35, max(0.75, behavior.speechRate * voiceIdentity.persona.baseCadenceRate))
    }

    public func updateActiveTasksSnapshot(_ tasks: [VoiceTaskSummarySnapshot]) {
        activeTasksSnapshot = tasks
    }

    public func notifySpecialistTaskFinished(agentName: String, title: String, succeeded: Bool, summary: String) {
        let prefix = succeeded ? "Pronto, o agente \(agentName) concluiu \(title)." : "O agente \(agentName) encontrou um erro ao executar \(title)."
        let body = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullNotice = body.isEmpty ? prefix : "\(prefix) \(body)"

        memoryStore.appendAssistantTurn(fullNotice, providerID: "wisdai_agent_observer", wasInterruptedByBargeIn: false)
        if policy.allowPersistentVoiceMemory {
            knowledgeStore.storeFact(
                fullNotice,
                source: "specialist:\(agentName.lowercased())",
                projectScope: memoryStore.workspaceContext.projectName ?? "global",
                explicitTrusted: false
            )
        }

        guard isVoiceSessionActive, !isOutputMuted else { return }
        let expectedSession = sessionGenerationID
        if state == .userSpeaking || state == .processing {
            Task { @MainActor [weak self] in
                for _ in 0..<25 {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    guard let self,
                          self.sessionGenerationID == expectedSession,
                          self.isVoiceSessionActive,
                          !self.isOutputMuted else { return }
                    if self.state == .listening {
                        self.speakSystemNoticeNaturally(fullNotice, priorityInterrupt: false)
                        return
                    }
                }
            }
            return
        }
        speakSystemNoticeNaturally(fullNotice, priorityInterrupt: false)
    }

    public func startSessionWithContinuity(
        workspaceContext: VoiceWorkspaceContextSnapshot,
        continuityItems: [CodexContinuityItem],
        greetingText: String?,
        hasCodexAppServer: Bool,
        activeTasksProvider: (() -> [VoiceTaskSummarySnapshot])? = nil,
        onDelegateTaskToAgent: ((VoiceSpecialistAgentHint, String, VoiceActionRiskTier) -> VoiceDelegationDispatchResult)? = nil,
        onRecordLocalExchangeToChat: ((String, String) -> Void)? = nil,
        onCommitUserUtterance: @escaping (String) -> Void,
        onTranscriptDeltaUI: ((String, String) -> Void)? = nil
    ) async {
        stopSession(clearUI: false)
        sessionGenerationID &+= 1
        activeTurnGenerationID &+= 1
        activePlaybackEpoch &+= 1
        let currentSessionID = sessionGenerationID
        lastAcousticSpeechTimestampNs = 0
        lastMicNonSilenceTimestampNs = 0
        lastSTTResultTimestampNs = 0
        lastFrameClearedEchoGate = false
        userSpeechStartedAtNs = 0
        lastCommittedNormalizedUtterance = ""
        lastCommittedUtteranceAtNs = 0

        self.onCommitUserUtterance = onCommitUserUtterance
        self.onTranscriptDeltaUI = onTranscriptDeltaUI
        self.activeTasksProvider = activeTasksProvider
        self.onDelegateTaskToAgent = onDelegateTaskToAgent
        self.onRecordLocalExchangeToChat = onRecordLocalExchangeToChat
        if let tasks = activeTasksProvider?() {
            self.activeTasksSnapshot = tasks
        }

        let startNs = DispatchTime.now().uptimeNanoseconds
        self.lastErrorSummary = nil
        self.activeBannerNotice = nil
        self.memoryStore.updateWorkspaceContext(workspaceContext)
        self.memoryStore.seedFromHistoryItems(continuityItems, providerID: routing.requestedTransportProvider.rawValue)
        refreshResolvedPipeline(hasCodexAppServer: hasCodexAppServer)

        transitionState(.initializingLocalEngine, reason: "Iniciando Motor Autônomo WisdAI")
        isVoiceSessionActive = true
        isMuted = false
        liveUserTranscript = ""
        liveAssistantTranscript = ""
        liveAssistantMarkdownText = ""
        echoSuppressor.reset()

        updateComponentStatus(.interface, state: .ready, engineOrModel: "Modal / HUD Ativo", latencyMs: 0.5)
        updateComponentStatus(.permissions, state: .initializing, engineOrModel: "Verificando microfone macOS")
        updateComponentStatus(.audioCapture, state: .initializing, engineOrModel: "CoreAudio")
        updateComponentStatus(.audioPlayback, state: .initializing, engineOrModel: "AdaptiveJitterBuffer 24kHz")
        updateComponentStatus(.vad, state: .initializing, engineOrModel: "HybridVAD")
        updateComponentStatus(.stt, state: .initializing, engineOrModel: resolvedPipeline.activeSTTName)
        updateComponentStatus(.llm, state: .initializing, engineOrModel: localBrain.backendStatus.rawValue)
        updateComponentStatus(.tts, state: .initializing, engineOrModel: resolvedPipeline.activeTTSName)

        // Anti-hang startup watchdog: allows cold CoreAudio VPIO fallback stabilization (~2.4s max)
        // while guaranteeing never hanging indefinitely in .connecting/.initializingLocalEngine (> 3.5s).
        startupWatchdogTask?.cancel()
        startupWatchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard let self,
                  !Task.isCancelled,
                  self.sessionGenerationID == currentSessionID,
                  self.isVoiceSessionActive else { return }
            if self.state == .connecting || self.state == .initializingLocalEngine || self.state == .loadingModel {
                self.telemetry.log(category: "Startup", message: "Watchdog de 3.5s acionado; ativando estado observável não bloqueante.")
                if self.audioEngine.isRunning {
                    self.transitionState(.listening, reason: "Watchdog anti-travamento (3.5s)")
                    self.startTurnEvaluationLoop()
                } else {
                    let msg = "Tempo limite ao iniciar motor de áudio local (3,5s). Verifique dispositivos e permissões de microfone."
                    self.activeBannerNotice = msg
                    self.updateComponentStatus(.audioCapture, state: .error, engineOrModel: "CoreAudio", lastError: msg)
                    self.transitionState(.error, reason: "Timeout de inicialização (3.5s)")
                }
            }
        }

        // Silent parallel warmups (ANE FoundationModels + speechsynthesisd in-memory warm)
        let llmT0 = DispatchTime.now().uptimeNanoseconds
        let instructions = buildLocalBrainInstructions(for: behavior.languageVariant)
        localBrain.prewarm(instructions: instructions)
        brainStatus = localBrain.backendStatus
        let llmMs = Double(DispatchTime.now().uptimeNanoseconds &- llmT0) / 1_000_000.0
        updateComponentStatus(
            .llm,
            state: localBrain.backendStatus == .appleFoundationModelsReady ? .ready : .degraded,
            engineOrModel: localBrain.backendStatus.rawValue,
            latencyMs: llmMs,
            dependencyHint: localBrain.backendStatus == .appleFoundationModelsReady ? nil : "Apple FoundationModels indisponível; respostas gerais locais não estão disponíveis."
        )

        let ptVoices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.lowercased().hasPrefix("pt") }
        installedPTVoicesCount = ptVoices.count
        if let activeVoice = AppleNaturalPCMStreamingTTSProvider.selectBestNaturalVoice(for: behavior.languageVariant, preferredIdentifier: effectiveTTSVoicePreference()) {
            updateComponentStatus(.tts, state: .ready, engineOrModel: "\(activeVoice.name) (Apple Natural PCM)")
        } else {
            updateComponentStatus(
                .tts,
                state: .unavailable,
                engineOrModel: "Voz TTS não instalada",
                lastError: "Nenhuma voz local instalada para \(behavior.languageVariant.displayName).",
                dependencyHint: "Instale uma voz em Ajustes do Sistema → Acessibilidade → Conteúdo Falado → Vozes do Sistema."
            )
        }
        if !hasLocalTTSWarmedUp {
            VoiceTTSWarmupCoordinator.warmupInBackground(
                provider: appleTTS,
                language: behavior.languageVariant,
                voicePreference: effectiveTTSVoicePreference()
            )
            hasLocalTTSWarmedUp = true
        }

        let permT0 = DispatchTime.now().uptimeNanoseconds
        let micGranted = await BoundedVoicePermissions.requestMicrophoneAuthorized(timeoutSeconds: 2.0)
        let permMs = Double(DispatchTime.now().uptimeNanoseconds &- permT0) / 1_000_000.0
        guard isVoiceSessionActive, sessionGenerationID == currentSessionID else { return }
        guard micGranted else {
            startupWatchdogTask?.cancel()
            let err = "Acesso ao microfone negado ou expirado. Habilite em Ajustes do Sistema → Privacidade e Segurança → Microfone."
            activeBannerNotice = err
            updateComponentStatus(.permissions, state: .error, engineOrModel: "AVCaptureDevice .audio", latencyMs: permMs, lastError: err, dependencyHint: "Autorize o WisdAI em Privacidade e Segurança → Microfone.")
            updateComponentStatus(.audioCapture, state: .unavailable, engineOrModel: "Bloqueado sem permissão")
            transitionState(.error, reason: "Permissão de microfone negada")
            telemetry.log(category: "Permissions", message: "Microfone não autorizado após 2.0s.")
            lastStartupDurationMs = Double(DispatchTime.now().uptimeNanoseconds &- startNs) / 1_000_000.0
            return
        }
        updateComponentStatus(.permissions, state: .ready, engineOrModel: "Microfone Autorizado", latencyMs: permMs)

        let audioT0 = DispatchTime.now().uptimeNanoseconds
        do {
            try await audioEngine.startFullDuplexAsync(enableCapture: true, enablePlayback: true, enableVoiceProcessing: true)
            guard isVoiceSessionActive, sessionGenerationID == currentSessionID else {
                audioEngine.stop()
                return
            }
            let audioMs = Double(DispatchTime.now().uptimeNanoseconds &- audioT0) / 1_000_000.0
            let telSnap = audioEngine.telemetrySnapshot()
            let capState: VoiceComponentHealthState = (audioEngine.lastFault == nil) ? .ready : .degraded
            updateComponentStatus(
                .audioCapture,
                state: capState,
                engineOrModel: "\(telSnap.inputDeviceName) (\(telSnap.processingStatus.rawValue))",
                latencyMs: audioMs,
                lastError: audioEngine.lastFault,
                dependencyHint: audioEngine.lastFault != nil ? "Hardware AEC VPIO recusou inicialização; supressão de eco por software está ativa." : nil
            )
            updateComponentStatus(.audioPlayback, state: .ready, engineOrModel: telSnap.outputDeviceName, latencyMs: audioMs)
            updateComponentStatus(.vad, state: .ready, engineOrModel: "AcousticVADTracker + HybridTurnTakingAnalyzer")
        } catch {
            startupWatchdogTask?.cancel()
            let err = "Não foi possível iniciar o motor de áudio nativo: \(error.localizedDescription)"
            activeBannerNotice = err
            updateComponentStatus(.audioCapture, state: .error, engineOrModel: "AVAudioEngine", lastError: err)
            updateComponentStatus(.audioPlayback, state: .error, engineOrModel: "AVAudioEngine", lastError: err)
            transitionState(.error, reason: "Falha no motor de áudio")
            telemetry.log(category: "AudioEngine", message: "Erro ao iniciar full-duplex: \(error.localizedDescription)")
            lastStartupDurationMs = Double(DispatchTime.now().uptimeNanoseconds &- startNs) / 1_000_000.0
            return
        }

        let targetPipeline = resolvedPipeline
        guard isVoiceSessionActive, sessionGenerationID == currentSessionID else { return }
        if targetPipeline.effectiveProvider == .openAIRealtimeAPI || targetPipeline.effectiveProvider == .geminiLiveAPI {
            await startNativeS2SSession(pipeline: targetPipeline, greetingText: greetingText, sessionID: currentSessionID)
        } else {
            await startStreamingPipelineSession(pipeline: targetPipeline, greetingText: greetingText, sessionID: currentSessionID)
        }

        guard isVoiceSessionActive, sessionGenerationID == currentSessionID else { return }
        startupWatchdogTask?.cancel()
        lastStartupDurationMs = Double(DispatchTime.now().uptimeNanoseconds &- startNs) / 1_000_000.0
        startResourcePolling()
    }

    public func stopSession(clearUI: Bool = true) {
        sessionGenerationID &+= 1
        activeTurnGenerationID &+= 1
        activePlaybackEpoch &+= 1
        startupWatchdogTask?.cancel()
        startupWatchdogTask = nil
        localBrainGenerationTask?.cancel()
        localBrainGenerationTask = nil
        turnEvalTimer?.cancel()
        turnEvalTimer = nil
        resourceTimer?.cancel()
        resourceTimer = nil

        cancelAllOutgoingSpeechAndGeneration()
        activeSTTProvider?.stop()
        activeSTTProvider = nil

        if let s2s = activeS2STransport {
            activeS2STransport = nil
            Task { await s2s.disconnect() }
        }

        audioEngine.stop()
        echoSuppressor.reset()
        vadTracker.reset()
        speechSegmenter.reset()
        isVoiceSessionActive = false
        userSpeechStartedAtNs = 0
        lastAcousticSpeechTimestampNs = 0
        lastMicNonSilenceTimestampNs = 0
        lastSTTResultTimestampNs = 0
        stateMachine.resetToIdle(reason: "Sessão encerrada pelo usuário")
        state = stateMachine.state

        if clearUI {
            liveUserTranscript = ""
            liveAssistantTranscript = ""
            showVoiceHUDWindow = false
        }
    }

    public func toggleMute() {
        isMuted.toggle()
        if isMuted {
            transitionState(.muted, reason: "Microfone silenciado pelo usuário")
            audioEngine.captureRingBuffer.flush()
        } else if isVoiceSessionActive {
            transitionState(.listening, reason: "Microfone reativado")
        }
    }

    public func toggleOutputMute() {
        isOutputMuted.toggle()
        if isOutputMuted {
            _ = audioEngine.bargeInFlushPlayback()
        }
    }

    public func grantExternalAudioConsent() {
        policy.externalAudioConsentGranted = true
        policy.preferOnDeviceSpeechOnly = false
        showConsentDialog = false
        telemetry.log(category: "Privacy", message: "Consentimento explícito de áudio externo concedido pelo usuário.")
    }

    public func revokeExternalAudioConsent() {
        policy.externalAudioConsentGranted = false
        policy.allowPaidVoiceAPIs = false
        policy.preferOnDeviceSpeechOnly = true
        telemetry.log(category: "Privacy", message: "Consentimento revogado; revertendo para modo local seguro.")
    }

    public func openHUDWindow(expanded: Bool) {
        presentationMode = expanded ? .expandedWindow : .compactWindow
        showVoiceHUDWindow = true
    }

    // MARK: - Streaming LLM -> Incremental TTS Execution (Mode B)

    public func beginAssistantTurnResponseTracking() {
        turnSubmittedAtNs = DispatchTime.now().uptimeNanoseconds
        firstLLMDeltaRecorded = false
        firstAudioChunkRecorded = false
        speechSegmenter.reset()
        audioEngine.outputJitterBuffer.resetForNewResponse()
        liveAssistantTranscript = ""
        liveAssistantMarkdownText = ""
    }

    public func handleStreamingAssistantDelta(_ delta: String) {
        guard isVoiceSessionActive, !delta.isEmpty else { return }
        if !firstLLMDeltaRecorded && turnSubmittedAtNs > 0 {
            firstLLMDeltaRecorded = true
            let ms = Double(DispatchTime.now().uptimeNanoseconds &- turnSubmittedAtNs) / 1_000_000.0
            telemetry.recordLLMFirstChunkLatency(ms: ms)
        }
        liveAssistantMarkdownText += delta

        let clauses = speechSegmenter.appendDelta(delta)
        for clause in clauses {
            enqueueAdaptedSpeechClause(clause)
        }
    }

    public func finishAssistantResponse(fullMarkdownText: String) {
        guard isVoiceSessionActive else { return }
        let remainder = speechSegmenter.flushFinal()
        if !remainder.isEmpty {
            for clause in remainder {
                enqueueAdaptedSpeechClause(clause)
            }
        } else if liveAssistantMarkdownText.isEmpty && !fullMarkdownText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let adapted = VoiceResponseAdapter.adaptForSpeech(
                fullMarkdownText,
                profile: behavior,
                customDictionary: customPronunciation
            )
            if !adapted.spokenText.isEmpty {
                enqueueSpokenTextDirectly(adapted.spokenText)
            }
        }
    }

    public func speakSystemNoticeNaturally(_ notice: String, priorityInterrupt: Bool = false) {
        guard isVoiceSessionActive, !isOutputMuted else { return }
        if priorityInterrupt {
            _ = audioEngine.bargeInFlushPlayback()
            queuedSpeechChunks.removeAll()
        }
        guard state != .userSpeaking else { return }
        enqueueAdaptedSpeechClause(notice)
    }

    // MARK: - Barge-In Trigger

    public func performManualOrVADBarageIn(reason: String = "Barge-in") {
        guard state == .assistantSpeaking || state == .processing || state == .consultingAgent else { return }
        let outcome = bargeInCoordinator.executeBargeIn(audioEngine: audioEngine) { [weak self] in
            self?.cancelAllOutgoingSpeechAndGeneration()
        }
        telemetry.recordBargeInStopLatency(ms: outcome.stopLatencyMs)
        if !outcome.heardAssistantText.isEmpty {
            memoryStore.appendAssistantTurn(
                outcome.heardAssistantText,
                providerID: resolvedPipeline.effectiveProvider.rawValue,
                wasInterruptedByBargeIn: true
            )
        }
        if let s2s = activeS2STransport, !activeS2SAssistantItemID.isEmpty {
            let itemId = activeS2SAssistantItemID
            let playedMs = Int(outcome.playedMilliseconds.rounded())
            Task {
                await s2s.cancelActiveResponse()
                await s2s.truncateAssistantItem(itemId: itemId, audioEndMs: playedMs)
            }
        }
        if let unified = activeSTTProvider as? UnifiedLocalSTTCoordinator {
            unified.resetUtteranceBuffer()
        } else if let apple = activeSTTProvider as? AppleSpeechStreamingSTTProvider {
            apple.resetUtteranceBuffer()
        }
        echoSuppressor.reset()
        transitionState(.userSpeaking, reason: reason)
    }

    // MARK: - Private Audio & Session Pipelines

    private func startNativeS2SSession(pipeline: ResolvedVoicePipeline, greetingText: String?, sessionID: UInt64) async {
        guard isVoiceSessionActive, sessionGenerationID == sessionID else { return }
        let transport: RealtimeSpeechToSpeechTransport = (pipeline.effectiveProvider == .geminiLiveAPI)
            ? geminiLive
            : openAIRealtime
        activeS2STransport = transport

        let portable = memoryStore.exportPortableSnapshot(targetProviderID: transport.providerID)
        var fullInstructions = behavior.systemPromptInstructions(projectName: memoryStore.workspaceContext.projectName)
        let portableText = portable.renderPortableSystemContext()
        if !portableText.isEmpty {
            fullInstructions += "\n\n<portable_context>\n\(portableText)\n</portable_context>"
        }

        let cfg = VoiceSessionConfig(
            language: behavior.languageVariant,
            systemInstructions: fullInstructions,
            voiceName: selectedVoiceIdentifier,
            semanticVADPreferred: true,
            initialContextItems: portable.recentTurns,
            speechRate: behavior.speechRate
        )

        do {
            try await transport.connect(config: cfg, resumptionHandle: geminiResumptionHandle) { [weak self] event in
                Task { @MainActor [weak self] in
                    guard let self, self.sessionGenerationID == sessionID, self.isVoiceSessionActive else { return }
                    self.handleS2SEvent(event, providerID: transport.providerID)
                }
            }
            guard isVoiceSessionActive, sessionGenerationID == sessionID else {
                await transport.disconnect()
                return
            }
            transitionState(.listening, reason: "Sessão S2S conectada (\(transport.providerID))")
            if let greetingText, !greetingText.isEmpty {
                await transport.injectContextUpdate(
                    "[Ativação da conversa de voz] Diga exatamente esta saudação inicial natural ao usuário: \(greetingText)",
                    triggerReply: true
                )
            }
        } catch {
            guard isVoiceSessionActive, sessionGenerationID == sessionID else { return }
            telemetry.log(category: "S2S", message: "Falha ao conectar \(transport.providerID): \(error.localizedDescription); alternando para pipeline streaming local.")
            activeBannerNotice = error.localizedDescription
            await startStreamingPipelineSession(
                pipeline: ResolvedVoicePipeline(
                    effectiveProvider: .appleLocalHybrid,
                    activeSTTName: "Apple Speech",
                    activeTTSName: "Apple Natural PCM",
                    isUsingPaidCloud: false,
                    advisoryBanner: error.localizedDescription
                ),
                greetingText: greetingText,
                sessionID: sessionID
            )
        }
    }

    private func handleS2SEvent(_ event: RealtimeGatewayEvent, providerID: String) {
        switch event {
        case .sessionReady:
            transitionState(.listening, reason: "S2S pronto")
        case .resumptionHandleUpdated(let handle):
            geminiResumptionHandle = handle
        case .userSpeechStarted:
            if state == .assistantSpeaking {
                performManualOrVADBarageIn(reason: "Barge-in detectado no S2S")
            } else {
                transitionState(.userSpeaking, reason: "Usuário começou a falar")
            }
        case .userSpeechStopped:
            turnSubmittedAtNs = DispatchTime.now().uptimeNanoseconds
            firstAudioChunkRecorded = false
            transitionState(.processing, reason: "Fim de turno no S2S")
        case .inputTranscriptDelta(_, let delta):
            liveUserTranscript += delta
            onTranscriptDeltaUI?("user", liveUserTranscript)
        case .inputTranscriptCompleted(_, let text):
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty {
                liveUserTranscript = clean
                memoryStore.appendUserTurn(clean, providerID: providerID)
                onCommitUserUtterance?(clean)
            }
        case .assistantItemStarted(let itemId):
            activeS2SAssistantItemID = itemId
            liveAssistantTranscript = ""
            audioEngine.outputJitterBuffer.resetForNewResponse()
        case .assistantAudioDelta(let itemId, let pcm16, let sampleRate):
            activeS2SAssistantItemID = itemId
            if !isOutputMuted {
                if !firstAudioChunkRecorded && turnSubmittedAtNs > 0 {
                    firstAudioChunkRecorded = true
                    let e2eMs = Double(DispatchTime.now().uptimeNanoseconds &- turnSubmittedAtNs) / 1_000_000.0
                    telemetry.recordEndToEndResponseLatency(ms: e2eMs)
                }
                let rawFloats = AudioPCMConverter.pcm16DataToFloats(pcm16)
                let target24k = abs(sampleRate - 24_000) < 1.0
                    ? rawFloats
                    : AudioPCMConverter.resampleLinear(samples: rawFloats, fromSampleRate: sampleRate, toSampleRate: 24_000)
                _ = audioEngine.outputJitterBuffer.pushFloatSamples(target24k, transcriptText: nil)
                transitionState(.assistantSpeaking, reason: "Reproduzindo áudio S2S")
            }
        case .assistantTranscriptDelta(_, let text):
            liveAssistantTranscript += text
            onTranscriptDeltaUI?("assistant", liveAssistantTranscript)
        case .assistantTurnCompleted(_, let finalText):
            let clean = finalText.isEmpty ? liveAssistantTranscript : finalText
            if !clean.isEmpty {
                memoryStore.appendAssistantTurn(clean, providerID: providerID, wasInterruptedByBargeIn: false)
            }
            if isVoiceSessionActive && state != .userSpeaking && state != .muted {
                transitionState(.listening, reason: "Turno S2S concluído")
            }
        case .assistantInterrupted:
            performManualOrVADBarageIn(reason: "Interrupção reportada pelo servidor")
        case .error(let msg):
            activeBannerNotice = msg
            telemetry.log(category: "S2S", message: msg)
        case .disconnected(let reason):
            telemetry.recordReconnect(reason: "S2S desconectado: \(reason)")
            if isVoiceSessionActive {
                transitionState(.reconnecting, reason: reason)
            }
        }
    }

    private func startStreamingPipelineSession(pipeline: ResolvedVoicePipeline, greetingText: String?, sessionID: UInt64) async {
        guard isVoiceSessionActive, sessionGenerationID == sessionID else { return }
        activeS2STransport = nil
        let sttProvider: StreamingSpeechToTextProvider = (pipeline.effectiveProvider == .hybridDeepgramElevenLabs)
            ? deepgramSTT
            : localSTT
        activeSTTProvider = sttProvider
        let sttT0 = DispatchTime.now().uptimeNanoseconds
        let turnSnapshotAtStart = activeTurnGenerationID

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { [weak self, language = behavior.languageVariant, policy = self.policy, sttProvider] in
                    try await sttProvider.start(
                        language: language,
                        policy: policy,
                        onPartial: { [weak self] text in
                            Task { @MainActor [weak self] in
                                guard let self, self.sessionGenerationID == sessionID else { return }
                                self.handlePartialTranscript(text, isFinalEvent: false, sessionID: sessionID, expectedTurnGeneration: turnSnapshotAtStart)
                            }
                        },
                        onFinal: { [weak self] text in
                            Task { @MainActor [weak self] in
                                guard let self, self.sessionGenerationID == sessionID else { return }
                                self.handlePartialTranscript(text, isFinalEvent: true, sessionID: sessionID, expectedTurnGeneration: turnSnapshotAtStart)
                            }
                        },
                        onError: { [weak self] err in
                            Task { @MainActor [weak self] in
                                guard let self, self.sessionGenerationID == sessionID else { return }
                                self.telemetry.log(category: "STT", message: err)
                                self.updateComponentStatus(.stt, state: .error, engineOrModel: sttProvider.providerID, lastError: err)
                            }
                        }
                    )
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 2_500_000_000)
                    throw VoiceGatewayError.networkConnectionFailed("Tempo limite (2,5s) ao inicializar reconhecimento de fala local.")
                }
                try await group.next()
                group.cancelAll()
            }

            guard isVoiceSessionActive, sessionGenerationID == sessionID else {
                sttProvider.stop()
                return
            }

            let sttMs = Double(DispatchTime.now().uptimeNanoseconds &- sttT0) / 1_000_000.0
            let backendName: String = {
                if #available(macOS 26.0, *), (sttProvider as? UnifiedLocalSTTCoordinator) != nil {
                    return "Apple SpeechTranscriber On-Device (\(behavior.languageVariant.shortCode))"
                }
                return pipeline.activeSTTName
            }()
            updateComponentStatus(.stt, state: .ready, engineOrModel: backendName, latencyMs: sttMs)
            transitionState(.listening, reason: "Motor Autônomo ativo (\(sttProvider.providerID))")
            startTurnEvaluationLoop()
        } catch {
            guard isVoiceSessionActive, sessionGenerationID == sessionID else { return }
            if case VoiceGatewayError.onDeviceRecognitionUnavailable = error {
                showConsentDialog = true
            }
            let sttMs = Double(DispatchTime.now().uptimeNanoseconds &- sttT0) / 1_000_000.0
            let errText = error.localizedDescription
            activeBannerNotice = errText
            updateComponentStatus(
                .stt,
                state: .unavailable,
                engineOrModel: sttProvider.providerID,
                latencyMs: sttMs,
                lastError: errText,
                dependencyHint: "Verifique em Ajustes do Sistema → Geral → Idioma e Região / Teclado (Ditado Offline) se o idioma \(behavior.languageVariant.displayName) está instalado."
            )
            transitionState(.error, reason: "Falha ao iniciar STT local")
            telemetry.log(category: "STT", message: errText)
            return
        }

        if let greetingText, !greetingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            beginAssistantTurnResponseTracking()
            let adapted = VoiceResponseAdapter.adaptForSpeech(greetingText, profile: behavior, customDictionary: customPronunciation)
            enqueueSpokenTextDirectly(adapted.spokenText)
            onTranscriptDeltaUI?("assistant", adapted.spokenText)
        }
    }

    private func handlePartialTranscript(_ text: String, isFinalEvent: Bool, sessionID: UInt64, expectedTurnGeneration: UInt64) {
        guard sessionID == sessionGenerationID, isVoiceSessionActive, !isMuted else { return }
        _ = expectedTurnGeneration // Epoch checked at STT segment boundary; sessionID isolates across restarts.
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !VoiceMemoryHygieneAnalyzer.isZeroSemanticFragment(clean) else { return }
        guard state != .processing, state != .consultingAgent else { return }

        let now = DispatchTime.now().uptimeNanoseconds
        let hasRecentVAD = lastAcousticSpeechTimestampNs > 0 && (now &- lastAcousticSpeechTimestampNs < 2_200_000_000)
        let hasRecentMicSignal = lastMicNonSilenceTimestampNs > 0 && (now &- lastMicNonSilenceTimestampNs < 2_200_000_000)

        // Reject echoes and trailing speaker reverb, while allowing quiet/soft-spoken human mics when noise gate is quiet.
        if echoSuppressor.isInEchoOrHangoverWindow && !(lastAcousticSpeechTimestampNs > 0 && (now &- lastAcousticSpeechTimestampNs < 550_000_000)) {
            return
        }
        guard hasRecentVAD || hasRecentMicSignal else { return }

        // Ignore duplicate echo of the just-committed utterance within 3.0s
        let normClean = VoiceMemoryHygieneAnalyzer.normalizeForComparison(clean)
        if !normClean.isEmpty,
           normClean == lastCommittedNormalizedUtterance,
           lastCommittedUtteranceAtNs > 0,
           (now &- lastCommittedUtteranceAtNs) < 3_000_000_000 {
            return
        }

        lastSTTResultTimestampNs = now
        telemetry.recordPipelineTrace(
            stage: isFinalEvent ? .finalSTT : .partialSTT,
            sessionToken: "\(sessionGenerationID)",
            turnEpoch: activeTurnGenerationID,
            detail: clean
        )

        if state == .assistantSpeaking {
            // Backchannel brief acknowledgements ("aham", "ok") should NOT cut off an ongoing reply unless sustained.
            if HybridTurnTakingAnalyzer.isLikelyBackchannelOnly(clean) {
                return
            }
            guard lastAcousticSpeechTimestampNs > 0, (now &- lastAcousticSpeechTimestampNs < 1_000_000_000) else {
                return
            }
            performManualOrVADBarageIn(reason: "Fala do usuário durante resposta")
        } else if state != .userSpeaking {
            transitionState(.userSpeaking, reason: "Transcrição parcial iniciada")
            if userSpeechStartedAtNs == 0 {
                userSpeechStartedAtNs = now
            }
        }
        liveUserTranscript = clean
        onTranscriptDeltaUI?("user", clean)
    }

    private func startTurnEvaluationLoop() {
        turnEvalTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + 0.09, repeating: 0.09)
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.evaluateTurnTakingTick()
            }
        }
        turnEvalTimer = timer
        timer.resume()
    }

    private func evaluateTurnTakingTick() {
        guard isVoiceSessionActive, !isMuted, activeS2STransport == nil else { return }
        let transcript = liveUserTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty, state == .userSpeaking else { return }

        let nowNs = DispatchTime.now().uptimeNanoseconds
        let latestActivityNs = max(lastAcousticSpeechTimestampNs, lastSTTResultTimestampNs)
        let silenceMs = latestActivityNs > 0 ? Double(nowNs &- latestActivityNs) / 1_000_000.0 : 0
        let evaluation = HybridTurnTakingAnalyzer.evaluate(
            transcript: transcript,
            silenceDurationMs: silenceMs,
            isAcousticSpeechActive: lastAcousticSpeechTimestampNs > 0 && (nowNs &- lastAcousticSpeechTimestampNs) < 180_000_000,
            language: behavior.languageVariant
        )
        lastTurnEvaluation = evaluation

        if evaluation.shouldFinalizeTurn {
            let committed: String
            if let unified = activeSTTProvider as? UnifiedLocalSTTCoordinator {
                committed = unified.commitCurrentUtterance()
            } else if let apple = activeSTTProvider as? AppleSpeechStreamingSTTProvider {
                committed = apple.commitCurrentUtterance()
            } else {
                committed = transcript
            }
            let rawFinal = committed.isEmpty ? transcript : committed
            let finalUtterance = rawFinal.trimmingCharacters(in: .whitespacesAndNewlines)
            liveUserTranscript = ""
            userSpeechStartedAtNs = 0
            lastSTTResultTimestampNs = 0

            guard !finalUtterance.isEmpty, !VoiceMemoryHygieneAnalyzer.isZeroSemanticFragment(finalUtterance) else {
                transitionState(.listening, reason: "Enunciado vazio após filtragem")
                return
            }

            let normFinal = VoiceMemoryHygieneAnalyzer.normalizeForComparison(finalUtterance)
            if !normFinal.isEmpty,
               normFinal == lastCommittedNormalizedUtterance,
               lastCommittedUtteranceAtNs > 0,
               (nowNs &- lastCommittedUtteranceAtNs) < 3_000_000_000 {
                transitionState(.listening, reason: "Turno duplicado ignorado")
                return
            }

            lastCommittedNormalizedUtterance = normFinal
            lastCommittedUtteranceAtNs = nowNs
            activeTurnGenerationID &+= 1

            telemetry.recordPipelineTrace(
                stage: .finalSTT,
                sessionToken: "\(sessionGenerationID)",
                turnEpoch: activeTurnGenerationID,
                detail: finalUtterance
            )

            turnSubmittedAtNs = nowNs
            firstLLMDeltaRecorded = false
            firstAudioChunkRecorded = false
            transitionState(.processing, reason: evaluation.diagnosticReason)
            handleFinalizedAutonomousTurn(finalUtterance)
        }
    }

    private func handleFinalizedAutonomousTurn(_ utterance: String) {
        memoryStore.appendUserTurn(utterance, providerID: resolvedPipeline.effectiveProvider.rawValue)
        // Raw ASR output is not a verified fact. Keep it in session history only.

        let decision = LocalQueryComplexityAnalyzer.route(
            utterance: utterance,
            currentLanguage: behavior.languageVariant
        )

        switch decision {
        case .voiceControl(let action):
            handleVoiceControlAction(action, rawUtterance: utterance)

        case .queryTaskStatus(_):
            let liveTasks = activeTasksProvider?() ?? activeTasksSnapshot
            activeTasksSnapshot = liveTasks
            let reply = LocalConversationalBrain.formatTaskStatusReply(
                tasks: liveTasks,
                projectName: memoryStore.workspaceContext.projectName,
                language: behavior.languageVariant
            )
            emitImmediateLocalSpeechReply(reply, userUtterance: utterance)

        case .delegateToSpecialist(let hint, let prompt, let riskTier, _):
            if let delegate = onDelegateTaskToAgent {
                let outcome = delegate(hint, prompt, riskTier)
                switch outcome {
                case .awaitingUserApproval(let reason):
                    let safetyReply = behavior.languageVariant.bcp47LanguagePrefix == "en"
                        ? "This action requires manual approval on your screen before executing. \(reason)"
                        : "Essa operação exige sua aprovação manual na tela antes de executar. \(reason)"
                    emitImmediateLocalSpeechReply(safetyReply, userUtterance: utterance)

                case .dispatched(let confirmedAgentName):
                    let ackReply = behavior.languageVariant.bcp47LanguagePrefix == "en"
                        ? "Got it. \(confirmedAgentName) started working on that in the background, and we can keep talking while it runs."
                        : "Certo, já acionei \(confirmedAgentName) em segundo plano com confirmação real da tarefa. Pode continuar conversando comigo normalmente enquanto ele executa."
                    emitImmediateLocalSpeechReply(ackReply, userUtterance: utterance)

                case .unavailable(let reason):
                    let failReply = behavior.languageVariant.bcp47LanguagePrefix == "en"
                        ? "I could not dispatch the task to an agent: \(reason)"
                        : "Não foi possível encaminhar a tarefa ao agente agora: \(reason)"
                    emitImmediateLocalSpeechReply(failReply, userUtterance: utterance)
                }
            } else {
                // Standalone / unit-test caller with single callback
                onCommitUserUtterance?(utterance)
            }

        case .handleLocally(_, let detectedLang):
            if let detectedLang, detectedLang != behavior.languageVariant {
                behavior.languageVariant = detectedLang
            }
            if onRecordLocalExchangeToChat == nil, let commitCB = onCommitUserUtterance, routing.requestedTransportProvider != .autoBestCompliant && routing.requestedTransportProvider != .appleLocalHybrid {
                commitCB(utterance)
                return
            }
            runLocalBrainConversationalTurn(utterance: utterance)
        }
    }

    private func handleVoiceControlAction(_ action: VoiceControlAction, rawUtterance: String) {
        switch action {
        case .muteMicrophone:
            if !isMuted { toggleMute() }
        case .unmuteMicrophone:
            if isMuted { toggleMute() }
        case .interruptSpeech:
            performManualOrVADBarageIn(reason: "Interrupção solicitada por voz")
        case .stopVoiceSession:
            let bye = behavior.languageVariant.bcp47LanguagePrefix == "en" ? "Closing voice mode. Talk soon!" : "Encerrando a conversa por voz. Até já!"
            emitImmediateLocalSpeechReply(bye, userUtterance: rawUtterance)
            let expectedSess = sessionGenerationID
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let self, self.sessionGenerationID == expectedSess else { return }
                self.stopSession(clearUI: true)
            }
        case .switchLanguage(let targetLang):
            behavior.languageVariant = targetLang
            let instructions = buildLocalBrainInstructions(for: targetLang)
            localBrain.resetSession(instructions: instructions)
            let confirm: String = {
                switch targetLang {
                case .englishUS: return "Sure, switching to English now. How can I help?"
                case .spanishES: return "Claro, ahora hablamos en español. ¿En qué te ayudo?"
                case .portuguesePT: return "Com certeza, passo a responder em português europeu. Em que posso ajudar?"
                case .portugueseBR: return "Combinado! Voltando para português do Brasil. Como posso te ajudar?"
                }
            }()
            emitImmediateLocalSpeechReply(confirm, userUtterance: rawUtterance)
        }
    }

    private func emitImmediateLocalSpeechReply(_ reply: String, userUtterance: String) {
        beginAssistantTurnResponseTracking()
        handleStreamingAssistantDelta(reply)
        finishAssistantResponse(fullMarkdownText: reply)
        memoryStore.appendAssistantTurn(reply, providerID: "wisdai_local_autonomous", wasInterruptedByBargeIn: false)
        onTranscriptDeltaUI?("assistant", reply)
        onRecordLocalExchangeToChat?(userUtterance, reply)
    }

    private func runLocalBrainConversationalTurn(utterance: String) {
        localBrainGenerationTask?.cancel()
        beginAssistantTurnResponseTracking()

        let expectedSession = sessionGenerationID
        let expectedTurn = activeTurnGenerationID
        let activeLang = behavior.languageVariant
        let systemPrompt = buildLocalBrainInstructions(for: activeLang)
        let portable = memoryStore.exportPortableSnapshot(targetProviderID: "wisdai_local_brain")
        var contextSummary = portable.renderPortableSystemContext()

        if policy.allowPersistentVoiceMemory {
            let scope = memoryStore.workspaceContext.projectName ?? "global"
            let facts = knowledgeStore.searchRecallableFacts(query: utterance, projectScope: scope, limit: 3)
            if !facts.isEmpty {
                let snippets = facts.map { "- \($0.content)" }.joined(separator: "\n")
                contextSummary += "\nFatos relevantes da memória local:\n\(snippets)"
            }
        }

        telemetry.recordPipelineTrace(
            stage: .retrievedContext,
            sessionToken: "\(expectedSession)",
            turnEpoch: expectedTurn,
            detail: contextSummary.isEmpty ? "(vazio)" : contextSummary
        )
        telemetry.recordPipelineTrace(
            stage: .systemPrompt,
            sessionToken: "\(expectedSession)",
            turnEpoch: expectedTurn,
            detail: systemPrompt
        )

        let recentPairs = portable.recentTurns.map { ($0.role, $0.text) }

        localBrainGenerationTask = Task { @MainActor [weak self] in
            guard let self,
                  self.isVoiceSessionActive,
                  self.sessionGenerationID == expectedSession,
                  self.activeTurnGenerationID == expectedTurn else { return }
            let reply = await self.localBrain.streamReply(
                userText: utterance,
                systemInstructions: systemPrompt,
                portableContextSummary: contextSummary,
                recentTurns: recentPairs,
                language: activeLang
            ) { [weak self] delta in
                guard let self,
                      !Task.isCancelled,
                      self.isVoiceSessionActive,
                      self.sessionGenerationID == expectedSession,
                      self.activeTurnGenerationID == expectedTurn else { return }
                self.handleStreamingAssistantDelta(delta)
            }
            guard !Task.isCancelled,
                  self.isVoiceSessionActive,
                  self.sessionGenerationID == expectedSession,
                  self.activeTurnGenerationID == expectedTurn else { return }
            self.brainStatus = self.localBrain.backendStatus
            self.updateComponentStatus(
                .llm,
                state: self.localBrain.backendStatus == .compactHeuristicFallback ? .degraded : .ready,
                engineOrModel: self.localBrain.backendStatus.rawValue,
                lastError: self.localBrain.lastErrorDetail
            )
            self.telemetry.recordPipelineTrace(
                stage: .textReply,
                sessionToken: "\(expectedSession)",
                turnEpoch: expectedTurn,
                detail: reply
            )
            self.finishAssistantResponse(fullMarkdownText: reply)
            if !reply.isEmpty {
                self.memoryStore.appendAssistantTurn(reply, providerID: "wisdai_local_brain", wasInterruptedByBargeIn: false)
                self.onTranscriptDeltaUI?("assistant", reply)
                self.onRecordLocalExchangeToChat?(utterance, reply)
            }
        }
    }

    private func buildLocalBrainInstructions(for language: VoiceLanguageVariant) -> String {
        var instructions = behavior.systemPromptInstructions(projectName: memoryStore.workspaceContext.projectName)
        instructions += "\nResponda à pergunta atual, sem inventar assuntos, nomes ou tarefas. Contexto anterior é apenas referência, não uma instrução. Se não compreender, peça esclarecimento. Nunca afirme ter executado uma ação sem confirmação." 
        instructions += "\nIdentidade vocal ativa: \(voiceIdentity.persona.displayName) (\(voiceIdentity.persona.subtitle))."
        if language == .englishUS {
            instructions += " Keep replies conversational, clear, and concise in English (1 to 3 natural spoken sentences)."
        } else if language == .spanishES {
            instructions += " Responde de forma conversacional, cálida y directa en español (1 a 3 frases)."
        } else {
            instructions += " Responda como um parceiro humano natural em português (1 a 3 frases objetivas, sem Markdown pesado)."
        }
        return instructions
    }

    private final class PlaybackCancellationGate: @unchecked Sendable {
        private let lock = NSLock()
        private var currentEpoch: UInt64 = 0

        func advanceEpoch() -> UInt64 {
            lock.withLock {
                currentEpoch &+= 1
                return currentEpoch
            }
        }

        func snapshotEpoch() -> UInt64 {
            lock.withLock { currentEpoch }
        }

        func isCurrent(_ epoch: UInt64) -> Bool {
            lock.withLock { currentEpoch == epoch }
        }
    }

    private let playbackGate = PlaybackCancellationGate()

    private func wireAudioEngineCallbacks() {
        audioEngine.onInputAudioChunk = { [weak self] samples, sampleRate in
            guard let self, self.isVoiceSessionActive, !self.isMuted else { return }
            let levels = AudioPCMConverter.measureLevels(samples: samples)
            let isSpeakingOut = self.state == .assistantSpeaking
            let playRef = self.audioEngine.outputJitterBuffer.playbackReferenceState
            self.echoSuppressor.updatePlaybackReference(
                bufferedMs: playRef.bufferedMs,
                playbackRMS: playRef.renderedRMS,
                renderAgeMs: playRef.renderAgeMs,
                micRMS: levels.rms,
                isAssistantSpeaking: isSpeakingOut
            )

            let suppressedSelfEcho = self.echoSuppressor.shouldSuppressAsSelfEcho(
                micRMS: levels.rms,
                lowEnergy: levels.low,
                isAssistantSpeaking: isSpeakingOut
            )
            self.lastFrameClearedEchoGate = !suppressedSelfEcho
            if suppressedSelfEcho {
                return
            }

            let nowNs = DispatchTime.now().uptimeNanoseconds
            if levels.rms >= 0.0065 && !self.echoSuppressor.isInEchoOrHangoverWindow {
                self.lastMicNonSilenceTimestampNs = nowNs
            }

            let vadResult = self.vadTracker.processFrame(
                rms: levels.rms,
                lowEnergy: levels.low,
                highEnergy: levels.high,
                isAssistantSpeaking: isSpeakingOut
            )

            if vadResult.isSpeechActive {
                self.lastAcousticSpeechTimestampNs = nowNs
                self.lastMicNonSilenceTimestampNs = nowNs
                if self.userSpeechStartedAtNs == 0 {
                    self.userSpeechStartedAtNs = nowNs
                }
                self.telemetry.recordPipelineTrace(
                    stage: .acousticProcessing,
                    sessionToken: "\(self.sessionGenerationID)",
                    turnEpoch: self.activeTurnGenerationID,
                    detail: String(format: "rms=%.3f low=%.3f high=%.3f sustained=%.0fms", levels.rms, levels.low, levels.high, vadResult.sustainedSpeechMs)
                )
            }

            if vadResult.isIntentionalBargeIn {
                self.performManualOrVADBarageIn(reason: "Barge-in acústico (<150ms)")
            }

            if let s2s = self.activeS2STransport {
                let targetRate = s2s.inputSampleRateHz
                let resampled = AudioPCMConverter.resampleLinear(samples: samples, fromSampleRate: sampleRate, toSampleRate: targetRate)
                let pcm16 = AudioPCMConverter.floatsToPCM16Data(resampled)
                Task { await s2s.sendAudioPCM16(pcm16) }
            }
        }

        audioEngine.onRawAudioBufferForSpeech = { [weak self] buffer in
            guard let self, self.isVoiceSessionActive, !self.isMuted else { return }
            // Never feed STT while processing/thinking or when active frame belongs to self-playback echo.
            guard self.state != .processing, self.state != .consultingAgent else { return }
            guard self.lastFrameClearedEchoGate else { return }
            guard let stt = self.activeSTTProvider else { return }
            let floats = AudioPCMConverter.mixToMono(buffer: buffer)
            let levels = AudioPCMConverter.measureLevels(samples: floats)
            if self.echoSuppressor.shouldSuppressAsSelfEcho(
                micRMS: levels.rms,
                lowEnergy: levels.low,
                isAssistantSpeaking: self.state == .assistantSpeaking
            ) {
                return
            }
            stt.feedAudioBuffer(buffer, monoFloats: floats, sampleRate: buffer.format.sampleRate)
        }

        audioEngine.onDeviceTopologyChanged = { [weak self] in
            self?.telemetry.log(category: "AudioDevice", message: "Dispositivos de áudio atualizados; gráfico sincronizado.")
        }
    }

    private func enqueueAdaptedSpeechClause(_ rawClause: String) {
        let adapted = VoiceResponseAdapter.adaptForSpeech(
            rawClause,
            profile: behavior,
            customDictionary: customPronunciation
        )
        guard !adapted.spokenText.isEmpty else { return }
        telemetry.recordPipelineTrace(
            stage: .speechAdaptation,
            sessionToken: "\(sessionGenerationID)",
            turnEpoch: activeTurnGenerationID,
            detail: adapted.spokenText
        )
        enqueueSpokenTextDirectly(adapted.spokenText)
    }

    private func enqueueSpokenTextDirectly(_ spokenClause: String) {
        guard isVoiceSessionActive, !isOutputMuted else { return }
        let idx = queuedSpeechChunks.count
        queuedSpeechChunks.append((text: spokenClause, originalIndex: idx))
        liveAssistantTranscript = [liveAssistantTranscript, spokenClause]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !isTTSWorkerRunning else { return }
        isTTSWorkerRunning = true
        transitionState(.assistantSpeaking, reason: "Sintetizando resposta em streaming")

        let expectedSession = sessionGenerationID
        let expectedPlayback = playbackGate.advanceEpoch()
        let gateRef = playbackGate

        ttsQueueTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.sessionGenerationID == expectedSession {
                    self.isTTSWorkerRunning = false
                    if self.isVoiceSessionActive && self.state == .assistantSpeaking {
                        // Wait smoothly until jitter buffer drains before slipping back to .listening
                        Task { @MainActor [weak self] in
                            while let self,
                                  self.sessionGenerationID == expectedSession,
                                  gateRef.isCurrent(expectedPlayback),
                                  self.audioEngine.outputJitterBuffer.stats.bufferedMs > 40 {
                                if !self.isVoiceSessionActive || self.state != .assistantSpeaking { return }
                                try? await Task.sleep(nanoseconds: 45_000_000)
                            }
                            if let self,
                               self.sessionGenerationID == expectedSession,
                               gateRef.isCurrent(expectedPlayback),
                               self.isVoiceSessionActive && self.state == .assistantSpeaking {
                                self.telemetry.recordPipelineTrace(
                                    stage: .playback,
                                    sessionToken: "\(expectedSession)",
                                    turnEpoch: self.activeTurnGenerationID,
                                    detail: "Reprodução concluída (jitter drenado)"
                                )
                                self.transitionState(.listening, reason: "Fala da IA concluída")
                            }
                        }
                    }
                }
            }

            final class ChunkLatencyGate: @unchecked Sendable {
                private let lock = NSLock()
                private var recorded = false
                func claim() -> Bool {
                    lock.withLock {
                        guard !recorded else { return false }
                        recorded = true
                        return true
                    }
                }
            }

            while !Task.isCancelled,
                  self.sessionGenerationID == expectedSession,
                  gateRef.isCurrent(expectedPlayback),
                  !self.queuedSpeechChunks.isEmpty {
                let nextChunk = self.queuedSpeechChunks.removeFirst()
                let tts = self.selectActiveTTSProvider()
                let ttsStartNs = DispatchTime.now().uptimeNanoseconds
                let latencyGate = ChunkLatencyGate()

                self.telemetry.recordPipelineTrace(
                    stage: .vocalSynthesis,
                    sessionToken: "\(expectedSession)",
                    turnEpoch: self.activeTurnGenerationID,
                    detail: "[\(tts.providerID)] \(nextChunk.text)"
                )

                do {
                    try await tts.synthesizeChunk(
                        nextChunk.text,
                        language: self.behavior.languageVariant,
                        voicePreference: self.effectiveTTSVoicePreference(),
                        rate: self.effectiveSpeechRate()
                    ) { [weak self] floats24k, spanLabel in
                        guard let self,
                              !Task.isCancelled,
                              gateRef.isCurrent(expectedPlayback) else { return }
                        let nowNs = DispatchTime.now().uptimeNanoseconds
                        if latencyGate.claim() {
                            let ttsMs = Double(nowNs &- ttsStartNs) / 1_000_000.0
                            Task { @MainActor [weak self] in
                                guard let self,
                                      self.sessionGenerationID == expectedSession,
                                      gateRef.isCurrent(expectedPlayback) else { return }
                                self.hasLocalTTSWarmedUp = true
                                self.telemetry.recordTTSFirstAudioLatency(ms: ttsMs)
                                if !self.firstAudioChunkRecorded && self.turnSubmittedAtNs > 0 {
                                    self.firstAudioChunkRecorded = true
                                    let e2eMs = Double(nowNs &- self.turnSubmittedAtNs) / 1_000_000.0
                                    self.telemetry.recordEndToEndResponseLatency(ms: e2eMs)
                                }
                            }
                        }
                        _ = self.audioEngine.outputJitterBuffer.pushFloatSamples(floats24k, transcriptText: spanLabel)
                    }
                } catch {
                    // Transparent fallback to local clean Apple Natural voice if paid cloud TTS fails.
                    if tts.requiresPaidOptIn && gateRef.isCurrent(expectedPlayback) {
                        await MainActor.run {
                            self.telemetry.log(category: "TTS", message: "Fallback de TTS (\(tts.providerID)): \(error.localizedDescription)")
                        }
                        try? await self.appleTTS.synthesizeChunk(
                            nextChunk.text,
                            language: self.behavior.languageVariant,
                            voicePreference: self.effectiveTTSVoicePreference(),
                            rate: self.effectiveSpeechRate()
                        ) { [weak self] floats24k, spanLabel in
                            guard let self, !Task.isCancelled, gateRef.isCurrent(expectedPlayback) else { return }
                            _ = self.audioEngine.outputJitterBuffer.pushFloatSamples(floats24k, transcriptText: spanLabel)
                        }
                    }
                }
            }
        }
    }

    private func selectActiveTTSProvider() -> StreamingTextToSpeechProvider {
        switch resolvedPipeline.effectiveProvider {
        case .hybridDeepgramElevenLabs:
            return elevenLabsTTS
        case .hybridOpenAITTS:
            return openAITTS
        default:
            return appleTTS
        }
    }

    private func cancelAllOutgoingSpeechAndGeneration() {
        _ = playbackGate.advanceEpoch()
        activeTurnGenerationID &+= 1
        localBrainGenerationTask?.cancel()
        localBrainGenerationTask = nil
        ttsQueueTask?.cancel()
        ttsQueueTask = nil
        queuedSpeechChunks.removeAll()
        speechSegmenter.reset()
        appleTTS.cancelAll()
        elevenLabsTTS.cancelAll()
        openAITTS.cancelAll()
        isTTSWorkerRunning = false
    }

    private func transitionState(_ newState: VoiceConversationState, reason: String) {
        if stateMachine.transition(to: newState, reason: reason) {
            state = stateMachine.state
        }
    }

    private func startResourcePolling() {
        resourceTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + 1.0, repeating: 2.0)
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.telemetry.refreshResources()
            }
        }
        resourceTimer = timer
        timer.resume()
    }

    // MARK: - Permanent Diagnostics, Component Self-Tests & Sanitized Log Export (Section 7)

    public func probeComponent(_ kind: VoiceComponentKind) async {
        refreshDependencyInventory()
        let t0 = DispatchTime.now().uptimeNanoseconds

        switch kind {
        case .interface:
            updateComponentStatus(.interface, state: .ready, engineOrModel: "UI Desacoplada OK", latencyMs: 0.2)

        case .permissions:
            let micOk = await BoundedVoicePermissions.requestMicrophoneAuthorized(timeoutSeconds: 2.0)
            let ms = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000.0
            updateComponentStatus(
                .permissions,
                state: micOk ? .ready : .error,
                engineOrModel: micOk ? "Microfone Autorizado" : "Negado / Expirado",
                latencyMs: ms,
                lastError: micOk ? nil : "Permissão de microfone negada.",
                dependencyHint: micOk ? nil : "Autorize em Ajustes do Sistema → Privacidade e Segurança → Microfone."
            )

        case .audioCapture:
            updateComponentStatus(.audioCapture, state: .initializing, engineOrModel: "Testando captura…")
            let res = await audioEngine.testMicrophoneSignalProbe(durationSeconds: 0.75)
            let ms = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000.0
            updateComponentStatus(
                .audioCapture,
                state: res.ok ? (audioEngine.lastFault == nil ? .ready : .degraded) : .error,
                engineOrModel: "\(res.framesCaptured) amostras · pico \(String(format: "%.3f", res.peakRMS))",
                latencyMs: ms,
                lastError: res.ok ? audioEngine.lastFault : res.detail,
                dependencyHint: audioEngine.lastFault
            )
            telemetry.log(category: "DiagCapture", message: res.detail)

        case .audioPlayback:
            updateComponentStatus(.audioPlayback, state: .initializing, engineOrModel: "Testando saída…")
            let res = await audioEngine.testAudioPlaybackTone()
            updateComponentStatus(
                .audioPlayback,
                state: res.ok ? .ready : .error,
                engineOrModel: audioEngine.telemetrySnapshot().outputDeviceName,
                latencyMs: res.latencyMs,
                lastError: res.ok ? nil : res.detail,
                dependencyHint: res.ok ? res.detail : nil
            )
            telemetry.log(category: "DiagPlayback", message: res.detail)

        case .vad:
            let hold = HybridTurnTakingAnalyzer.evaluate(
                transcript: "Eu estava pensando… talvez mudar depois…",
                silenceDurationMs: 1100,
                isAcousticSpeechActive: false,
                language: behavior.languageVariant
            )
            let ms = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000.0
            let ok = !hold.shouldFinalizeTurn && hold.intent == .pauseToThinkHold
            updateComponentStatus(.vad, state: ok ? .ready : .error, engineOrModel: "HybridTurnTaking + AcousticVAD", latencyMs: ms)

        case .stt:
            updateComponentStatus(.stt, state: .initializing, engineOrModel: "Verificando SpeechAnalyzer…")
            let tempSTT = UnifiedLocalSTTCoordinator()
            do {
                try await tempSTT.start(
                    language: behavior.languageVariant,
                    policy: policy,
                    onPartial: { _ in },
                    onFinal: { _ in },
                    onError: { _ in }
                )
                tempSTT.stop()
                let ms = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000.0
                updateComponentStatus(.stt, state: .ready, engineOrModel: "SpeechTranscriber (\(behavior.languageVariant.shortCode))", latencyMs: ms)
                telemetry.log(category: "DiagSTT", message: "STT local validado em \(String(format: "%.0f", ms)) ms.")
            } catch {
                let ms = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000.0
                updateComponentStatus(.stt, state: .unavailable, engineOrModel: tempSTT.providerID, latencyMs: ms, lastError: error.localizedDescription)
                telemetry.log(category: "DiagSTT", message: "Falha STT: \(error.localizedDescription)")
            }

        case .llm:
            localBrain.prewarm(instructions: buildLocalBrainInstructions(for: behavior.languageVariant))
            brainStatus = localBrain.backendStatus
            let ms = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000.0
            updateComponentStatus(
                .llm,
                state: brainStatus == .appleFoundationModelsReady ? .ready : .degraded,
                engineOrModel: brainStatus.rawValue,
                latencyMs: ms,
                dependencyHint: brainStatus == .appleFoundationModelsReady ? nil : "Apple FoundationModels indisponível; respostas gerais locais não estão disponíveis."
            )

        case .tts:
            updateComponentStatus(.tts, state: .initializing, engineOrModel: "Sintetizando amostra…")
            final class SynthDiagCount: @unchecked Sendable {
                private let lock = NSLock()
                var total = 0
                func add(_ n: Int) { lock.withLock { total += n } }
            }
            let counter = SynthDiagCount()
            let engineRunningNow = audioEngine.isRunning
            let jitterRef = audioEngine.outputJitterBuffer
            do {
                try await appleTTS.synthesizeChunk(
                    "Teste de voz local WisdAI operacional.",
                    language: behavior.languageVariant,
                    voicePreference: effectiveTTSVoicePreference(),
                    rate: effectiveSpeechRate()
                ) { floats, span in
                    counter.add(floats.count)
                    if engineRunningNow {
                        _ = jitterRef.pushFloatSamples(floats, transcriptText: span)
                    }
                }
                let ms = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000.0
                let vName = AppleNaturalPCMStreamingTTSProvider.selectBestNaturalVoice(for: behavior.languageVariant, preferredIdentifier: effectiveTTSVoicePreference())?.name ?? "Apple Voice"
                let ok = counter.total > 1200
                updateComponentStatus(.tts, state: ok ? .ready : .error, engineOrModel: "\(vName) (\(counter.total) amostras)", latencyMs: ms)
                telemetry.log(category: "DiagTTS", message: "TTS gerou \(counter.total) amostras @ 24kHz em \(String(format: "%.0f", ms)) ms.")
            } catch {
                let ms = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000.0
                updateComponentStatus(.tts, state: .error, engineOrModel: "Apple Natural PCM", latencyMs: ms, lastError: error.localizedDescription)
            }

        case .agentOrchestrator:
            refreshResolvedPipeline()
        }
    }

    public func restartVoiceEngine() async {
        let prevCtx = memoryStore.workspaceContext
        let prevHasServer = hasCodexAppServerConnected
        let prevCommit = onCommitUserUtterance ?? { _ in }
        let prevDelta = onTranscriptDeltaUI
        let prevTasks = activeTasksProvider
        let prevDelegate = onDelegateTaskToAgent
        let prevRecord = onRecordLocalExchangeToChat

        stopSession(clearUI: false)
        try? await Task.sleep(nanoseconds: 120_000_000)
        await startSessionWithContinuity(
            workspaceContext: prevCtx,
            continuityItems: [],
            greetingText: "Motor de voz reiniciado. Pode falar.",
            hasCodexAppServer: prevHasServer,
            activeTasksProvider: prevTasks,
            onDelegateTaskToAgent: prevDelegate,
            onRecordLocalExchangeToChat: prevRecord,
            onCommitUserUtterance: prevCommit,
            onTranscriptDeltaUI: prevDelta
        )
    }

    public func exportSanitizedDiagnosticsReport() -> String {
        telemetry.refreshResources()
        modelAssetManager.refreshStorageInfo()
        let engStats = audioEngine.telemetrySnapshot()
        let res = telemetry.resourceSnapshot
        var lines: [String] = []
        lines.append("=== WisdAI Voice Engine Diagnostic Report ===")
        lines.append("Timestamp: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("Engine State: \(state.rawValue) (\(state.displayTitle)) | SessionActive: \(isVoiceSessionActive)")
        lines.append(String(format: "Startup Latency: %.1f ms | Hardware Profile: %@", lastStartupDurationMs, audioEngine.memoryProfile.displayName))
        lines.append(String(format: "Host: RAM %.1f MB / %.1f GB | CPU %.1f%% (%d cores) | GPU: %@ (max %llu MB) | Free Disk: %.1f GB",
                            res.residentMemoryMB, res.physicalRAMGB, res.cpuPercent, res.cpuCoreCount, res.gpuName, res.gpuMaxRecommendedMB, modelAssetManager.availableDiskGB))
        lines.append("Audio Route: In='\(engStats.inputDeviceName)' Out='\(engStats.outputDeviceName)' Processing=\(engStats.processingStatus.rawValue)")
        lines.append("Installed Speech Locales: \(installedSpeechLocales.isEmpty ? "(pending probe)" : installedSpeechLocales.joined(separator: ", "))")
        lines.append("Installed PT Voices: \(installedPTVoicesCount) | Active Persona: \(voiceIdentity.persona.displayName)")
        lines.append("Last Error Summary: \(lastErrorSummary ?? activeBannerNotice ?? "None")")
        lines.append("--- Component States ---")
        for kind in VoiceComponentKind.allCases {
            if let snap = componentStatuses[kind] {
                let lat = snap.latencyMs.map { String(format: "%.1fms", $0) } ?? "-"
                lines.append("• \(kind.displayName): \(snap.state.rawValue) | Engine='\(snap.activeEngineOrModel)' | Lat=\(lat) | Err=\(snap.lastError ?? "-")")
            }
        }
        lines.append("--- Recent Logs (Redacted) ---")
        for ev in telemetry.diagnosticLogs.suffix(40) {
            lines.append("[\(ev.category)] \(ev.message)")
        }
        return VoiceLogRedactor.redact(lines.joined(separator: "\n"))
    }
}

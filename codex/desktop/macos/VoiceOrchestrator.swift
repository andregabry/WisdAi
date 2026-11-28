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
            if !isApplyingIdentityManagerUpdate {
                let b = behavior
                identityManager.updateConfig(invalidateCache: true) { cfg in
                    cfg.language = b.languageVariant
                    cfg.speechRate = Double(b.speechRate)
                    cfg.personalityId = b.personality
                    cfg.design.expressivity = b.expressivity
                    cfg.design.formality = b.formality
                    cfg.design.detailLevel = b.detailLevel
                    cfg.design.pauseScale = b.pauseScale
                    cfg.design.warmth = cfg.identityId.defaultConversationalWarmth
                }
            }
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
    @Published public private(set) var lastAcousticFeatures: AcousticTurnFeatures = .unavailable
    @Published public private(set) var isMuted: Bool = false
    @Published public private(set) var isOutputMuted: Bool = false
    @Published public private(set) var isVoiceSessionActive: Bool = false
    @Published public var showVoiceHUDWindow: Bool = false
    @Published public var showConsentDialog: Bool = false
    @Published public private(set) var activeBannerNotice: String?
    @Published public var selectedVoiceIdentifier: String = UserDefaults.standard.string(forKey: "wisdai.voice.preferredVoiceID") ?? "auto" {
        didSet {
            UserDefaults.standard.set(selectedVoiceIdentifier, forKey: "wisdai.voice.preferredVoiceID")
            if !isApplyingIdentityManagerUpdate && selectedVoiceIdentifier != "auto" {
                let rawID = selectedVoiceIdentifier
                identityManager.selectSpeaker(rawID)
            }
        }
    }
    @Published public var voiceIdentity: VoiceIdentityDescriptor {
        didSet {
            guard !isSyncingIdentityWarmth else { return }
            let targetWarmth = voiceIdentity.persona.defaultConversationalWarmth
            if abs(voiceIdentity.warmth - targetWarmth) > 0.001 {
                isSyncingIdentityWarmth = true
                voiceIdentity.warmth = targetWarmth
                isSyncingIdentityWarmth = false
            }
            if !isApplyingIdentityManagerUpdate {
                identityManager.selectPersona(voiceIdentity.persona)
            }
        }
    }
    @Published public private(set) var hasLocalTTSWarmedUp: Bool = false
    @Published public var selectedTTSEngine: VoiceTTSEngineKind = .supertonic3 {
        didSet {
            if !isApplyingIdentityManagerUpdate {
                identityManager.selectEngine(selectedTTSEngine)
            }
        }
    }
    @Published public var selectedKokoroPreset: KokoroVoicePreset = .pmAlex {
        didSet {
            if !isApplyingIdentityManagerUpdate {
                identityManager.selectSpeaker(selectedKokoroPreset.rawValue)
            }
        }
    }
    @Published public var selectedSupertonicPreset: SupertonicVoicePreset = .m4 {
        didSet {
            if !isApplyingIdentityManagerUpdate {
                identityManager.selectSpeaker(selectedSupertonicPreset.rawValue)
            }
        }
    }
    private var isApplyingIdentityManagerUpdate: Bool = false
    private var isSyncingIdentityWarmth: Bool = false
    @Published public var executionArchitecture: VoiceExecutionArchitectureMode = VoiceExecutionArchitectureMode(rawValue: UserDefaults.standard.string(forKey: "wisdai.voice.executionArchitecture") ?? "") ?? .neuralHybrid {
        didSet {
            UserDefaults.standard.set(executionArchitecture.rawValue, forKey: "wisdai.voice.executionArchitecture")
        }
    }
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

    // Managed Apache-2.0 OpenJarvis Native Runtime + Audio/Speech Engines
    public let openJarvis: OpenJarvisProcessManager
    public let localSTT: UnifiedLocalSTTCoordinator
    public let echoSuppressor: AcousticEchoSuppressor
    public let knowledgeStore: VoiceSQLiteKnowledgeStore
    public let modelAssetManager: VoiceModelAssetManager
    public let identityManager: VoiceIdentityManager
    public let supertonicTTS: SupertonicNeuralTTSProvider
    public let kokoroTTS: KokoroNeuralTTSProvider
    public let sherpaPiperTTS: SherpaVitsPiperTTSProvider
    public let mlxExpressiveTTS: LocalExpressiveTTSLoopbackClient
    public let llamaBrainRuntime: LocalLlamaServerBrainRuntime
    public let mlxBrainRuntime: LocalMLXClientRuntime
    public let previewPlayer: VoiceAudioPreviewPlayer
    public var memoryPressureWatcher: VoiceMemoryPressureWatcher?
    public let acousticExtractor = AcousticFeatureExtractor()

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
    private var openJarvisTurnTask: Task<Void, Never>?
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
    private var turnUserSpeechEndNs: UInt64 = 0
    private var turnSubmittedAtNs: UInt64 = 0
    private var lastCommittedNormalizedUtterance: String = ""
    private var lastCommittedUtteranceAtNs: UInt64 = 0
    private var firstLLMDeltaRecorded = false
    private var firstClauseRecorded = false
    private var firstAudioChunkRecorded = false
    private var firstAudiblePlaybackRecorded = false
    private var turnTTSTotalSynthAccumMs: Double = 0
    private var activeS2SAssistantItemID: String = ""
    private var geminiResumptionHandle: String?
    private var clauseEnqueueCounter: Int = 0
    private var captureTurnSamples16k: [Float] = []
    @Published public var executionEventBus = ExecutionEventBus()
    @Published public private(set) var lastPresentedSpokenTextForTelemetry: String = ""
    private var activeConversationIDProvider: (() -> String?)?
    private var onSubmitUnifiedMessage: ((String, MessageInputSource, VoiceSpecialistAgentHint, VoiceActionRiskTier, Bool) -> UnifiedSubmissionOutcome)?
    private var onCancelActiveTask: (() -> Bool)?

    private var onCommitUserUtterance: ((String) -> Void)?
    private var onTranscriptDeltaUI: ((String, String) -> Void)?
    private var activeTasksProvider: (() -> [VoiceTaskSummarySnapshot])?
    private var onDelegateTaskToAgent: ((VoiceSpecialistAgentHint, String, VoiceActionRiskTier) -> VoiceDelegationDispatchResult)?
    private var onRecordLocalExchangeToChat: ((String, String) -> Void)?
    public var onScanAdditionalChatThreads: (() -> [(threadID: String, items: [CodexContinuityItem])])?
    public var onRemoveAdditionalChatItems: ((_ threadID: String, _ matchingNormalizedTexts: Set<String>) -> Int)?
    public var workspaceSnapshotProvider: (() -> [String: Any])?
    private var hasCodexAppServerConnected: Bool = false

    private var cancellables: Set<AnyCancellable> = []

    public init() {
        let initialPolicy = VoicePolicyPreferences.load()
        var initialBehavior = VoiceBehaviorProfile.load()
        let initialRouting = VoiceRoleRoutingConfig.load()
        let profile = HardwareMemoryProfile.detect()
        let idMgr = VoiceIdentityManager()
        let unified = idMgr.config
        initialBehavior.languageVariant = unified.language
        initialBehavior.speechRate = Float(unified.speechRate)
        initialBehavior.personality = unified.personalityId
        initialBehavior.expressivity = unified.design.expressivity
        initialBehavior.formality = unified.design.formality
        initialBehavior.detailLevel = unified.design.detailLevel
        initialBehavior.pauseScale = unified.design.pauseScale

        let initialIdentity = VoiceIdentityDescriptor(
            persona: unified.identityId,
            warmth: unified.identityId.defaultConversationalWarmth,
            clarityEmphasis: unified.design.directness,
            brandName: "WisdAI"
        )

        self.identityManager = idMgr
        self.policy = initialPolicy
        self.behavior = initialBehavior
        self.routing = initialRouting
        self.voiceIdentity = initialIdentity
        self.selectedTTSEngine = unified.engineId
        self.selectedKokoroPreset = KokoroVoicePreset(rawValue: unified.speakerId.lowercased())
            ?? KokoroVoicePreset.defaultPreset(for: unified.identityId, language: unified.language)
            ?? .pmAlex
        self.selectedSupertonicPreset = SupertonicVoicePreset.from(identifier: unified.speakerId)
            ?? SupertonicVoicePreset.defaultPreset(for: unified.identityId)
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

        self.localSTT = UnifiedLocalSTTCoordinator()
        self.echoSuppressor = AcousticEchoSuppressor()
        self.knowledgeStore = VoiceSQLiteKnowledgeStore()
        let assets = VoiceModelAssetManager()
        self.modelAssetManager = assets
        let supertonic = SupertonicNeuralTTSProvider()
        supertonic.setDefaultFlowMatchingSteps(unified.design.flowMatchingSteps)
        self.supertonicTTS = supertonic
        self.kokoroTTS = KokoroNeuralTTSProvider()
        self.sherpaPiperTTS = SherpaVitsPiperTTSProvider()
        self.mlxExpressiveTTS = LocalExpressiveTTSLoopbackClient()
        let llamaRuntime = LocalLlamaServerBrainRuntime(assetManager: assets)
        self.llamaBrainRuntime = llamaRuntime
        self.openJarvis = OpenJarvisProcessManager(localLlamaRuntime: llamaRuntime)
        self.mlxBrainRuntime = LocalMLXClientRuntime()
        self.previewPlayer = VoiceAudioPreviewPlayer()

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
            if level == .critical {
                self.kokoroTTS.unload()
                self.supertonicTTS.unload()
                self.llamaBrainRuntime.unloadModel()
                self.modelAssetManager.setRuntimeActivity(modelID: VoiceModelCatalog.kokoroInt8ModelID, state: nil)
                self.modelAssetManager.setRuntimeActivity(modelID: VoiceModelCatalog.kokoroFP32ModelID, state: nil)
                self.modelAssetManager.setRuntimeActivity(modelID: VoiceModelCatalog.supertonic3Int8ModelID, state: nil)
            }
            self.telemetry.log(category: "MemoryPressure", message: "Pressão de memória (\(level.rawValue)): compactação e descarregamento aplicados.")
        }

        idMgr.onDidChangeConfiguration = { [weak self] nextCfg, invalidateCache in
            self?.handleIdentityManagerChange(nextCfg, invalidateCache: invalidateCache)
        }

        openJarvis.$lifecycleState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] nextState in
                guard let self else { return }
                let compState: VoiceComponentHealthState = {
                    switch nextState {
                    case .ready: return .ready
                    case .bootstrappingRuntime, .startingLLM, .startingDaemon, .recovering: return .initializing
                    case .failed: return .error
                    case .stopped: return .idle
                    }
                }()
                self.updateComponentStatus(
                    .llm,
                    state: compState,
                    engineOrModel: self.openJarvis.lastHealth.map { "OpenJarvis (\($0.model))" } ?? nextState.displayTitle,
                    lastError: self.openJarvis.lastError
                )
            }
            .store(in: &cancellables)

        refreshConfiguredTruthSnapshot()
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
        var activeTTSLabel = next.activeTTSName
        var banner = next.advisoryBanner
        if !next.effectiveProvider.isSpeechToSpeech && !next.isUsingPaidCloud {
            let activeTTS = selectActiveTTSProvider()
            if activeTTS.providerID == supertonicTTS.providerID {
                activeTTSLabel = "Supertonic-3 44.1kHz (\(selectedSupertonicPreset.rawValue))"
            } else if activeTTS.providerID == kokoroTTS.providerID {
                let kokPreset = effectiveKokoroPreset(for: behavior.languageVariant)
                activeTTSLabel = "Kokoro-82M Neural (\(kokPreset.rawValue))"
            } else if activeTTS.providerID == appleTTS.providerID {
                let appleName = AppleNaturalPCMStreamingTTSProvider.selectBestNaturalVoice(
                    for: behavior.languageVariant,
                    preferredIdentifier: effectiveTTSVoicePreference()
                )?.name ?? "Apple Natural"
                activeTTSLabel = "\(appleName) (Apple Natural PCM)"
                if selectedTTSEngine == .kokoro82M && behavior.languageVariant == .portuguesePT {
                    banner = "Kokoro-82M não suporta Português Europeu (pt-PT) nativo; selecione Supertonic-3 ou Apple Natural."
                } else if identityManager.config.vocalGender == .male &&
                            !AppleNaturalPCMStreamingTTSProvider.hasInstalledNonEloquenceMaleVoice(for: behavior.languageVariant) {
                    banner = "macOS sem voz masculina nativa instalada para \(behavior.languageVariant.displayName) (Apple fallback pode usar Luciana feminina)."
                }
            }
        }
        activeBannerNotice = banner
        telemetry.setActiveProviderLabel("\(next.activeSTTName) → \(activeTTSLabel)")
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

    private func handleIdentityManagerChange(_ nextCfg: UnifiedVoiceConfig, invalidateCache: Bool) {
        isApplyingIdentityManagerUpdate = true
        defer { isApplyingIdentityManagerUpdate = false }

        voiceIdentity = VoiceIdentityDescriptor(
            persona: nextCfg.identityId,
            warmth: nextCfg.identityId.defaultConversationalWarmth,
            clarityEmphasis: nextCfg.design.directness,
            brandName: "WisdAI"
        )
        selectedTTSEngine = nextCfg.engineId
        if let st = SupertonicVoicePreset.from(identifier: nextCfg.speakerId) {
            selectedSupertonicPreset = st
        } else {
            selectedSupertonicPreset = SupertonicVoicePreset.defaultPreset(for: nextCfg.identityId)
        }
        if let kok = KokoroVoicePreset(rawValue: nextCfg.speakerId.lowercased()) {
            selectedKokoroPreset = kok
        } else if let matched = KokoroVoicePreset.defaultPreset(for: nextCfg.identityId, language: nextCfg.language) {
            selectedKokoroPreset = matched
        }
        behavior.languageVariant = nextCfg.language
        behavior.speechRate = Float(nextCfg.speechRate)
        behavior.personality = nextCfg.personalityId
        behavior.expressivity = nextCfg.design.expressivity
        behavior.formality = nextCfg.design.formality
        behavior.detailLevel = nextCfg.design.detailLevel
        behavior.pauseScale = nextCfg.design.pauseScale
        supertonicTTS.setDefaultFlowMatchingSteps(nextCfg.design.flowMatchingSteps)

        refreshResolvedPipeline()
        refreshConfiguredTruthSnapshot()
        if invalidateCache && isVoiceSessionActive {
            cancelPendingSpeechForLiveVoiceSwitch()
        }
        let activeTTS = selectActiveTTSProvider()
        if activeTTS.providerID == supertonicTTS.providerID {
            updateComponentStatus(.tts, state: .ready, engineOrModel: "Supertonic-3 44.1kHz (\(selectedSupertonicPreset.rawValue))")
        } else if activeTTS.providerID == kokoroTTS.providerID {
            updateComponentStatus(.tts, state: .ready, engineOrModel: "Kokoro-82M Neural (\(effectiveKokoroPreset(for: nextCfg.language).rawValue))")
        } else if activeTTS.providerID == appleTTS.providerID {
            let vName = AppleNaturalPCMStreamingTTSProvider.selectBestNaturalVoice(for: nextCfg.language, preferredIdentifier: effectiveTTSVoicePreference())?.name ?? "Apple Natural"
            updateComponentStatus(.tts, state: .ready, engineOrModel: "\(vName) (Apple Natural PCM)")
        }
    }

    private func cancelPendingSpeechForLiveVoiceSwitch() {
        _ = playbackGate.advanceEpoch()
        queuedSpeechChunks.removeAll()
        speechSegmenter.reset()
        ttsQueueTask?.cancel()
        ttsQueueTask = nil
        kokoroTTS.cancelAll()
        supertonicTTS.cancelAll()
        sherpaPiperTTS.cancelAll()
        mlxExpressiveTTS.cancelAll()
        appleTTS.cancelAll()
        _ = audioEngine.bargeInFlushPlayback()
        audioEngine.flushAuxiliaryVocalizationOnly()
        isTTSWorkerRunning = false
        if isVoiceSessionActive && state == .assistantSpeaking {
            transitionState(.listening, reason: "Troca de voz ao vivo concluída")
        }
    }

    public func effectiveKokoroPreset(for language: VoiceLanguageVariant) -> KokoroVoicePreset {
        if let exact = KokoroVoicePreset(rawValue: identityManager.config.speakerId.lowercased()),
           exact.supportedLanguage == language,
           exact.timbre == identityManager.config.vocalGender {
            return exact
        }
        if selectedKokoroPreset.supportedLanguage == language && selectedKokoroPreset.timbre == identityManager.config.vocalGender {
            return selectedKokoroPreset
        }
        return KokoroVoicePreset.defaultPreset(for: voiceIdentity.persona, language: language)
            ?? (identityManager.config.vocalGender == .male ? .pmAlex : .pfDora)
    }

    public func refreshConfiguredTruthSnapshot() {
        let active = selectActiveTTSProvider()
        let lang = behavior.languageVariant
        let cfg = identityManager.config
        let resolvedEngine: VoiceTTSEngineKind = {
            if active.providerID == supertonicTTS.providerID { return .supertonic3 }
            if active.providerID == kokoroTTS.providerID { return .kokoro82M }
            if active.providerID == sherpaPiperTTS.providerID { return .sherpaPiperVits }
            if active.providerID == mlxExpressiveTTS.providerID { return cfg.engineId }
            return .appleNaturalPCM
        }()
        let pref = effectiveTTSVoicePreference()
        let sid = VoiceIdentityManager.resolvedNumericSID(
            engine: resolvedEngine,
            speakerId: pref,
            persona: cfg.identityId,
            language: lang
        )
        identityManager.recordConfiguredRuntime(
            engineId: resolvedEngine,
            modelId: VoiceIdentityManager.defaultModelID(for: resolvedEngine),
            speakerId: pref,
            numericSID: sid,
            language: lang,
            speechRate: Double(effectiveSpeechRate()),
            flowSteps: cfg.design.flowMatchingSteps
        )
    }

    public func effectiveTTSVoicePreference(forText text: String? = nil) -> String {
        let activeProvider = selectActiveTTSProvider()
        let cfg = identityManager.config
        let targetLang = effectiveSynthesisLanguage(forText: text, configured: behavior.languageVariant)
        if activeProvider.providerID == supertonicTTS.providerID {
            let resolved = SupertonicVoicePreset.from(identifier: cfg.speakerId)
            if let resolved, resolved.timbre == cfg.vocalGender {
                return resolved.rawValue
            }
            return SupertonicVoicePreset.defaultPreset(for: cfg.identityId).rawValue
        }
        if activeProvider.providerID == kokoroTTS.providerID {
            if targetLang != behavior.languageVariant {
                return KokoroVoicePreset.defaultPreset(for: cfg.identityId, language: targetLang)?.rawValue
                    ?? (cfg.vocalGender == .male ? "pm_alex" : "pf_dora")
            }
            return effectiveKokoroPreset(for: targetLang).rawValue
        }
        if selectedVoiceIdentifier != "auto",
           !selectedVoiceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return selectedVoiceIdentifier
        }
        return "persona:\(cfg.identityId.rawValue)"
    }

    public func effectiveSynthesisLanguage(forText text: String?, configured: VoiceLanguageVariant) -> VoiceLanguageVariant {
        guard configured == .englishGB || configured == .englishUS,
              let raw = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return configured
        }
        let lower = raw.lowercased()
        let hasPTDiacritics = raw.unicodeScalars.contains { scalar in
            "ãõçáéíóúâêôàÃÕÇÁÉÍÓÚÂÊÔÀ".unicodeScalars.contains(scalar)
        }
        if hasPTDiacritics {
            return .portugueseBR
        }
        let ptKeywords = ["olá", "oi ", "tudo bem", "voce ", "você", "nao ", "não", "para ", "isso ", "teste", "sistema", "problema", "deixe-me", "tudo pronto", "obrigado"]
        if ptKeywords.contains(where: { lower.contains($0) }) {
            return .portugueseBR
        }
        return configured
    }

    public func effectiveSpeechRate() -> Float {
        min(1.30, max(0.75, behavior.speechRate))
    }

    public func updateActiveTasksSnapshot(_ tasks: [VoiceTaskSummarySnapshot]) {
        activeTasksSnapshot = tasks
    }

    public func notifySpecialistTaskFinished(agentName: String, title: String, succeeded: Bool, summary: String) {
        let isEn = behavior.languageVariant.bcp47LanguagePrefix == "en"
        let body = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullNotice: String = {
            if body.isEmpty {
                return succeeded
                    ? (isEn ? "\(agentName) finished \(title)." : "Pronto, o agente \(agentName) concluiu \(title).")
                    : (isEn ? "\(agentName) encountered an error while running \(title)." : "O agente \(agentName) encontrou um erro ao executar \(title).")
            }
            let lead = succeeded
                ? (isEn ? "\(agentName) finished:" : "Concluí com \(agentName).")
                : (isEn ? "\(agentName) reported a problem:" : "O agente \(agentName) encontrou um problema:")
            return "\(lead) \(body)"
        }()

        memoryStore.appendAssistantTurn(fullNotice, providerID: "wisdai_agent_observer", wasInterruptedByBargeIn: false)
        recordPresentedSpokenTextForTelemetry(fullNotice)
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

    public func updateContextualVocabulary(_ terms: [String]) {
        localSTT.setContextualVocabulary(terms)
        appleSTT.setContextualVocabulary(terms)
    }

    public func updateWorkspaceContext(_ context: VoiceWorkspaceContextSnapshot) {
        memoryStore.updateWorkspaceContext(context)
        if let vocab = context.resolvedProject?.contextualVocabulary, !vocab.isEmpty {
            updateContextualVocabulary(vocab)
        }
    }

    public func configureAgenticBridgeForSession(
        workspaceContext: VoiceWorkspaceContextSnapshot,
        executionEventBus: ExecutionEventBus?,
        conversationIDProvider: (() -> String?)?,
        activeTasksProvider: (() -> [VoiceTaskSummarySnapshot])?,
        onSubmitUnifiedMessage: ((String, MessageInputSource, VoiceSpecialistAgentHint, VoiceActionRiskTier, Bool) -> UnifiedSubmissionOutcome)?,
        onCancelActiveTask: (() -> Bool)?,
        onCommitUserUtterance: ((String) -> Void)? = nil,
        onRecordLocalExchangeToChat: ((String, String) -> Void)? = nil
    ) {
        updateWorkspaceContext(workspaceContext)
        if let executionEventBus {
            self.executionEventBus = executionEventBus
        }
        self.activeConversationIDProvider = conversationIDProvider
        self.activeTasksProvider = activeTasksProvider
        self.onSubmitUnifiedMessage = onSubmitUnifiedMessage
        self.onCancelActiveTask = onCancelActiveTask
        self.onCommitUserUtterance = onCommitUserUtterance
        self.onRecordLocalExchangeToChat = onRecordLocalExchangeToChat
        if let tasks = activeTasksProvider?() {
            self.activeTasksSnapshot = tasks
        }
    }

    /// Normalizes a raw transcript with project/ecosystem context and routes it through the full autonomous voice pipeline.
    @discardableResult
    public func submitNormalizedVoiceTranscript(_ rawTranscript: String) -> NormalizedTranscriptResult {
        let normalized = ContextualTranscriptNormalizer.normalize(
            rawTranscript,
            activeProjectName: memoryStore.workspaceContext.projectName
        )
        let finalUtterance = normalized.normalizedTranscript
        guard !finalUtterance.isEmpty else { return normalized }
        handleFinalizedAutonomousTurn(finalUtterance)
        return normalized
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
        onTranscriptDeltaUI: ((String, String) -> Void)? = nil,
        executionEventBus: ExecutionEventBus? = nil,
        conversationIDProvider: (() -> String?)? = nil,
        onSubmitUnifiedMessage: ((String, MessageInputSource, VoiceSpecialistAgentHint, VoiceActionRiskTier, Bool) -> UnifiedSubmissionOutcome)? = nil,
        onCancelActiveTask: (() -> Bool)? = nil
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

        if let executionEventBus {
            self.executionEventBus = executionEventBus
        }
        self.activeConversationIDProvider = conversationIDProvider
        self.onSubmitUnifiedMessage = onSubmitUnifiedMessage
        self.onCancelActiveTask = onCancelActiveTask
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
        self.lastAcousticFeatures = .unavailable
        self.acousticExtractor.resetTurn()
        self.captureTurnSamples16k.removeAll(keepingCapacity: true)
        self.updateWorkspaceContext(workspaceContext)
        self.memoryStore.seedFromHistoryItems(continuityItems, providerID: routing.requestedTransportProvider.rawValue)
        refreshResolvedPipeline(hasCodexAppServer: hasCodexAppServer)

        transitionState(.initializingLocalEngine, reason: "Iniciando OpenJarvis + Motor de Áudio WisdAI")
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
        updateComponentStatus(.llm, state: .initializing, engineOrModel: openJarvis.lifecycleState.displayTitle)
        updateComponentStatus(.tts, state: .initializing, engineOrModel: resolvedPipeline.activeTTSName)

        // Start OpenJarvis daemon + Metal LLM in parallel with CoreAudio initialization
        Task { @MainActor [weak self] in
            guard let self, self.isVoiceSessionActive, self.sessionGenerationID == currentSessionID else { return }
            let llmT0 = DispatchTime.now().uptimeNanoseconds
            do {
                let health = try await self.openJarvis.ensureRunning()
                let llmMs = Double(DispatchTime.now().uptimeNanoseconds &- llmT0) / 1_000_000.0
                self.updateComponentStatus(
                    .llm,
                    state: .ready,
                    engineOrModel: "OpenJarvis (\(health.model) · \(health.toolsCount) tools)",
                    latencyMs: llmMs
                )
                await self.openJarvis.pushWorkspaceSnapshot([
                    "project_name": self.memoryStore.workspaceContext.projectName ?? "",
                    "project_path": self.memoryStore.workspaceContext.absoluteDirectoryPath ?? "",
                    "git_branch": self.memoryStore.workspaceContext.resolvedProject?.gitBranch ?? "",
                    "active_agent": self.memoryStore.workspaceContext.activeExecutionAgent,
                    "active_model": self.memoryStore.workspaceContext.selectedModelID ?? "",
                    "active_effort": self.memoryStore.workspaceContext.selectedEffortTitle ?? "",
                    "active_tasks_count": self.memoryStore.workspaceContext.activeTasksCount,
                ])
                _ = await self.openJarvis.warmupSTT()
            } catch {
                let llmMs = Double(DispatchTime.now().uptimeNanoseconds &- llmT0) / 1_000_000.0
                self.telemetry.log(category: "OpenJarvis", message: "Erro ao iniciar OpenJarvis: \(error.localizedDescription)")
                self.updateComponentStatus(
                    .llm,
                    state: .error,
                    engineOrModel: "OpenJarvis Indisponível",
                    latencyMs: llmMs,
                    lastError: error.localizedDescription
                )
            }
        }

        // Anti-hang startup watchdog: allows CoreAudio VPIO/HAL recovery stabilization (~2.5s max)
        // while guaranteeing never hanging indefinitely in .connecting/.initializingLocalEngine (> 5.0s).
        startupWatchdogTask?.cancel()
        startupWatchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self,
                  !Task.isCancelled,
                  self.sessionGenerationID == currentSessionID,
                  self.isVoiceSessionActive else { return }
            if self.state == .connecting || self.state == .initializingLocalEngine || self.state == .loadingModel {
                self.telemetry.log(category: "Startup", message: "Watchdog de 5.0s acionado; estado AudioEngine=\(self.audioEngine.lifecycleState.rawValue), op=\(self.audioEngine.lastOperation.rawValue).")
                if self.audioEngine.isRunning {
                    self.transitionState(.listening, reason: "Watchdog anti-travamento (5.0s)")
                    self.startTurnEvaluationLoop()
                } else {
                    let failDetail = self.audioEngine.lastFailure?.formattedSummary ?? "Timeout após 5,0s em \(self.audioEngine.lastOperation.rawValue)"
                    let msg = "Tempo limite ao iniciar motor de áudio local (5,0s): \(failDetail)."
                    self.activeBannerNotice = msg
                    self.updateComponentStatus(.audioCapture, state: .error, engineOrModel: "CoreAudio", lastError: msg)
                    self.transitionState(.error, reason: "Timeout de inicialização (5.0s)")
                }
            }
        }

        // Audio & STT warmups continue in background without blocking hardware startup

        let ptVoices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.lowercased().hasPrefix("pt") }
        installedPTVoicesCount = ptVoices.count
        let activeTTS = selectActiveTTSProvider()
        if activeTTS.providerID == supertonicTTS.providerID {
            let supDiag = supertonicTTS.currentDiagnostics()
            updateComponentStatus(
                .tts,
                state: .ready,
                engineOrModel: "Supertonic-3 44.1kHz (\(selectedSupertonicPreset.rawValue))",
                latencyMs: supDiag.loadLatencyMs,
                lastError: supDiag.lastError
            )
            Task { @MainActor [weak self] in
                guard let self else { return }
                let installedID = self.supertonicTTS.resolveInstalledPaths()?.modelID
                if let installedID { self.modelAssetManager.setRuntimeActivity(modelID: installedID, state: .loading) }
                do {
                    let diag = try await self.supertonicTTS.preload()
                    self.hasLocalTTSWarmedUp = true
                    if let mid = diag.activeModelID {
                        self.modelAssetManager.setRuntimeActivity(modelID: mid, state: .operational)
                    }
                    self.identityManager.recordLoadedRuntime(VoiceLoadedRuntimeSnapshot(
                        engineId: self.supertonicTTS.providerID,
                        modelId: diag.activeModelID ?? VoiceModelCatalog.supertonic3Int8ModelID,
                        langCode: self.behavior.languageVariant.bcp47LanguagePrefix,
                        loadedSpeakerCount: diag.numSpeakers,
                        sampleRateHz: diag.sampleRateHz,
                        isLoaded: true
                    ))
                    self.updateComponentStatus(
                        .tts,
                        state: .ready,
                        engineOrModel: "Supertonic-3 44.1kHz (\(self.selectedSupertonicPreset.rawValue))",
                        latencyMs: diag.loadLatencyMs
                    )
                } catch {
                    if let installedID {
                        self.modelAssetManager.setRuntimeActivity(modelID: installedID, state: .error, error: error.localizedDescription)
                    }
                    self.updateComponentStatus(
                        .tts,
                        state: .degraded,
                        engineOrModel: "Supertonic falhou -> Fallback",
                        lastError: error.localizedDescription
                    )
                }
            }
        } else if activeTTS.providerID == kokoroTTS.providerID {
            let kokoroDiag = kokoroTTS.currentDiagnostics()
            let kokPreset = effectiveKokoroPreset(for: behavior.languageVariant)
            updateComponentStatus(
                .tts,
                state: .ready,
                engineOrModel: "Kokoro-82M Neural (\(kokPreset.rawValue))",
                latencyMs: kokoroDiag.loadLatencyMs,
                lastError: kokoroDiag.lastError
            )
            let langNow = behavior.languageVariant
            Task { @MainActor [weak self] in
                guard let self else { return }
                let installedID = self.kokoroTTS.resolveInstalledPaths()?.modelID
                if let installedID {
                    self.modelAssetManager.setRuntimeActivity(modelID: installedID, state: .loading)
                }
                do {
                    let diag = try await self.kokoroTTS.preload(language: langNow)
                    self.hasLocalTTSWarmedUp = true
                    if let mid = diag.activeModelID {
                        self.modelAssetManager.setRuntimeActivity(modelID: mid, state: .operational)
                    }
                    self.identityManager.recordLoadedRuntime(VoiceLoadedRuntimeSnapshot(
                        engineId: self.kokoroTTS.providerID,
                        modelId: diag.activeModelID ?? VoiceModelCatalog.kokoroInt8ModelID,
                        langCode: diag.loadedLangCode ?? langNow.rawValue,
                        loadedSpeakerCount: diag.numSpeakers,
                        sampleRateHz: diag.sampleRateHz,
                        isLoaded: true
                    ))
                    self.updateComponentStatus(
                        .tts,
                        state: .ready,
                        engineOrModel: "Kokoro-82M Neural (\(self.effectiveKokoroPreset(for: langNow).rawValue))",
                        latencyMs: diag.loadLatencyMs
                    )
                } catch {
                    if let installedID {
                        self.modelAssetManager.setRuntimeActivity(modelID: installedID, state: .error, error: error.localizedDescription)
                    }
                    self.updateComponentStatus(
                        .tts,
                        state: .degraded,
                        engineOrModel: "Kokoro falhou -> Apple Natural",
                        lastError: error.localizedDescription
                    )
                }
            }
        } else if let activeVoice = AppleNaturalPCMStreamingTTSProvider.selectBestNaturalVoice(for: behavior.languageVariant, preferredIdentifier: effectiveTTSVoicePreference()) {
            let hint = (selectedTTSEngine == .kokoro82M && !kokoroTTS.isReadyOnDisk)
                ? "Kokoro-82M ainda não instalado no Laboratório de Voz; usando Apple Natural."
                : ((selectedTTSEngine == .kokoro82M && behavior.languageVariant == .portuguesePT) ? "Kokoro-82M não suporta pt-PT nativo; usando Apple Natural." : nil)
            updateComponentStatus(.tts, state: .ready, engineOrModel: "\(activeVoice.name) (Apple Natural PCM)", dependencyHint: hint)
        } else {
            updateComponentStatus(
                .tts,
                state: .unavailable,
                engineOrModel: "Voz TTS não instalada",
                lastError: "Nenhuma voz local instalada para \(behavior.languageVariant.displayName).",
                dependencyHint: "Instale uma voz em Ajustes do Sistema → Acessibilidade → Conteúdo Falado → Vozes do Sistema."
            )
        }
        if !hasLocalTTSWarmedUp && activeTTS.providerID != kokoroTTS.providerID {
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
            let isDegraded = (telSnap.lifecycleState == .degradedCompatibility) || !telSnap.vpioActive || (audioEngine.lastFault != nil)
            let capState: VoiceComponentHealthState = isDegraded ? .degraded : .ready
            let depHint: String? = isDegraded
                ? (audioEngine.lastFault ?? "Modo de compatibilidade sem VPIO hardware; supressão de eco por software ativa.")
                : nil
            if isDegraded {
                activeBannerNotice = depHint
            }
            updateComponentStatus(
                .audioPlayback,
                state: telSnap.isSplitEngineCompatibility ? .degraded : .ready,
                engineOrModel: "\(telSnap.outputDeviceName) (\(Int(telSnap.outputSampleRateHz))Hz/\(telSnap.outputChannels)ch)",
                latencyMs: audioMs,
                lastError: telSnap.isSplitEngineCompatibility ? audioEngine.lastFault : nil
            )
            updateComponentStatus(
                .audioCapture,
                state: capState,
                engineOrModel: "\(telSnap.inputDeviceName) (\(Int(telSnap.inputSampleRateHz))Hz/\(telSnap.inputChannels)ch · \(telSnap.processingStatus.rawValue))",
                latencyMs: audioMs,
                lastError: audioEngine.lastFault,
                dependencyHint: depHint
            )
            updateComponentStatus(.vad, state: .ready, engineOrModel: "AcousticVADTracker + HybridTurnTakingAnalyzer")
            telemetry.log(
                category: "AudioEngine",
                message: "Motor de áudio ativo em \(String(format: "%.0f", audioMs))ms: state=\(telSnap.lifecycleState.rawValue), graph='\(telSnap.nodeGraphSummary)'."
            )
        } catch {
            startupWatchdogTask?.cancel()
            let telSnap = audioEngine.telemetrySnapshot()
            let failRec = telSnap.lastFailure
            let failSummary = failRec?.formattedSummary ?? error.localizedDescription
            let err = "Não foi possível iniciar o motor de áudio nativo: \(failSummary)"
            activeBannerNotice = err

            let isCaptureCause: Bool = {
                guard let op = failRec?.operation else { return Int32((error as NSError).code) == -3 }
                switch op {
                case .validatePermissions, .enableVoiceProcessingIO, .installInputTap:
                    return true
                case .attachOutputSource:
                    return false
                default:
                    return Int32((error as NSError).code) == -3
                }
            }()

            if isCaptureCause {
                updateComponentStatus(.audioPlayback, state: .error, engineOrModel: "\(telSnap.outputDeviceName) (AVAudioEngine)", lastError: err)
                updateComponentStatus(.audioCapture, state: .error, engineOrModel: "\(telSnap.inputDeviceName) (AVAudioEngine)", lastError: err)
            } else {
                updateComponentStatus(.audioCapture, state: .error, engineOrModel: "\(telSnap.inputDeviceName) (AVAudioEngine)", lastError: err)
                updateComponentStatus(.audioPlayback, state: .error, engineOrModel: "\(telSnap.outputDeviceName) (AVAudioEngine)", lastError: err)
            }
            transitionState(.error, reason: "Falha no motor de áudio (\(failRec?.operation.rawValue ?? "Start"))")
            telemetry.log(category: "AudioEngine", message: "Erro ao iniciar full-duplex: \(failSummary) | Graph='\(telSnap.nodeGraphSummary)' | AU='\(telSnap.audioUnitState)'")
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
        openJarvisTurnTask?.cancel()
        openJarvisTurnTask = nil
        openJarvis.cancelActiveVoiceTurnAudioOnly()
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
        acousticExtractor.resetTurn()
        captureTurnSamples16k.removeAll(keepingCapacity: false)
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

    public func beginAssistantTurnResponseTracking(userSpeechEndNs: UInt64? = nil) {
        if let userSpeechEndNs {
            turnUserSpeechEndNs = userSpeechEndNs
        }
        turnSubmittedAtNs = DispatchTime.now().uptimeNanoseconds
        firstLLMDeltaRecorded = false
        firstClauseRecorded = false
        firstAudioChunkRecorded = false
        firstAudiblePlaybackRecorded = false
        turnTTSTotalSynthAccumMs = 0
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
            if !firstClauseRecorded && turnSubmittedAtNs > 0 {
                firstClauseRecorded = true
                let clauseMs = Double(DispatchTime.now().uptimeNanoseconds &- turnSubmittedAtNs) / 1_000_000.0
                telemetry.recordFirstClauseLatency(ms: clauseMs)
            }
            enqueueAdaptedSpeechClause(clause)
        }
    }

    public func finishAssistantResponse(fullMarkdownText: String) {
        guard isVoiceSessionActive else { return }
        let remainder = speechSegmenter.flushFinal()
        if !remainder.isEmpty {
            for clause in remainder {
                if !firstClauseRecorded && turnSubmittedAtNs > 0 {
                    firstClauseRecorded = true
                    let clauseMs = Double(DispatchTime.now().uptimeNanoseconds &- turnSubmittedAtNs) / 1_000_000.0
                    telemetry.recordFirstClauseLatency(ms: clauseMs)
                }
                enqueueAdaptedSpeechClause(clause)
            }
        } else if liveAssistantMarkdownText.isEmpty && !fullMarkdownText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let adapted = VoiceResponseAdapter.adaptForSpeech(
                fullMarkdownText,
                profile: behavior,
                customDictionary: customPronunciation
            )
            if !adapted.spokenText.isEmpty {
                if !firstClauseRecorded && turnSubmittedAtNs > 0 {
                    firstClauseRecorded = true
                    let clauseMs = Double(DispatchTime.now().uptimeNanoseconds &- turnSubmittedAtNs) / 1_000_000.0
                    telemetry.recordFirstClauseLatency(ms: clauseMs)
                }
                enqueueSpokenTextDirectly(adapted.spokenText)
            }
        }
    }

    public func recordPresentedSpokenTextForTelemetry(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            lastPresentedSpokenTextForTelemetry = trimmed
        }
    }

    public func speakSystemNoticeNaturally(_ notice: String, priorityInterrupt: Bool = false) {
        let trimmed = notice.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recordPresentedSpokenTextForTelemetry(trimmed)
        guard isVoiceSessionActive, !isOutputMuted else { return }
        if priorityInterrupt {
            _ = audioEngine.bargeInFlushPlayback()
            queuedSpeechChunks.removeAll()
        }
        guard state != .userSpeaking else { return }
        if trimmed.count > 140 {
            speechSegmenter.reset()
            let segments = speechSegmenter.appendDelta(trimmed) + speechSegmenter.flushFinal()
            if !segments.isEmpty {
                for seg in segments {
                    enqueueAdaptedSpeechClause(seg)
                }
                return
            }
        }
        enqueueAdaptedSpeechClause(trimmed)
    }

    // MARK: - Barge-In Trigger

    public func performManualOrVADBarageIn(reason: String = "Barge-in", triggerOriginNs: UInt64? = nil) {
        guard state == .assistantSpeaking || state == .processing || state == .consultingAgent else { return }
        let originNs = triggerOriginNs ?? DispatchTime.now().uptimeNanoseconds
        let outcome = bargeInCoordinator.executeBargeIn(audioEngine: audioEngine) { [weak self] in
            self?.cancelAllOutgoingSpeechAndGeneration()
        }
        telemetry.recordBargeInStopLatency(ms: outcome.stopLatencyMs)
        monitorAudibleBargeInStop(originNs: originNs, flushNs: outcome.flushTimestampUptimeNs)
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

    private func monitorAudibleBargeInStop(originNs: UInt64, flushNs: UInt64) {
        let hwLatencyMs = audioEngine.currentOutputHardwareLatencyMs
        let expectedSession = sessionGenerationID
        Task { @MainActor [weak self] in
            for _ in 0..<40 {
                guard let self, self.sessionGenerationID == expectedSession else { return }
                if let zeroRenderNs = self.audioEngine.outputJitterBuffer.firstSilentRenderAfterFlushTimestampNs(matchingFlush: flushNs) {
                    let renderDeltaMs = zeroRenderNs >= originNs
                        ? Double(zeroRenderNs &- originNs) / 1_000_000.0
                        : 0
                    self.telemetry.recordBargeInAudibleStopLatency(ms: renderDeltaMs + hwLatencyMs)
                    return
                }
                try? await Task.sleep(nanoseconds: 4_000_000)
            }
            guard let self, self.sessionGenerationID == expectedSession else { return }
            let fallbackMs = Double(DispatchTime.now().uptimeNanoseconds &- originNs) / 1_000_000.0 + hwLatencyMs
            self.telemetry.recordBargeInAudibleStopLatency(ms: min(fallbackMs, 180.0))
        }
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
                    return "Apple SpeechTranscriber + OpenJarvis Whisper (\(behavior.languageVariant.shortCode))"
                }
                return pipeline.activeSTTName
            }()
            updateComponentStatus(.stt, state: .ready, engineOrModel: backendName, latencyMs: sttMs)
            transitionState(.listening, reason: "OpenJarvis + Áudio Nativo ativo (\(sttProvider.providerID))")
            startTurnEvaluationLoop()
        } catch {
            guard isVoiceSessionActive, sessionGenerationID == sessionID else { return }
            let sttMs = Double(DispatchTime.now().uptimeNanoseconds &- sttT0) / 1_000_000.0
            let errText = error.localizedDescription
            activeSTTProvider = nil
            telemetry.log(category: "STT", message: "Apple STT indisponível (\(errText)); usando OpenJarvis Faster-Whisper com captura VPIO.")
            updateComponentStatus(
                .stt,
                state: .ready,
                engineOrModel: "OpenJarvis Faster-Whisper (hotwords)",
                latencyMs: sttMs,
                dependencyHint: errText
            )
            transitionState(.listening, reason: "OpenJarvis Whisper ativo em captura contínua")
            startTurnEvaluationLoop()
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
            if HybridTurnTakingAnalyzer.isLikelyBackchannelOnly(clean) {
                return
            }
            guard lastAcousticSpeechTimestampNs > 0, (now &- lastAcousticSpeechTimestampNs < 1_000_000_000) else {
                return
            }
            performManualOrVADBarageIn(
                reason: "Fala do usuário durante resposta",
                triggerOriginNs: vadTracker.currentSpeechOnsetUptimeNs ?? lastAcousticSpeechTimestampNs
            )
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
        guard state == .userSpeaking else { return }

        let nowNs = DispatchTime.now().uptimeNanoseconds
        let latestActivityNs = max(lastAcousticSpeechTimestampNs, lastSTTResultTimestampNs)
        let silenceMs = latestActivityNs > 0 ? Double(nowNs &- latestActivityNs) / 1_000_000.0 : 0
        let isMicActivelySpeaking = lastAcousticSpeechTimestampNs > 0 && (nowNs &- lastAcousticSpeechTimestampNs) < 180_000_000

        // Support pure-Whisper turn finalization when Apple live STT is disabled/unavailable
        if transcript.isEmpty {
            if !captureTurnSamples16k.isEmpty && !isMicActivelySpeaking && silenceMs >= 850.0 {
                let pcmCopy = captureTurnSamples16k
                captureTurnSamples16k.removeAll(keepingCapacity: true)
                userSpeechStartedAtNs = 0
                transitionState(.processing, reason: "Transcrevendo áudio via OpenJarvis Whisper")
                let expectedSession = sessionGenerationID
                let hotwords = memoryStore.workspaceContext.resolvedProject?.contextualVocabulary ?? ContextualTranscriptNormalizer.defaultEcosystemVocabulary
                let langHint = behavior.languageVariant.bcp47LanguagePrefix
                Task { @MainActor [weak self] in
                    guard let self, self.isVoiceSessionActive, self.sessionGenerationID == expectedSession else { return }
                    let wav = CodexVoiceAudioCues.makeWAVContainer(
                        pcm16Mono: AudioPCMConverter.floatsToPCM16Data(pcmCopy),
                        sampleRate: 16_000,
                        channels: 1
                    )
                    if let whisperText = try? await self.openJarvis.transcribeWAV(audioData: wav, language: langHint, hotwords: hotwords),
                       !whisperText.isEmpty,
                       !VoiceMemoryHygieneAnalyzer.isZeroSemanticFragment(whisperText) {
                        let norm = ContextualTranscriptNormalizer.normalize(whisperText, activeProjectName: self.memoryStore.workspaceContext.projectName)
                        self.onTranscriptDeltaUI?("user", norm.normalizedTranscript)
                        self.handleFinalizedAutonomousTurn(norm.normalizedTranscript)
                    } else {
                        self.transitionState(.listening, reason: "Áudio sem fala inteligível")
                    }
                }
            }
            return
        }

        let evaluation = HybridTurnTakingAnalyzer.evaluate(
            transcript: transcript,
            silenceDurationMs: silenceMs,
            isAcousticSpeechActive: isMicActivelySpeaking,
            language: behavior.languageVariant,
            pitchContour: acousticExtractor.currentContour(),
            adaptiveHoldOffsetMs: 0
        )
        lastTurnEvaluation = evaluation

        guard evaluation.shouldFinalizeTurn else { return }

        acousticExtractor.resetTurn()
        let committed: String
        if let unified = activeSTTProvider as? UnifiedLocalSTTCoordinator {
            committed = unified.commitCurrentUtterance()
        } else if let apple = activeSTTProvider as? AppleSpeechStreamingSTTProvider {
            committed = apple.commitCurrentUtterance()
        } else {
            committed = transcript
        }
        let pcmSnapshot = captureTurnSamples16k
        captureTurnSamples16k.removeAll(keepingCapacity: true)

        let rawFinal = committed.isEmpty ? transcript : committed
        let trimmedFinal = rawFinal.trimmingCharacters(in: .whitespacesAndNewlines)
        let speechEndNs = lastAcousticSpeechTimestampNs > 0
            ? lastAcousticSpeechTimestampNs
            : (lastSTTResultTimestampNs > 0 ? lastSTTResultTimestampNs : nowNs)
        let lastSttNs = lastSTTResultTimestampNs > 0 ? lastSTTResultTimestampNs : nowNs
        let sttFromSpeechEndMs = nowNs >= speechEndNs ? Double(nowNs &- speechEndNs) / 1_000_000.0 : 0
        let pureSttSettlingMs = nowNs >= lastSttNs ? Double(nowNs &- lastSttNs) / 1_000_000.0 : 0
        telemetry.recordSTTLatency(ms: sttFromSpeechEndMs, settlingMs: pureSttSettlingMs)

        liveUserTranscript = ""
        userSpeechStartedAtNs = 0
        lastSTTResultTimestampNs = 0

        guard !trimmedFinal.isEmpty, !VoiceMemoryHygieneAnalyzer.isZeroSemanticFragment(trimmedFinal) else {
            transitionState(.listening, reason: "Enunciado vazio após filtragem")
            return
        }

        let normalizedSTT = ContextualTranscriptNormalizer.normalize(
            trimmedFinal,
            activeProjectName: memoryStore.workspaceContext.projectName
        )
        let finalUtterance = normalizedSTT.normalizedTranscript

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

        let sttTraceDetail = normalizedSTT.wasModified
            ? "raw='\(normalizedSTT.originalTranscript)' -> norm='\(finalUtterance)'"
            : finalUtterance
        telemetry.recordPipelineTrace(
            stage: .finalSTT,
            sessionToken: "\(sessionGenerationID)",
            turnEpoch: activeTurnGenerationID,
            detail: sttTraceDetail
        )

        turnUserSpeechEndNs = speechEndNs
        turnSubmittedAtNs = nowNs
        firstLLMDeltaRecorded = false
        firstClauseRecorded = false
        firstAudioChunkRecorded = false
        firstAudiblePlaybackRecorded = false
        turnTTSTotalSynthAccumMs = 0
        transitionState(.processing, reason: evaluation.diagnosticReason)

        // If Whisper is already warmed in OpenJarvis and we captured >= 0.4s of audio, verify project/technical names with Whisper hotwords when confidence warrants it
        if openJarvis.lastHealth?.sttLoaded == true && pcmSnapshot.count >= 6400 && normalizedSTT.appliedReplacements.isEmpty && finalUtterance.split(whereSeparator: \.isWhitespace).count <= 14 {
            let expectedSession = sessionGenerationID
            let hotwords = memoryStore.workspaceContext.resolvedProject?.contextualVocabulary ?? ContextualTranscriptNormalizer.defaultEcosystemVocabulary
            let langHint = behavior.languageVariant.bcp47LanguagePrefix
            Task { @MainActor [weak self] in
                guard let self, self.sessionGenerationID == expectedSession, self.isVoiceSessionActive else { return }
                let wav = CodexVoiceAudioCues.makeWAVContainer(
                    pcm16Mono: AudioPCMConverter.floatsToPCM16Data(pcmSnapshot),
                    sampleRate: 16_000,
                    channels: 1
                )
                if let refined = try? await self.openJarvis.transcribeWAV(audioData: wav, language: langHint, hotwords: hotwords),
                   !refined.isEmpty,
                   refined.lowercased().contains("wisd") || refined.lowercased().contains("antigrav") || refined.lowercased().contains("codex") {
                    let renorm = ContextualTranscriptNormalizer.normalize(refined, activeProjectName: self.memoryStore.workspaceContext.projectName).normalizedTranscript
                    self.handleFinalizedAutonomousTurn(renorm)
                } else {
                    self.handleFinalizedAutonomousTurn(finalUtterance)
                }
            }
            return
        }

        handleFinalizedAutonomousTurn(finalUtterance)
    }

    private func handleFinalizedAutonomousTurn(_ utterance: String) {
        memoryStore.appendUserTurn(utterance, providerID: resolvedPipeline.effectiveProvider.rawValue)
        let liveTasks = activeTasksProvider?() ?? activeTasksSnapshot
        activeTasksSnapshot = liveTasks

        let lower = utterance.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower == "silenciar microfone" || lower == "mute microphone" || lower == "mutar microfone" {
            if !isMuted { toggleMute() }
            return
        }
        if lower == "ativar microfone" || lower == "unmute microphone" || lower == "desmutar microfone" {
            if isMuted { toggleMute() }
            return
        }
        if lower == "encerrar conversa por voz" || lower == "stop voice mode" || lower == "fechar modo de voz" {
            let bye = behavior.languageVariant.bcp47LanguagePrefix == "en" ? "Closing voice mode. Talk soon!" : "Encerrando a conversa por voz. Até já!"
            emitImmediateLocalSpeechReply(bye, userUtterance: utterance)
            let expectedSess = sessionGenerationID
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let self, self.sessionGenerationID == expectedSess else { return }
                self.stopSession(clearUI: true)
            }
            return
        }

        runOpenJarvisStreamingTurn(utterance: utterance)
    }

    private func emitImmediateLocalSpeechReply(_ reply: String, userUtterance: String, persistToChat: Bool = true) {
        let clean = VoicePresentationEngine.stripRepetitiveOpeners(reply)
        recordPresentedSpokenTextForTelemetry(clean)
        beginAssistantTurnResponseTracking(userSpeechEndNs: turnUserSpeechEndNs)
        handleStreamingAssistantDelta(clean)
        finishAssistantResponse(fullMarkdownText: clean)
        memoryStore.appendAssistantTurn(clean, providerID: "openjarvis", wasInterruptedByBargeIn: false)
        onTranscriptDeltaUI?("assistant", clean)
        if persistToChat {
            onRecordLocalExchangeToChat?(userUtterance, clean)
        }
    }

    /// Executes a turn natively through OpenJarvis streaming orchestrator + 12 WisdAI tools.
    @discardableResult
    public func submitVoiceTurnAsync(_ rawUtterance: String) async -> (reply: String, toolCalls: [(tool: String, success: Bool, preview: String)]) {
        let norm = ContextualTranscriptNormalizer.normalize(
            rawUtterance,
            activeProjectName: memoryStore.workspaceContext.projectName
        )
        let utterance = norm.normalizedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !utterance.isEmpty else { return ("", []) }
        memoryStore.appendUserTurn(utterance, providerID: "openjarvis")
        return await executeOpenJarvisTurnAndWait(utterance: utterance)
    }

    private func runOpenJarvisStreamingTurn(utterance: String) {
        openJarvisTurnTask?.cancel()
        openJarvis.cancelActiveVoiceTurnAudioOnly()
        let expectedSession = sessionGenerationID
        let expectedTurn = activeTurnGenerationID
        openJarvisTurnTask = Task { @MainActor [weak self] in
            guard let self,
                  self.sessionGenerationID == expectedSession,
                  self.activeTurnGenerationID == expectedTurn else { return }
            _ = await self.executeOpenJarvisTurnAndWait(utterance: utterance)
        }
    }

    private func executeOpenJarvisTurnAndWait(utterance: String) async -> (reply: String, toolCalls: [(tool: String, success: Bool, preview: String)]) {
        beginAssistantTurnResponseTracking(userSpeechEndNs: turnUserSpeechEndNs)
        clauseEnqueueCounter = 0

        let expectedSession = sessionGenerationID
        let expectedTurn = activeTurnGenerationID
        let portable = memoryStore.exportPortableSnapshot(targetProviderID: "openjarvis")
        var historyPayload: [[String: String]] = []
        for turn in portable.recentTurns {
            if turn.role == "user" && turn.text == utterance { continue }
            historyPayload.append(["role": turn.role == "assistant" ? "assistant" : "user", "content": turn.text])
        }
        if historyPayload.last?["role"] == "user" && historyPayload.last?["content"] == utterance {
            historyPayload.removeLast()
        }

        let liveTasks = activeTasksProvider?() ?? activeTasksSnapshot
        activeTasksSnapshot = liveTasks
        var workspaceDict: [String: Any] = workspaceSnapshotProvider?() ?? [:]
        if workspaceDict.isEmpty {
            workspaceDict = [
                "project_id": memoryStore.workspaceContext.projectID?.uuidString ?? "",
                "project_name": memoryStore.workspaceContext.projectName ?? "",
                "project_path": memoryStore.workspaceContext.absoluteDirectoryPath ?? "",
                "git_branch": memoryStore.workspaceContext.resolvedProject?.gitBranch ?? "",
                "active_agent": memoryStore.workspaceContext.activeExecutionAgent,
                "active_model": memoryStore.workspaceContext.selectedModelID ?? "",
                "active_effort": memoryStore.workspaceContext.selectedEffortTitle ?? "",
            ]
        }
        workspaceDict["active_tasks_count"] = liveTasks.count

        final class TurnBox: @unchecked Sendable {
            private let lock = NSLock()
            private var _fullText = ""
            private var _tools: [(tool: String, success: Bool, preview: String)] = []
            private var _hadSentenceEvents = false
            private var _cancelled = false
            private var _errorMessage: String?
            private var _lastUITask: Task<Void, Never>?

            func appendTool(tool: String, success: Bool, preview: String) {
                lock.withLock { _tools.append((tool: tool, success: success, preview: preview)) }
            }
            func markSentenceReceived() {
                lock.withLock { _hadSentenceEvents = true }
            }
            func setFullText(_ value: String) {
                lock.withLock { _fullText = value }
            }
            func markCancelled() {
                lock.withLock { _cancelled = true }
            }
            func setError(_ msg: String) {
                lock.withLock { _errorMessage = msg }
            }
            func enqueueUI(_ work: @escaping @MainActor () -> Void) {
                lock.withLock {
                    let prev = _lastUITask
                    let next = Task { @MainActor in
                        await prev?.value
                        work()
                    }
                    _lastUITask = next
                }
            }
            func awaitPendingUI() async {
                let pending = lock.withLock { _lastUITask }
                await pending?.value
            }
            func snapshot() -> (fullText: String, tools: [(tool: String, success: Bool, preview: String)], hadSentenceEvents: Bool, cancelled: Bool, errorMessage: String?) {
                lock.withLock {
                    (fullText: _fullText, tools: _tools, hadSentenceEvents: _hadSentenceEvents, cancelled: _cancelled, errorMessage: _errorMessage)
                }
            }
        }
        let box = TurnBox()

        do {
            try await openJarvis.streamVoiceTurn(
                userText: utterance,
                history: historyPayload,
                personaID: voiceIdentity.persona.rawValue,
                preferredLanguage: behavior.languageVariant.bcp47LanguagePrefix == "en" ? "en" : "pt-BR",
                workspaceSnapshot: workspaceDict
            ) { [weak self] event in
                switch event {
                case .started(_, let lang):
                    box.enqueueUI {
                        guard let self,
                              self.sessionGenerationID == expectedSession,
                              self.activeTurnGenerationID == expectedTurn else { return }
                        let prefix = lang.lowercased()
                        if prefix.hasPrefix("en") && self.behavior.languageVariant.bcp47LanguagePrefix != "en" {
                            // Keep spoken reply aligned without mutating user persisted setting unnecessarily
                        }
                    }
                case .toolStart(let tool, let args):
                    box.enqueueUI {
                        guard let self,
                              self.sessionGenerationID == expectedSession,
                              self.activeTurnGenerationID == expectedTurn else { return }
                        if self.isVoiceSessionActive {
                            self.transitionState(.consultingAgent, reason: "Executando ferramenta \(tool)")
                        }
                        self.telemetry.recordPipelineTrace(
                            stage: .retrievedContext,
                            sessionToken: "\(expectedSession)",
                            turnEpoch: expectedTurn,
                            detail: "Tool start: \(tool) \(args)"
                        )
                    }
                case .toolResult(let tool, let ok, let preview):
                    box.appendTool(tool: tool, success: ok, preview: preview)
                    box.enqueueUI {
                        guard let self,
                              self.sessionGenerationID == expectedSession,
                              self.activeTurnGenerationID == expectedTurn else { return }
                        self.telemetry.recordPipelineTrace(
                            stage: .retrievedContext,
                            sessionToken: "\(expectedSession)",
                            turnEpoch: expectedTurn,
                            detail: "Tool result: \(tool) ok=\(ok)"
                        )
                    }
                case .tokenDelta(let delta):
                    box.enqueueUI {
                        guard let self,
                              self.sessionGenerationID == expectedSession,
                              self.activeTurnGenerationID == expectedTurn else { return }
                        if !self.firstLLMDeltaRecorded && self.turnSubmittedAtNs > 0 {
                            self.firstLLMDeltaRecorded = true
                            let ms = Double(DispatchTime.now().uptimeNanoseconds &- self.turnSubmittedAtNs) / 1_000_000.0
                            self.telemetry.recordLLMFirstChunkLatency(ms: ms)
                        }
                        self.liveAssistantMarkdownText += delta
                    }
                case .sentence(_, let sentenceText):
                    box.markSentenceReceived()
                    let cleanClause = VoicePresentationEngine.stripRepetitiveOpeners(sentenceText)
                    box.enqueueUI {
                        guard let self,
                              self.sessionGenerationID == expectedSession,
                              self.activeTurnGenerationID == expectedTurn else { return }
                        if !self.firstClauseRecorded && self.turnSubmittedAtNs > 0 {
                            self.firstClauseRecorded = true
                            let clauseMs = Double(DispatchTime.now().uptimeNanoseconds &- self.turnSubmittedAtNs) / 1_000_000.0
                            self.telemetry.recordFirstClauseLatency(ms: clauseMs)
                        }
                        if self.isVoiceSessionActive {
                            self.enqueueAdaptedSpeechClause(cleanClause)
                        }
                    }
                case .done(_, let fullText, _, _):
                    box.setFullText(VoicePresentationEngine.stripRepetitiveOpeners(fullText))
                case .cancelled:
                    box.markCancelled()
                case .error(let msg):
                    box.setError(msg)
                }
            }
        } catch {
            let snap = box.snapshot()
            if !Task.isCancelled && !snap.cancelled {
                box.setError(error.localizedDescription)
            }
        }

        await box.awaitPendingUI()
        let snap = box.snapshot()
        guard !Task.isCancelled && !snap.cancelled else { return (snap.fullText, snap.tools) }

        var finalFullText = snap.fullText
        if let err = snap.errorMessage, finalFullText.isEmpty {
            let errReply = behavior.languageVariant.bcp47LanguagePrefix == "en"
                ? "OpenJarvis could not complete this request right now: \(err)"
                : "O runtime OpenJarvis encontrou um problema ao responder: \(err)"
            finalFullText = errReply
            if isVoiceSessionActive {
                enqueueAdaptedSpeechClause(errReply)
            }
        } else if !snap.hadSentenceEvents && !finalFullText.isEmpty && isVoiceSessionActive {
            enqueueAdaptedSpeechClause(finalFullText)
        }

        let finalVisibleReply = finalFullText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalVisibleReply.isEmpty {
            recordPresentedSpokenTextForTelemetry(finalVisibleReply)
            telemetry.recordPipelineTrace(
                stage: .textReply,
                sessionToken: "\(expectedSession)",
                turnEpoch: expectedTurn,
                detail: finalVisibleReply
            )
            memoryStore.appendAssistantTurn(finalVisibleReply, providerID: "openjarvis", wasInterruptedByBargeIn: false)
            onTranscriptDeltaUI?("assistant", finalVisibleReply)
            onRecordLocalExchangeToChat?(utterance, finalVisibleReply)
        }
        return (finalVisibleReply, snap.tools)
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
            let isSpeakingOut = self.state == .assistantSpeaking || self.audioEngine.isAuxiliaryPlaybackActive
            let playRef = self.audioEngine.combinedPlaybackReferenceState
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
                isAssistantSpeaking: self.state == .assistantSpeaking
            )

            if vadResult.isSpeechActive {
                self.lastAcousticSpeechTimestampNs = nowNs
                self.lastMicNonSilenceTimestampNs = nowNs
                if self.userSpeechStartedAtNs == 0 {
                    self.userSpeechStartedAtNs = nowNs
                }
                self.lastAcousticFeatures = self.acousticExtractor.processAudioChunk(
                    samples: samples,
                    sampleRate: sampleRate,
                    levels: levels
                )
                let resampled16k = abs(sampleRate - 16_000) < 1.0
                    ? samples
                    : AudioPCMConverter.resampleLinear(samples: samples, fromSampleRate: sampleRate, toSampleRate: 16_000)
                self.captureTurnSamples16k.append(contentsOf: resampled16k)
                if self.captureTurnSamples16k.count > 400_000 {
                    self.captureTurnSamples16k.removeFirst(self.captureTurnSamples16k.count - 400_000)
                }
                if self.state == .listening {
                    self.transitionState(.userSpeaking, reason: "Fala detectada pelo VAD")
                }
            }

            if vadResult.isIntentionalBargeIn {
                self.performManualOrVADBarageIn(
                    reason: "Barge-in acústico (<150ms)",
                    triggerOriginNs: self.vadTracker.currentSpeechOnsetUptimeNs ?? nowNs
                )
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
            guard let self else { return }
            let telSnap = self.audioEngine.telemetrySnapshot()
            self.telemetry.log(
                category: "AudioDevice",
                message: "Topologia atualizada: state=\(telSnap.lifecycleState.rawValue), graph='\(telSnap.nodeGraphSummary)', op=\(telSnap.lastOperation.rawValue)."
            )
            if telSnap.lifecycleState == .failed {
                let err = telSnap.lastFailure?.formattedSummary ?? telSnap.lastFaultDescription ?? "Falha de hardware/rota após atualização de áudio."
                self.activeBannerNotice = err
                self.updateComponentStatus(.audioCapture, state: .error, engineOrModel: telSnap.inputDeviceName, lastError: err)
                self.updateComponentStatus(.audioPlayback, state: .error, engineOrModel: telSnap.outputDeviceName, lastError: err)
                if self.isVoiceSessionActive {
                    self.transitionState(.error, reason: "Falha de rota CoreAudio")
                }
            } else {
                let degraded = (telSnap.lifecycleState == .degradedCompatibility) || !telSnap.vpioActive
                self.updateComponentStatus(
                    .audioCapture,
                    state: degraded ? .degraded : .ready,
                    engineOrModel: "\(telSnap.inputDeviceName) (\(Int(telSnap.inputSampleRateHz))Hz/\(telSnap.inputChannels)ch · \(telSnap.processingStatus.rawValue))",
                    lastError: self.audioEngine.lastFault
                )
                self.updateComponentStatus(
                    .audioPlayback,
                    state: telSnap.isSplitEngineCompatibility ? .degraded : .ready,
                    engineOrModel: "\(telSnap.outputDeviceName) (\(Int(telSnap.outputSampleRateHz))Hz/\(telSnap.outputChannels)ch)",
                    lastError: telSnap.isSplitEngineCompatibility ? self.audioEngine.lastFault : nil
                )
            }
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
        let cleanClause = spokenClause.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanClause.isEmpty else { return }
        audioEngine.flushAuxiliaryVocalizationOnly()

        let idx = clauseEnqueueCounter
        clauseEnqueueCounter += 1
        queuedSpeechChunks.append((text: cleanClause, originalIndex: idx))
        liveAssistantTranscript = [liveAssistantTranscript, cleanClause]
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

            let gain = Float(self.identityManager.activeDSPParameters.outputVolume)

            while !Task.isCancelled,
                  self.sessionGenerationID == expectedSession,
                  gateRef.isCurrent(expectedPlayback),
                  !self.queuedSpeechChunks.isEmpty {
                let nextChunk = self.queuedSpeechChunks.removeFirst()
                let tts = self.selectActiveTTSProvider()
                let rateMul = self.effectiveSpeechRate()
                let silenceScale = Float(max(0.10, min(0.40, 0.20 * self.behavior.pauseScale)))
                let ttsStartNs = DispatchTime.now().uptimeNanoseconds
                let latencyGate = ChunkLatencyGate()

                self.telemetry.recordPipelineTrace(
                    stage: .vocalSynthesis,
                    sessionToken: "\(expectedSession)",
                    turnEpoch: self.activeTurnGenerationID,
                    detail: "[\(tts.providerID) · \(String(format: "%.2fx", rateMul))] \(nextChunk.text)"
                )

                final class TurnAudioProbeBox: @unchecked Sendable {
                    private let lock = NSLock()
                    private var samples: [Float] = []
                    func append(_ xs: [Float]) {
                        lock.withLock {
                            if samples.count < 48_000 {
                                samples.append(contentsOf: xs.prefix(max(0, 48_000 - samples.count)))
                            }
                        }
                    }
                    func snapshot() -> [Float] { lock.withLock { samples } }
                }
                let probeBox = TurnAudioProbeBox()
                let deliverAudioChunk: @Sendable ([Float], String) -> Void = { [weak self] floats24k, spanLabel in
                    guard let self,
                          !Task.isCancelled,
                          gateRef.isCurrent(expectedPlayback),
                          !floats24k.isEmpty else { return }
                    let shaped24k: [Float] = abs(gain - 1.0) <= 0.01
                        ? floats24k
                        : floats24k.map { max(-0.98, min(0.98, $0 * gain)) }
                    probeBox.append(shaped24k)
                    let nowNs = DispatchTime.now().uptimeNanoseconds
                    if latencyGate.claim() {
                        let ttsFirstChunkMs = Double(nowNs &- ttsStartNs) / 1_000_000.0
                        Task { @MainActor [weak self] in
                            guard let self,
                                  self.sessionGenerationID == expectedSession,
                                  gateRef.isCurrent(expectedPlayback) else { return }
                            self.hasLocalTTSWarmedUp = true
                            self.telemetry.recordTTSFirstAudioLatency(ms: ttsFirstChunkMs)
                            if !self.firstAudioChunkRecorded && self.turnSubmittedAtNs > 0 {
                                self.firstAudioChunkRecorded = true
                                let e2eMs = Double(nowNs &- self.turnSubmittedAtNs) / 1_000_000.0
                                self.telemetry.recordEndToEndResponseLatency(ms: e2eMs)
                            }
                            if !self.firstAudiblePlaybackRecorded {
                                self.firstAudiblePlaybackRecorded = true
                                self.monitorFirstAudiblePlayback(
                                    expectedSession: expectedSession,
                                    expectedPlayback: expectedPlayback,
                                    turnCommitNs: self.turnSubmittedAtNs,
                                    speechEndNs: self.turnUserSpeechEndNs
                                )
                            }
                        }
                    }
                    _ = self.audioEngine.outputJitterBuffer.pushFloatSamples(shaped24k, transcriptText: spanLabel)
                }

                do {
                    let effLang = self.effectiveSynthesisLanguage(forText: nextChunk.text, configured: self.behavior.languageVariant)
                    let voicePref = self.effectiveTTSVoicePreference(forText: nextChunk.text)
                    if let supertonic = tts as? SupertonicNeuralTTSProvider {
                        try await supertonic.synthesizeChunk(
                            nextChunk.text,
                            language: effLang,
                            voicePreference: voicePref,
                            rate: rateMul,
                            silenceScale: silenceScale,
                            flowSteps: self.identityManager.config.design.flowMatchingSteps,
                            targetSampleRate: 24_000,
                            onAudioFloats: deliverAudioChunk
                        )
                    } else if let kokoro = tts as? KokoroNeuralTTSProvider {
                        try await kokoro.synthesizeChunk(
                            nextChunk.text,
                            language: effLang,
                            voicePreference: voicePref,
                            rate: rateMul,
                            silenceScale: silenceScale,
                            onAudioFloats24k: deliverAudioChunk
                        )
                    } else if let piper = tts as? SherpaVitsPiperTTSProvider {
                        try await piper.synthesizeChunk(
                            nextChunk.text,
                            language: effLang,
                            voicePreference: voicePref,
                            rate: rateMul,
                            silenceScale: silenceScale,
                            onAudioFloats24k: deliverAudioChunk
                        )
                    } else if let apple = tts as? AppleNaturalPCMStreamingTTSProvider {
                        try await apple.synthesizeChunk(
                            nextChunk.text,
                            language: effLang,
                            voicePreference: voicePref,
                            rate: rateMul,
                            pitchMultiplier: 1.0,
                            onAudioFloats24k: deliverAudioChunk
                        )
                    } else {
                        try await tts.synthesizeChunk(
                            nextChunk.text,
                            language: effLang,
                            voicePreference: voicePref,
                            rate: rateMul,
                            onAudioFloats24k: deliverAudioChunk
                        )
                    }
                    let fullClauseSynthMs = Double(DispatchTime.now().uptimeNanoseconds &- ttsStartNs) / 1_000_000.0
                    self.turnTTSTotalSynthAccumMs += fullClauseSynthMs
                    if self.queuedSpeechChunks.isEmpty {
                        self.telemetry.recordTTSTotalSynthesisLatency(ms: self.turnTTSTotalSynthAccumMs)
                        self.turnTTSTotalSynthAccumMs = 0
                    }
                    let measuredF0 = AcousticFeatureExtractor.measureMedianFundamentalFrequencyHz(samples: probeBox.snapshot(), sampleRate: 24_000)
                    await MainActor.run {
                        self.recordProviderExecutionTruth(
                            provider: tts,
                            voicePreference: voicePref,
                            language: self.behavior.languageVariant,
                            synthMs: fullClauseSynthMs,
                            measuredF0Hz: measuredF0,
                            fallbackOccurred: false
                        )
                    }
                } catch {
                    let isOptionalFallback = tts.requiresPaidOptIn || (selectedTTSEngine == .autoLocal && tts.providerID != appleTTS.providerID)
                    await MainActor.run {
                        self.telemetry.log(category: "TTS", message: "Erro/Fallback TTS (\(tts.providerID)): \(error.localizedDescription)")
                        if tts.providerID == self.kokoroTTS.providerID || tts.providerID == self.supertonicTTS.providerID {
                            self.updateComponentStatus(.tts, state: .degraded, engineOrModel: "\(tts.providerID) falhou -> Apple Natural", lastError: error.localizedDescription)
                        }
                    }
                    if isOptionalFallback && gateRef.isCurrent(expectedPlayback) {
                        let fallbackPref = self.effectiveTTSVoicePreference()
                        try? await self.appleTTS.synthesizeChunk(
                            nextChunk.text,
                            language: self.behavior.languageVariant,
                            voicePreference: fallbackPref,
                            rate: self.effectiveSpeechRate()
                        ) { [weak self] floats24k, spanLabel in
                            guard let self, !Task.isCancelled, gateRef.isCurrent(expectedPlayback), !floats24k.isEmpty else { return }
                            _ = self.audioEngine.outputJitterBuffer.pushFloatSamples(floats24k, transcriptText: spanLabel)
                        }
                        let fbSynthMs = Double(DispatchTime.now().uptimeNanoseconds &- ttsStartNs) / 1_000_000.0
                        await MainActor.run {
                            self.recordProviderExecutionTruth(
                                provider: self.appleTTS,
                                voicePreference: fallbackPref,
                                language: self.behavior.languageVariant,
                                synthMs: fbSynthMs,
                                measuredF0Hz: nil,
                                fallbackOccurred: true,
                                overrideNote: "Fallback para Apple Natural após falha em \(tts.providerID): \(error.localizedDescription)"
                            )
                        }
                    }
                }
            }
        }
    }

    private func monitorFirstAudiblePlayback(
        expectedSession: UInt64,
        expectedPlayback: UInt64,
        turnCommitNs: UInt64,
        speechEndNs: UInt64
    ) {
        let hwLatencyMs = audioEngine.currentOutputHardwareLatencyMs
        let gateRef = playbackGate
        Task { @MainActor [weak self] in
            for _ in 0..<60 {
                guard let self,
                      self.sessionGenerationID == expectedSession,
                      gateRef.isCurrent(expectedPlayback) else { return }
                if let firstRenderNs = self.audioEngine.outputJitterBuffer.firstRenderTimestampNsForResponse() {
                    let fromCommitMs = (turnCommitNs > 0 && firstRenderNs >= turnCommitNs)
                        ? Double(firstRenderNs &- turnCommitNs) / 1_000_000.0 + hwLatencyMs
                        : hwLatencyMs
                    let fromSpeechEndMs = (speechEndNs > 0 && firstRenderNs >= speechEndNs)
                        ? Double(firstRenderNs &- speechEndNs) / 1_000_000.0 + hwLatencyMs
                        : nil
                    self.telemetry.recordFirstAudiblePlaybackLatency(fromCommitMs: fromCommitMs, fromSpeechEndMs: fromSpeechEndMs)
                    return
                }
                try? await Task.sleep(nanoseconds: 6_000_000)
            }
        }
    }

    public func selectActiveTTSProvider() -> StreamingTextToSpeechProvider {
        switch resolvedPipeline.effectiveProvider {
        case .hybridDeepgramElevenLabs:
            return elevenLabsTTS
        case .hybridOpenAITTS:
            return openAITTS
        default:
            break
        }
        switch selectedTTSEngine {
        case .supertonic3:
            if supertonicTTS.isReadyOnDisk {
                return supertonicTTS
            }
            if kokoroTTS.isReadyOnDisk && VoiceTTSEngineKind.kokoro82M.supportsLanguage(behavior.languageVariant) {
                return kokoroTTS
            }
            return appleTTS
        case .kokoro82M:
            if kokoroTTS.isReadyOnDisk && VoiceTTSEngineKind.kokoro82M.supportsLanguage(behavior.languageVariant) {
                return kokoroTTS
            }
            if behavior.languageVariant == .portuguesePT && supertonicTTS.isReadyOnDisk {
                return supertonicTTS
            }
            return appleTTS
        case .sherpaPiperVits:
            if sherpaPiperTTS.isReadyOnDisk(for: behavior.languageVariant) {
                return sherpaPiperTTS
            }
            if supertonicTTS.isReadyOnDisk {
                return supertonicTTS
            }
            if kokoroTTS.isReadyOnDisk && VoiceTTSEngineKind.kokoro82M.supportsLanguage(behavior.languageVariant) {
                return kokoroTTS
            }
            return appleTTS
        case .cosyVoice2, .chatterbox, .sesameCSM, .diaTTS:
            if mlxExpressiveTTS.isServerReachable {
                return mlxExpressiveTTS
            }
            if supertonicTTS.isReadyOnDisk {
                return supertonicTTS
            }
            if kokoroTTS.isReadyOnDisk && VoiceTTSEngineKind.kokoro82M.supportsLanguage(behavior.languageVariant) {
                return kokoroTTS
            }
            return appleTTS
        case .autoLocal:
            if supertonicTTS.isReadyOnDisk && !identityManager.config.speakerId.hasPrefix("pf_") && !identityManager.config.speakerId.hasPrefix("pm_") && !identityManager.config.speakerId.hasPrefix("bm_") && !identityManager.config.speakerId.hasPrefix("af_") {
                return supertonicTTS
            }
            if kokoroTTS.isReadyOnDisk && VoiceTTSEngineKind.kokoro82M.supportsLanguage(behavior.languageVariant) {
                return kokoroTTS
            }
            if supertonicTTS.isReadyOnDisk {
                return supertonicTTS
            }
            if sherpaPiperTTS.isReadyOnDisk(for: behavior.languageVariant) {
                return sherpaPiperTTS
            }
            return appleTTS
        default:
            return appleTTS
        }
    }

    private func recordProviderExecutionTruth(
        provider: StreamingTextToSpeechProvider,
        voicePreference: String,
        language: VoiceLanguageVariant,
        synthMs: Double,
        measuredF0Hz: Double?,
        fallbackOccurred: Bool,
        overrideNote: String? = nil
    ) {
        if provider.providerID == supertonicTTS.providerID, let info = supertonicTTS.lastExecutionInfo() {
            identityManager.recordInferredSynthesis(VoiceInferredRuntimeSnapshot(
                actualEngineId: VoiceTTSEngineKind.supertonic3.rawValue,
                actualModelId: info.modelID,
                actualSpeakerId: info.speakerID,
                actualNumericSID: info.numericSID,
                actualLanguage: info.langCode,
                actualSampleRateHz: info.sampleRateHz,
                estimatedF0Hz: measuredF0Hz,
                synthLatencyMs: info.synthMs,
                fallbackOccurred: fallbackOccurred,
                note: overrideNote,
                updatedAt: Date()
            ))
            return
        }
        if provider.providerID == kokoroTTS.providerID, let info = kokoroTTS.lastExecutionInfo() {
            identityManager.recordInferredSynthesis(VoiceInferredRuntimeSnapshot(
                actualEngineId: VoiceTTSEngineKind.kokoro82M.rawValue,
                actualModelId: info.modelID,
                actualSpeakerId: info.speakerID,
                actualNumericSID: info.numericSID,
                actualLanguage: info.langCode,
                actualSampleRateHz: info.sampleRateHz,
                estimatedF0Hz: measuredF0Hz,
                synthLatencyMs: info.synthMs,
                fallbackOccurred: fallbackOccurred,
                note: overrideNote,
                updatedAt: Date()
            ))
            return
        }
        if provider.providerID == appleTTS.providerID {
            let resolved = appleTTS.lastResolvedVoiceSnapshot
            let warn = appleTTS.lastSelectionWarning
            identityManager.recordInferredSynthesis(VoiceInferredRuntimeSnapshot(
                actualEngineId: VoiceTTSEngineKind.appleNaturalPCM.rawValue,
                actualModelId: "apple-natural-pcm",
                actualSpeakerId: resolved?.name ?? voicePreference,
                actualNumericSID: nil,
                actualLanguage: language.rawValue,
                actualSampleRateHz: 24_000,
                estimatedF0Hz: measuredF0Hz,
                synthLatencyMs: synthMs,
                fallbackOccurred: fallbackOccurred || (selectedTTSEngine != .appleNaturalPCM && selectedTTSEngine != .autoLocal),
                note: overrideNote ?? warn,
                updatedAt: Date()
            ))
            return
        }
        identityManager.recordInferredSynthesis(VoiceInferredRuntimeSnapshot(
            actualEngineId: provider.providerID,
            actualModelId: provider.providerID,
            actualSpeakerId: voicePreference,
            actualNumericSID: nil,
            actualLanguage: language.rawValue,
            actualSampleRateHz: 24_000,
            estimatedF0Hz: measuredF0Hz,
            synthLatencyMs: synthMs,
            fallbackOccurred: fallbackOccurred,
            note: overrideNote,
            updatedAt: Date()
        ))
    }

    public func applyConversationProfilePreset(_ preset: VoiceConversationProfilePreset) {
        behavior = behavior.applyingPreset(preset)
    }

    private func finalizePreviewAudio(
        samples: [Float],
        sampleRate: Int,
        dspParameters: VoiceDSPParameters?,
        saveToURL: URL?,
        playAudio: Bool,
        playerLabel: String
    ) throws -> (samples: [Float], wavData: Data, f0Hz: Double?) {
        let gain = Float((dspParameters ?? identityManager.activeDSPParameters).outputVolume)
        let finalSamples: [Float] = abs(gain - 1.0) <= 0.01
            ? samples
            : samples.map { max(-0.98, min(0.98, $0 * gain)) }
        let f0 = AcousticFeatureExtractor.measureMedianFundamentalFrequencyHz(samples: finalSamples, sampleRate: Double(sampleRate))
        let wav = CodexVoiceAudioCues.makeWAVContainer(
            pcm16Mono: AudioPCMConverter.floatsToPCM16Data(finalSamples),
            sampleRate: sampleRate,
            channels: 1
        )
        if let saveToURL {
            try previewPlayer.saveWAV(samples: finalSamples, sampleRate: sampleRate, to: saveToURL)
        }
        if playAudio {
            previewPlayer.playWAVData(wav, label: playerLabel)
        }
        return (finalSamples, wav, f0)
    }

    public func previewCurrentConfiguredVoice(
        sampleText: String? = nil,
        playAudio: Bool = true
    ) async -> (ok: Bool, engineUsed: String, sampleRate: Int, synthMs: Double, wavData: Data?, detail: String) {
        let lang = effectiveSynthesisLanguage(forText: sampleText, configured: behavior.languageVariant)
        let text = sampleText ?? {
            switch lang {
            case .englishGB:
                return "Very well. Checking the calibrated \(voiceIdentity.persona.shortName) vocal channel."
            case .englishUS:
                return "Ready when you are. Testing the \(voiceIdentity.persona.shortName) voice configuration."
            case .spanishES:
                return "Perfecto. Comprobando la voz configurada de \(voiceIdentity.persona.shortName)."
            case .portuguesePT:
                return "Com certeza. A testar a identidade vocal \(voiceIdentity.persona.shortName)."
            case .portugueseBR:
                if voiceIdentity.persona == .ultronBR {
                    return "Ah, interessante. Deixe-me verificar isso para você. O canal Ultron BR está calibrado com precisão."
                }
                return voiceIdentity.persona == .jarvis
                    ? "Perfeitamente. Canal vocal JARVIS calibrado e pronto para conversação."
                    : "Olá! Esta é a voz configurada agora para conversarmos no WisdAI."
            }
        }()
        return await synthesizeAndPreviewVoiceSample(
            text: text,
            ttsEngine: selectedTTSEngine,
            kokoroPreset: effectiveKokoroPreset(for: lang),
            language: lang,
            rate: effectiveSpeechRate(),
            playAudio: playAudio,
            applyBehaviorComposition: false
        )
    }

    public func synthesizeAndPreviewVoiceSample(
        text: String,
        ttsEngine: VoiceTTSEngineKind,
        kokoroPreset: KokoroVoicePreset,
        language: VoiceLanguageVariant,
        rate: Float? = nil,
        playAudio: Bool = true,
        saveToURL: URL? = nil,
        applyBehaviorComposition: Bool = true,
        supertonicPresetOverride: SupertonicVoicePreset? = nil,
        dspOverride: VoiceDSPParameters? = nil
    ) async -> (ok: Bool, engineUsed: String, sampleRate: Int, synthMs: Double, wavData: Data?, detail: String) {
        let targetLang = effectiveSynthesisLanguage(forText: text, configured: language)
        let shouldUseSupertonic = ttsEngine == .supertonic3 ||
            (ttsEngine == .autoLocal && supertonicTTS.isReadyOnDisk && (identityManager.config.speakerId.hasPrefix("supertonic:") || targetLang == .portuguesePT))

        let adapted = VoiceResponseAdapter.adaptForSpeech(
            text,
            profile: behavior,
            customDictionary: customPronunciation
        ).spokenText
        let spokenText = adapted.isEmpty ? text : adapted
        let effectiveRate = rate ?? effectiveSpeechRate()
        let flowSteps = identityManager.config.design.flowMatchingSteps

        if shouldUseSupertonic {
            guard supertonicTTS.isReadyOnDisk else {
                return (false, "Supertonic-3", 44_100, 0, nil, "Pesos Supertonic-3 ainda não estão instalados. Baixe no Catálogo de Modelos primeiro.")
            }
            let supPreset = supertonicPresetOverride ?? SupertonicVoicePreset.from(identifier: effectiveTTSVoicePreference(forText: spokenText)) ?? selectedSupertonicPreset
            do {
                let res = try await supertonicTTS.synthesizeStandaloneSamples(
                    text: spokenText,
                    language: targetLang,
                    preset: supPreset,
                    rate: effectiveRate,
                    flowSteps: flowSteps,
                    silenceScale: 0.20,
                    targetSampleRate: 44_100
                )
                let pkg = try finalizePreviewAudio(
                    samples: res.samples,
                    sampleRate: res.sampleRate,
                    dspParameters: dspOverride,
                    saveToURL: saveToURL,
                    playAudio: playAudio,
                    playerLabel: "Supertonic-3 \(supPreset.rawValue)"
                )
                recordProviderExecutionTruth(
                    provider: supertonicTTS,
                    voicePreference: supPreset.rawValue,
                    language: targetLang,
                    synthMs: res.synthMs,
                    measuredF0Hz: pkg.f0Hz,
                    fallbackOccurred: false
                )
                modelAssetManager.setRuntimeActivity(modelID: VoiceModelCatalog.supertonic3Int8ModelID, state: .operational)
                let durSec = Double(pkg.samples.count) / Double(res.sampleRate)
                let f0Note = pkg.f0Hz.map { String(format: " · F0=%.0f Hz", $0) } ?? ""
                return (true, "Supertonic-3 (\(supPreset.rawValue))", res.sampleRate, res.synthMs, pkg.wavData, String(format: "%.2fs gerados em %.0f ms (@ 44.1kHz, steps=%d%@)", durSec, res.synthMs, flowSteps, f0Note))
            } catch {
                return (false, "Supertonic-3", 44_100, 0, nil, error.localizedDescription)
            }
        }

        if ttsEngine == .sherpaPiperVits {
            guard sherpaPiperTTS.isReadyOnDisk(for: targetLang) else {
                return (false, "Piper VITS", 24_000, 0, nil, "Pesos Piper VITS para \(targetLang.displayName) ainda não instalados em Models/vits-piper-*.")
            }
            final class PiperBox: @unchecked Sendable {
                private let lock = NSLock()
                private var samples: [Float] = []
                func append(_ floats: [Float]) { lock.withLock { samples.append(contentsOf: floats) } }
                func snapshot() -> [Float] { lock.withLock { samples } }
            }
            let pBox = PiperBox()
            let t0 = DispatchTime.now().uptimeNanoseconds
            do {
                try await sherpaPiperTTS.synthesizeChunk(spokenText, language: targetLang, voicePreference: "piper", rate: effectiveRate) { floats, _ in
                    pBox.append(floats)
                }
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000.0
                let pkg = try finalizePreviewAudio(
                    samples: pBox.snapshot(),
                    sampleRate: 24_000,
                    dspParameters: dspOverride,
                    saveToURL: saveToURL,
                    playAudio: playAudio,
                    playerLabel: "Piper VITS (\(targetLang.shortCode))"
                )
                let durSec = Double(pkg.samples.count) / 24_000.0
                return (!pkg.samples.isEmpty, "Piper VITS ONNX", 24_000, elapsed, pkg.wavData, String(format: "%.2fs gerados em %.0f ms (%d amostras @ 24kHz)", durSec, elapsed, pkg.samples.count))
            } catch {
                return (false, "Piper VITS ONNX", 24_000, 0, nil, error.localizedDescription)
            }
        }

        if ttsEngine == .chatterbox || ttsEngine == .cosyVoice2 || ttsEngine == .sesameCSM || ttsEngine == .diaTTS {
            let reachable = await mlxExpressiveTTS.probeServer()
            guard reachable else {
                return (false, ttsEngine.displayName, 24_000, 0, nil, "Servidor mlx-audio loopback não responde em 127.0.0.1:\(mlxExpressiveTTS.port). Inicie o servidor local para avaliar este motor.")
            }
            final class MLXBox: @unchecked Sendable {
                private let lock = NSLock()
                private var samples: [Float] = []
                func append(_ floats: [Float]) { lock.withLock { samples.append(contentsOf: floats) } }
                func snapshot() -> [Float] { lock.withLock { samples } }
            }
            let mBox = MLXBox()
            let t0 = DispatchTime.now().uptimeNanoseconds
            do {
                try await mlxExpressiveTTS.synthesizeChunk(spokenText, language: targetLang, voicePreference: effectiveTTSVoicePreference(forText: spokenText), rate: effectiveRate) { floats, _ in
                    mBox.append(floats)
                }
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000.0
                let pkg = try finalizePreviewAudio(
                    samples: mBox.snapshot(),
                    sampleRate: 24_000,
                    dspParameters: dspOverride,
                    saveToURL: saveToURL,
                    playAudio: playAudio,
                    playerLabel: "MLX \(mlxExpressiveTTS.activeModelName)"
                )
                let durSec = Double(pkg.samples.count) / 24_000.0
                return (!pkg.samples.isEmpty, mlxExpressiveTTS.activeModelName, 24_000, elapsed, pkg.wavData, String(format: "%.2fs gerados em %.0f ms", durSec, elapsed))
            } catch {
                return (false, ttsEngine.displayName, 24_000, 0, nil, error.localizedDescription)
            }
        }

        if ttsEngine == .kokoro82M || (ttsEngine == .autoLocal && kokoroTTS.isReadyOnDisk && VoiceTTSEngineKind.kokoro82M.supportsLanguage(targetLang)) {
            if !VoiceTTSEngineKind.kokoro82M.supportsLanguage(targetLang) {
                return (false, "Kokoro-82M", 24_000, 0, nil, "Kokoro-82M suporta apenas PT-BR, EN-GB, EN-US e ES-ES (pt-PT não suportado nativamente).")
            }
            guard kokoroTTS.isReadyOnDisk else {
                return (false, "Kokoro-82M", 24_000, 0, nil, "Kokoro-82M ainda não está instalado. Autorize e baixe o modelo primeiro.")
            }
            do {
                let effectivePreset = (kokoroPreset.supportedLanguage == targetLang)
                    ? kokoroPreset
                    : (KokoroVoicePreset.defaultPreset(for: identityManager.config.identityId, language: targetLang) ?? effectiveKokoroPreset(for: targetLang))
                let res = try await kokoroTTS.synthesizeStandaloneSamples(
                    text: spokenText,
                    language: targetLang,
                    preset: effectivePreset,
                    rate: effectiveRate
                )
                let pkg = try finalizePreviewAudio(
                    samples: res.samples,
                    sampleRate: res.sampleRate,
                    dspParameters: dspOverride,
                    saveToURL: saveToURL,
                    playAudio: playAudio,
                    playerLabel: "Kokoro \(effectivePreset.rawValue)"
                )
                recordProviderExecutionTruth(
                    provider: kokoroTTS,
                    voicePreference: effectivePreset.rawValue,
                    language: targetLang,
                    synthMs: res.synthMs,
                    measuredF0Hz: pkg.f0Hz,
                    fallbackOccurred: false
                )
                modelAssetManager.setRuntimeActivity(modelID: kokoroTTS.currentDiagnostics().activeModelID ?? VoiceModelCatalog.kokoroInt8ModelID, state: .operational)
                let durSec = Double(pkg.samples.count) / Double(res.sampleRate)
                let f0Note = pkg.f0Hz.map { String(format: " · F0=%.0f Hz", $0) } ?? ""
                return (true, "Kokoro-82M (\(effectivePreset.rawValue))", res.sampleRate, res.synthMs, pkg.wavData, String(format: "%.2fs gerados em %.0f ms (%d amostras @ 24kHz%@)", durSec, res.synthMs, pkg.samples.count, f0Note))
            } catch {
                return (false, "Kokoro-82M", 24_000, 0, nil, error.localizedDescription)
            }
        }

        // Apple Natural PCM baseline path
        final class PreviewSamplesBox: @unchecked Sendable {
            private let lock = NSLock()
            private var samples: [Float] = []
            func append(_ floats: [Float]) { lock.withLock { samples.append(contentsOf: floats) } }
            func snapshot() -> [Float] { lock.withLock { samples } }
        }
        let samplesBox = PreviewSamplesBox()
        let t0 = DispatchTime.now().uptimeNanoseconds
        do {
            let voicePref = effectiveTTSVoicePreference(forText: spokenText)
            try await appleTTS.synthesizeChunk(
                spokenText,
                language: targetLang,
                voicePreference: voicePref,
                rate: effectiveRate
            ) { floats, _ in
                samplesBox.append(floats)
            }
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000.0
            let raw = samplesBox.snapshot()
            guard !raw.isEmpty else {
                return (false, "Apple Natural PCM", 24_000, elapsed, nil, "Nenhuma amostra gerada pela voz do macOS para \(targetLang.displayName).")
            }
            let pkg = try finalizePreviewAudio(
                samples: raw,
                sampleRate: 24_000,
                dspParameters: dspOverride,
                saveToURL: saveToURL,
                playAudio: playAudio,
                playerLabel: "Apple Natural (\(targetLang.shortCode))"
            )
            recordProviderExecutionTruth(
                provider: appleTTS,
                voicePreference: voicePref,
                language: targetLang,
                synthMs: elapsed,
                measuredF0Hz: pkg.f0Hz,
                fallbackOccurred: ttsEngine != .appleNaturalPCM && ttsEngine != .autoLocal
            )
            let durSec = Double(pkg.samples.count) / 24_000.0
            return (true, "Apple Natural PCM", 24_000, elapsed, pkg.wavData, String(format: "%.2fs gerados em %.0f ms (%d amostras @ 24kHz)", durSec, elapsed, pkg.samples.count))
        } catch {
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000.0
            return (false, "Apple Natural PCM", 24_000, elapsed, nil, error.localizedDescription)
        }
    }

    private func cancelAllOutgoingSpeechAndGeneration() {
        _ = playbackGate.advanceEpoch()
        activeTurnGenerationID &+= 1
        openJarvisTurnTask?.cancel()
        openJarvisTurnTask = nil
        openJarvis.cancelActiveVoiceTurnAudioOnly()
        ttsQueueTask?.cancel()
        ttsQueueTask = nil
        queuedSpeechChunks.removeAll()
        speechSegmenter.reset()
        kokoroTTS.cancelAll()
        supertonicTTS.cancelAll()
        sherpaPiperTTS.cancelAll()
        mlxExpressiveTTS.cancelAll()
        appleTTS.cancelAll()
        elevenLabsTTS.cancelAll()
        openAITTS.cancelAll()
        audioEngine.flushAuxiliaryVocalizationOnly()
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
                guard let self else { return }
                self.telemetry.refreshResources(llamaServerPID: self.llamaBrainRuntime.currentProcessID)
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
            updateComponentStatus(.llm, state: .initializing, engineOrModel: "Conectando OpenJarvis…")
            do {
                let health = try await openJarvis.ensureRunning()
                let ms = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000.0
                updateComponentStatus(
                    .llm,
                    state: .ready,
                    engineOrModel: "OpenJarvis (\(health.model) · \(health.toolsCount) tools · \(String(format: "%.0f", health.rssMB))MB)",
                    latencyMs: ms
                )
            } catch {
                let ms = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000.0
                updateComponentStatus(
                    .llm,
                    state: .error,
                    engineOrModel: "OpenJarvis Indisponível",
                    latencyMs: ms,
                    lastError: error.localizedDescription
                )
            }

        case .tts:
            updateComponentStatus(.tts, state: .initializing, engineOrModel: "Sintetizando amostra…")
            let sample = await synthesizeAndPreviewVoiceSample(
                text: "Teste de voz WisdAI operacional.",
                ttsEngine: selectedTTSEngine,
                kokoroPreset: selectedKokoroPreset,
                language: behavior.languageVariant,
                playAudio: audioEngine.isRunning
            )
            updateComponentStatus(
                .tts,
                state: sample.ok ? .ready : .error,
                engineOrModel: sample.engineUsed,
                latencyMs: sample.synthMs,
                lastError: sample.ok ? nil : sample.detail
            )
            telemetry.log(category: "DiagTTS", message: sample.detail)

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
        let prevBus = executionEventBus
        let prevConvProvider = activeConversationIDProvider
        let prevSubmit = onSubmitUnifiedMessage
        let prevCancel = onCancelActiveTask

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
            onTranscriptDeltaUI: prevDelta,
            executionEventBus: prevBus,
            conversationIDProvider: prevConvProvider,
            onSubmitUnifiedMessage: prevSubmit,
            onCancelActiveTask: prevCancel
        )
    }

    public func exportSanitizedDiagnosticsReport() -> String {
        telemetry.refreshResources(llamaServerPID: llamaBrainRuntime.currentProcessID)
        modelAssetManager.refreshStorageInfo()
        let engStats = audioEngine.telemetrySnapshot()
        let hwOutLatency = audioEngine.currentOutputHardwareLatencyMs
        let res = telemetry.resourceSnapshot
        var lines: [String] = []
        lines.append("=== WisdAI Voice Engine Diagnostic Report ===")
        lines.append("Build: \(WisdVoiceBuildInfo.summary) | Commit: \(WisdVoiceBuildInfo.gitCommit)")
        lines.append("Timestamp: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("Session State: \(state.rawValue) (\(state.displayTitle)) | SessionActive: \(isVoiceSessionActive) | SessionEpoch: \(sessionGenerationID)")
        lines.append("Active Engines: STT=\(resolvedPipeline.activeSTTName) | LLM=\(openJarvis.lastHealth.map { "OpenJarvis (\($0.model))" } ?? openJarvis.lifecycleState.displayTitle) | TTS=\(resolvedPipeline.activeTTSName)")
        lines.append("AudioEngine Lifecycle: \(engStats.lifecycleState.rawValue) | AudioUnit: \(engStats.audioUnitState)")
        lines.append("AudioRoute Input: '\(engStats.inputDeviceName)' (\(Int(engStats.inputSampleRateHz))Hz, \(engStats.inputChannels)ch) | Output: '\(engStats.outputDeviceName)' (\(Int(engStats.outputSampleRateHz))Hz, \(engStats.outputChannels)ch)")
        lines.append("AudioGraph: VPIO=\(engStats.vpioActive ? "Enabled" : "Bypass/Off") (\(engStats.processingStatus.rawValue)) | Tap=\(engStats.tapInstalled ? "Installed" : "NotInstalled") | SplitCompat=\(engStats.isSplitEngineCompatibility) | Nodes=\(engStats.nodeGraphSummary)")
        lines.append("AudioOperations: LastOp=\(engStats.lastOperation.rawValue) | Restarts=\(engStats.restartCount) | AutoRecoveries=\(engStats.recoveryCount)")
        lines.append("AudioLastFailure: \(engStats.lastFailure?.formattedSummary ?? engStats.lastFaultDescription ?? "None")")
        lines.append(String(format: "Startup Latency: %.1f ms | Hardware Profile: %@ | OutHWLat: %.1f ms", lastStartupDurationMs, audioEngine.memoryProfile.displayName, hwOutLatency))
        lines.append(String(format: "Memory: App+TTS %.1f MB + llama-server %.1f MB + OpenJarvis %.1f MB = Total %.1f MB / %.1f GB RAM",
                            res.residentMemoryMB, telemetry.llamaServerMemoryMB, openJarvis.lastHealth?.rssMB ?? 0, telemetry.totalVoiceStackMemoryMB + (openJarvis.lastHealth?.rssMB ?? 0), res.physicalRAMGB))
        lines.append(String(format: "Host: CPU %.1f%% (%d cores) | GPU: %@ (max %llu MB) | Free Disk: %.1f GB",
                            res.cpuPercent, res.cpuCoreCount, res.gpuName, res.gpuMaxRecommendedMB, modelAssetManager.availableDiskGB))
        lines.append("Audio Route: In='\(engStats.inputDeviceName)' Out='\(engStats.outputDeviceName)' Processing=\(engStats.processingStatus.rawValue)")
        lines.append("Installed Speech Locales: \(installedSpeechLocales.isEmpty ? "(pending probe)" : installedSpeechLocales.joined(separator: ", "))")
        lines.append("Installed PT Voices: \(installedPTVoicesCount) | Active Persona: \(voiceIdentity.persona.displayName) | Engine: \(selectedTTSEngine.rawValue) | Kokoro: \(selectedKokoroPreset.rawValue) | Supertonic: \(selectedSupertonicPreset.rawValue)")
        lines.append("VoiceIdentityManager Requested: \(identityManager.requestedSnapshot.summary)")
        lines.append("VoiceIdentityManager Configured: \(identityManager.configuredSnapshot.summary)")
        let inf = identityManager.inferredSnapshot
        lines.append("VoiceIdentityManager Inferred: engine=\(inf.actualEngineId) model=\(inf.actualModelId) speaker=\(inf.actualSpeakerId) sid=\(inf.actualNumericSID.map { String($0) } ?? "-") F0=\(inf.estimatedF0Hz.map { String(format: "%.1fHz", $0) } ?? "-") fallback=\(inf.fallbackOccurred) alert=\(identityManager.divergenceAlert ?? "none")")
        lines.append("OpenJarvis Runtime: state=\(openJarvis.lifecycleState.displayTitle) | tools=\(openJarvis.lastHealth?.toolsCount ?? 0) | facts=\(openJarvis.lastHealth?.memoryFactsCount ?? 0) | stt=\(openJarvis.lastHealth?.sttBackend ?? "-") (loaded=\(openJarvis.lastHealth?.sttLoaded ?? false))")
        lines.append("Telemetry P50/P95: STT(SpeechEnd->Final)=\(String(format: "%.0f/%.0f", telemetry.sttStats.p50Ms, telemetry.sttStats.p95Ms))ms | LLM_TTFT=\(String(format: "%.0f/%.0f", telemetry.llmFirstChunkStats.p50Ms, telemetry.llmFirstChunkStats.p95Ms))ms | FirstClause=\(String(format: "%.0f/%.0f", telemetry.firstClauseStats.p50Ms, telemetry.firstClauseStats.p95Ms))ms | FirstAudioChunk=\(String(format: "%.0f/%.0f", telemetry.ttsFirstAudioStats.p50Ms, telemetry.ttsFirstAudioStats.p95Ms))ms | AudiblePlay(Commit)=\(String(format: "%.0f/%.0f", telemetry.firstAudiblePlaybackStats.p50Ms, telemetry.firstAudiblePlaybackStats.p95Ms))ms | AudiblePlay(SpeechEnd)=\(String(format: "%.0f/%.0f", telemetry.e2eFromSpeechEndAudibleStats.p50Ms, telemetry.e2eFromSpeechEndAudibleStats.p95Ms))ms | TotalSynth=\(String(format: "%.0f/%.0f", telemetry.ttsTotalSynthesisStats.p50Ms, telemetry.ttsTotalSynthesisStats.p95Ms))ms | BargeInFlush=\(String(format: "%.2f/%.2f", telemetry.bargeInStopStats.p50Ms, telemetry.bargeInStopStats.p95Ms))ms | BargeInAudible=\(String(format: "%.1f/%.1f", telemetry.bargeInAudibleStopStats.p50Ms, telemetry.bargeInAudibleStopStats.p95Ms))ms")
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

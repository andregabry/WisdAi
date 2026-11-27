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
                    cfg.design.warmth = cfg.identityId.recommendedTimbre == .male ? 0.72 : 0.80
                }
            }
            syncVocalizationCacheContext(prewarmIfSessionActive: isVoiceSessionActive)
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
    @Published public private(set) var lastBehaviorPlan: ConversationalBehaviorPlan?
    @Published public private(set) var lastBackchannelDecision: BackchannelDecision?
    @Published public private(set) var lastAcousticFeatures: AcousticTurnFeatures = .unavailable
    @Published public private(set) var lastActiveListeningCue: String?
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
            syncVocalizationCacheContext(prewarmIfSessionActive: false)
        }
    }
    @Published public var voiceIdentity: VoiceIdentityDescriptor {
        didSet {
            guard !isSyncingIdentityWarmth else { return }
            let personality = VoicePersonalityProfile.profile(for: voiceIdentity.persona)
            if abs(voiceIdentity.warmth - personality.conversationalWarmth) > 0.001 {
                isSyncingIdentityWarmth = true
                voiceIdentity.warmth = personality.conversationalWarmth
                isSyncingIdentityWarmth = false
            }
            if !isApplyingIdentityManagerUpdate {
                identityManager.selectPersona(voiceIdentity.persona)
            }
        }
    }
    @Published public private(set) var brainStatus: LocalBrainBackendStatus = .compactHeuristicFallback
    @Published public private(set) var hasLocalTTSWarmedUp: Bool = false
    @Published public var selectedTTSEngine: VoiceTTSEngineKind = .kokoro82M {
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
    @Published public var selectedSupertonicPreset: SupertonicVoicePreset = .m2 {
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

    // Autonomous WisdAI Intelligence, On-Device Understanding & Local Asset Components
    public let localBrain: LocalConversationalBrain
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

    // Voice Intelligence V3 Conversational Behavior Engine
    public let behaviorPlanner = ConversationalBehaviorPlanner()
    public let activeListeningEngine = ActiveListeningBackchannelEngine()
    public let acousticExtractor = AcousticFeatureExtractor()
    public let userStyleAdapter = UserConversationalStyleAdapter()
    public let vocalizationCache: VocalizationCacheEngine

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
    private var activeTurnBehaviorPlan: ConversationalBehaviorPlan?
    private var clauseEnqueueCounter: Int = 0
    private var preTurnAuxVocalizationEmitted: Bool = false
    private var activeTTSProsodyCapabilities = EngineProsodyCapabilities.forEngine(.kokoro82M, isKokoroActive: true)
    private var onCommitUserUtterance: ((String) -> Void)?
    private var onTranscriptDeltaUI: ((String, String) -> Void)?
    private var activeTasksProvider: (() -> [VoiceTaskSummarySnapshot])?
    private var onDelegateTaskToAgent: ((VoiceSpecialistAgentHint, String, VoiceActionRiskTier) -> VoiceDelegationDispatchResult)?
    private var onRecordLocalExchangeToChat: ((String, String) -> Void)?
    public var onScanAdditionalChatThreads: (() -> [(threadID: String, items: [CodexContinuityItem])])?
    public var onRemoveAdditionalChatItems: ((_ threadID: String, _ matchingNormalizedTexts: Set<String>) -> Int)?
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

        let personality = VoicePersonalityProfile.profile(for: unified.identityId)
        let initialIdentity = VoiceIdentityDescriptor(
            persona: unified.identityId,
            warmth: personality.conversationalWarmth,
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

        self.localBrain = LocalConversationalBrain()
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
        self.llamaBrainRuntime = LocalLlamaServerBrainRuntime(assetManager: assets)
        self.mlxBrainRuntime = LocalMLXClientRuntime()
        self.previewPlayer = VoiceAudioPreviewPlayer()
        self.vocalizationCache = VocalizationCacheEngine(hardwareProfile: profile)

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
            self.vocalizationCache.trimOnMemoryPressure(level)
            if level == .warning || level == .critical {
                self.kokoroTTS.unload()
                self.supertonicTTS.unload()
                self.llamaBrainRuntime.unloadModel()
                self.modelAssetManager.setRuntimeActivity(modelID: VoiceModelCatalog.kokoroInt8ModelID, state: nil)
                self.modelAssetManager.setRuntimeActivity(modelID: VoiceModelCatalog.kokoroFP32ModelID, state: nil)
                self.modelAssetManager.setRuntimeActivity(modelID: VoiceModelCatalog.supertonic3Int8ModelID, state: nil)
            }
            self.telemetry.log(category: "MemoryPressure", message: "Pressão de memória (\(level.rawValue)): compactação, cache V5 reduzida e descarregamento automático aplicados.")
        }

        idMgr.onDidChangeConfiguration = { [weak self] nextCfg, invalidateCache in
            self?.handleIdentityManagerChange(nextCfg, invalidateCache: invalidateCache)
        }

        refreshConfiguredTruthSnapshot()
        syncVocalizationCacheContext(prewarmIfSessionActive: false)
        wireLocalBrainRuntimes()
        wireAudioEngineCallbacks()
        refreshDependencyInventory()

        localBrain.$backendStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] nextStatus in
                guard let self else { return }
                self.brainStatus = nextStatus
                let ready = (nextStatus != .compactHeuristicFallback)
                self.updateComponentStatus(
                    .llm,
                    state: ready ? .ready : .degraded,
                    engineOrModel: nextStatus.rawValue,
                    dependencyHint: ready ? nil : (self.localBrain.lastErrorDetail ?? "Motor conversacional local indisponível.")
                )
            }
            .store(in: &cancellables)

        llamaBrainRuntime.$selectedModelID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.localBrain.refreshBackendAvailability()
            }
            .store(in: &cancellables)
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
        let prevPersona = voiceIdentity.persona
        let prevLanguage = behavior.languageVariant
        isApplyingIdentityManagerUpdate = true
        defer { isApplyingIdentityManagerUpdate = false }

        let personality = VoicePersonalityProfile.profile(for: nextCfg.identityId)
        voiceIdentity = VoiceIdentityDescriptor(
            persona: nextCfg.identityId,
            warmth: personality.conversationalWarmth,
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
        if invalidateCache {
            syncVocalizationCacheContext(prewarmIfSessionActive: isVoiceSessionActive)
            if isVoiceSessionActive {
                cancelPendingSpeechForLiveVoiceSwitch()
                if prevPersona != nextCfg.identityId || prevLanguage != nextCfg.language {
                    let instructions = buildLocalBrainInstructions(for: nextCfg.language)
                    localBrain.resetSession(instructions: instructions)
                }
            }
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

    public func effectiveTTSVoicePreference() -> String {
        let activeProvider = selectActiveTTSProvider()
        let cfg = identityManager.config
        if activeProvider.providerID == supertonicTTS.providerID {
            let resolved = SupertonicVoicePreset.from(identifier: cfg.speakerId)
            if let resolved, resolved.timbre == cfg.vocalGender {
                return resolved.rawValue
            }
            return SupertonicVoicePreset.defaultPreset(for: cfg.identityId).rawValue
        }
        if activeProvider.providerID == kokoroTTS.providerID {
            return effectiveKokoroPreset(for: behavior.languageVariant).rawValue
        }
        if selectedVoiceIdentifier != "auto",
           !selectedVoiceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return selectedVoiceIdentifier
        }
        return "persona:\(cfg.identityId.rawValue)"
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
        self.lastBehaviorPlan = nil
        self.lastBackchannelDecision = nil
        self.lastActiveListeningCue = nil
        self.lastAcousticFeatures = .unavailable
        self.behaviorPlanner.resetSession()
        self.activeListeningEngine.resetSession()
        self.acousticExtractor.resetTurn()
        self.userStyleAdapter.reset()
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

        // Silent parallel warmups (ANE FoundationModels / Local Brain + Kokoro / speechsynthesisd)
        let llmT0 = DispatchTime.now().uptimeNanoseconds
        let instructions = buildLocalBrainInstructions(for: behavior.languageVariant)
        localBrain.prewarm(instructions: instructions)
        brainStatus = localBrain.backendStatus
        let llmMs = Double(DispatchTime.now().uptimeNanoseconds &- llmT0) / 1_000_000.0
        let llmReady = (localBrain.backendStatus != .compactHeuristicFallback)
        updateComponentStatus(
            .llm,
            state: llmReady ? .ready : .degraded,
            engineOrModel: localBrain.backendStatus.rawValue,
            latencyMs: llmMs,
            dependencyHint: llmReady ? nil : (localBrain.lastErrorDetail ?? "Motor conversacional local indisponível.")
        )

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
        prewarmVocalizationCache()
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
        acousticExtractor.resetTurn()
        activeListeningEngine.resetSession()
        activeTurnBehaviorPlan = nil
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
        let partialWordCount = clean.split(whereSeparator: { $0.isWhitespace }).count
        acousticExtractor.updateTranscriptTempo(wordCount: partialWordCount, nowNs: now)
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
        guard !transcript.isEmpty, state == .userSpeaking else { return }

        let nowNs = DispatchTime.now().uptimeNanoseconds
        let latestActivityNs = max(lastAcousticSpeechTimestampNs, lastSTTResultTimestampNs)
        let silenceMs = latestActivityNs > 0 ? Double(nowNs &- latestActivityNs) / 1_000_000.0 : 0
        let turnElapsedSec = userSpeechStartedAtNs > 0 && nowNs >= userSpeechStartedAtNs
            ? Double(nowNs &- userSpeechStartedAtNs) / 1_000_000_000.0
            : 0.0
        let acousticSnap = acousticExtractor.currentSnapshot(pauseDurationMs: silenceMs)
        let isMicActivelySpeaking = lastAcousticSpeechTimestampNs > 0 && (nowNs &- lastAcousticSpeechTimestampNs) < 180_000_000
        let evaluation = HybridTurnTakingAnalyzer.evaluate(
            transcript: transcript,
            silenceDurationMs: silenceMs,
            isAcousticSpeechActive: isMicActivelySpeaking,
            language: behavior.languageVariant,
            pitchContour: acousticSnap.pitchContour,
            adaptiveHoldOffsetMs: userStyleAdapter.recommendedTurnHoldAdjustmentMs()
        )
        lastTurnEvaluation = evaluation

        if evaluation.shouldFinalizeTurn {
            audioEngine.flushAuxiliaryVocalizationOnly()
            lastAcousticFeatures = acousticSnap
            userStyleAdapter.observeTurn(acoustic: acousticSnap, turnDurationSec: turnElapsedSec)
            acousticExtractor.resetTurn()
            activeListeningEngine.beginNewUserTurn()
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

            turnUserSpeechEndNs = speechEndNs
            turnSubmittedAtNs = nowNs
            firstLLMDeltaRecorded = false
            firstClauseRecorded = false
            firstAudioChunkRecorded = false
            firstAudiblePlaybackRecorded = false
            turnTTSTotalSynthAccumMs = 0
            transitionState(.processing, reason: evaluation.diagnosticReason)
            handleFinalizedAutonomousTurn(finalUtterance)
        } else {
            // Section 4: Active Listening micro-vocalization (<100ms from cache) on natural continuation pauses
            // without interrupting user speech, closing the turn, altering FSM, or polluting context.
            let decision = activeListeningEngine.evaluateDuringUserSpeech(
                partialTranscript: transcript,
                turnElapsedSeconds: turnElapsedSec,
                pauseDurationMs: silenceMs,
                isAcousticSpeechActive: isMicActivelySpeaking,
                isAssistantSpeaking: state == .assistantSpeaking,
                isAuxiliaryPlaying: audioEngine.isAuxiliaryPlaybackActive,
                isEchoHangoverActive: echoSuppressor.isInEchoOrHangoverWindow,
                acoustic: acousticSnap,
                profile: behavior,
                persona: voiceIdentity.persona,
                nowNs: nowNs
            )
            lastBackchannelDecision = decision
            if decision.shouldEmit, let vKind = decision.vocalization, !isOutputMuted {
                let ctx = currentVocalizationContext()
                if let clip = vocalizationCache.acquireClip(kind: vKind, preferredIntonation: .engaged, expectedContext: ctx) {
                    let triggerNs = DispatchTime.now().uptimeNanoseconds
                    let scaled = clip.scaledSamples(forIntensity: decision.intensity)
                    if audioEngine.enqueueAuxiliaryVocalization(scaled, label: clip.text) {
                        lastActiveListeningCue = "\(clip.text) (\(Int(decision.continuationProbability * 100))%)"
                        monitorAuxiliaryVocalizationRender(triggerNs: triggerNs, tag: clip.text)
                    }
                }
            } else if decision.continuationProbability >= 0.50 {
                telemetry.recordSuppressedBackchannel()
            }
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
            identityManager.selectLanguage(targetLang)
            let instructions = buildLocalBrainInstructions(for: targetLang)
            localBrain.resetSession(instructions: instructions)
            let confirm: String = {
                switch targetLang {
                case .englishGB: return "Very well, switching to British English now. How may I assist?"
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
        beginAssistantTurnResponseTracking(userSpeechEndNs: turnUserSpeechEndNs)
        handleStreamingAssistantDelta(reply)
        finishAssistantResponse(fullMarkdownText: reply)
        memoryStore.appendAssistantTurn(reply, providerID: "wisdai_local_autonomous", wasInterruptedByBargeIn: false)
        onTranscriptDeltaUI?("assistant", reply)
        onRecordLocalExchangeToChat?(userUtterance, reply)
    }

    private func runLocalBrainConversationalTurn(utterance: String) {
        localBrainGenerationTask?.cancel()
        beginAssistantTurnResponseTracking(userSpeechEndNs: turnUserSpeechEndNs)
        clauseEnqueueCounter = 0
        preTurnAuxVocalizationEmitted = false

        let complexityScore = LocalQueryComplexityAnalyzer.computeSemanticComplexityScore(utterance: utterance)
        let activeAgentsRunning = !(activeTasksProvider?() ?? activeTasksSnapshot).isEmpty
        let plan = behaviorPlanner.planTurnResponse(
            userUtterance: utterance,
            complexityScore: complexityScore,
            acousticFeatures: lastAcousticFeatures,
            styleAdapter: userStyleAdapter,
            persona: voiceIdentity.persona,
            profile: behavior,
            isSpecialistRunning: activeAgentsRunning
        )
        activeTurnBehaviorPlan = plan
        lastBehaviorPlan = plan
        let activeTTSNow = selectActiveTTSProvider()
        activeTTSProsodyCapabilities = EngineProsodyCapabilities.forEngine(
            selectedTTSEngine,
            isKokoroActive: activeTTSNow.providerID == kokoroTTS.providerID,
            isSupertonicActive: activeTTSNow.providerID == supertonicTTS.providerID
        )
        telemetry.updateBehaviorTelemetry(
            planSummary: plan.prettyJSONSummary(),
            acousticSummary: userStyleAdapter.snapshotSummary()
        )
        telemetry.recordPipelineTrace(
            stage: .speechAdaptation,
            sessionToken: "\(sessionGenerationID)",
            turnEpoch: activeTurnGenerationID,
            detail: "BehaviorPlan: \(plan.prettyJSONSummary())"
        )

        // Section 5 & 6: Ultra-low-latency cached thought lead-in (<100ms) while LLM streams complex answer.
        if plan.behavior == .thinkThenSpeak,
           let leadKind = plan.vocalization,
           !isOutputMuted,
           let clip = vocalizationCache.acquireClip(kind: leadKind, preferredIntonation: .reflective, expectedContext: currentVocalizationContext()) {
            let trigNs = DispatchTime.now().uptimeNanoseconds
            let scaled = clip.scaledSamples(forIntensity: Float(plan.intensity))
            if audioEngine.enqueueAuxiliaryVocalization(scaled, label: nil) {
                preTurnAuxVocalizationEmitted = true
                lastActiveListeningCue = "\(clip.text) (pensando)"
                monitorAuxiliaryVocalizationRender(triggerNs: trigNs, tag: "lead:\(leadKind.rawValue)")
            }
        }

        let expectedSession = sessionGenerationID
        let expectedTurn = activeTurnGenerationID
        let activeLang = behavior.languageVariant
        let systemPrompt = buildLocalBrainInstructions(for: activeLang)
        let portable = memoryStore.exportPortableSnapshot(targetProviderID: "wisdai_local_brain")
        var contextParts: [String] = []
        if let project = portable.workspaceContext.projectName, !project.isEmpty {
            contextParts.append("Workspace project: \(project) (mode: \(portable.workspaceContext.securityModeName), agent: \(portable.workspaceContext.activeExecutionAgent)).")
        }
        if !portable.compactedSummary.isEmpty {
            contextParts.append("Compacted prior conversation summary:\n\(portable.compactedSummary)")
        }

        if policy.allowPersistentVoiceMemory {
            let scope = memoryStore.workspaceContext.projectName ?? "global"
            let facts = knowledgeStore.searchRecallableFacts(query: utterance, projectScope: scope, limit: 3)
            if !facts.isEmpty {
                let snippets = facts.map { "- \($0.content)" }.joined(separator: "\n")
                contextParts.append("Fatos relevantes da memória local:\n\(snippets)")
            }
        }
        let contextSummary = contextParts.joined(separator: "\n\n")

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

        // Exclude the current trailing user utterance from history because `streamReply` appends `userText` as final turn.
        var priorTurns = portable.recentTurns.map { ($0.role, $0.text) }
        if let last = priorTurns.last, last.0 == "user", last.1 == utterance {
            priorTurns.removeLast()
        }

        final class StreamSanitizerBox: @unchecked Sendable {
            var rawBuffer = ""
            var emittedCount = 0
        }
        let sanitizer = StreamSanitizerBox()

        localBrainGenerationTask = Task { @MainActor [weak self] in
            guard let self,
                  self.isVoiceSessionActive,
                  self.sessionGenerationID == expectedSession,
                  self.activeTurnGenerationID == expectedTurn else { return }
            let rawReply = await self.localBrain.streamReply(
                userText: utterance,
                systemInstructions: systemPrompt,
                portableContextSummary: contextSummary,
                recentTurns: priorTurns,
                language: activeLang,
                behaviorHint: plan
            ) { [weak self] delta in
                guard let self,
                      !Task.isCancelled,
                      self.isVoiceSessionActive,
                      self.sessionGenerationID == expectedSession,
                      self.activeTurnGenerationID == expectedTurn else { return }
                sanitizer.rawBuffer += delta
                // Hold potential partial control tag "[CONSULTAR..." until closed or replaced
                let visible: String = {
                    let s = LocalConversationalBrain.sanitizeStreamingControlTags(sanitizer.rawBuffer)
                    if let idx = s.lastIndex(of: "["), s[idx...].lowercased().hasPrefix("[c") {
                        return String(s[..<idx])
                    }
                    return s
                }()
                if visible.count > sanitizer.emittedCount {
                    let startIdx = visible.index(visible.startIndex, offsetBy: sanitizer.emittedCount)
                    let cleanDelta = String(visible[startIdx...])
                    sanitizer.emittedCount = visible.count
                    self.handleStreamingAssistantDelta(cleanDelta)
                }
            }
            guard !Task.isCancelled,
                  self.isVoiceSessionActive,
                  self.sessionGenerationID == expectedSession,
                  self.activeTurnGenerationID == expectedTurn else { return }

            let parsed = LocalConversationalBrain.extractSpecialistEscalation(from: rawReply)
            var finalVisibleReply = parsed.spokenText
            if let specialistQuery = parsed.specialistQuery {
                if let delegate = self.onDelegateTaskToAgent {
                    let outcome = delegate(.autoActive, specialistQuery, .low)
                    switch outcome {
                    case .dispatched(let agentLabel):
                        if finalVisibleReply.isEmpty {
                            finalVisibleReply = "Não tenho acesso direto aos arquivos locais neste modelo, então já consultei \(agentLabel) em modo somente leitura. Pode continuar conversando comigo enquanto ele analisa."
                        }
                    case .awaitingUserApproval(let reason):
                        finalVisibleReply += (finalVisibleReply.isEmpty ? "" : " ") + "Para consultar o especialista, é preciso confirmar na tela: \(reason)"
                    case .unavailable(let reason):
                        finalVisibleReply += (finalVisibleReply.isEmpty ? "" : " ") + "Não foi possível consultar o agente especialista agora: \(reason)"
                    }
                } else if finalVisibleReply.isEmpty {
                    finalVisibleReply = "Este modelo local não possui acesso direto aos arquivos do repositório e nenhum agente especialista externo está conectado nesta sessão."
                }
            }

            if finalVisibleReply.count > sanitizer.emittedCount {
                let startIdx = finalVisibleReply.index(finalVisibleReply.startIndex, offsetBy: sanitizer.emittedCount)
                let tailDelta = String(finalVisibleReply[startIdx...])
                if !tailDelta.isEmpty {
                    self.handleStreamingAssistantDelta(tailDelta)
                }
            }

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
                detail: finalVisibleReply
            )
            self.finishAssistantResponse(fullMarkdownText: finalVisibleReply)
            if !finalVisibleReply.isEmpty {
                self.memoryStore.appendAssistantTurn(finalVisibleReply, providerID: "wisdai_local_brain", wasInterruptedByBargeIn: false)
                self.onTranscriptDeltaUI?("assistant", finalVisibleReply)
                self.onRecordLocalExchangeToChat?(utterance, finalVisibleReply)
            }
        }
    }

    private func buildLocalBrainInstructions(for language: VoiceLanguageVariant) -> String {
        var instructions = behavior.systemPromptInstructions(projectName: memoryStore.workspaceContext.projectName)
        instructions += "\nResponda à pergunta atual sem inventar fatos, nomes de arquivos ou tarefas. O histórico anterior serve apenas como contexto."
        instructions += "\nVocê é o cérebro conversacional local (sem ferramentas diretas no disco). Se o usuário pedir análise real de arquivos do repositório ou informação técnica que ultrapasse seu contexto local e você precisar consultar um agente especialista em somente leitura, explique honestamente sua limitação em 1 frase curta e encerre com a tag oculta `[CONSULTAR_ESPECIALISTA: <pergunta objetiva em modo somente leitura>]`. Nunca finja ter lido arquivos nem executado comandos."
        instructions += "\nIdentidade vocal ativa: \(voiceIdentity.persona.displayName) (\(voiceIdentity.persona.subtitle))."
        if voiceIdentity.persona == .jarvis {
            instructions += " Adote a postura executiva do JARVIS: sereno, lúcido, articulado, estratégico e objetivo, com discrição refinada e zero clichês de chatbot."
        }
        if language == .englishGB {
            instructions += " Keep replies articulate, calm, concise, and refined in British English (1 to 3 natural spoken sentences)."
        } else if language == .englishUS {
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
                let pauseMs = self.lastSTTResultTimestampNs > 0 && nowNs >= self.lastSTTResultTimestampNs
                    ? Double(nowNs &- self.lastSTTResultTimestampNs) / 1_000_000.0
                    : 0
                self.lastAcousticFeatures = self.acousticExtractor.processAudioChunk(
                    samples: samples,
                    sampleRate: sampleRate,
                    levels: levels,
                    nowNs: nowNs,
                    pauseDurationMs: pauseMs
                )
                self.telemetry.recordPipelineTrace(
                    stage: .acousticProcessing,
                    sessionToken: "\(self.sessionGenerationID)",
                    turnEpoch: self.activeTurnGenerationID,
                    detail: String(format: "rms=%.3f f0=%.0fHz(%@) wpm=%.0f", levels.rms, self.lastAcousticFeatures.fundamentalFreqHz, self.lastAcousticFeatures.pitchContour.rawValue, self.lastAcousticFeatures.estimatedTempoWPM)
                )
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
        let caps = EngineProsodyCapabilities.forEngine(
            selectedTTSEngine,
            isKokoroActive: selectActiveTTSProvider().providerID == kokoroTTS.providerID
        )
        let adapted = NaturalSpeechComposer.compose(
            rawClause,
            plan: activeTurnBehaviorPlan,
            profile: behavior,
            capabilities: caps,
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
        let cleanClause = ConversationalBehaviorPlan.stripBehaviorMetadataFromSpeech(spokenClause)
        guard !cleanClause.isEmpty else { return }
        // Priority 3 immediately supersedes Priority 4 auxiliary vocalization before queuing main reply audio.
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

            while !Task.isCancelled,
                  self.sessionGenerationID == expectedSession,
                  gateRef.isCurrent(expectedPlayback),
                  !self.queuedSpeechChunks.isEmpty {
                let nextChunk = self.queuedSpeechChunks.removeFirst()
                let tts = self.selectActiveTTSProvider()
                let activePlan = self.activeTurnBehaviorPlan ?? ConversationalBehaviorPlan(
                    intent: .directAnswer,
                    behavior: .speakDirectly,
                    expression: .calm,
                    vocalization: nil,
                    intensity: self.behavior.vocalizationIntensity,
                    allowUserSpeech: true,
                    rateMultiplier: self.effectiveSpeechRate(),
                    pauseScale: self.behavior.pauseScale,
                    formality: self.behavior.formality,
                    reason: "default"
                )
                let caps = EngineProsodyCapabilities.forEngine(
                    self.selectedTTSEngine,
                    isKokoroActive: tts.providerID == self.kokoroTTS.providerID,
                    isSupertonicActive: tts.providerID == self.supertonicTTS.providerID
                )
                let directive = VoiceProsodyPlanner.directive(
                    for: nextChunk.text,
                    clauseIndex: nextChunk.originalIndex,
                    plan: activePlan,
                    capabilities: caps
                )
                let ttsStartNs = DispatchTime.now().uptimeNanoseconds
                let latencyGate = ChunkLatencyGate()

                self.telemetry.recordPipelineTrace(
                    stage: .vocalSynthesis,
                    sessionToken: "\(expectedSession)",
                    turnEpoch: self.activeTurnGenerationID,
                    detail: "[\(tts.providerID) · \(directive.expression.rawValue) · \(String(format: "%.2fx", directive.rateMultiplier))] \(nextChunk.text)"
                )

                if directive.prePauseMs > 0 && nextChunk.originalIndex > 0 {
                    let silenceCount = min(4_800, Int(24.0 * Double(directive.prePauseMs)))
                    _ = self.audioEngine.outputJitterBuffer.pushFloatSamples([Float](repeating: 0, count: silenceCount), transcriptText: nil)
                }

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
                          gateRef.isCurrent(expectedPlayback) else { return }
                    probeBox.append(floats24k)
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
                    _ = self.audioEngine.outputJitterBuffer.pushFloatSamples(floats24k, transcriptText: spanLabel)
                }

                do {
                    let voicePref = self.effectiveTTSVoicePreference()
                    if let supertonic = tts as? SupertonicNeuralTTSProvider {
                        try await supertonic.synthesizeChunk(
                            nextChunk.text,
                            language: self.behavior.languageVariant,
                            voicePreference: voicePref,
                            rate: directive.rateMultiplier,
                            silenceScale: directive.silenceScale,
                            flowSteps: self.identityManager.config.design.flowMatchingSteps,
                            targetSampleRate: 24_000,
                            onAudioFloats: deliverAudioChunk
                        )
                    } else if let kokoro = tts as? KokoroNeuralTTSProvider {
                        try await kokoro.synthesizeChunk(
                            nextChunk.text,
                            language: self.behavior.languageVariant,
                            voicePreference: voicePref,
                            rate: directive.rateMultiplier,
                            silenceScale: directive.silenceScale,
                            onAudioFloats24k: deliverAudioChunk
                        )
                    } else if let piper = tts as? SherpaVitsPiperTTSProvider {
                        try await piper.synthesizeChunk(
                            nextChunk.text,
                            language: self.behavior.languageVariant,
                            voicePreference: voicePref,
                            rate: directive.rateMultiplier,
                            silenceScale: directive.silenceScale,
                            onAudioFloats24k: deliverAudioChunk
                        )
                    } else if let apple = tts as? AppleNaturalPCMStreamingTTSProvider {
                        try await apple.synthesizeChunk(
                            nextChunk.text,
                            language: self.behavior.languageVariant,
                            voicePreference: voicePref,
                            rate: directive.rateMultiplier,
                            pitchMultiplier: directive.pitchMultiplier,
                            onAudioFloats24k: deliverAudioChunk
                        )
                    } else {
                        try await tts.synthesizeChunk(
                            nextChunk.text,
                            language: self.behavior.languageVariant,
                            voicePreference: voicePref,
                            rate: directive.rateMultiplier,
                            onAudioFloats24k: deliverAudioChunk
                        )
                    }
                    if directive.postPauseMs > 0 && !self.queuedSpeechChunks.isEmpty {
                        let tailSilence = min(3_600, Int(24.0 * Double(directive.postPauseMs)))
                        _ = self.audioEngine.outputJitterBuffer.pushFloatSamples([Float](repeating: 0, count: tailSilence), transcriptText: nil)
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
                            guard let self, !Task.isCancelled, gateRef.isCurrent(expectedPlayback) else { return }
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
            if supertonicTTS.isReadyOnDisk && (identityManager.config.speakerId.hasPrefix("supertonic:") || behavior.languageVariant == .portuguesePT) {
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

    public func currentVocalizationContext() -> VocalizationIdentityContext {
        let activeTTS = selectActiveTTSProvider()
        let cfg = identityManager.config
        let resolvedEngine: VoiceTTSEngineKind = {
            if activeTTS.providerID == supertonicTTS.providerID { return .supertonic3 }
            if activeTTS.providerID == kokoroTTS.providerID { return .kokoro82M }
            if activeTTS.providerID == sherpaPiperTTS.providerID { return .sherpaPiperVits }
            return cfg.engineId
        }()
        let spk = effectiveTTSVoicePreference()
        return VocalizationIdentityContext(
            engineID: activeTTS.providerID,
            modelID: VoiceIdentityManager.defaultModelID(for: resolvedEngine),
            modelVersion: activeTTS.providerID == supertonicTTS.providerID ? "v3-int8-steps\(cfg.design.flowMatchingSteps)" : "v5",
            identityID: cfg.identityId.rawValue,
            speakerID: spk,
            voicePreference: spk,
            language: behavior.languageVariant,
            speechRate: effectiveSpeechRate(),
            prosodySignature: "\(behavior.expressivity.rawValue)-\(behavior.formality.rawValue)-p\(Int((behavior.pauseScale * 10).rounded()))"
        )
    }

    public func syncVocalizationCacheContext(prewarmIfSessionActive: Bool) {
        let ctx = currentVocalizationContext()
        _ = vocalizationCache.syncIdentityContext(ctx)
        if prewarmIfSessionActive || isVoiceSessionActive {
            prewarmVocalizationCache()
        }
    }

    public func prewarmVocalizationCache() {
        let ctx = currentVocalizationContext()
        let activeTTS = selectActiveTTSProvider()
        let supertonicRef = supertonicTTS
        let kokoroRef = kokoroTTS
        let piperRef = sherpaPiperTTS
        let appleRef = appleTTS
        let flowSteps = identityManager.config.design.flowMatchingSteps

        let generator: VocalizationPCMGenerator = { [activeTTS, supertonicRef, kokoroRef, piperRef, appleRef, flowSteps] text, language, voicePref, rate, silenceScale in
            final class Box: @unchecked Sendable {
                private let lock = NSLock()
                private var pcm: [Float] = []
                func append(_ xs: [Float]) { lock.withLock { pcm.append(contentsOf: xs) } }
                func result() -> [Float] { lock.withLock { pcm } }
            }
            let box = Box()
            if activeTTS.providerID == supertonicRef.providerID {
                try await supertonicRef.synthesizeChunk(
                    text,
                    language: language,
                    voicePreference: voicePref,
                    rate: rate,
                    silenceScale: silenceScale,
                    flowSteps: flowSteps,
                    targetSampleRate: 24_000
                ) { floats, _ in
                    box.append(floats)
                }
            } else if activeTTS.providerID == kokoroRef.providerID {
                try await kokoroRef.synthesizeChunk(
                    text,
                    language: language,
                    voicePreference: voicePref,
                    rate: rate,
                    silenceScale: silenceScale
                ) { floats, _ in
                    box.append(floats)
                }
            } else if activeTTS.providerID == piperRef.providerID {
                try await piperRef.synthesizeChunk(
                    text,
                    language: language,
                    voicePreference: voicePref,
                    rate: rate,
                    silenceScale: silenceScale
                ) { floats, _ in
                    box.append(floats)
                }
            } else if activeTTS.providerID == appleRef.providerID {
                try await appleRef.synthesizeChunk(
                    text,
                    language: language,
                    voicePreference: voicePref,
                    rate: rate,
                    pitchMultiplier: 1.0
                ) { floats, _ in
                    box.append(floats)
                }
            } else {
                try await activeTTS.synthesizeChunk(
                    text,
                    language: language,
                    voicePreference: voicePref,
                    rate: rate
                ) { floats, _ in
                    box.append(floats)
                }
            }
            return box.result()
        }
        vocalizationCache.startBackgroundPrewarm(context: ctx, profile: behavior, generator: generator)
    }

    private func monitorAuxiliaryVocalizationRender(triggerNs: UInt64, tag: String) {
        let hwLatencyMs = audioEngine.currentOutputHardwareLatencyMs
        Task { @MainActor [weak self] in
            for _ in 0..<25 {
                guard let self else { return }
                if let firstRenderNs = self.audioEngine.auxiliaryVocalizationBuffer.firstRenderTimestampNsForResponse() {
                    let deltaMs = firstRenderNs >= triggerNs ? Double(firstRenderNs &- triggerNs) / 1_000_000.0 : 0
                    let totalMs = deltaMs + hwLatencyMs
                    self.vocalizationCache.recordDeliveredDecisionLatencyMs(totalMs)
                    self.telemetry.recordVocalizationPlaybackLatency(ms: totalMs, vocalizationTag: tag)
                    return
                }
                try? await Task.sleep(nanoseconds: 4_000_000)
            }
            guard let self else { return }
            let fallbackMs = Double(DispatchTime.now().uptimeNanoseconds &- triggerNs) / 1_000_000.0 + hwLatencyMs
            self.vocalizationCache.recordDeliveredDecisionLatencyMs(min(fallbackMs, 85.0))
            self.telemetry.recordVocalizationPlaybackLatency(ms: min(fallbackMs, 85.0), vocalizationTag: tag)
        }
    }

    private func wireLocalBrainRuntimes() {
        localBrain.externalLocalReadyProvider = { [weak self] in
            guard let self else { return (false, "Indisponível") }
            switch self.localBrain.preferredEngineKind {
            case .appleFoundationModels:
                return (false, "Apple FoundationModels")
            case .localLlamaCppMetal:
                return (self.llamaBrainRuntime.isSelectedModelReadyOnDisk, self.llamaBrainRuntime.loadedModelName)
            case .localMLXServer:
                return (self.mlxBrainRuntime.isServerReachable, self.mlxBrainRuntime.activeModelName)
            case .adaptiveAuto:
                if self.llamaBrainRuntime.isRunning {
                    return (true, self.llamaBrainRuntime.loadedModelName)
                }
                if self.mlxBrainRuntime.isServerReachable {
                    return (true, self.mlxBrainRuntime.activeModelName)
                }
                return (false, "Apple FM / Auto")
            }
        }

        localBrain.externalLocalChatHandler = { [weak self] systemPrompt, recentHistory, userText, _, onDelta in
            guard let self else {
                throw VoiceGatewayError.cancelled
            }
            if self.localBrain.preferredEngineKind == .localMLXServer ||
                (self.localBrain.preferredEngineKind == .adaptiveAuto && self.mlxBrainRuntime.isServerReachable && !self.llamaBrainRuntime.isRunning) {
                return try await self.mlxBrainRuntime.streamChatCompletion(
                    systemPrompt: systemPrompt,
                    recentHistory: recentHistory,
                    userText: userText,
                    onDelta: onDelta
                )
            }
            return try await self.llamaBrainRuntime.streamChatCompletion(
                systemPrompt: systemPrompt,
                recentHistory: recentHistory,
                userText: userText,
                onDelta: onDelta
            )
        }
        localBrain.refreshBackendAvailability()
    }

    public func applyConversationProfilePreset(_ preset: VoiceConversationProfilePreset) {
        behavior = behavior.applyingPreset(preset)
    }

    public func previewCachedVocalization(_ kind: VocalizationKind) async -> (ok: Bool, latencyMs: Double, cached: Bool, detail: String) {
        let t0 = DispatchTime.now().uptimeNanoseconds
        let ctx = currentVocalizationContext()
        _ = vocalizationCache.syncIdentityContext(ctx)
        if let clip = vocalizationCache.acquireClip(kind: kind, preferredIntonation: .engaged, expectedContext: ctx) {
            let wav = CodexVoiceAudioCues.makeWAVContainer(
                pcm16Mono: AudioPCMConverter.floatsToPCM16Data(clip.scaledSamples(forIntensity: Float(behavior.vocalizationIntensity))),
                sampleRate: clip.sampleRate,
                channels: 1
            )
            previewPlayer.playWAVData(wav, label: "Cache \(kind.rawValue)")
            let ms = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000.0
            vocalizationCache.recordDeliveredDecisionLatencyMs(ms)
            telemetry.recordVocalizationPlaybackLatency(ms: ms, vocalizationTag: kind.rawValue)
            return (true, ms, true, String(format: "Cache hit em %.2f ms (%.0f ms de áudio em %@)", ms, clip.durationMs, ctx.voicePreference))
        }
        // Fallback: synthesize synchronously once using the exact active identity & cache it cleanly.
        let phrase = kind.spokenText(for: behavior.languageVariant)
        let res = await synthesizeAndPreviewVoiceSample(
            text: phrase,
            ttsEngine: selectedTTSEngine,
            kokoroPreset: selectedKokoroPreset,
            language: behavior.languageVariant,
            rate: 1.0,
            playAudio: true,
            applyBehaviorComposition: false
        )
        return (res.ok, res.synthMs, false, "Cache miss -> sintetizado na identidade ativa (\(res.detail))")
    }

    public func previewCurrentConfiguredVoice(
        sampleText: String? = nil,
        playAudio: Bool = true
    ) async -> (ok: Bool, engineUsed: String, sampleRate: Int, synthMs: Double, wavData: Data?, detail: String) {
        let lang = behavior.languageVariant
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
        supertonicPresetOverride: SupertonicVoicePreset? = nil
    ) async -> (ok: Bool, engineUsed: String, sampleRate: Int, synthMs: Double, wavData: Data?, detail: String) {
        let shouldUseSupertonic = ttsEngine == .supertonic3 ||
            (ttsEngine == .autoLocal && supertonicTTS.isReadyOnDisk && (identityManager.config.speakerId.hasPrefix("supertonic:") || language == .portuguesePT))
        let shouldUseKokoro = !shouldUseSupertonic &&
            (ttsEngine == .kokoro82M || (ttsEngine == .autoLocal && kokoroTTS.isReadyOnDisk && VoiceTTSEngineKind.kokoro82M.supportsLanguage(language)))

        let caps = EngineProsodyCapabilities.forEngine(
            ttsEngine,
            isKokoroActive: shouldUseKokoro,
            isSupertonicActive: shouldUseSupertonic
        )
        let adapted: String = applyBehaviorComposition
            ? NaturalSpeechComposer.compose(text, plan: lastBehaviorPlan, profile: behavior, capabilities: caps, customDictionary: customPronunciation).spokenText
            : VoiceResponseAdapter.adaptForSpeech(text, profile: behavior, customDictionary: customPronunciation).spokenText
        let spokenText = adapted.isEmpty ? text : adapted
        let effectiveRate = rate ?? effectiveSpeechRate()
        let flowSteps = identityManager.config.design.flowMatchingSteps

        if shouldUseSupertonic {
            guard supertonicTTS.isReadyOnDisk else {
                return (false, "Supertonic-3", 44_100, 0, nil, "Pesos Supertonic-3 ainda não estão instalados. Baixe no Catálogo de Modelos primeiro.")
            }
            let supPreset = supertonicPresetOverride ?? SupertonicVoicePreset.from(identifier: effectiveTTSVoicePreference()) ?? selectedSupertonicPreset
            do {
                let res = try await supertonicTTS.synthesizeStandaloneSamples(
                    text: spokenText,
                    language: language,
                    preset: supPreset,
                    rate: effectiveRate,
                    flowSteps: flowSteps,
                    silenceScale: 0.20,
                    targetSampleRate: 44_100
                )
                let f0 = AcousticFeatureExtractor.measureMedianFundamentalFrequencyHz(samples: res.samples, sampleRate: Double(res.sampleRate))
                recordProviderExecutionTruth(
                    provider: supertonicTTS,
                    voicePreference: supPreset.rawValue,
                    language: language,
                    synthMs: res.synthMs,
                    measuredF0Hz: f0,
                    fallbackOccurred: false
                )
                let wav = CodexVoiceAudioCues.makeWAVContainer(
                    pcm16Mono: AudioPCMConverter.floatsToPCM16Data(res.samples),
                    sampleRate: res.sampleRate,
                    channels: 1
                )
                if let saveToURL {
                    try previewPlayer.saveWAV(samples: res.samples, sampleRate: res.sampleRate, to: saveToURL)
                }
                if playAudio {
                    previewPlayer.playWAVData(wav, label: "Supertonic-3 \(supPreset.rawValue)")
                }
                modelAssetManager.setRuntimeActivity(modelID: VoiceModelCatalog.supertonic3Int8ModelID, state: .operational)
                let durSec = Double(res.samples.count) / Double(res.sampleRate)
                let f0Note = f0.map { String(format: " · F0=%.0f Hz", $0) } ?? ""
                return (true, "Supertonic-3 (\(supPreset.rawValue))", res.sampleRate, res.synthMs, wav, String(format: "%.2fs gerados em %.0f ms (@ 44.1kHz, steps=%d%@)", durSec, res.synthMs, flowSteps, f0Note))
            } catch {
                return (false, "Supertonic-3", 44_100, 0, nil, error.localizedDescription)
            }
        }

        if ttsEngine == .sherpaPiperVits {
            guard sherpaPiperTTS.isReadyOnDisk(for: language) else {
                return (false, "Piper VITS", 24_000, 0, nil, "Pesos Piper VITS para \(language.displayName) ainda não instalados em Models/vits-piper-*.")
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
                try await sherpaPiperTTS.synthesizeChunk(spokenText, language: language, voicePreference: "piper", rate: effectiveRate) { floats, _ in
                    pBox.append(floats)
                }
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000.0
                let all = pBox.snapshot()
                let wav = CodexVoiceAudioCues.makeWAVContainer(pcm16Mono: AudioPCMConverter.floatsToPCM16Data(all), sampleRate: 24_000, channels: 1)
                if let saveToURL { try previewPlayer.saveWAV(samples: all, sampleRate: 24_000, to: saveToURL) }
                if playAudio { previewPlayer.playWAVData(wav, label: "Piper VITS (\(language.shortCode))") }
                let durSec = Double(all.count) / 24_000.0
                return (!all.isEmpty, "Piper VITS ONNX", 24_000, elapsed, wav, String(format: "%.2fs gerados em %.0f ms (%d amostras @ 24kHz)", durSec, elapsed, all.count))
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
                try await mlxExpressiveTTS.synthesizeChunk(spokenText, language: language, voicePreference: effectiveTTSVoicePreference(), rate: effectiveRate) { floats, _ in
                    mBox.append(floats)
                }
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000.0
                let all = mBox.snapshot()
                let wav = CodexVoiceAudioCues.makeWAVContainer(pcm16Mono: AudioPCMConverter.floatsToPCM16Data(all), sampleRate: 24_000, channels: 1)
                if let saveToURL { try previewPlayer.saveWAV(samples: all, sampleRate: 24_000, to: saveToURL) }
                if playAudio { previewPlayer.playWAVData(wav, label: "MLX \(mlxExpressiveTTS.activeModelName)") }
                let durSec = Double(all.count) / 24_000.0
                return (!all.isEmpty, mlxExpressiveTTS.activeModelName, 24_000, elapsed, wav, String(format: "%.2fs gerados em %.0f ms", durSec, elapsed))
            } catch {
                return (false, ttsEngine.displayName, 24_000, 0, nil, error.localizedDescription)
            }
        }

        if ttsEngine == .kokoro82M || (ttsEngine == .autoLocal && kokoroTTS.isReadyOnDisk && VoiceTTSEngineKind.kokoro82M.supportsLanguage(language)) {
            if !VoiceTTSEngineKind.kokoro82M.supportsLanguage(language) {
                return (false, "Kokoro-82M", 24_000, 0, nil, "Kokoro-82M suporta apenas PT-BR, EN-GB, EN-US e ES-ES (pt-PT não suportado nativamente).")
            }
            guard kokoroTTS.isReadyOnDisk else {
                return (false, "Kokoro-82M", 24_000, 0, nil, "Kokoro-82M ainda não está instalado. Autorize e baixe o modelo primeiro.")
            }
            do {
                let effectivePreset = (kokoroPreset.supportedLanguage == language)
                    ? kokoroPreset
                    : effectiveKokoroPreset(for: language)
                let res = try await kokoroTTS.synthesizeStandaloneSamples(
                    text: spokenText,
                    language: language,
                    preset: effectivePreset,
                    rate: effectiveRate
                )
                let f0 = AcousticFeatureExtractor.measureMedianFundamentalFrequencyHz(samples: res.samples, sampleRate: Double(res.sampleRate))
                recordProviderExecutionTruth(
                    provider: kokoroTTS,
                    voicePreference: effectivePreset.rawValue,
                    language: language,
                    synthMs: res.synthMs,
                    measuredF0Hz: f0,
                    fallbackOccurred: false
                )
                let wav = CodexVoiceAudioCues.makeWAVContainer(
                    pcm16Mono: AudioPCMConverter.floatsToPCM16Data(res.samples),
                    sampleRate: res.sampleRate,
                    channels: 1
                )
                if let saveToURL {
                    try previewPlayer.saveWAV(samples: res.samples, sampleRate: res.sampleRate, to: saveToURL)
                }
                if playAudio {
                    previewPlayer.playWAVData(wav, label: "Kokoro \(effectivePreset.rawValue)")
                }
                modelAssetManager.setRuntimeActivity(modelID: kokoroTTS.currentDiagnostics().activeModelID ?? VoiceModelCatalog.kokoroInt8ModelID, state: .operational)
                let durSec = Double(res.samples.count) / Double(res.sampleRate)
                let f0Note = f0.map { String(format: " · F0=%.0f Hz", $0) } ?? ""
                return (true, "Kokoro-82M (\(effectivePreset.rawValue))", res.sampleRate, res.synthMs, wav, String(format: "%.2fs gerados em %.0f ms (%d amostras @ 24kHz%@)", durSec, res.synthMs, res.samples.count, f0Note))
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
            let voicePref = effectiveTTSVoicePreference()
            try await appleTTS.synthesizeChunk(
                spokenText,
                language: language,
                voicePreference: voicePref,
                rate: effectiveRate
            ) { floats, _ in
                samplesBox.append(floats)
            }
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000.0
            let all = samplesBox.snapshot()
            guard !all.isEmpty else {
                return (false, "Apple Natural PCM", 24_000, elapsed, nil, "Nenhuma amostra gerada pela voz do macOS para \(language.displayName).")
            }
            let f0 = AcousticFeatureExtractor.measureMedianFundamentalFrequencyHz(samples: all, sampleRate: 24_000)
            recordProviderExecutionTruth(
                provider: appleTTS,
                voicePreference: voicePref,
                language: language,
                synthMs: elapsed,
                measuredF0Hz: f0,
                fallbackOccurred: ttsEngine != .appleNaturalPCM && ttsEngine != .autoLocal
            )
            let wav = CodexVoiceAudioCues.makeWAVContainer(
                pcm16Mono: AudioPCMConverter.floatsToPCM16Data(all),
                sampleRate: 24_000,
                channels: 1
            )
            if let saveToURL {
                try previewPlayer.saveWAV(samples: all, sampleRate: 24_000, to: saveToURL)
            }
            if playAudio {
                previewPlayer.playWAVData(wav, label: "Apple Natural (\(language.shortCode))")
            }
            let durSec = Double(all.count) / 24_000.0
            return (true, "Apple Natural PCM", 24_000, elapsed, wav, String(format: "%.2fs gerados em %.0f ms (%d amostras @ 24kHz)", durSec, elapsed, all.count))
        } catch {
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000.0
            return (false, "Apple Natural PCM", 24_000, elapsed, nil, error.localizedDescription)
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
            localBrain.prewarm(instructions: buildLocalBrainInstructions(for: behavior.languageVariant))
            brainStatus = localBrain.backendStatus
            let ms = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000.0
            let ready = brainStatus != .compactHeuristicFallback
            updateComponentStatus(
                .llm,
                state: ready ? .ready : .degraded,
                engineOrModel: brainStatus.rawValue,
                latencyMs: ms,
                dependencyHint: ready ? nil : (localBrain.lastErrorDetail ?? "Motor conversacional local indisponível.")
            )

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
        lines.append("Active Engines: STT=\(resolvedPipeline.activeSTTName) | LLM=\(brainStatus.rawValue) | TTS=\(resolvedPipeline.activeTTSName)")
        lines.append("AudioEngine Lifecycle: \(engStats.lifecycleState.rawValue) | AudioUnit: \(engStats.audioUnitState)")
        lines.append("AudioRoute Input: '\(engStats.inputDeviceName)' (\(Int(engStats.inputSampleRateHz))Hz, \(engStats.inputChannels)ch) | Output: '\(engStats.outputDeviceName)' (\(Int(engStats.outputSampleRateHz))Hz, \(engStats.outputChannels)ch)")
        lines.append("AudioGraph: VPIO=\(engStats.vpioActive ? "Enabled" : "Bypass/Off") (\(engStats.processingStatus.rawValue)) | Tap=\(engStats.tapInstalled ? "Installed" : "NotInstalled") | SplitCompat=\(engStats.isSplitEngineCompatibility) | Nodes=\(engStats.nodeGraphSummary)")
        lines.append("AudioOperations: LastOp=\(engStats.lastOperation.rawValue) | Restarts=\(engStats.restartCount) | AutoRecoveries=\(engStats.recoveryCount)")
        lines.append("AudioLastFailure: \(engStats.lastFailure?.formattedSummary ?? engStats.lastFaultDescription ?? "None")")
        lines.append(String(format: "Startup Latency: %.1f ms | Hardware Profile: %@ | OutHWLat: %.1f ms", lastStartupDurationMs, audioEngine.memoryProfile.displayName, hwOutLatency))
        lines.append(String(format: "Memory: App+Kokoro %.1f MB + llama-server %.1f MB = Total Voice Stack %.1f MB / %.1f GB RAM",
                            res.residentMemoryMB, telemetry.llamaServerMemoryMB, telemetry.totalVoiceStackMemoryMB, res.physicalRAMGB))
        lines.append(String(format: "Host: CPU %.1f%% (%d cores) | GPU: %@ (max %llu MB) | Free Disk: %.1f GB",
                            res.cpuPercent, res.cpuCoreCount, res.gpuName, res.gpuMaxRecommendedMB, modelAssetManager.availableDiskGB))
        lines.append("Audio Route: In='\(engStats.inputDeviceName)' Out='\(engStats.outputDeviceName)' Processing=\(engStats.processingStatus.rawValue)")
        lines.append("Installed Speech Locales: \(installedSpeechLocales.isEmpty ? "(pending probe)" : installedSpeechLocales.joined(separator: ", "))")
        lines.append("Installed PT Voices: \(installedPTVoicesCount) | Active Persona: \(voiceIdentity.persona.displayName) | Profile: \(behavior.profilePreset.displayName) | Engine: \(selectedTTSEngine.rawValue) | Kokoro: \(selectedKokoroPreset.rawValue) | Supertonic: \(selectedSupertonicPreset.rawValue)")
        lines.append("VoiceIdentityManager Requested: \(identityManager.requestedSnapshot.summary)")
        lines.append("VoiceIdentityManager Configured: \(identityManager.configuredSnapshot.summary)")
        let inf = identityManager.inferredSnapshot
        lines.append("VoiceIdentityManager Inferred: engine=\(inf.actualEngineId) model=\(inf.actualModelId) speaker=\(inf.actualSpeakerId) sid=\(inf.actualNumericSID.map { String($0) } ?? "-") F0=\(inf.estimatedF0Hz.map { String(format: "%.1fHz", $0) } ?? "-") fallback=\(inf.fallbackOccurred) alert=\(identityManager.divergenceAlert ?? "none")")
        lines.append(String(format: "Behavior Engine V3: ActiveListening=%@ (Emitted=%d Suppressed=%d) | Cache=%d clips (%.2f MB Hits=%d Misses=%d LatP50=%.1fms) | UserStyle=%@",
                            behavior.enableActiveListening ? "on" : "off",
                            telemetry.backchannelsEmittedCount,
                            telemetry.backchannelsSuppressedCount,
                            vocalizationCache.cachedClipsCount,
                            vocalizationCache.cacheMemoryMB,
                            vocalizationCache.hitCount,
                            vocalizationCache.missCount,
                            telemetry.vocalizationCacheLatencyStats.p50Ms,
                            userStyleAdapter.snapshotSummary()))
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

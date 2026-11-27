import Foundation

// MARK: - WisdAI Exclusive Voice Identity (Section 8 — Independent of Coding Agents & Accounts)

public enum WisdVoiceTimbre: String, CaseIterable, Identifiable, Codable, Sendable {
    case female
    case male

    public var id: String { rawValue }
}

public enum WisdVoicePersona: String, CaseIterable, Identifiable, Codable, Sendable {
    case aurora   // WisdAI Signature Female Natural
    case atlas    // WisdAI Structured Male
    case aria     // WisdAI Energetic Brainstorm

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .aurora: return "Aurora · WisdAI Padrão"
        case .atlas: return "Atlas · WisdAI Estruturada"
        case .aria: return "Aria · WisdAI Dinâmica"
        }
    }

    public var subtitle: String {
        switch self {
        case .aurora: return "Timbre natural, acolhedor e fluido"
        case .atlas: return "Tom firme, calmo e técnico"
        case .aria: return "Ritmo ágil e colaborativo para brainstorming"
        }
    }

    public var recommendedTimbre: WisdVoiceTimbre {
        switch self {
        case .aurora, .aria: return .female
        case .atlas: return .male
        }
    }

    public var kokoroStyleVectorID: String {
        switch self {
        case .aurora: return "pf_dora"
        case .atlas: return "pm_santa"
        case .aria: return "pf_dora"
        }
    }

    public var baseCadenceRate: Float {
        switch self {
        case .aurora: return 1.00
        case .atlas: return 0.96
        case .aria: return 1.07
        }
    }
}

public struct VoiceIdentityDescriptor: Equatable, Codable, Sendable {
    public var persona: WisdVoicePersona
    public var warmth: Double          // 0.0...1.0
    public var clarityEmphasis: Double // 0.0...1.0
    public var brandName: String       // "WisdAI"

    public static let wisdAIDefault = VoiceIdentityDescriptor(
        persona: .aurora,
        warmth: 0.80,
        clarityEmphasis: 0.75,
        brandName: "WisdAI"
    )
}

// MARK: - Local Model Asset & Disk / RAM Feasibility Manager (Sections 14, 16, 23)

public struct LocalVoiceModelDescriptor: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let displayName: String
    public let kind: String // "TTS" | "STT" | "LLM"
    public let licenseName: String
    public let sizeBytes: Int64
    public let minimumRAMProfile: HardwareMemoryProfile
    public let description: String

    public var sizeMBText: String {
        let mb = Double(sizeBytes) / (1024.0 * 1024.0)
        return String(format: "%.0f MB", mb)
    }
}

public struct ModelAssetTransferState: Equatable, Sendable {
    public var modelID: String
    public var modelName: String
    public var isDownloading: Bool
    public var progress: Double
    public var bytesPerSecond: Double
    public var statusMessage: String
}

public enum VoiceModelCatalog {
    public static let availableLocalModels: [LocalVoiceModelDescriptor] = [
        LocalVoiceModelDescriptor(
            id: "apple-speech-analyzer-ondevice",
            displayName: "Apple SpeechTranscriber (On-Device)",
            kind: "STT",
            licenseName: "Apple macOS SDK",
            sizeBytes: 0,
            minimumRAMProfile: .low8GB,
            description: "Reconhecimento local PT-BR/PT-PT integrado ao macOS sem download adicional."
        ),
        LocalVoiceModelDescriptor(
            id: "apple-foundation-models-ane",
            displayName: "Apple FoundationModels (On-Device ANE)",
            kind: "LLM",
            licenseName: "Apple macOS SDK",
            sizeBytes: 0,
            minimumRAMProfile: .low8GB,
            description: "Cérebro conversacional local executado no Apple Neural Engine sem chaves ou downloads."
        ),
        LocalVoiceModelDescriptor(
            id: "apple-natural-pcm",
            displayName: "Apple Voz Natural (PCM Streaming)",
            kind: "TTS",
            licenseName: "Apple macOS SDK",
            sizeBytes: 0,
            minimumRAMProfile: .low8GB,
            description: "Voz local do sistema operacional com aquecimento silencioso (~158 ms)."
        ),
        LocalVoiceModelDescriptor(
            id: "kokoro-82m-ptbr-onnx",
            displayName: "Kokoro-82M Neural PT-BR / Multilíngue",
            kind: "TTS",
            licenseName: "Apache-2.0",
            sizeBytes: 335_000_000,
            minimumRAMProfile: .low8GB,
            description: "Motor expressivo open-source 82M (pf_dora / pm_santa) com vetores de estilo próprios WisdAI. Requer autorização de download (~320 MB)."
        )
    ]

    public static func availableDiskSpaceBytes() -> Int64 {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }
}

@MainActor
public final class VoiceModelAssetManager: ObservableObject {
    @Published public private(set) var activeTransfer: ModelAssetTransferState?
    @Published public private(set) var availableDiskGB: Double = 0
    @Published public private(set) var hardwareProfile: HardwareMemoryProfile = .detect()

    private var downloadTask: URLSessionDownloadTask?

    public init() {
        refreshStorageInfo()
    }

    public func refreshStorageInfo() {
        hardwareProfile = HardwareMemoryProfile.detect()
        let bytes = VoiceModelCatalog.availableDiskSpaceBytes()
        availableDiskGB = Double(bytes) / 1_073_741_824.0
    }

    public func canFitOnDevice(_ model: LocalVoiceModelDescriptor) -> (ok: Bool, reason: String?) {
        let freeBytes = VoiceModelCatalog.availableDiskSpaceBytes()
        if freeBytes > 0 && freeBytes < (model.sizeBytes + 500_000_000) {
            let gb = Double(freeBytes) / 1_073_741_824.0
            return (false, "Espaço insuficiente em disco (\(String(format: "%.1f", gb)) GB livres).")
        }
        return (true, nil)
    }

    public func cancelTransfer() {
        downloadTask?.cancel()
        downloadTask = nil
        activeTransfer = nil
    }
}

// MARK: - Silent Proactive TTS Warmup (Eliminates 2.8s Cold Speech Daemon Lag)

public enum VoiceTTSWarmupCoordinator {
    /// Silently pre-warms speechsynthesisd via in-memory `write` without emitting any speaker audio.
    public static func warmupInBackground(
        provider: AppleNaturalPCMStreamingTTSProvider,
        language: VoiceLanguageVariant,
        voicePreference: String
    ) {
        Task.detached(priority: .utility) {
            try? await provider.synthesizeChunk(
                "Oi.",
                language: language,
                voicePreference: voicePreference,
                rate: 1.0
            ) { _, _ in
                // Deliberately discard warmup PCM samples; goal is daemon initialization only.
            }
        }
    }
}

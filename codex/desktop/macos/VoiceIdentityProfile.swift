import CryptoKit
import Foundation

// MARK: - WisdAI Exclusive Voice Identity & V2 Neural Capabilities

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
        case .atlas: return "pm_alex"
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

// MARK: - Hardware Tiers, Execution Mode & Neural Engine Selectors (Phases 3–5, 10–11)

public enum VoiceHardwareTier: String, CaseIterable, Identifiable, Codable, Sendable {
    case automatic = "automatic"
    case essential8GB = "essential_8gb"
    case advanced16to24GB = "advanced_16_24gb"
    case ultra32PlusGB = "ultra_32plus_gb"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .automatic: return "Automático (Detectado)"
        case .essential8GB: return "Essential (8 GB RAM)"
        case .advanced16to24GB: return "Advanced (16–24 GB RAM)"
        case .ultra32PlusGB: return "Ultra (32–64+ GB RAM)"
        }
    }

    public var recommendationSummary: String {
        switch self {
        case .automatic:
            return "Detecta a memória física do Mac e limita modelos simultâneos automaticamente."
        case .essential8GB:
            return "Apple FM ou Qwen3-1.7B Q4 + Kokoro INT8 (~140 MB). Libera modelo sob pressão de memória."
        case .advanced16to24GB:
            return "Qwen3-4B / Gemma-3-4B Q4 + Kokoro FP32/INT8 ou MLX local de baixa latência."
        case .ultra32PlusGB:
            return "Modelos 7B–8B, múltiplos agentes e Speech-to-Speech nativo experimental quando runtime instalado."
        }
    }

    public func resolvedRAMGB(physicalGB: Double = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0) -> Double {
        switch self {
        case .automatic: return physicalGB
        case .essential8GB: return min(physicalGB, 8.0)
        case .advanced16to24GB: return min(physicalGB, 16.0)
        case .ultra32PlusGB: return min(physicalGB, 32.0)
        }
    }

    public func effectiveMemoryProfile() -> HardwareMemoryProfile {
        switch self {
        case .automatic: return .detect()
        case .essential8GB: return .low8GB
        case .advanced16to24GB: return .balanced16GB
        case .ultra32PlusGB: return .studio32GBPlus
        }
    }
}

public enum VoiceExecutionArchitectureMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case neuralHybrid = "neural_hybrid"
    case nativeSpeechToSpeech = "native_s2s"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .neuralHybrid: return "Híbrido Neural Local (STT → Brain → TTS)"
        case .nativeSpeechToSpeech: return "Speech-to-Speech Nativo (Moshi / MiniCPM-o · Experimental)"
        }
    }
}

public enum VoiceTTSEngineKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case autoLocal = "auto_local"
    case kokoro82M = "kokoro_82m"
    case sherpaPiperVits = "sherpa_piper_vits"
    case appleNaturalPCM = "apple_natural"
    case cosyVoice2 = "cosyvoice2"
    case chatterbox = "chatterbox"
    case sesameCSM = "sesame_csm"
    case diaTTS = "dia_tts"
    case f5TTS = "f5_tts"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .autoLocal: return "Automático Local (Kokoro Neural se pronto, senão Apple Natural)"
        case .kokoro82M: return "Kokoro-82M Neural (ONNX Local · PT-BR / EN / ES)"
        case .sherpaPiperVits: return "Piper VITS Neural (ONNX Local · PT-BR & PT-PT Nativo · PoC)"
        case .appleNaturalPCM: return "Apple Voz Natural (macOS Nativo · Sem Download)"
        case .cosyVoice2: return "CosyVoice2 / 3 (Servidor MLX/PyTorch Loopback)"
        case .chatterbox: return "Chatterbox Multilingual MIT (Servidor MLX Loopback)"
        case .sesameCSM: return "Sesame CSM-1B (Servidor MLX/PyTorch · Inglês)"
        case .diaTTS: return "Nari Labs Dia-1.6B (Apache-2.0 · Inglês · 10+ GB RAM)"
        case .f5TTS: return "F5-TTS (Aviso: Licença CC-BY-NC-4.0 Não Comercial)"
        }
    }

    public var supportsExplicitEmotionSlider: Bool {
        switch self {
        case .chatterbox, .cosyVoice2: return true
        default: return false
        }
    }

    public var supportsSpeedControl: Bool {
        switch self {
        case .autoLocal, .kokoro82M, .sherpaPiperVits, .appleNaturalPCM, .chatterbox, .cosyVoice2:
            return true
        default:
            return false
        }
    }

    public var supportsPitchControl: Bool {
        switch self {
        case .appleNaturalPCM: return true
        default: return false
        }
    }

    public var supportsDynamicSilenceScale: Bool {
        switch self {
        case .autoLocal, .kokoro82M, .sherpaPiperVits: return true
        default: return false
        }
    }

    public var supportsCustomProfileSettings: Bool {
        return supportsSpeedControl
    }

    public var licenseWarning: String? {
        switch self {
        case .f5TTS:
            return "F5-TTS utiliza licença CC-BY-NC-4.0 (uso estritamente não comercial) e requer ambiente Python/PyTorch separado."
        case .cosyVoice2, .chatterbox, .sesameCSM, .diaTTS:
            return "Requer servidor local mlx-audio / PyTorch em 127.0.0.1 iniciado pelo usuário; não empacotado neste app."
        case .sherpaPiperVits:
            return "PoC alternativa leve (MIT + espeak-ng GPL via sherpa-onnx C ABI) com suporte genuíno a PT-BR e PT-PT; requer pesos Piper em Application Support."
        default:
            return nil
        }
    }

    public func supportsLanguage(_ language: VoiceLanguageVariant) -> Bool {
        switch self {
        case .kokoro82M:
            // Kokoro "p" lexicon targets Brazilian Portuguese specifically, NOT European Portuguese.
            return language == .portugueseBR || language == .englishUS || language == .spanishES
        case .sherpaPiperVits, .appleNaturalPCM, .autoLocal:
            return true
        case .sesameCSM, .diaTTS:
            return language == .englishUS
        case .cosyVoice2, .f5TTS:
            return language == .englishUS || language == .spanishES
        case .chatterbox:
            return true // Chatterbox Multilingual covers PT, EN, ES (with community PT-BR / PT-PT packs)
        }
    }
}

public enum KokoroVoicePreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case pfDora = "pf_dora"
    case pmAlex = "pm_alex"
    case pmSanta = "pm_santa"
    case afHeart = "af_heart"
    case afBella = "af_bella"
    case afNova = "af_nova"
    case amFenrir = "am_fenrir"
    case amMichael = "am_michael"
    case efDora = "ef_dora"
    case emAlex = "em_alex"
    case emSanta = "em_santa"

    public var id: String { rawValue }

    /// Exact speaker ID table from k2-fsa/sherpa-onnx v1.0 multi-lang generate_voices_bin.py
    public var speakerID: Int32 {
        switch self {
        case .afBella: return 2
        case .afHeart: return 3
        case .afNova: return 7
        case .amFenrir: return 14
        case .amMichael: return 16
        case .efDora: return 28
        case .emAlex: return 29
        case .pfDora: return 42
        case .pmAlex: return 43
        case .pmSanta: return 44
        case .emSanta: return 53
        }
    }

    /// Upstream sherpa-onnx / espeak-ng voice identifiers for kokoro-multi-lang-v1_0
    public var kokoroLangCode: String {
        switch self {
        case .pfDora, .pmAlex, .pmSanta: return "pt-br"
        case .afHeart, .afBella, .afNova, .amFenrir, .amMichael: return "en-us"
        case .efDora, .emAlex, .emSanta: return "es"
        }
    }

    public var supportedLanguage: VoiceLanguageVariant {
        switch self {
        case .pfDora, .pmAlex, .pmSanta: return .portugueseBR
        case .afHeart, .afBella, .afNova, .amFenrir, .amMichael: return .englishUS
        case .efDora, .emAlex, .emSanta: return .spanishES
        }
    }

    public var displayName: String {
        switch self {
        case .pfDora: return "Aurora / Dora (pf_dora · PT-BR Feminina)"
        case .pmAlex: return "Alex (pm_alex · PT-BR Masculina)"
        case .pmSanta: return "Atlas / Santa (pm_santa · PT-BR Masculina Grave)"
        case .afHeart: return "Heart (af_heart · EN-US Feminina)"
        case .afBella: return "Bella (af_bella · EN-US Feminina)"
        case .afNova: return "Nova (af_nova · EN-US Feminina)"
        case .amFenrir: return "Fenrir (am_fenrir · EN-US Masculina)"
        case .amMichael: return "Michael (am_michael · EN-US Masculina)"
        case .efDora: return "Dora ES (ef_dora · Español Feminina)"
        case .emAlex: return "Alex ES (em_alex · Español Masculina)"
        case .emSanta: return "Santa ES (em_santa · Español Masculina)"
        }
    }

    public static func defaultPreset(for persona: WisdVoicePersona, language: VoiceLanguageVariant) -> KokoroVoicePreset? {
        switch language {
        case .portugueseBR:
            return persona.recommendedTimbre == .male ? .pmAlex : .pfDora
        case .portuguesePT:
            // Kokoro does NOT speak genuine European Portuguese; return nil rather than faking pt-PT.
            return nil
        case .englishUS:
            return persona.recommendedTimbre == .male ? .amMichael : .afHeart
        case .spanishES:
            return persona.recommendedTimbre == .male ? .emAlex : .efDora
        }
    }
}

// MARK: - Explicit Real Model Lifecycle States (Section 4)

public enum VoiceModelInstallState: String, Codable, Sendable, Equatable {
    case notInstalled = "Não instalado"
    case awaitingConsent = "Aguardando autorização"
    case installing = "Instalando"
    case available = "Disponível"
    case loading = "Carregando"
    case operational = "Operacional"
    case incompatible = "Incompatível"
    case error = "Erro"
}

public enum LocalModelCategory: String, Codable, Sendable {
    case runtime = "Runtime"
    case stt = "STT"
    case llm = "LLM"
    case tts = "TTS"
    case s2s = "S2S"
}

public enum LocalArchiveFormat: String, Codable, Sendable {
    case builtIn
    case rawFile
    case tarBz2
    case tarGz
    case externalManual
}

public struct LocalVoiceModelDescriptor: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let displayName: String
    public let kind: String // "STT" | "LLM" | "TTS" | "Runtime" | "S2S"
    public let category: LocalModelCategory
    public let licenseName: String
    public let licenseWarning: String?
    public let sizeBytes: Int64
    public let minimumRAMProfile: HardwareMemoryProfile
    public let minimumRAMGB: Double
    public let supportedLanguages: [String]
    public let supportsEmotionControl: Bool
    public let downloadURLString: String?
    public let expectedSHA256: String?
    public let archiveFormat: LocalArchiveFormat
    public let relativeEntryPoint: String?
    public let requiredRuntimeID: String?
    public let description: String

    public init(
        id: String,
        displayName: String,
        kind: String,
        category: LocalModelCategory = .tts,
        licenseName: String,
        licenseWarning: String? = nil,
        sizeBytes: Int64,
        minimumRAMProfile: HardwareMemoryProfile,
        minimumRAMGB: Double = 8.0,
        supportedLanguages: [String] = ["pt-BR", "en-US"],
        supportsEmotionControl: Bool = false,
        downloadURLString: String? = nil,
        expectedSHA256: String? = nil,
        archiveFormat: LocalArchiveFormat = .builtIn,
        relativeEntryPoint: String? = nil,
        requiredRuntimeID: String? = nil,
        description: String
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.category = category
        self.licenseName = licenseName
        self.licenseWarning = licenseWarning
        self.sizeBytes = sizeBytes
        self.minimumRAMProfile = minimumRAMProfile
        self.minimumRAMGB = minimumRAMGB
        self.supportedLanguages = supportedLanguages
        self.supportsEmotionControl = supportsEmotionControl
        self.downloadURLString = downloadURLString
        self.expectedSHA256 = expectedSHA256
        self.archiveFormat = archiveFormat
        self.relativeEntryPoint = relativeEntryPoint
        self.requiredRuntimeID = requiredRuntimeID
        self.description = description
    }

    public var sizeMBText: String {
        if sizeBytes == 0 { return "Integrado" }
        let gb = Double(sizeBytes) / 1_073_741_824.0
        if gb >= 1.0 {
            return String(format: "%.2f GB", gb)
        }
        let mb = Double(sizeBytes) / (1024.0 * 1024.0)
        return String(format: "%.0f MB", mb)
    }

    public var isDownloadable: Bool {
        downloadURLString != nil && expectedSHA256 != nil && archiveFormat != .externalManual
    }
}

public struct ModelAssetTransferState: Equatable, Sendable {
    public var modelID: String
    public var modelName: String
    public var isDownloading: Bool
    public var progress: Double
    public var downloadedBytes: Int64
    public var totalBytes: Int64
    public var bytesPerSecond: Double
    public var statusMessage: String
}

// MARK: - Verified Real Model & Runtime Catalog (2026-11 Upstream Checksums)

public enum VoiceModelCatalog {
    public static let sherpaRuntimeID = "sherpa-onnx-v1.13.8-arm64"
    public static let kokoroInt8ModelID = "kokoro-82m-ptbr-onnx"
    public static let kokoroFP32ModelID = "kokoro-82m-multilang-fp32"
    public static let llamaRuntimeID = "llama-cpp-b12809-metal"
    public static let qwen3SmallID = "qwen3-1.7b-q4_k_m"
    public static let qwen25SmallID = "qwen2.5-1.5b-instruct-q4_k_m"
    public static let gemma3SmallID = "gemma-3-1b-it-q4_k_m"
    public static let qwen3MediumID = "qwen3-4b-q4_k_m"
    public static let gemma3MediumID = "google-gemma-3-4b-it-q4_k_m"
    public static let llama32MediumID = "llama-3.2-3b-instruct-q4_k_m"
    public static let phi4MiniID = "microsoft-phi-4-mini-instruct-q4_k_m"

    public static let availableLocalModels: [LocalVoiceModelDescriptor] = [
        // 1. Built-in macOS Zero-Download Baseline
        LocalVoiceModelDescriptor(
            id: "apple-speech-analyzer-ondevice",
            displayName: "Apple SpeechTranscriber (On-Device)",
            kind: "STT",
            category: .stt,
            licenseName: "Apple macOS SDK",
            sizeBytes: 0,
            minimumRAMProfile: .low8GB,
            minimumRAMGB: 8.0,
            supportedLanguages: ["pt-BR", "pt-PT", "en-US", "es-ES"],
            archiveFormat: .builtIn,
            description: "Reconhecimento local integrado ao macOS (SpeechAnalyzer/SpeechTranscriber) sem download."
        ),
        LocalVoiceModelDescriptor(
            id: "apple-foundation-models-ane",
            displayName: "Apple FoundationModels (On-Device ANE)",
            kind: "LLM",
            category: .llm,
            licenseName: "Apple macOS SDK",
            sizeBytes: 0,
            minimumRAMProfile: .low8GB,
            minimumRAMGB: 8.0,
            supportedLanguages: ["pt-BR", "pt-PT", "en-US", "es-ES"],
            archiveFormat: .builtIn,
            description: "Cérebro conversacional nativo no Apple Neural Engine sem API key ou download."
        ),
        LocalVoiceModelDescriptor(
            id: "apple-natural-pcm",
            displayName: "Apple Voz Natural (PCM Streaming)",
            kind: "TTS",
            category: .tts,
            licenseName: "Apple macOS SDK",
            sizeBytes: 0,
            minimumRAMProfile: .low8GB,
            minimumRAMGB: 8.0,
            supportedLanguages: ["pt-BR", "pt-PT", "en-US", "es-ES"],
            archiveFormat: .builtIn,
            description: "Voz natural do macOS (Luciana/Joana/Samantha) via PCM Streaming sem download."
        ),

        // 2. Local Neural TTS Runtimes & Kokoro-82M (PT-BR, EN-US, ES-ES; NOT pt-PT)
        LocalVoiceModelDescriptor(
            id: sherpaRuntimeID,
            displayName: "sherpa-onnx C Runtime v1.13.8 (macOS arm64)",
            kind: "Runtime",
            category: .runtime,
            licenseName: "Apache-2.0 (+ espeak-ng GPL-3.0)",
            sizeBytes: 8_773_198,
            minimumRAMProfile: .low8GB,
            minimumRAMGB: 8.0,
            supportedLanguages: ["pt-BR", "en-US", "es-ES"],
            downloadURLString: "https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.8/sherpa-onnx-v1.13.8-osx-arm64-shared-lib.tar.bz2",
            expectedSHA256: "ae77050cdae565496059d96f5ab33d77b397a0864282a4e4a26e3b3b3effb948",
            archiveFormat: .tarBz2,
            relativeEntryPoint: "sherpa-onnx-v1.13.8-osx-arm64-shared-lib/lib/libsherpa-onnx-c-api.dylib",
            description: "Bibliotecas dinâmicas ONNX + C API com G2P integrado (espeak-ng) para Kokoro-82M multilíngue no macOS arm64."
        ),
        LocalVoiceModelDescriptor(
            id: kokoroInt8ModelID,
            displayName: "Kokoro-82M Multi-Lang INT8 (v1.0 · PT-BR / EN / ES)",
            kind: "TTS",
            category: .tts,
            licenseName: "Apache-2.0",
            sizeBytes: 132_353_410,
            minimumRAMProfile: .low8GB,
            minimumRAMGB: 8.0,
            supportedLanguages: ["pt-BR", "en-US", "es-ES"],
            supportsEmotionControl: false,
            downloadURLString: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-int8-multi-lang-v1_0.tar.bz2",
            expectedSHA256: "72c347230107ef8a31098ec4d468a605244beef5f1ed00db97efa13518800653",
            archiveFormat: .tarBz2,
            relativeEntryPoint: "kokoro-int8-multi-lang-v1_0/model.int8.onnx",
            requiredRuntimeID: sherpaRuntimeID,
            description: "Síntese neural Kokoro-82M INT8 (24 kHz) com pf_dora, pm_alex e pm_santa em PT-BR, EN-US e ES-ES. Não suporta pt-PT nativo."
        ),
        LocalVoiceModelDescriptor(
            id: kokoroFP32ModelID,
            displayName: "Kokoro-82M Multi-Lang FP32 (v1.0 · Alta Fidelidade)",
            kind: "TTS",
            category: .tts,
            licenseName: "Apache-2.0",
            sizeBytes: 349_886_476,
            minimumRAMProfile: .balanced16GB,
            minimumRAMGB: 12.0,
            supportedLanguages: ["pt-BR", "en-US", "es-ES"],
            supportsEmotionControl: false,
            downloadURLString: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_0.tar.bz2",
            expectedSHA256: "60703707bc05ccd48d60e1eb723f38b07d6e474795a0b6a588d7220400e0f7a4",
            archiveFormat: .tarBz2,
            relativeEntryPoint: "kokoro-multi-lang-v1_0/model.onnx",
            requiredRuntimeID: sherpaRuntimeID,
            description: "Versão completa FP32 (54 vozes, 24 kHz) recomendada para Macs de 16+ GB RAM."
        ),

        // 3. Interchangeable Local LLM Runtime + GGUF Catalog (Phase 3)
        LocalVoiceModelDescriptor(
            id: llamaRuntimeID,
            displayName: "llama.cpp Metal Runtime b12809 (macOS arm64)",
            kind: "Runtime",
            category: .runtime,
            licenseName: "MIT",
            sizeBytes: 16_894_812,
            minimumRAMProfile: .low8GB,
            minimumRAMGB: 8.0,
            supportedLanguages: ["pt-BR", "pt-PT", "en-US", "es-ES"],
            downloadURLString: "https://github.com/ggml-org/llama.cpp/releases/download/b12809/llama-b12809-bin-macos-arm64.tar.gz",
            expectedSHA256: "ff05fb893855a926cc5a5f5c049b741a6196261133493ef14698d2604e3b7df5",
            archiveFormat: .tarGz,
            relativeEntryPoint: "llama-b12809/llama-server",
            description: "Servidor local loopback (127.0.0.1) com aceleração Apple Metal para modelos GGUF Qwen, Gemma, Llama e Phi."
        ),
        LocalVoiceModelDescriptor(
            id: qwen3SmallID,
            displayName: "Qwen3-1.7B Instruct Q4_K_M",
            kind: "LLM",
            category: .llm,
            licenseName: "Apache-2.0",
            sizeBytes: 1_107_409_472,
            minimumRAMProfile: .low8GB,
            minimumRAMGB: 8.0,
            supportedLanguages: ["pt-BR", "pt-PT", "en-US", "es-ES"],
            downloadURLString: "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf",
            expectedSHA256: "b139949c5bd74937ad8ed8c8cf3d9ffb1e99c866c823204dc42c0d91fa181897",
            archiveFormat: .rawFile,
            relativeEntryPoint: "Qwen3-1.7B-Q4_K_M.gguf",
            requiredRuntimeID: llamaRuntimeID,
            description: "Modelo local rápido em Português/Inglês (~1.03 GB), ideal para Perfil Essential 8 GB via Metal."
        ),
        LocalVoiceModelDescriptor(
            id: qwen25SmallID,
            displayName: "Qwen2.5-1.5B Instruct Q4_K_M",
            kind: "LLM",
            category: .llm,
            licenseName: "Apache-2.0",
            sizeBytes: 1_117_320_736,
            minimumRAMProfile: .low8GB,
            minimumRAMGB: 8.0,
            supportedLanguages: ["pt-BR", "pt-PT", "en-US", "es-ES"],
            downloadURLString: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf",
            expectedSHA256: "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e",
            archiveFormat: .rawFile,
            relativeEntryPoint: "qwen2.5-1.5b-instruct-q4_k_m.gguf",
            requiredRuntimeID: llamaRuntimeID,
            description: "Alternativa leve Apache-2.0 (~1.04 GB) com baixa pegada de memória."
        ),
        LocalVoiceModelDescriptor(
            id: gemma3SmallID,
            displayName: "Gemma-3-1B Instruct Q4_K_M",
            kind: "LLM",
            category: .llm,
            licenseName: "Gemma License",
            sizeBytes: 806_058_272,
            minimumRAMProfile: .low8GB,
            minimumRAMGB: 8.0,
            supportedLanguages: ["pt-BR", "pt-PT", "en-US", "es-ES"],
            downloadURLString: "https://huggingface.co/unsloth/gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-Q4_K_M.gguf",
            expectedSHA256: "8270790f3ab69fdfe860b7b64008d9a19986d8df7e407bb018184caa08798ebd",
            archiveFormat: .rawFile,
            relativeEntryPoint: "gemma-3-1b-it-Q4_K_M.gguf",
            requiredRuntimeID: llamaRuntimeID,
            description: "Modelo ultraleve de 1B (~769 MB) para respostas conversacionais muito rápidas em 8 GB RAM."
        ),
        LocalVoiceModelDescriptor(
            id: qwen3MediumID,
            displayName: "Qwen3-4B Instruct Q4_K_M",
            kind: "LLM",
            category: .llm,
            licenseName: "Apache-2.0",
            sizeBytes: 2_497_281_312,
            minimumRAMProfile: .balanced16GB,
            minimumRAMGB: 16.0,
            supportedLanguages: ["pt-BR", "pt-PT", "en-US", "es-ES"],
            downloadURLString: "https://huggingface.co/unsloth/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf",
            expectedSHA256: "f6f851777709861056efcdad3af01da38b31223a3ba26e61a4f8bf3a2195813a",
            archiveFormat: .rawFile,
            relativeEntryPoint: "Qwen3-4B-Q4_K_M.gguf",
            requiredRuntimeID: llamaRuntimeID,
            description: "Raciocínio local superior (~2.33 GB) para Macs de 16+ GB RAM (Perfil Advanced)."
        ),
        LocalVoiceModelDescriptor(
            id: gemma3MediumID,
            displayName: "Gemma-3-4B Instruct Q4_K_M",
            kind: "LLM",
            category: .llm,
            licenseName: "Gemma License",
            sizeBytes: 2_489_758_112,
            minimumRAMProfile: .balanced16GB,
            minimumRAMGB: 16.0,
            supportedLanguages: ["pt-BR", "pt-PT", "en-US", "es-ES"],
            downloadURLString: "https://huggingface.co/bartowski/google_gemma-3-4b-it-GGUF/resolve/main/google_gemma-3-4b-it-Q4_K_M.gguf",
            expectedSHA256: "4996030242583a40aa151ff93f49ed787ac8c25e4120c3ae4588b2e2a7d1ae94",
            archiveFormat: .rawFile,
            relativeEntryPoint: "google_gemma-3-4b-it-Q4_K_M.gguf",
            requiredRuntimeID: llamaRuntimeID,
            description: "Gemma 3 4B quantizado Q4_K_M (~2.32 GB) para Macs 16+ GB."
        ),
        LocalVoiceModelDescriptor(
            id: llama32MediumID,
            displayName: "Llama-3.2-3B Instruct Q4_K_M",
            kind: "LLM",
            category: .llm,
            licenseName: "Llama 3.2 Community",
            sizeBytes: 2_019_377_696,
            minimumRAMProfile: .balanced16GB,
            minimumRAMGB: 12.0,
            supportedLanguages: ["pt-BR", "pt-PT", "en-US", "es-ES"],
            downloadURLString: "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf",
            expectedSHA256: "6c1a2b41161032677be168d354123594c0e6e67d2b9227c84f296ad037c728ff",
            archiveFormat: .rawFile,
            relativeEntryPoint: "Llama-3.2-3B-Instruct-Q4_K_M.gguf",
            requiredRuntimeID: llamaRuntimeID,
            description: "Llama 3.2 3B (~1.88 GB) equilibrado para diálogo multi-idioma."
        ),
        LocalVoiceModelDescriptor(
            id: phi4MiniID,
            displayName: "Phi-4-mini Instruct Q4_K_M",
            kind: "LLM",
            category: .llm,
            licenseName: "MIT",
            sizeBytes: 2_491_874_688,
            minimumRAMProfile: .balanced16GB,
            minimumRAMGB: 16.0,
            supportedLanguages: ["en-US", "pt-BR"],
            downloadURLString: "https://huggingface.co/bartowski/microsoft_Phi-4-mini-instruct-GGUF/resolve/main/microsoft_Phi-4-mini-instruct-Q4_K_M.gguf",
            expectedSHA256: "01999f17c39cc3074afae5e9c539bc82d45f2dd7faa3917c66cbef76fce8c0c2",
            archiveFormat: .rawFile,
            relativeEntryPoint: "microsoft_Phi-4-mini-instruct-Q4_K_M.gguf",
            requiredRuntimeID: llamaRuntimeID,
            description: "Microsoft Phi-4-mini (~2.32 GB) sob licença MIT para raciocínio técnico."
        ),

        // 4. Honest S2S & Heavy Alternative TTS Catalog Entries (Hardware & Runtime Gated)
        LocalVoiceModelDescriptor(
            id: "cosyvoice2-0.5b",
            displayName: "CosyVoice2-0.5B (PyTorch / FunASR)",
            kind: "TTS",
            category: .tts,
            licenseName: "Apache-2.0",
            licenseWarning: "Sem binário nativo Swift/ONNX oficial para macOS; requer runtime Python/PyTorch externo.",
            sizeBytes: 2_100_000_000,
            minimumRAMProfile: .balanced16GB,
            minimumRAMGB: 16.0,
            supportedLanguages: ["en-US"],
            supportsEmotionControl: true,
            archiveFormat: .externalManual,
            description: "Catálogo técnico: excelente expressividade zero-shot, mas depende de stack Python/PyTorch externa."
        ),
        LocalVoiceModelDescriptor(
            id: "chatterbox-mit",
            displayName: "Chatterbox (~500M · PyTorch)",
            kind: "TTS",
            category: .tts,
            licenseName: "MIT",
            licenseWarning: "Pesos ~13.2 GB e inferência PyTorch pesada; incompatível com operação fluida em 8 GB RAM.",
            sizeBytes: 13_223_900_000,
            minimumRAMProfile: .balanced16GB,
            minimumRAMGB: 16.0,
            supportedLanguages: ["pt-BR", "en-US", "es-ES"],
            supportsEmotionControl: true,
            archiveFormat: .externalManual,
            description: "Catálogo técnico: suporte MIT multilíngue com clonagem/emoção, pesado para Apple M2 8 GB."
        ),
        LocalVoiceModelDescriptor(
            id: "sesame-csm-1b",
            displayName: "Sesame CSM-1B (PyTorch)",
            kind: "TTS",
            category: .tts,
            licenseName: "Apache-2.0",
            licenseWarning: "Requer ~18.6 GB em disco/VRAM e runtime PyTorch; focado em inglês.",
            sizeBytes: 18_681_700_000,
            minimumRAMProfile: .performance24GB,
            minimumRAMGB: 24.0,
            supportedLanguages: ["en-US"],
            archiveFormat: .externalManual,
            description: "Catálogo técnico: modelo conversacional 1B em inglês inviável nativamente em 8 GB RAM."
        ),
        LocalVoiceModelDescriptor(
            id: "vits-piper-pt_BR-faber-medium",
            displayName: "Piper VITS PT-BR (faber-medium · PoC ONNX)",
            kind: "TTS",
            category: .tts,
            licenseName: "MIT (via sherpa-onnx C ABI)",
            licenseWarning: "Instalação opcional via pasta local em Application Support/WisdAI/Voice/Models/vits-piper-pt_BR-faber-medium (reutiliza libsherpa-onnx-c-api.dylib já instalada).",
            sizeBytes: 63_200_000,
            minimumRAMProfile: .low8GB,
            minimumRAMGB: 8.0,
            supportedLanguages: ["pt-BR"],
            supportsEmotionControl: false,
            archiveFormat: .externalManual,
            requiredRuntimeID: sherpaRuntimeID,
            description: "Alternativa VITS ultraleve (~63 MB, latência baixa em CPU) sem substituir Kokoro-82M."
        ),
        LocalVoiceModelDescriptor(
            id: "vits-piper-pt_PT-tugao-medium",
            displayName: "Piper VITS PT-PT (tugao-medium · PoC Nativo)",
            kind: "TTS",
            category: .tts,
            licenseName: "MIT (via sherpa-onnx C ABI)",
            licenseWarning: "Alternativa genuína em Português Europeu (pt-PT); instalação manual/local em Models/vits-piper-pt_PT-tugao-medium.",
            sizeBytes: 63_500_000,
            minimumRAMProfile: .low8GB,
            minimumRAMGB: 8.0,
            supportedLanguages: ["pt-PT"],
            supportsEmotionControl: false,
            archiveFormat: .externalManual,
            requiredRuntimeID: sherpaRuntimeID,
            description: "Modelo VITS local em Português Europeu nativo como prova de conceito para suprir lacuna pt-PT do Kokoro."
        ),
        LocalVoiceModelDescriptor(
            id: "nari-dia-1.6b",
            displayName: "Nari Labs Dia-1.6B (Apache-2.0 · Inglês)",
            kind: "TTS",
            category: .tts,
            licenseName: "Apache-2.0",
            licenseWarning: "Exige 8–10+ GB de memória unificada e é focado em inglês; inviável simultaneamente com LLM em 8 GB RAM.",
            sizeBytes: 6_400_000_000,
            minimumRAMProfile: .balanced16GB,
            minimumRAMGB: 16.0,
            supportedLanguages: ["en-US"],
            supportsEmotionControl: true,
            archiveFormat: .externalManual,
            description: "Catálogo técnico: gera risos/suspiros em inglês via servidor mlx-audio/PyTorch, sem suporte nativo a português."
        ),
        LocalVoiceModelDescriptor(
            id: "f5-tts-noncommercial",
            displayName: "F5-TTS (Apenas Não Comercial)",
            kind: "TTS",
            category: .tts,
            licenseName: "CC-BY-NC-4.0",
            licenseWarning: "ATENÇÃO: Licença CC-BY-NC-4.0 proíbe uso comercial sem acordo separado.",
            sizeBytes: 5_400_000_000,
            minimumRAMProfile: .balanced16GB,
            minimumRAMGB: 16.0,
            supportedLanguages: ["en-US"],
            archiveFormat: .externalManual,
            description: "Bloqueado de empacotamento comercial por licença CC-BY-NC-4.0."
        ),
        LocalVoiceModelDescriptor(
            id: "kyutai-moshi-mlx-q4",
            displayName: "Kyutai Moshi MLX Q4 (Speech-to-Speech Nativo)",
            kind: "S2S",
            category: .s2s,
            licenseName: "CC-BY-4.0",
            licenseWarning: "Requer pacote MLX (`mlx` + `moshi_mlx`) e ~5 GB livres só para pesos (16+ GB RAM recomendados; foco em inglês).",
            sizeBytes: 5_190_000_000,
            minimumRAMProfile: .balanced16GB,
            minimumRAMGB: 16.0,
            supportedLanguages: ["en-US"],
            archiveFormat: .externalManual,
            description: "Speech-to-Speech full-duplex nativo via Apple MLX; indisponível em runtime sem Python MLX instalado e insuficiente em 8 GB sob carga simultânea."
        ),
        LocalVoiceModelDescriptor(
            id: "nvidia-personaplex-7b",
            displayName: "NVIDIA PersonaPlex 7B v1 (Speech-to-Speech)",
            kind: "S2S",
            category: .s2s,
            licenseName: "NVIDIA Open Model",
            licenseWarning: "Exige ~16.3 GB de pesos e perfil Ultra (>= 24–32 GB RAM).",
            sizeBytes: 16_341_800_000,
            minimumRAMProfile: .performance24GB,
            minimumRAMGB: 24.0,
            supportedLanguages: ["en-US"],
            archiveFormat: .externalManual,
            description: "Modelo full-duplex S2S pesado para hardware de estúdio."
        ),
        LocalVoiceModelDescriptor(
            id: "openbmb-minicpm-o",
            displayName: "MiniCPM-o 2.6 / 4.5 Multimodal S2S",
            kind: "S2S",
            category: .s2s,
            licenseName: "Apache-2.0",
            licenseWarning: "Exige 16.6–19.1 GB para pesos e perfil Ultra (>= 24–32 GB RAM).",
            sizeBytes: 16_625_100_000,
            minimumRAMProfile: .studio32GBPlus,
            minimumRAMGB: 32.0,
            supportedLanguages: ["en-US"],
            archiveFormat: .externalManual,
            description: "Modelo multimodal voz-para-voz para Macs Studio 32–64+ GB."
        )
    ]

    public static func descriptor(id: String) -> LocalVoiceModelDescriptor? {
        availableLocalModels.first(where: { $0.id == id })
    }

    public static func availableDiskSpaceBytes() -> Int64 {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }
}

private struct VerifiedAssetReceipt: Codable {
    let modelID: String
    let sha256: String
    let sizeBytes: Int64
    let verifiedAtISO8601: String
}

public enum WisdVoiceBuildInfo {
    public static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.7.1"
    }

    public static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "dev"
    }

    public static var gitCommit: String {
        (Bundle.main.infoDictionary?["WisdAIGitCommit"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "source"
    }

    public static var gitBranch: String {
        (Bundle.main.infoDictionary?["WisdAIGitBranch"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "feature/voice-intelligence-v2"
    }

    public static var buildTimestamp: String {
        (Bundle.main.infoDictionary?["WisdAIBuildTimestamp"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    public static var shortCommit: String {
        let c = gitCommit
        return c.count > 7 ? String(c.prefix(7)) : c
    }

    public static var summary: String {
        let base = "WisdAI v\(version) (\(buildNumber)) · \(gitBranch)@\(shortCommit)"
        return buildTimestamp.isEmpty ? base : "\(base) · \(buildTimestamp)"
    }
}

// MARK: - Consent-Gated Downloader, SHA-256 Verifier & Storage Manager

@MainActor
public final class VoiceModelAssetManager: NSObject, ObservableObject {
    @Published public private(set) var activeTransfer: ModelAssetTransferState?
    @Published public private(set) var pendingConsentModels: [LocalVoiceModelDescriptor] = []
    @Published public private(set) var pendingConsentReason: String?
    @Published public private(set) var installStates: [String: VoiceModelInstallState] = [:]
    @Published public private(set) var modelErrorMessages: [String: String] = [:]
    @Published public private(set) var availableDiskGB: Double = 0
    @Published public var selectedHardwareTier: VoiceHardwareTier = VoiceHardwareTier(rawValue: UserDefaults.standard.string(forKey: "wisdai.voice.hardwareTier") ?? "") ?? .automatic {
        didSet {
            UserDefaults.standard.set(selectedHardwareTier.rawValue, forKey: "wisdai.voice.hardwareTier")
            refreshStorageInfo()
        }
    }
    @Published public private(set) var hardwareProfile: HardwareMemoryProfile = .detect()

    private let baseDirectory: URL
    private let runtimesDirectory: URL
    private let modelsDirectory: URL

    private var urlSession: URLSession?
    private var downloadTask: URLSessionDownloadTask?
    private var downloadContinuation: CheckedContinuation<URL, Error>?
    private var downloadQueue: [LocalVoiceModelDescriptor] = []
    private var activeDownloadStartNs: UInt64 = 0
    private var loadedRuntimeIDs: Set<String> = []
    private var loadingRuntimeIDs: Set<String> = []

    public override init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        self.baseDirectory = appSupport.appendingPathComponent("WisdAI/Voice", isDirectory: true)
        self.runtimesDirectory = baseDirectory.appendingPathComponent("Runtimes", isDirectory: true)
        self.modelsDirectory = baseDirectory.appendingPathComponent("Models", isDirectory: true)
        super.init()
        refreshStorageInfo()
    }

    public func setRuntimeActivity(modelID: String, state: VoiceModelInstallState?, error: String? = nil) {
        if state == .loading {
            loadingRuntimeIDs.insert(modelID)
            loadedRuntimeIDs.remove(modelID)
        } else if state == .operational {
            loadingRuntimeIDs.remove(modelID)
            loadedRuntimeIDs.insert(modelID)
        } else {
            loadingRuntimeIDs.remove(modelID)
            loadedRuntimeIDs.remove(modelID)
        }
        if let error {
            modelErrorMessages[modelID] = error
        } else {
            modelErrorMessages.removeValue(forKey: modelID)
        }
        refreshStorageInfo()
    }

    public func refreshStorageInfo() {
        hardwareProfile = selectedHardwareTier.effectiveMemoryProfile()
        let bytes = VoiceModelCatalog.availableDiskSpaceBytes()
        availableDiskGB = Double(bytes) / 1_073_741_824.0
        let physicalRAMGB = selectedHardwareTier.resolvedRAMGB()

        var nextStates: [String: VoiceModelInstallState] = [:]
        for model in VoiceModelCatalog.availableLocalModels {
            if let existingErr = modelErrorMessages[model.id] {
                _ = existingErr
                nextStates[model.id] = .error
                continue
            }
            if activeTransfer?.modelID == model.id {
                nextStates[model.id] = .installing
                continue
            }
            if pendingConsentModels.contains(where: { $0.id == model.id }) {
                nextStates[model.id] = .awaitingConsent
                continue
            }
            if model.archiveFormat == .builtIn {
                nextStates[model.id] = .operational
                continue
            }
            if loadingRuntimeIDs.contains(model.id) {
                nextStates[model.id] = .loading
                continue
            }
            if loadedRuntimeIDs.contains(model.id) && isModelInstalledOnDisk(model) {
                nextStates[model.id] = .operational
                continue
            }
            if isModelInstalledOnDisk(model) {
                if let depID = model.requiredRuntimeID,
                   let dep = VoiceModelCatalog.descriptor(id: depID),
                   !isModelInstalledOnDisk(dep) {
                    nextStates[model.id] = .incompatible
                    modelErrorMessages[model.id] = "Dependência ausente: \(dep.displayName)"
                } else {
                    nextStates[model.id] = .available
                }
                continue
            }
            if physicalRAMGB + 0.5 < model.minimumRAMGB || model.archiveFormat == .externalManual {
                nextStates[model.id] = .incompatible
                continue
            }
            nextStates[model.id] = .notInstalled
        }
        installStates = nextStates
    }

    public func storageRootURL(for model: LocalVoiceModelDescriptor) -> URL {
        let parent = (model.category == .runtime) ? runtimesDirectory : modelsDirectory
        return parent.appendingPathComponent(model.id, isDirectory: true)
    }

    public func entryPointURL(for model: LocalVoiceModelDescriptor) -> URL? {
        guard let rel = model.relativeEntryPoint else { return nil }
        return storageRootURL(for: model).appendingPathComponent(rel)
    }

    public func isModelInstalledOnDisk(_ model: LocalVoiceModelDescriptor) -> Bool {
        if model.archiveFormat == .builtIn { return true }
        let root = storageRootURL(for: model)
        let receiptURL = root.appendingPathComponent(".wisdai-verified.json")
        guard let receiptData = try? Data(contentsOf: receiptURL),
              let receipt = try? JSONDecoder().decode(VerifiedAssetReceipt.self, from: receiptData),
              receipt.modelID == model.id else {
            return false
        }
        if let expectedHash = model.expectedSHA256,
           receipt.sha256.lowercased() != expectedHash.lowercased() {
            return false
        }
        guard let entryURL = resolvedEntryPointURL(for: model, under: root) else {
            return false
        }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: entryURL.path),
              let size = attrs[.size] as? NSNumber,
              size.int64Value > 0 else {
            return false
        }
        return true
    }

    private func resolvedEntryPointURL(for model: LocalVoiceModelDescriptor, under root: URL) -> URL? {
        if let entryURL = entryPointURL(for: model),
           FileManager.default.fileExists(atPath: entryURL.path),
           isContained(url: entryURL, within: root) {
            return entryURL
        }
        if model.id == VoiceModelCatalog.llamaRuntimeID,
           let bin = findBinaryNamed("llama-server", under: root),
           isContained(url: bin, within: root) {
            return bin
        }
        return nil
    }

    public func verifyInstalledIntegrityOnDemand(for modelID: String) -> (ok: Bool, detail: String) {
        guard let model = VoiceModelCatalog.descriptor(id: modelID) else {
            return (false, "Modelo desconhecido: \(modelID)")
        }
        if model.archiveFormat == .builtIn {
            return (true, "Componente nativo macOS.")
        }
        let root = storageRootURL(for: model)
        let receiptURL = root.appendingPathComponent(".wisdai-verified.json")
        guard let receiptData = try? Data(contentsOf: receiptURL),
              let receipt = try? JSONDecoder().decode(VerifiedAssetReceipt.self, from: receiptData),
              receipt.modelID == model.id else {
            return (false, "Recibo .wisdai-verified.json ausente ou corrompido para \(model.id).")
        }
        if let expectedHash = model.expectedSHA256,
           receipt.sha256.lowercased() != expectedHash.lowercased() {
            return (false, "Recibo SHA-256 diverge do catálogo oficial para \(model.id).")
        }
        do {
            try validateExtractedTree(under: root)
        } catch {
            return (false, "Validação de árvore/symlinks falhou: \(error.localizedDescription)")
        }
        guard let entryURL = resolvedEntryPointURL(for: model, under: root) else {
            return (false, "Arquivo principal de \(model.id) ausente em \(root.lastPathComponent).")
        }
        if model.archiveFormat == .rawFile, let expectedHash = model.expectedSHA256 {
            do {
                let actual = try computeSHA256Hex(fileAt: entryURL)
                guard actual.lowercased() == expectedHash.lowercased() else {
                    return (false, "SHA-256 do arquivo em disco diverge do esperado.")
                }
            } catch {
                return (false, "Falha ao calcular SHA-256 de \(entryURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return (true, "Integridade verificada (SHA-256 \(receipt.sha256.prefix(12))…).")
    }

    public func findBinaryNamed(_ name: String, under directory: URL) -> URL? {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return nil
        }
        for case let url as URL in en {
            if url.lastPathComponent == name {
                return url
            }
        }
        return nil
    }

    public func canFitOnDevice(_ model: LocalVoiceModelDescriptor) -> (ok: Bool, reason: String?) {
        let freeBytes = VoiceModelCatalog.availableDiskSpaceBytes()
        if freeBytes > 0 && freeBytes < (model.sizeBytes + 500_000_000) {
            let gb = Double(freeBytes) / 1_073_741_824.0
            return (false, "Espaço insuficiente em disco (\(String(format: "%.1f", gb)) GB livres).")
        }
        let ram = selectedHardwareTier.resolvedRAMGB()
        if ram + 0.5 < model.minimumRAMGB {
            return (false, String(format: "Requer %.0f GB de RAM (perfil atual: %.0f GB).", model.minimumRAMGB, ram))
        }
        if model.archiveFormat == .externalManual {
            return (false, model.licenseWarning ?? "Requer runtime Python externo não empacotado.")
        }
        return (true, nil)
    }

    public func requestDownloadConsent(for modelID: String) {
        guard let model = VoiceModelCatalog.descriptor(id: modelID), model.isDownloadable else { return }
        var requiredChain: [LocalVoiceModelDescriptor] = []
        if let depID = model.requiredRuntimeID,
           let dep = VoiceModelCatalog.descriptor(id: depID),
           !isModelInstalledOnDisk(dep) {
            requiredChain.append(dep)
        }
        if !isModelInstalledOnDisk(model) {
            requiredChain.append(model)
        }
        guard !requiredChain.isEmpty else {
            refreshStorageInfo()
            return
        }
        let totalBytes = requiredChain.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let totalMB = Double(totalBytes) / (1024.0 * 1024.0)
        pendingConsentModels = requiredChain
        pendingConsentReason = String(
            format: "Autoriza o download de %.1f MB com verificação SHA-256 para %@?",
            totalMB,
            requiredChain.map(\.displayName).joined(separator: " + ")
        )
        refreshStorageInfo()
    }

    public func declineConsent() {
        pendingConsentModels = []
        pendingConsentReason = nil
        refreshStorageInfo()
    }

    public func confirmAndStartAuthorizedDownload() {
        let items = pendingConsentModels
        pendingConsentModels = []
        pendingConsentReason = nil
        guard !items.isEmpty else { return }
        Task { @MainActor [weak self] in
            await self?.runDownloadBatch(items)
        }
    }

    private func runDownloadBatch(_ models: [LocalVoiceModelDescriptor]) async {
        for model in models {
            modelErrorMessages.removeValue(forKey: model.id)
            let fit = canFitOnDevice(model)
            guard fit.ok else {
                modelErrorMessages[model.id] = fit.reason ?? "Dispositivo incompatível."
                refreshStorageInfo()
                break
            }
            guard let urlStr = model.downloadURLString,
                  let url = URL(string: urlStr),
                  let expectedHash = model.expectedSHA256 else {
                modelErrorMessages[model.id] = "Metadados de download incompletos."
                refreshStorageInfo()
                break
            }

            do {
                activeTransfer = ModelAssetTransferState(
                    modelID: model.id,
                    modelName: model.displayName,
                    isDownloading: true,
                    progress: 0,
                    downloadedBytes: 0,
                    totalBytes: model.sizeBytes,
                    bytesPerSecond: 0,
                    statusMessage: "Baixando \(model.displayName)…"
                )
                refreshStorageInfo()

                let tempFile = try await downloadFile(from: url)

                activeTransfer?.statusMessage = "Verificando SHA-256…"
                let actualHash = try computeSHA256Hex(fileAt: tempFile)
                guard actualHash.lowercased() == expectedHash.lowercased() else {
                    try? FileManager.default.removeItem(at: tempFile)
                    throw NSError(domain: "VoiceModelAsset", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "Checksum SHA-256 divergente (esperado \(expectedHash.prefix(12)), obtido \(actualHash.prefix(12)))."
                    ])
                }

                activeTransfer?.statusMessage = "Extraindo e validando pacote…"
                try installVerifiedFile(tempFile: tempFile, for: model, verifiedHash: actualHash)
                try? FileManager.default.removeItem(at: tempFile)
                activeTransfer = nil
                refreshStorageInfo()
            } catch {
                activeTransfer = nil
                if (error as NSError).code != NSUserCancelledError {
                    modelErrorMessages[model.id] = error.localizedDescription
                }
                refreshStorageInfo()
                break
            }
        }
    }

    private func downloadFile(from url: URL) async throws -> URL {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpCookieStorage = nil
        cfg.urlCredentialStorage = nil
        cfg.timeoutIntervalForResource = 1800
        let session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        urlSession = session
        activeDownloadStartNs = DispatchTime.now().uptimeNanoseconds

        return try await withCheckedThrowingContinuation { continuation in
            self.downloadContinuation = continuation
            let task = session.downloadTask(with: url)
            self.downloadTask = task
            task.resume()
        }
    }

    private func computeSHA256Hex(fileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: 1_048_576)
            if chunk.isEmpty { return false }
            hasher.update(data: chunk)
            return true
        }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func installVerifiedFile(tempFile: URL, for model: LocalVoiceModelDescriptor, verifiedHash: String) throws {
        let fm = FileManager.default
        let destRoot = storageRootURL(for: model)
        let stagingParent = destRoot.deletingLastPathComponent()
        try fm.createDirectory(at: stagingParent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let stagingRoot = stagingParent.appendingPathComponent(".staging-\(model.id)-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? fm.removeItem(at: stagingRoot)
        }
        try fm.createDirectory(at: stagingRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        switch model.archiveFormat {
        case .rawFile:
            guard let rel = model.relativeEntryPoint else {
                throw NSError(domain: "VoiceModelAsset", code: 3, userInfo: [NSLocalizedDescriptionKey: "Caminho de destino inválido."])
            }
            let targetURL = stagingRoot.appendingPathComponent(rel)
            try validateSafeRelativePath(rel)
            try fm.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: tempFile, to: targetURL)
        case .tarBz2, .tarGz:
            try validateArchiveEntries(archiveURL: tempFile, format: model.archiveFormat)
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            proc.arguments = model.archiveFormat == .tarBz2
                ? ["--no-same-owner", "--no-same-permissions", "-xjf", tempFile.path, "-C", stagingRoot.path]
                : ["--no-same-owner", "--no-same-permissions", "-xzf", tempFile.path, "-C", stagingRoot.path]
            let errPipe = Pipe()
            proc.standardError = errPipe
            proc.standardOutput = FileHandle.nullDevice
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else {
                let errText = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                throw NSError(domain: "VoiceModelAsset", code: 4, userInfo: [
                    NSLocalizedDescriptionKey: "Falha ao extrair arquivo (\(proc.terminationStatus)): \(errText)"
                ])
            }
            try validateExtractedTree(under: stagingRoot)
        case .builtIn, .externalManual:
            break
        }

        let receipt = VerifiedAssetReceipt(
            modelID: model.id,
            sha256: verifiedHash,
            sizeBytes: model.sizeBytes,
            verifiedAtISO8601: ISO8601DateFormatter().string(from: Date())
        )
        let data = try JSONEncoder().encode(receipt)
        try data.write(to: stagingRoot.appendingPathComponent(".wisdai-verified.json"), options: [.atomic])

        if fm.fileExists(atPath: destRoot.path) {
            try fm.removeItem(at: destRoot)
        }
        try fm.moveItem(at: stagingRoot, to: destRoot)
    }

    private func validateSafeRelativePath(_ relPath: String) throws {
        let trimmed = relPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("/") else {
            throw NSError(domain: "VoiceModelAsset", code: 10, userInfo: [
                NSLocalizedDescriptionKey: "Caminho inválido/absoluto bloqueado por segurança: \(relPath)"
            ])
        }
        let parts = trimmed.split(separator: "/").map(String.init)
        if parts.contains("..") {
            throw NSError(domain: "VoiceModelAsset", code: 11, userInfo: [
                NSLocalizedDescriptionKey: "Path traversal (..) bloqueado no pacote: \(relPath)"
            ])
        }
    }

    private func validateArchiveEntries(archiveURL: URL, format: LocalArchiveFormat) throws {
        func runTarList(_ flag: String) throws -> String {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            p.arguments = [flag, archiveURL.path]
            let outPipe = Pipe()
            let errPipe = Pipe()
            p.standardOutput = outPipe
            p.standardError = errPipe
            try p.run()
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0, let txt = String(data: outData, encoding: .utf8) else {
                let errText = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                throw NSError(domain: "VoiceModelAsset", code: 12, userInfo: [
                    NSLocalizedDescriptionKey: "Falha ao inspecionar cabeçalho do arquivo compactado: \(errText)"
                ])
            }
            return txt
        }

        // Exact path check (handles spaces safely via `-tf`)
        let rawPaths = try runTarList(format == .tarBz2 ? "-tjf" : "-tzf")
        for line in rawPaths.split(whereSeparator: \.isNewline) {
            try validateArchiveMemberName(String(line))
        }

        // Entry type & symlink/hardlink target check via `-tvf`
        let verboseList = try runTarList(format == .tarBz2 ? "-tvjf" : "-tvzf")
        for rawLine in verboseList.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let typeChar = line.first ?? "-"
            if typeChar == "b" || typeChar == "c" || typeChar == "p" || typeChar == "s" || typeChar == "h" {
                throw NSError(domain: "VoiceModelAsset", code: 13, userInfo: [
                    NSLocalizedDescriptionKey: "Entrada especial/hardlink não permitida no arquivo: \(line)"
                ])
            }
            if typeChar == "l", let linkSep = line.range(of: " -> ") {
                let targetName = String(line[linkSep.upperBound...]).trimmingCharacters(in: .whitespaces)
                if targetName.hasPrefix("/") || targetName.split(separator: "/").contains("..") {
                    throw NSError(domain: "VoiceModelAsset", code: 14, userInfo: [
                        NSLocalizedDescriptionKey: "Symlink inseguro bloqueado no pacote: -> \(targetName)"
                    ])
                }
            }
        }
    }

    private func validateArchiveMemberName(_ member: String) throws {
        var clean = member.trimmingCharacters(in: .whitespacesAndNewlines)
        while clean.hasPrefix("./") { clean.removeFirst(2) }
        guard !clean.hasPrefix("/") else {
            throw NSError(domain: "VoiceModelAsset", code: 15, userInfo: [
                NSLocalizedDescriptionKey: "Caminho absoluto no arquivo bloqueado: \(member)"
            ])
        }
        if clean.split(separator: "/").contains("..") {
            throw NSError(domain: "VoiceModelAsset", code: 16, userInfo: [
                NSLocalizedDescriptionKey: "Path traversal (..) no arquivo bloqueado: \(member)"
            ])
        }
    }

    private func validateExtractedTree(under root: URL) throws {
        let resolvedRoot = root.resolvingSymlinksInPath().path
        let fm = FileManager.default
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: []) else {
            return
        }
        for case let itemURL as URL in en {
            let resolvedItem = itemURL.resolvingSymlinksInPath().path
            guard resolvedItem == resolvedRoot || resolvedItem.hasPrefix(resolvedRoot + "/") else {
                throw NSError(domain: "VoiceModelAsset", code: 17, userInfo: [
                    NSLocalizedDescriptionKey: "Symlink/arquivo fora do diretório permitido bloqueado: \(itemURL.lastPathComponent)"
                ])
            }
        }
    }

    private func isContained(url: URL, within root: URL) -> Bool {
        let resolvedRoot = root.resolvingSymlinksInPath().path
        let resolvedItem = url.resolvingSymlinksInPath().path
        return resolvedItem == resolvedRoot || resolvedItem.hasPrefix(resolvedRoot + "/")
    }

    public func uninstallModel(id: String) {
        guard let model = VoiceModelCatalog.descriptor(id: id), model.archiveFormat != .builtIn else { return }
        if activeTransfer?.modelID == id {
            cancelTransfer()
        }
        loadedRuntimeIDs.remove(id)
        loadingRuntimeIDs.remove(id)
        modelErrorMessages.removeValue(forKey: id)
        try? FileManager.default.removeItem(at: storageRootURL(for: model))
        refreshStorageInfo()
    }

    public func cancelTransfer() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadContinuation?.resume(throwing: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
        downloadContinuation = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        downloadQueue.removeAll()
        activeTransfer = nil
        refreshStorageInfo()
    }
}

extension VoiceModelAssetManager: URLSessionDownloadDelegate {
    nonisolated public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let nowNs = DispatchTime.now().uptimeNanoseconds
        Task { @MainActor [weak self] in
            guard let self, var current = self.activeTransfer else { return }
            let elapsed = max(0.05, Double(nowNs &- self.activeDownloadStartNs) / 1_000_000_000.0)
            let denom = max(totalBytesExpectedToWrite, current.totalBytes, 1)
            current.downloadedBytes = totalBytesWritten
            current.totalBytes = denom
            current.progress = min(1.0, max(0.0, Double(totalBytesWritten) / Double(denom)))
            current.bytesPerSecond = Double(totalBytesWritten) / elapsed
            self.activeTransfer = current
        }
    }

    nonisolated public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent("wisdai-dl-\(UUID().uuidString)")
        do {
            try FileManager.default.copyItem(at: location, to: staged)
            Task { @MainActor [weak self] in
                guard let self else {
                    try? FileManager.default.removeItem(at: staged)
                    return
                }
                let cont = self.downloadContinuation
                self.downloadContinuation = nil
                self.downloadTask = nil
                self.urlSession?.finishTasksAndInvalidate()
                self.urlSession = nil
                cont?.resume(returning: staged)
            }
        } catch {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let cont = self.downloadContinuation
                self.downloadContinuation = nil
                self.downloadTask = nil
                self.urlSession?.invalidateAndCancel()
                self.urlSession = nil
                cont?.resume(throwing: error)
            }
        }
    }

    nonisolated public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let cont = self.downloadContinuation
            self.downloadContinuation = nil
            self.downloadTask = nil
            self.urlSession?.invalidateAndCancel()
            self.urlSession = nil
            cont?.resume(throwing: error)
        }
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

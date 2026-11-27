import CryptoKit
import Foundation

// MARK: - WisdAI Exclusive Voice Identity & V2 Neural Capabilities

public enum WisdVoiceTimbre: String, CaseIterable, Identifiable, Codable, Sendable {
    case female
    case male

    public var id: String { rawValue }
}

public enum WisdVoicePersona: String, CaseIterable, Identifiable, Codable, Sendable {
    case jarvis   // WisdAI Executive Male Identity (Serene, Lucid, Refined)
    case aurora   // WisdAI Signature Female Natural
    case atlas    // WisdAI Structured Male
    case aria     // WisdAI Energetic Brainstorm

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .jarvis: return "JARVIS · Executivo WisdAI"
        case .aurora: return "Aurora · WisdAI Padrão"
        case .atlas: return "Atlas · WisdAI Estruturada"
        case .aria: return "Aria · WisdAI Dinâmica"
        }
    }

    public var shortName: String {
        switch self {
        case .jarvis: return "JARVIS"
        case .aurora: return "Aurora"
        case .atlas: return "Atlas"
        case .aria: return "Aria"
        }
    }

    public var subtitle: String {
        switch self {
        case .jarvis: return "Voz masculina refinada, articulada, calma e estratégica"
        case .aurora: return "Timbre natural, acolhedor e fluido"
        case .atlas: return "Tom firme, calmo e técnico"
        case .aria: return "Ritmo ágil e colaborativo para brainstorming"
        }
    }

    public var recommendedTimbre: WisdVoiceTimbre {
        switch self {
        case .jarvis, .atlas: return .male
        case .aurora, .aria: return .female
        }
    }

    public var kokoroStyleVectorID: String {
        switch self {
        case .jarvis: return "pm_alex"
        case .aurora: return "pf_dora"
        case .atlas: return "pm_santa"
        case .aria: return "pf_dora"
        }
    }

    public var defaultSupertonicPresetID: String {
        switch self {
        case .jarvis: return "supertonic:m2" // sid=6: deep calm baritone ~90Hz
        case .atlas: return "supertonic:m5"  // sid=9: authoritative baritone ~92Hz
        case .aurora: return "supertonic:f1" // sid=0: clean neutral female
        case .aria: return "supertonic:f4"   // sid=3: expressive female
        }
    }

    public var baseCadenceRate: Float {
        switch self {
        case .jarvis: return 0.98
        case .aurora: return 1.00
        case .atlas: return 0.96
        case .aria: return 1.07
        }
    }

    public var recommendedPersonalityStyle: VoicePersonalityStyle {
        switch self {
        case .jarvis: return .jarvisExecutive
        case .atlas: return .conciseExecutive
        case .aurora: return .naturalPartner
        case .aria: return .creativeBrainstorm
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

    public static let jarvisDefault = VoiceIdentityDescriptor(
        persona: .jarvis,
        warmth: 0.72,
        clarityEmphasis: 0.88,
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
    case supertonic3 = "supertonic_3"
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
        case .autoLocal: return "Automático Local (Melhor Motor Neural Pronto)"
        case .supertonic3: return "Supertonic-3 Flow Matching (ONNX 44.1 kHz · PT/EN/ES)"
        case .kokoro82M: return "Kokoro-82M Neural (ONNX 24 kHz · PT-BR / EN-GB / EN-US / ES)"
        case .sherpaPiperVits: return "Piper VITS Neural (ONNX Local · PT-BR & PT-PT Nativo · PoC)"
        case .appleNaturalPCM: return "Apple Voz Natural (macOS Nativo · Sem Download)"
        case .cosyVoice2: return "CosyVoice2 / 3 (Servidor MLX/PyTorch Loopback)"
        case .chatterbox: return "Chatterbox Multilingual MIT (Servidor MLX Loopback)"
        case .sesameCSM: return "Sesame CSM-1B (Servidor MLX/PyTorch · Inglês)"
        case .diaTTS: return "Nari Labs Dia-1.6B (Apache-2.0 · Inglês · 10+ GB RAM)"
        case .f5TTS: return "F5-TTS (Aviso: Licença CC-BY-NC-4.0 Não Comercial)"
        }
    }

    public var shortName: String {
        switch self {
        case .autoLocal: return "Auto Neural"
        case .supertonic3: return "Supertonic-3 (44.1kHz)"
        case .kokoro82M: return "Kokoro-82M"
        case .sherpaPiperVits: return "Piper VITS"
        case .appleNaturalPCM: return "Apple Natural"
        case .cosyVoice2: return "CosyVoice2/3"
        case .chatterbox: return "Chatterbox MIT"
        case .sesameCSM: return "Sesame CSM-1B"
        case .diaTTS: return "Dia-1.6B"
        case .f5TTS: return "F5-TTS"
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
        case .autoLocal, .supertonic3, .kokoro82M, .sherpaPiperVits, .appleNaturalPCM, .chatterbox, .cosyVoice2:
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
        case .autoLocal, .supertonic3, .kokoro82M, .sherpaPiperVits: return true
        default: return false
        }
    }

    public var supportsFlowMatchingSteps: Bool {
        switch self {
        case .supertonic3: return true
        default: return false
        }
    }

    public var supportsCustomProfileSettings: Bool {
        return supportsSpeedControl
    }

    public var supportsVoiceSelection: Bool {
        switch self {
        case .autoLocal, .supertonic3, .kokoro82M, .appleNaturalPCM, .chatterbox, .cosyVoice2: return true
        default: return false
        }
    }

    public var licenseWarning: String? {
        switch self {
        case .supertonic3:
            return "Código Supertone MIT; pesos Supertonic-3 sob licença BigScience Open RAIL-M (uso local responsável permitido)."
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
            // Kokoro covers Brazilian Portuguese, UK English (en-GB-x-rp), US English, and Spanish — NOT European Portuguese.
            return language == .portugueseBR || language == .englishGB || language == .englishUS || language == .spanishES
        case .supertonic3, .sherpaPiperVits, .appleNaturalPCM, .autoLocal:
            return true
        case .sesameCSM, .diaTTS:
            return language == .englishUS || language == .englishGB
        case .cosyVoice2, .f5TTS:
            return language == .englishUS || language == .englishGB || language == .spanishES
        case .chatterbox:
            return true // Chatterbox Multilingual covers PT, EN, ES (with community PT-BR / PT-PT packs)
        }
    }
}

public enum SupertonicVoicePreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case m2 = "supertonic:m2" // sid=6: Serene Deep Baritone (~90 Hz PT / ~87 Hz EN) — JARVIS primary
    case m4 = "supertonic:m4" // sid=8: Articulate Tenor-Baritone (~132 Hz PT / ~114 Hz EN)
    case m5 = "supertonic:m5" // sid=9: Resonant Authoritative Baritone (~92 Hz PT / ~83 Hz EN)
    case m1 = "supertonic:m1" // sid=5: Dynamic Clear Male (~132 Hz PT / ~115 Hz EN)
    case m3 = "supertonic:m3" // sid=7: Firm Male (~103 Hz PT / ~101 Hz EN)
    case f1 = "supertonic:f1" // sid=0: Clear Neutral Female (~185 Hz)
    case f2 = "supertonic:f2" // sid=1: Warm Female (~217 Hz)
    case f3 = "supertonic:f3" // sid=2: Balanced Female (~165 Hz)
    case f4 = "supertonic:f4" // sid=3: Expressive Female (~207 Hz)
    case f5 = "supertonic:f5" // sid=4: Soft Female (~162 Hz)

    public var id: String { rawValue }

    public var speakerID: Int32 {
        switch self {
        case .f1: return 0
        case .f2: return 1
        case .f3: return 2
        case .f4: return 3
        case .f5: return 4
        case .m1: return 5
        case .m2: return 6
        case .m3: return 7
        case .m4: return 8
        case .m5: return 9
        }
    }

    public var timbre: WisdVoiceTimbre {
        switch self {
        case .m1, .m2, .m3, .m4, .m5: return .male
        case .f1, .f2, .f3, .f4, .f5: return .female
        }
    }

    public var displayName: String {
        switch self {
        case .m2: return "Supertonic M2 · JARVIS Barítono Sereno (~90 Hz)"
        case .m4: return "Supertonic M4 · JARVIS Articulado (~132 Hz)"
        case .m5: return "Supertonic M5 · Barítono Executivo (~92 Hz)"
        case .m1: return "Supertonic M1 · Masculina Dinâmica (~132 Hz)"
        case .m3: return "Supertonic M3 · Masculina Firme (~103 Hz)"
        case .f1: return "Supertonic F1 · Feminina Neutra (~185 Hz)"
        case .f2: return "Supertonic F2 · Feminina Acolhedora (~217 Hz)"
        case .f3: return "Supertonic F3 · Feminina Equilibrada (~165 Hz)"
        case .f4: return "Supertonic F4 · Feminina Expressiva (~207 Hz)"
        case .f5: return "Supertonic F5 · Feminina Suave (~162 Hz)"
        }
    }

    public func supertonicLangCode(for language: VoiceLanguageVariant) -> String {
        switch language {
        case .portugueseBR, .portuguesePT: return "pt"
        case .englishGB, .englishUS: return "en"
        case .spanishES: return "es"
        }
    }

    public static func from(identifier: String) -> SupertonicVoicePreset? {
        let lower = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let exact = SupertonicVoicePreset(rawValue: lower) { return exact }
        if lower.hasPrefix("supertonic:") {
            let short = String(lower.dropFirst("supertonic:".count))
            return SupertonicVoicePreset(rawValue: "supertonic:\(short)")
        }
        if ["m1","m2","m3","m4","m5","f1","f2","f3","f4","f5"].contains(lower) {
            return SupertonicVoicePreset(rawValue: "supertonic:\(lower)")
        }
        return nil
    }

    public static func defaultPreset(for persona: WisdVoicePersona) -> SupertonicVoicePreset {
        switch persona {
        case .jarvis: return .m2
        case .atlas: return .m5
        case .aurora: return .f1
        case .aria: return .f4
        }
    }
}

public enum KokoroVoicePreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case pfDora = "pf_dora"
    case pmAlex = "pm_alex"
    case pmSanta = "pm_santa"
    case bmGeorge = "bm_george"
    case bmDaniel = "bm_daniel"
    case bmLewis = "bm_lewis"
    case bfEmma = "bf_emma"
    case afHeart = "af_heart"
    case afBella = "af_bella"
    case afNova = "af_nova"
    case amOnyx = "am_onyx"
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
        case .amOnyx: return 17
        case .bfEmma: return 21
        case .bmDaniel: return 24
        case .bmGeorge: return 26
        case .bmLewis: return 27
        case .efDora: return 28
        case .emAlex: return 29
        case .pfDora: return 42
        case .pmAlex: return 43
        case .pmSanta: return 44
        case .emSanta: return 53
        }
    }

    public var timbre: WisdVoiceTimbre {
        switch self {
        case .pfDora, .bfEmma, .afHeart, .afBella, .afNova, .efDora: return .female
        case .pmAlex, .pmSanta, .bmGeorge, .bmDaniel, .bmLewis, .amOnyx, .amFenrir, .amMichael, .emAlex, .emSanta: return .male
        }
    }

    /// Upstream sherpa-onnx / espeak-ng voice identifiers for kokoro-multi-lang-v1_0
    public var kokoroLangCode: String {
        switch self {
        case .pfDora, .pmAlex, .pmSanta: return "pt-br"
        case .bmGeorge, .bmDaniel, .bmLewis, .bfEmma: return "en-GB-x-rp"
        case .afHeart, .afBella, .afNova, .amOnyx, .amFenrir, .amMichael: return "en-us"
        case .efDora, .emAlex, .emSanta: return "es"
        }
    }

    public var supportedLanguage: VoiceLanguageVariant {
        switch self {
        case .pfDora, .pmAlex, .pmSanta: return .portugueseBR
        case .bmGeorge, .bmDaniel, .bmLewis, .bfEmma: return .englishGB
        case .afHeart, .afBella, .afNova, .amOnyx, .amFenrir, .amMichael: return .englishUS
        case .efDora, .emAlex, .emSanta: return .spanishES
        }
    }

    public var displayName: String {
        switch self {
        case .pfDora: return "Aurora / Dora (pf_dora · PT-BR Feminina)"
        case .pmAlex: return "Alex / JARVIS Clássico (pm_alex · PT-BR Masculina)"
        case .pmSanta: return "Atlas / Santa (pm_santa · PT-BR Masculina Grave)"
        case .bmGeorge: return "George · JARVIS Britânico (bm_george · EN-GB Masculina)"
        case .bmDaniel: return "Daniel Britânico (bm_daniel · EN-GB Masculina)"
        case .bmLewis: return "Lewis Britânico Grave (bm_lewis · EN-GB Masculina)"
        case .bfEmma: return "Emma Britânica (bf_emma · EN-GB Feminina)"
        case .afHeart: return "Heart (af_heart · EN-US Feminina)"
        case .afBella: return "Bella (af_bella · EN-US Feminina)"
        case .afNova: return "Nova (af_nova · EN-US Feminina)"
        case .amOnyx: return "Onyx (am_onyx · EN-US Masculina)"
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
            switch persona {
            case .jarvis: return .pmAlex
            case .atlas: return .pmSanta
            case .aurora, .aria: return .pfDora
            }
        case .portuguesePT:
            // Kokoro does NOT speak genuine European Portuguese; return nil rather than faking pt-PT.
            return nil
        case .englishGB:
            return persona.recommendedTimbre == .male ? (persona == .jarvis ? .bmGeorge : .bmDaniel) : .bfEmma
        case .englishUS:
            if persona == .jarvis { return .amOnyx }
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
    public static let supertonic3Int8ModelID = "supertonic-3-multilang-int8"
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
            description: "Bibliotecas dinâmicas ONNX + C API com G2P integrado (espeak-ng) para Supertonic-3 e Kokoro-82M no macOS arm64."
        ),
        LocalVoiceModelDescriptor(
            id: supertonic3Int8ModelID,
            displayName: "Supertonic-3 Flow Matching INT8 (44.1 kHz · PT / EN / ES)",
            kind: "TTS",
            category: .tts,
            licenseName: "MIT + OpenRAIL-M",
            licenseWarning: "Código Supertone/sherpa MIT; pesos sob licença BigScience Open RAIL-M.",
            sizeBytes: 128_774_318,
            minimumRAMProfile: .low8GB,
            minimumRAMGB: 8.0,
            supportedLanguages: ["pt-BR", "pt-PT", "en-GB", "en-US", "es-ES"],
            supportsEmotionControl: false,
            downloadURLString: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/sherpa-onnx-supertonic-3-tts-int8-2026-05-11.tar.bz2",
            expectedSHA256: "82fa96f91c4ef8abaae3a14a3f4153facf88bed821d1f7331cec2700f432c427",
            archiveFormat: .tarBz2,
            relativeEntryPoint: "sherpa-onnx-supertonic-3-tts-int8-2026-05-11/vector_estimator.int8.onnx",
            requiredRuntimeID: sherpaRuntimeID,
            description: "Motor Flow-Matching nativo em 44.1 kHz via sherpa-onnx C ABI (RTF ~0.16–0.25 em CPU M2, 10 vozes M1–M5 / F1–F5, 31 idiomas incluindo PT e EN)."
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
        ),
        LocalVoiceModelDescriptor(
            id: "qwen3-tts-0.6b-customvoice",
            displayName: "Qwen3-TTS-12Hz-0.6B CustomVoice (MLX/PyTorch)",
            kind: "TTS",
            category: .tts,
            licenseName: "Apache-2.0",
            licenseWarning: "Requer runtime Python 3.10+ (`mlx-audio` ou `qwen-tts`) em servidor loopback 127.0.0.1.",
            sizeBytes: 1_850_000_000,
            minimumRAMProfile: .balanced16GB,
            minimumRAMGB: 12.0,
            supportedLanguages: ["pt-BR", "en-US", "es-ES"],
            supportsEmotionControl: true,
            archiveFormat: .externalManual,
            description: "Catálogo técnico V5: primeira latência ~97 ms e suporte nativo a português em runtime Python/MLX."
        ),
        LocalVoiceModelDescriptor(
            id: "qwen3-tts-1.7b-voicedesign",
            displayName: "Qwen3-TTS-12Hz-1.7B VoiceDesign (Apache-2.0)",
            kind: "TTS",
            category: .tts,
            licenseName: "Apache-2.0",
            licenseWarning: "Exige Python 3.10+ PyTorch/MLX e 16+ GB RAM para VoiceDesign por texto livre.",
            sizeBytes: 4_300_000_000,
            minimumRAMProfile: .balanced16GB,
            minimumRAMGB: 16.0,
            supportedLanguages: ["pt-BR", "en-US", "es-ES"],
            supportsEmotionControl: true,
            archiveFormat: .externalManual,
            description: "Catálogo técnico V5: criação de voz por instrução textual em 10 idiomas com estilo natural."
        ),
        LocalVoiceModelDescriptor(
            id: "fish-speech-openaudio-s1",
            displayName: "Fish Speech / OpenAudio S1 (MLX Loopback)",
            kind: "TTS",
            category: .tts,
            licenseName: "Fish Audio Research / Apache-2.0 Código",
            licenseWarning: "Verifique licença comercial dos pesos S1 e requer servidor Python/MLX separado (~16 GB RAM).",
            sizeBytes: 4_100_000_000,
            minimumRAMProfile: .balanced16GB,
            minimumRAMGB: 16.0,
            supportedLanguages: ["pt-BR", "en-US", "es-ES"],
            supportsEmotionControl: true,
            archiveFormat: .externalManual,
            description: "Catálogo técnico V5: ótima expressividade multilíngue via loopback quando host dispõe de Python 3.10+ MLX."
        ),
        LocalVoiceModelDescriptor(
            id: "indextts-2",
            displayName: "IndexTTS-2 (Bilibili · PyTorch Zero-Shot)",
            kind: "TTS",
            category: .tts,
            licenseName: "Apache-2.0 (Código) / Pesos sob revisão comercial",
            licenseWarning: "Foco principal em EN/ZH/ES/JA e requer PyTorch/MPS externo (~16–24 GB RAM).",
            sizeBytes: 5_200_000_000,
            minimumRAMProfile: .balanced16GB,
            minimumRAMGB: 16.0,
            supportedLanguages: ["en-US", "es-ES"],
            supportsEmotionControl: true,
            archiveFormat: .externalManual,
            description: "Catálogo técnico V5: controle explícito de duração e emoção via servidor PyTorch externo."
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

// MARK: - V5 Unified Single Source of Truth (VoiceIdentityManager & Honest Voice Design)

public struct VoiceDesignConfig: Equatable, Codable, Sendable {
    public var flowMatchingSteps: Int     // Real engine parameter on Supertonic-3 (4...12)
    public var cadence: Double            // Real speaking rate (0.75...1.30)
    public var pauseScale: Double         // Real silence_scale multiplier (0.65...1.60)
    public var warmth: Double             // Conversational behavior warmth (0.0...1.0)
    public var directness: Double         // Prompt/planner directness (0.0...1.0)
    public var expressivity: VoiceExpressivityLevel
    public var formality: VoiceFormalityLevel
    public var detailLevel: VoiceDetailLevel

    public static let jarvisBalanced = VoiceDesignConfig(
        flowMatchingSteps: 10,
        cadence: 0.98,
        pauseScale: 1.04,
        warmth: 0.72,
        directness: 0.90,
        expressivity: .balanced,
        formality: .balanced,
        detailLevel: .balanced
    )

    public static let naturalDefault = VoiceDesignConfig(
        flowMatchingSteps: 8,
        cadence: 1.00,
        pauseScale: 1.00,
        warmth: 0.76,
        directness: 0.78,
        expressivity: .balanced,
        formality: .balanced,
        detailLevel: .balanced
    )
}

public struct VoiceSelectionSnapshot: Equatable, Sendable {
    public var identityId: WisdVoicePersona
    public var engineId: VoiceTTSEngineKind
    public var modelId: String
    public var speakerId: String
    public var numericSpeakerSID: Int32?
    public var language: VoiceLanguageVariant
    public var vocalGender: WisdVoiceTimbre
    public var speechRate: Double
    public var flowMatchingSteps: Int

    public var summary: String {
        let sidLabel = numericSpeakerSID.map { " (sid=\($0))" } ?? ""
        return "\(identityId.shortName) · \(vocalGender == .male ? "Masculina" : "Feminina") · \(engineId.shortName) · \(speakerId)\(sidLabel) · \(language.shortCode)"
    }
}

public struct VoiceLoadedRuntimeSnapshot: Equatable, Sendable {
    public var engineId: String
    public var modelId: String
    public var langCode: String
    public var loadedSpeakerCount: Int
    public var sampleRateHz: Int
    public var isLoaded: Bool

    public static let idle = VoiceLoadedRuntimeSnapshot(
        engineId: "none",
        modelId: "none",
        langCode: "-",
        loadedSpeakerCount: 0,
        sampleRateHz: 0,
        isLoaded: false
    )
}

public struct VoiceInferredRuntimeSnapshot: Equatable, Sendable {
    public var actualEngineId: String
    public var actualModelId: String
    public var actualSpeakerId: String
    public var actualNumericSID: Int32?
    public var actualLanguage: String
    public var actualSampleRateHz: Int
    public var estimatedF0Hz: Double?
    public var synthLatencyMs: Double
    public var fallbackOccurred: Bool
    public var note: String?
    public var updatedAt: Date

    public static let none = VoiceInferredRuntimeSnapshot(
        actualEngineId: "pending",
        actualModelId: "pending",
        actualSpeakerId: "pending",
        actualNumericSID: nil,
        actualLanguage: "-",
        actualSampleRateHz: 0,
        estimatedF0Hz: nil,
        synthLatencyMs: 0,
        fallbackOccurred: false,
        note: "Aguardando primeira síntese nesta sessão",
        updatedAt: Date()
    )
}

public struct UnifiedVoiceConfig: Equatable, Codable, Sendable {
    public var identityId: WisdVoicePersona
    public var engineId: VoiceTTSEngineKind
    public var modelId: String
    public var speakerId: String
    public var language: VoiceLanguageVariant
    public var vocalGender: WisdVoiceTimbre
    public var speechRate: Double
    public var personalityId: VoicePersonalityStyle
    public var design: VoiceDesignConfig

    public static let defaultsKey = "wisdai.voice.unifiedConfig.v5"

    public static func defaultConfig(
        preferSupertonic: Bool = false,
        preferMaleJarvis: Bool = true
    ) -> UnifiedVoiceConfig {
        let persona: WisdVoicePersona = preferMaleJarvis ? .jarvis : .aurora
        let engine: VoiceTTSEngineKind = preferSupertonic ? .supertonic3 : .kokoro82M
        let speaker: String = preferSupertonic ? persona.defaultSupertonicPresetID : persona.kokoroStyleVectorID
        let model: String = preferSupertonic ? VoiceModelCatalog.supertonic3Int8ModelID : VoiceModelCatalog.kokoroInt8ModelID
        return UnifiedVoiceConfig(
            identityId: persona,
            engineId: engine,
            modelId: model,
            speakerId: speaker,
            language: .portugueseBR,
            vocalGender: persona.recommendedTimbre,
            speechRate: Double(persona.baseCadenceRate),
            personalityId: persona.recommendedPersonalityStyle,
            design: persona == .jarvis ? .jarvisBalanced : .naturalDefault
        )
    }

    public static func loadMigrated(from defaults: UserDefaults = .standard) -> UnifiedVoiceConfig {
        if let data = defaults.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(UnifiedVoiceConfig.self, from: data) {
            return decoded
        }

        // One-time deterministic migration reconciling disjoint V2/V3 + legacy Codex Voice keys!
        let legacyGenderRaw = (defaults.string(forKey: "wisdcode.voice.gender") ?? "").lowercased()
        let legacyKokoroRaw = (defaults.string(forKey: "wisdai.voice.kokoroPreset") ?? "").lowercased()
        let legacyEngineRaw = (defaults.string(forKey: "wisdai.voice.ttsEngineKind") ?? "").lowercased()

        let decodedLegacyIdentity: VoiceIdentityDescriptor? = {
            guard let data = defaults.data(forKey: "wisdai.voice.identity.v1") else { return nil }
            return try? JSONDecoder().decode(VoiceIdentityDescriptor.self, from: data)
        }()

        let resolvedPersona: WisdVoicePersona = {
            if legacyGenderRaw == "male" {
                return decodedLegacyIdentity?.persona == .atlas ? .atlas : .jarvis
            }
            if let existing = decodedLegacyIdentity {
                return existing.persona
            }
            if legacyKokoroRaw == "pm_alex" || legacyKokoroRaw == "pm_santa" || legacyKokoroRaw.hasPrefix("bm_") {
                return .jarvis
            }
            return .jarvis
        }()

        let engine: VoiceTTSEngineKind = {
            if let parsed = VoiceTTSEngineKind(rawValue: legacyEngineRaw) {
                return parsed
            }
            return .kokoro82M
        }()

        let speaker: String = {
            if engine == .supertonic3 {
                return SupertonicVoicePreset.defaultPreset(for: resolvedPersona).rawValue
            }
            if resolvedPersona.recommendedTimbre == .male {
                if let explicitKokoro = KokoroVoicePreset(rawValue: legacyKokoroRaw), explicitKokoro.timbre == .male {
                    return explicitKokoro.rawValue
                }
                return KokoroVoicePreset.defaultPreset(for: resolvedPersona, language: .portugueseBR)?.rawValue ?? "pm_alex"
            }
            return KokoroVoicePreset.defaultPreset(for: resolvedPersona, language: .portugueseBR)?.rawValue ?? "pf_dora"
        }()

        let model: String = {
            switch engine {
            case .supertonic3: return VoiceModelCatalog.supertonic3Int8ModelID
            case .kokoro82M: return VoiceModelCatalog.kokoroInt8ModelID
            case .appleNaturalPCM: return "apple-natural-pcm"
            default: return VoiceModelCatalog.kokoroInt8ModelID
            }
        }()

        return UnifiedVoiceConfig(
            identityId: resolvedPersona,
            engineId: engine,
            modelId: model,
            speakerId: speaker,
            language: .portugueseBR,
            vocalGender: resolvedPersona.recommendedTimbre,
            speechRate: Double(resolvedPersona.baseCadenceRate),
            personalityId: resolvedPersona.recommendedPersonalityStyle,
            design: resolvedPersona == .jarvis ? .jarvisBalanced : .naturalDefault
        )
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}

@MainActor
public final class VoiceIdentityManager: ObservableObject {
    @Published public private(set) var config: UnifiedVoiceConfig
    @Published public private(set) var requestedSnapshot: VoiceSelectionSnapshot
    @Published public private(set) var configuredSnapshot: VoiceSelectionSnapshot
    @Published public private(set) var loadedSnapshot: VoiceLoadedRuntimeSnapshot = .idle
    @Published public private(set) var inferredSnapshot: VoiceInferredRuntimeSnapshot = .none
    @Published public private(set) var divergenceAlert: String? = nil

    public var onDidChangeConfiguration: ((UnifiedVoiceConfig, _ requiresCacheInvalidation: Bool) -> Void)?

    private let defaults: UserDefaults
    private var isMutatingInternally = false

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let initial = UnifiedVoiceConfig.loadMigrated(from: defaults)
        self.config = initial
        let req = Self.buildSelectionSnapshot(from: initial)
        self.requestedSnapshot = req
        self.configuredSnapshot = req
        initial.save(to: defaults)
        syncLegacyDefaults(for: initial)
    }

    public static func resolvedNumericSID(engine: VoiceTTSEngineKind, speakerId: String, persona: WisdVoicePersona, language: VoiceLanguageVariant) -> Int32? {
        if engine == .supertonic3 {
            let p = SupertonicVoicePreset.from(identifier: speakerId) ?? SupertonicVoicePreset.defaultPreset(for: persona)
            return p.speakerID
        }
        if engine == .kokoro82M {
            if let exact = KokoroVoicePreset(rawValue: speakerId.lowercased()) {
                return exact.speakerID
            }
            return KokoroVoicePreset.defaultPreset(for: persona, language: language)?.speakerID
        }
        return nil
    }

    public static func buildSelectionSnapshot(from cfg: UnifiedVoiceConfig) -> VoiceSelectionSnapshot {
        VoiceSelectionSnapshot(
            identityId: cfg.identityId,
            engineId: cfg.engineId,
            modelId: cfg.modelId,
            speakerId: cfg.speakerId,
            numericSpeakerSID: resolvedNumericSID(engine: cfg.engineId, speakerId: cfg.speakerId, persona: cfg.identityId, language: cfg.language),
            language: cfg.language,
            vocalGender: cfg.vocalGender,
            speechRate: cfg.speechRate,
            flowMatchingSteps: cfg.design.flowMatchingSteps
        )
    }

    public func updateConfig(
        invalidateCache: Bool = true,
        _ transform: (inout UnifiedVoiceConfig) -> Void
    ) {
        guard !isMutatingInternally else { return }
        isMutatingInternally = true
        defer { isMutatingInternally = false }

        var next = config
        transform(&next)
        next.speechRate = min(1.30, max(0.75, next.speechRate))
        next.design.cadence = next.speechRate
        next.design.flowMatchingSteps = min(12, max(4, next.design.flowMatchingSteps))
        next.modelId = Self.defaultModelID(for: next.engineId)

        config = next
        requestedSnapshot = Self.buildSelectionSnapshot(from: next)
        next.save(to: defaults)
        syncLegacyDefaults(for: next)
        onDidChangeConfiguration?(next, invalidateCache)
    }

    public func selectPersona(_ persona: WisdVoicePersona) {
        updateConfig(invalidateCache: true) { cfg in
            cfg.identityId = persona
            cfg.vocalGender = persona.recommendedTimbre
            cfg.personalityId = persona.recommendedPersonalityStyle
            cfg.speechRate = Double(persona.baseCadenceRate)
            cfg.speakerId = Self.defaultSpeakerID(for: persona, engine: cfg.engineId, language: cfg.language)
            if persona == .jarvis {
                cfg.design.warmth = 0.72
                cfg.design.directness = 0.90
            }
        }
    }

    public func selectGender(_ gender: WisdVoiceTimbre) {
        updateConfig(invalidateCache: true) { cfg in
            cfg.vocalGender = gender
            let personaMatches = cfg.identityId.recommendedTimbre == gender
            let targetPersona: WisdVoicePersona = personaMatches
                ? cfg.identityId
                : (gender == .male ? .jarvis : .aurora)
            cfg.identityId = targetPersona
            cfg.personalityId = targetPersona.recommendedPersonalityStyle
            cfg.speakerId = Self.defaultSpeakerID(for: targetPersona, engine: cfg.engineId, language: cfg.language)
        }
    }

    public func selectEngine(_ engine: VoiceTTSEngineKind, resolvedModelId: String? = nil) {
        updateConfig(invalidateCache: true) { cfg in
            cfg.engineId = engine
            cfg.modelId = resolvedModelId ?? Self.defaultModelID(for: engine)
            cfg.speakerId = Self.defaultSpeakerID(for: cfg.identityId, engine: engine, language: cfg.language)
        }
    }

    public func selectSpeaker(_ speakerId: String) {
        let clean = speakerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        updateConfig(invalidateCache: true) { cfg in
            cfg.speakerId = clean
            if let st = SupertonicVoicePreset.from(identifier: clean) {
                cfg.vocalGender = st.timbre
                if cfg.identityId.recommendedTimbre != st.timbre {
                    cfg.identityId = st.timbre == .male ? .jarvis : .aurora
                    cfg.personalityId = cfg.identityId.recommendedPersonalityStyle
                }
                if cfg.engineId != .supertonic3 {
                    cfg.engineId = .supertonic3
                }
                return
            }
            if let kok = KokoroVoicePreset(rawValue: clean.lowercased()) {
                cfg.vocalGender = kok.timbre
                if cfg.identityId.recommendedTimbre != kok.timbre {
                    cfg.identityId = kok.timbre == .male ? .jarvis : .aurora
                    cfg.personalityId = cfg.identityId.recommendedPersonalityStyle
                }
                cfg.language = kok.supportedLanguage
                if cfg.engineId != .kokoro82M {
                    cfg.engineId = .kokoro82M
                }
                return
            }
        }
    }

    public func selectLanguage(_ language: VoiceLanguageVariant) {
        updateConfig(invalidateCache: true) { cfg in
            cfg.language = language
            if cfg.engineId == .kokoro82M && language == .portuguesePT {
                // Never fake pt-PT in Kokoro; switch cleanly or surface fallback in configuredSnapshot
            } else {
                cfg.speakerId = Self.defaultSpeakerID(for: cfg.identityId, engine: cfg.engineId, language: language)
            }
        }
    }

    public func recordConfiguredRuntime(
        engineId: VoiceTTSEngineKind,
        modelId: String,
        speakerId: String,
        numericSID: Int32?,
        language: VoiceLanguageVariant,
        speechRate: Double,
        flowSteps: Int
    ) {
        configuredSnapshot = VoiceSelectionSnapshot(
            identityId: config.identityId,
            engineId: engineId,
            modelId: modelId,
            speakerId: speakerId,
            numericSpeakerSID: numericSID,
            language: language,
            vocalGender: config.vocalGender,
            speechRate: speechRate,
            flowMatchingSteps: flowSteps
        )
        evaluateDivergence()
    }

    public func recordLoadedRuntime(_ loaded: VoiceLoadedRuntimeSnapshot) {
        loadedSnapshot = loaded
    }

    public func recordInferredSynthesis(_ inferred: VoiceInferredRuntimeSnapshot) {
        inferredSnapshot = inferred
        evaluateDivergence()
    }

    private func evaluateDivergence() {
        let req = requestedSnapshot
        let inf = inferredSnapshot
        guard inf.actualEngineId != "pending" else {
            divergenceAlert = nil
            return
        }
        var reasons: [String] = []
        if inf.fallbackOccurred {
            reasons.append(inf.note ?? "Motor principal indisponível; fallback para \(inf.actualEngineId) ativo.")
        }
        if let reqSid = req.numericSpeakerSID, let infSid = inf.actualNumericSID, reqSid != infSid, req.engineId.rawValue == inf.actualEngineId {
            reasons.append("SID solicitado (\(reqSid)) diverge do SID inferido (\(infSid)).")
        }
        if req.vocalGender == .male, let f0 = inf.estimatedF0Hz, f0 > 168.0, inf.actualEngineId.contains("apple") {
            reasons.append(String(format: "macOS sem voz masculina instalada para %@ (F0=%.0f Hz).", req.language.shortCode, f0))
        }
        divergenceAlert = reasons.isEmpty ? nil : reasons.joined(separator: " ")
    }

    public static func defaultSpeakerID(
        for persona: WisdVoicePersona,
        engine: VoiceTTSEngineKind,
        language: VoiceLanguageVariant
    ) -> String {
        switch engine {
        case .supertonic3:
            return SupertonicVoicePreset.defaultPreset(for: persona).rawValue
        case .kokoro82M, .autoLocal:
            return KokoroVoicePreset.defaultPreset(for: persona, language: language)?.rawValue
                ?? persona.kokoroStyleVectorID
        case .appleNaturalPCM:
            return "persona:\(persona.rawValue)"
        default:
            return persona.kokoroStyleVectorID
        }
    }

    public static func defaultModelID(for engine: VoiceTTSEngineKind) -> String {
        switch engine {
        case .supertonic3: return VoiceModelCatalog.supertonic3Int8ModelID
        case .kokoro82M: return VoiceModelCatalog.kokoroInt8ModelID
        case .appleNaturalPCM: return "apple-natural-pcm"
        case .sherpaPiperVits: return "vits-piper-local"
        case .autoLocal: return "auto_local"
        default: return engine.rawValue
        }
    }

    private func syncLegacyDefaults(for cfg: UnifiedVoiceConfig) {
        let genderRaw = (cfg.vocalGender == .male) ? "male" : "female"
        defaults.set(genderRaw, forKey: "wisdcode.voice.gender")
        defaults.set(cfg.vocalGender == .male ? "cedar" : "marin", forKey: "wisdcode.voice.codexVoice")
        defaults.set(cfg.engineId.rawValue, forKey: "wisdai.voice.ttsEngineKind")
        defaults.set(cfg.speakerId, forKey: "wisdai.voice.kokoroPreset")
        defaults.set(cfg.speechRate, forKey: "wisdcode.voice.speed")
        let legacyIdentity = VoiceIdentityDescriptor(
            persona: cfg.identityId,
            warmth: cfg.design.warmth,
            clarityEmphasis: cfg.design.directness,
            brandName: "WisdAI"
        )
        if let data = try? JSONEncoder().encode(legacyIdentity) {
            defaults.set(data, forKey: "wisdai.voice.identity.v1")
        }
    }
}

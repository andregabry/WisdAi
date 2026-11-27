import AVFoundation
import Darwin
import Foundation

// MARK: - C ABI Mirrors for sherpa-onnx v1.13.8 (Verified against c-api.h)

private struct SherpaOfflineTtsVitsModelConfigC {
    var model: UnsafePointer<CChar>?
    var lexicon: UnsafePointer<CChar>?
    var tokens: UnsafePointer<CChar>?
    var data_dir: UnsafePointer<CChar>?
    var noise_scale: Float = 0.667
    var noise_scale_w: Float = 0.8
    var length_scale: Float = 1.0
    var dict_dir: UnsafePointer<CChar>?
}

private struct SherpaOfflineTtsMatchaModelConfigC {
    var acoustic_model: UnsafePointer<CChar>?
    var vocoder: UnsafePointer<CChar>?
    var lexicon: UnsafePointer<CChar>?
    var tokens: UnsafePointer<CChar>?
    var data_dir: UnsafePointer<CChar>?
    var noise_scale: Float = 0.667
    var length_scale: Float = 1.0
    var dict_dir: UnsafePointer<CChar>?
}

private struct SherpaOfflineTtsKokoroModelConfigC {
    var model: UnsafePointer<CChar>?
    var voices: UnsafePointer<CChar>?
    var tokens: UnsafePointer<CChar>?
    var data_dir: UnsafePointer<CChar>?
    var length_scale: Float = 1.0
    var dict_dir: UnsafePointer<CChar>?
    var lexicon: UnsafePointer<CChar>?
    var lang: UnsafePointer<CChar>?
}

private struct SherpaOfflineTtsKittenModelConfigC {
    var model: UnsafePointer<CChar>?
    var voices: UnsafePointer<CChar>?
    var tokens: UnsafePointer<CChar>?
    var data_dir: UnsafePointer<CChar>?
    var length_scale: Float = 1.0
}

private struct SherpaOfflineTtsZipvoiceModelConfigC {
    var tokens: UnsafePointer<CChar>?
    var encoder: UnsafePointer<CChar>?
    var decoder: UnsafePointer<CChar>?
    var vocoder: UnsafePointer<CChar>?
    var data_dir: UnsafePointer<CChar>?
    var lexicon: UnsafePointer<CChar>?
    var feat_scale: Float = 0.1
    var t_shift: Float = 0.5
    var target_rms: Float = 0.1
    var guidance_scale: Float = 1.0
}

private struct SherpaOfflineTtsPocketModelConfigC {
    var lm_flow: UnsafePointer<CChar>?
    var lm_main: UnsafePointer<CChar>?
    var encoder: UnsafePointer<CChar>?
    var decoder: UnsafePointer<CChar>?
    var text_conditioner: UnsafePointer<CChar>?
    var vocab_json: UnsafePointer<CChar>?
    var token_scores_json: UnsafePointer<CChar>?
    var voice_embedding_cache_capacity: Int32 = 0
}

private struct SherpaOfflineTtsSupertonicModelConfigC {
    var duration_predictor: UnsafePointer<CChar>?
    var text_encoder: UnsafePointer<CChar>?
    var vector_estimator: UnsafePointer<CChar>?
    var vocoder: UnsafePointer<CChar>?
    var tts_json: UnsafePointer<CChar>?
    var unicode_indexer: UnsafePointer<CChar>?
    var voice_style: UnsafePointer<CChar>?
}

private struct SherpaOfflineTtsModelConfigC {
    var vits = SherpaOfflineTtsVitsModelConfigC()
    var num_threads: Int32 = 2
    var debug: Int32 = 0
    var provider: UnsafePointer<CChar>?
    var matcha = SherpaOfflineTtsMatchaModelConfigC()
    var kokoro = SherpaOfflineTtsKokoroModelConfigC()
    var kitten = SherpaOfflineTtsKittenModelConfigC()
    var zipvoice = SherpaOfflineTtsZipvoiceModelConfigC()
    var pocket = SherpaOfflineTtsPocketModelConfigC()
    var supertonic = SherpaOfflineTtsSupertonicModelConfigC()
}

private struct SherpaOfflineTtsConfigC {
    var model = SherpaOfflineTtsModelConfigC()
    var rule_fsts: UnsafePointer<CChar>?
    var max_num_sentences: Int32 = 1
    var rule_fars: UnsafePointer<CChar>?
    var silence_scale: Float = 0.2
}

private struct SherpaGeneratedAudioC {
    var samples: UnsafePointer<Float>?
    var n: Int32
    var sample_rate: Int32
}

private struct SherpaGenerationConfigC {
    var silence_scale: Float = 0.2
    var speed: Float = 1.0
    var sid: Int32 = 0
    var reference_audio: UnsafePointer<Float>?
    var reference_audio_len: Int32 = 0
    var reference_sample_rate: Int32 = 0
    var reference_text: UnsafePointer<CChar>?
    var num_steps: Int32 = 0
    var extra: UnsafePointer<CChar>?
}

private typealias SherpaProgressCallbackWithArg = @convention(c) (
    UnsafePointer<Float>?,
    Int32,
    Float,
    UnsafeMutableRawPointer?
) -> Int32

private typealias FnCreateOfflineTts = @convention(c) (UnsafeRawPointer?) -> OpaquePointer?
private typealias FnDestroyOfflineTts = @convention(c) (OpaquePointer?) -> Void
private typealias FnOfflineTtsSampleRate = @convention(c) (OpaquePointer?) -> Int32
private typealias FnOfflineTtsNumSpeakers = @convention(c) (OpaquePointer?) -> Int32
private typealias FnOfflineTtsGenerateWithConfig = @convention(c) (
    OpaquePointer?,
    UnsafePointer<CChar>?,
    UnsafeRawPointer?,
    SherpaProgressCallbackWithArg?,
    UnsafeMutableRawPointer?
) -> UnsafeRawPointer?
private typealias FnDestroyGeneratedAudio = @convention(c) (UnsafeRawPointer?) -> Void

private final class CStringArena {
    private var allocations: [UnsafeMutablePointer<CChar>] = []

    func cString(_ string: String) -> UnsafePointer<CChar>? {
        guard let dup = strdup(string) else { return nil }
        allocations.append(dup)
        return UnsafePointer(dup)
    }

    deinit {
        for ptr in allocations {
            free(ptr)
        }
    }
}

private final class KokoroGenerationContext {
    let chunkHandler: @Sendable ([Float], Int) -> Void
    let cancelCheck: @Sendable () -> Bool
    let sampleRate: Int
    var streamedSamplesCount: Int = 0

    init(
        sampleRate: Int,
        cancelCheck: @escaping @Sendable () -> Bool,
        chunkHandler: @escaping @Sendable ([Float], Int) -> Void
    ) {
        self.sampleRate = sampleRate
        self.cancelCheck = cancelCheck
        self.chunkHandler = chunkHandler
    }
}

private let kokoroProgressTrampoline: SherpaProgressCallbackWithArg = { samplesPtr, count, _, userData in
    guard let userData else { return 1 }
    let ctx = Unmanaged<KokoroGenerationContext>.fromOpaque(userData).takeUnretainedValue()
    if ctx.cancelCheck() {
        return 0
    }
    if count > 0, let samplesPtr {
        let buffer = Array(UnsafeBufferPointer(start: samplesPtr, count: Int(count)))
        ctx.streamedSamplesCount += buffer.count
        ctx.chunkHandler(buffer, ctx.sampleRate)
    }
    return ctx.cancelCheck() ? 0 : 1
}

// MARK: - Kokoro-82M Neural Local TTS Provider (ONNX via sherpa-onnx C ABI)

public struct KokoroEngineDiagnosticsSnapshot: Equatable, Sendable {
    public var isLoaded: Bool
    public var activeModelID: String?
    public var loadedLangCode: String?
    public var loadLatencyMs: Double?
    public var lastSynthesisMs: Double?
    public var sampleRateHz: Int
    public var numSpeakers: Int
    public var lastError: String?

    public static let idle = KokoroEngineDiagnosticsSnapshot(
        isLoaded: false,
        activeModelID: nil,
        loadedLangCode: nil,
        loadLatencyMs: nil,
        lastSynthesisMs: nil,
        sampleRateHz: 24_000,
        numSpeakers: 0,
        lastError: nil
    )
}

public final class KokoroNeuralTTSProvider: StreamingTextToSpeechProvider, @unchecked Sendable {
    public let providerID = "kokoro_82m_local_onnx"
    public let requiresPaidOptIn = false

    private struct LoadedHandles {
        let ortHandle: UnsafeMutableRawPointer?
        let sherpaHandle: UnsafeMutableRawPointer
        let createTts: FnCreateOfflineTts
        let destroyTts: FnDestroyOfflineTts
        let sampleRateFn: FnOfflineTtsSampleRate
        let numSpeakersFn: FnOfflineTtsNumSpeakers
        let generateWithConfigFn: FnOfflineTtsGenerateWithConfig
        let destroyAudioFn: FnDestroyGeneratedAudio
        var ttsPointer: OpaquePointer
        var modelID: String
        var langCode: String
        var sampleRate: Int
        var numSpeakers: Int
    }

    private let synthQueue = DispatchQueue(label: "local.wisdai.voice.kokoro", qos: .userInitiated)
    private let stateLock = NSLock()
    private var loaded: LoadedHandles?
    private var cancelledEpoch: UInt64 = 0
    private var lastIdleUnloadWorkItem: DispatchWorkItem?
    private var diagnosticsSnapshot: KokoroEngineDiagnosticsSnapshot = .idle

    private let appSupportVoiceRoot: URL

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        self.appSupportVoiceRoot = appSupport.appendingPathComponent("WisdAI/Voice", isDirectory: true)
    }

    deinit {
        unloadSync()
    }

    public var isReadyOnDisk: Bool {
        resolveInstalledPaths() != nil
    }

    public func currentDiagnostics() -> KokoroEngineDiagnosticsSnapshot {
        stateLock.withLock { diagnosticsSnapshot }
    }

    public func resolveInstalledPaths() -> (runtimeDir: URL, modelDir: URL, modelFile: URL, modelID: String)? {
        let fm = FileManager.default
        let rtRoot = appSupportVoiceRoot
            .appendingPathComponent("Runtimes/\(VoiceModelCatalog.sherpaRuntimeID)/sherpa-onnx-v1.13.8-osx-arm64-shared-lib/lib", isDirectory: true)
        let sherpaLib = rtRoot.appendingPathComponent("libsherpa-onnx-c-api.dylib")
        guard fm.fileExists(atPath: sherpaLib.path) else { return nil }

        // Prefer INT8 on Compact/Essential 8GB systems if present, else FP32 if installed.
        let candidates: [(id: String, dirName: String, onnxName: String)] = [
            (VoiceModelCatalog.kokoroInt8ModelID, "kokoro-int8-multi-lang-v1_0", "model.int8.onnx"),
            (VoiceModelCatalog.kokoroFP32ModelID, "kokoro-multi-lang-v1_0", "model.onnx")
        ]
        for cand in candidates {
            let modelDir = appSupportVoiceRoot
                .appendingPathComponent("Models/\(cand.id)/\(cand.dirName)", isDirectory: true)
            let onnx = modelDir.appendingPathComponent(cand.onnxName)
            let voices = modelDir.appendingPathComponent("voices.bin")
            let tokens = modelDir.appendingPathComponent("tokens.txt")
            let espeak = modelDir.appendingPathComponent("espeak-ng-data")
            if fm.fileExists(atPath: onnx.path),
               fm.fileExists(atPath: voices.path),
               fm.fileExists(atPath: tokens.path),
               fm.fileExists(atPath: espeak.path) {
                return (rtRoot, modelDir, onnx, cand.id)
            }
        }
        return nil
    }

    public static func resolvePreset(language: VoiceLanguageVariant, voicePreference: String) -> KokoroVoicePreset? {
        if language == .portuguesePT {
            return nil // Strictly honest: Kokoro "p" covers pt-BR only, NOT pt-PT
        }
        let cleaned = voicePreference.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let exact = KokoroVoicePreset(rawValue: cleaned), exact.supportedLanguage == language {
            return exact
        }
        if cleaned.hasPrefix("persona:") {
            let suffix = String(cleaned.dropFirst("persona:".count))
            if let persona = WisdVoicePersona(rawValue: suffix) {
                return KokoroVoicePreset.defaultPreset(for: persona, language: language)
            }
        }
        if cleaned.contains("mascul") || cleaned.contains("atlas") || cleaned.contains("alex") {
            return KokoroVoicePreset.defaultPreset(for: .atlas, language: language)
        }
        return KokoroVoicePreset.defaultPreset(for: .aurora, language: language)
    }

    public func preload(language: VoiceLanguageVariant = .portugueseBR) async throws -> KokoroEngineDiagnosticsSnapshot {
        guard let preset = Self.resolvePreset(language: language, voicePreference: "persona:aurora") else {
            throw VoiceGatewayError.protocolError("Kokoro-82M suporta apenas PT-BR, EN-US e ES-ES (não suporta pt-PT nativo).")
        }
        return try await withCheckedThrowingContinuation { continuation in
            synthQueue.async {
                do {
                    _ = try self.ensureLoadedSync(langCode: preset.kokoroLangCode)
                    continuation.resume(returning: self.currentDiagnostics())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func ensureLoadedSync(langCode: String) throws -> LoadedHandles {
        if let existing = stateLock.withLock({ loaded }), existing.langCode == langCode {
            scheduleIdleUnload()
            return existing
        }
        // If switching languages, unload old instance first so espeak-ng language state reloads cleanly.
        unloadSync()

        guard let paths = resolveInstalledPaths() else {
            throw VoiceGatewayError.protocolError("Runtime sherpa-onnx ou pesos Kokoro-82M não estão instalados no armazenamento local.")
        }

        let t0 = DispatchTime.now().uptimeNanoseconds
        let fm = FileManager.default
        let libs = (try? fm.contentsOfDirectory(at: paths.runtimeDir, includingPropertiesForKeys: nil)) ?? []
        var ortHandle: UnsafeMutableRawPointer? = nil
        if let ortURL = libs.first(where: { $0.lastPathComponent.hasPrefix("libonnxruntime") && $0.pathExtension == "dylib" }) {
            ortHandle = dlopen(ortURL.path, RTLD_NOW | RTLD_GLOBAL)
        }
        let sherpaURL = paths.runtimeDir.appendingPathComponent("libsherpa-onnx-c-api.dylib")
        guard let sherpaHandle = dlopen(sherpaURL.path, RTLD_NOW | RTLD_LOCAL) else {
            let err = dlerror().map { String(cString: $0) } ?? "dlopen falhou"
            throw VoiceGatewayError.protocolError("Falha ao carregar libsherpa-onnx-c-api.dylib: \(err)")
        }

        func resolveSymbol<T>(_ name: String) throws -> T {
            guard let ptr = dlsym(sherpaHandle, name) else {
                throw VoiceGatewayError.protocolError("Símbolo C ausente em libsherpa-onnx-c-api.dylib: \(name)")
            }
            return unsafeBitCast(ptr, to: T.self)
        }

        let createFn: FnCreateOfflineTts = try resolveSymbol("SherpaOnnxCreateOfflineTts")
        let destroyFn: FnDestroyOfflineTts = try resolveSymbol("SherpaOnnxDestroyOfflineTts")
        let srFn: FnOfflineTtsSampleRate = try resolveSymbol("SherpaOnnxOfflineTtsSampleRate")
        let spkFn: FnOfflineTtsNumSpeakers = try resolveSymbol("SherpaOnnxOfflineTtsNumSpeakers")
        let genCfgFn: FnOfflineTtsGenerateWithConfig = try resolveSymbol("SherpaOnnxOfflineTtsGenerateWithConfig")
        let destroyAudioFn: FnDestroyGeneratedAudio = try resolveSymbol("SherpaOnnxDestroyOfflineTtsGeneratedAudio")

        let arena = CStringArena()
        let voicesPath = paths.modelDir.appendingPathComponent("voices.bin").path
        let tokensPath = paths.modelDir.appendingPathComponent("tokens.txt").path
        let dataDirPath = paths.modelDir.appendingPathComponent("espeak-ng-data").path

        var config = SherpaOfflineTtsConfigC()
        config.model.num_threads = 2
        config.model.debug = 0
        config.model.provider = arena.cString("cpu")
        config.model.kokoro.model = arena.cString(paths.modelFile.path)
        config.model.kokoro.voices = arena.cString(voicesPath)
        config.model.kokoro.tokens = arena.cString(tokensPath)
        config.model.kokoro.data_dir = arena.cString(dataDirPath)
        config.model.kokoro.length_scale = 1.0
        config.model.kokoro.lang = arena.cString(langCode)
        config.max_num_sentences = 1
        config.silence_scale = 0.2

        let ttsPtr = withUnsafePointer(to: &config) { ptr in
            createFn(ptr)
        }
        guard let ttsPtr else {
            throw VoiceGatewayError.protocolError("SherpaOnnxCreateOfflineTts retornou NULL para modelo \(paths.modelID) (lang=\(langCode)).")
        }

        let sr = Int(srFn(ttsPtr))
        let spk = Int(spkFn(ttsPtr))
        let loadMs = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000.0
        let handles = LoadedHandles(
            ortHandle: ortHandle,
            sherpaHandle: sherpaHandle,
            createTts: createFn,
            destroyTts: destroyFn,
            sampleRateFn: srFn,
            numSpeakersFn: spkFn,
            generateWithConfigFn: genCfgFn,
            destroyAudioFn: destroyAudioFn,
            ttsPointer: ttsPtr,
            modelID: paths.modelID,
            langCode: langCode,
            sampleRate: sr > 0 ? sr : 24_000,
            numSpeakers: spk
        )

        stateLock.withLock {
            loaded = handles
            diagnosticsSnapshot = KokoroEngineDiagnosticsSnapshot(
                isLoaded: true,
                activeModelID: paths.modelID,
                loadedLangCode: langCode,
                loadLatencyMs: loadMs,
                lastSynthesisMs: diagnosticsSnapshot.lastSynthesisMs,
                sampleRateHz: handles.sampleRate,
                numSpeakers: spk,
                lastError: nil
            )
        }
        scheduleIdleUnload()
        return handles
    }

    public func unload() {
        synthQueue.async { [weak self] in
            self?.unloadSync()
        }
    }

    private func unloadSync() {
        lastIdleUnloadWorkItem?.cancel()
        lastIdleUnloadWorkItem = nil
        let old = stateLock.withLock { () -> LoadedHandles? in
            let current = loaded
            loaded = nil
            diagnosticsSnapshot.isLoaded = false
            return current
        }
        if let old {
            old.destroyTts(old.ttsPointer)
        }
    }

    private func scheduleIdleUnload() {
        lastIdleUnloadWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.unloadSync()
        }
        lastIdleUnloadWorkItem = work
        synthQueue.asyncAfter(deadline: .now() + 180.0, execute: work)
    }

    public func synthesizeChunk(
        _ text: String,
        language: VoiceLanguageVariant,
        voicePreference: String,
        rate: Float,
        onAudioFloats24k: @escaping @Sendable ([Float], String) -> Void
    ) async throws {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        guard let preset = Self.resolvePreset(language: language, voicePreference: voicePreference) else {
            throw VoiceGatewayError.protocolError("Kokoro-82M suporta apenas PT-BR, EN-US e ES-ES (não suporta pt-PT nativo).")
        }

        let startEpoch = stateLock.withLock { cancelledEpoch }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            synthQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                do {
                    guard !Task.isCancelled,
                          self.stateLock.withLock({ self.cancelledEpoch == startEpoch }) else {
                        continuation.resume()
                        return
                    }
                    let handles = try self.ensureLoadedSync(langCode: preset.kokoroLangCode)
                    let t0 = DispatchTime.now().uptimeNanoseconds

                    var genCfg = SherpaGenerationConfigC()
                    genCfg.silence_scale = 0.2
                    genCfg.speed = min(1.35, max(0.70, rate))
                    genCfg.sid = preset.speakerID

                    final class KokoroLabelState: @unchecked Sendable {
                        private let lock = NSLock()
                        private var labelled = false
                        private let text: String
                        init(text: String) { self.text = text }
                        func claimLabel() -> String {
                            lock.withLock {
                                guard !labelled else { return "" }
                                labelled = true
                                return text
                            }
                        }
                    }
                    let labelState = KokoroLabelState(text: clean)
                    let ctx = KokoroGenerationContext(
                        sampleRate: handles.sampleRate,
                        cancelCheck: {
                            self.stateLock.withLock { self.cancelledEpoch != startEpoch }
                        },
                        chunkHandler: { rawSamples, sr in
                            let converted: [Float]
                            if sr != 24_000 {
                                converted = AudioPCMConverter.resampleLinear(
                                    samples: rawSamples,
                                    fromSampleRate: Double(sr),
                                    toSampleRate: 24_000
                                )
                            } else {
                                converted = rawSamples
                            }
                            guard !converted.isEmpty else { return }
                            onAudioFloats24k(converted, labelState.claimLabel())
                        }
                    )

                    let arena = CStringArena()
                    guard let cText = arena.cString(clean) else {
                        throw VoiceGatewayError.protocolError("Falha ao alocar texto UTF-8.")
                    }

                    let audioPtr = withUnsafePointer(to: &genCfg) { cfgPtr in
                        handles.generateWithConfigFn(
                            handles.ttsPointer,
                            cText,
                            cfgPtr,
                            kokoroProgressTrampoline,
                            Unmanaged.passUnretained(ctx).toOpaque()
                        )
                    }

                    if let audioPtr {
                        defer { handles.destroyAudioFn(audioPtr) }
                        let cancelled = self.stateLock.withLock { self.cancelledEpoch != startEpoch }
                        if !cancelled && ctx.streamedSamplesCount == 0 {
                            let audio = audioPtr.assumingMemoryBound(to: SherpaGeneratedAudioC.self).pointee
                            if audio.n > 0, let ptr = audio.samples {
                                let raw = Array(UnsafeBufferPointer(start: ptr, count: Int(audio.n)))
                                let out = (audio.sample_rate > 0 && Int(audio.sample_rate) != 24_000)
                                    ? AudioPCMConverter.resampleLinear(samples: raw, fromSampleRate: Double(audio.sample_rate), toSampleRate: 24_000)
                                    : raw
                                if !out.isEmpty {
                                    onAudioFloats24k(out, clean)
                                }
                            }
                        }
                    }

                    let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000.0
                    self.stateLock.withLock {
                        self.diagnosticsSnapshot.lastSynthesisMs = elapsedMs
                        self.diagnosticsSnapshot.lastError = nil
                    }
                    self.scheduleIdleUnload()
                    continuation.resume()
                } catch {
                    self.stateLock.withLock {
                        self.diagnosticsSnapshot.lastError = error.localizedDescription
                    }
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func synthesizeStandaloneSamples(
        text: String,
        language: VoiceLanguageVariant,
        preset: KokoroVoicePreset,
        rate: Float = 1.0
    ) async throws -> (samples: [Float], sampleRate: Int, synthMs: Double) {
        final class SamplesBox: @unchecked Sendable {
            private let lock = NSLock()
            private var samples: [Float] = []
            func append(_ chunk: [Float]) { lock.withLock { samples.append(contentsOf: chunk) } }
            func snapshot() -> [Float] { lock.withLock { samples } }
        }
        let box = SamplesBox()
        let t0 = DispatchTime.now().uptimeNanoseconds
        try await synthesizeChunk(
            text,
            language: language,
            voicePreference: preset.rawValue,
            rate: rate
        ) { floats, _ in
            box.append(floats)
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000.0
        return (box.snapshot(), 24_000, elapsed)
    }

    public func cancelAll() {
        stateLock.withLock {
            cancelledEpoch &+= 1
        }
    }
}

// MARK: - Local llama.cpp Metal Runtime (loopback 127.0.0.1 SSE Server)

@MainActor
public final class LocalLlamaServerBrainRuntime: ObservableObject {
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var isLoadingModel: Bool = false
    @Published public private(set) var loadedModelID: String?
    @Published public private(set) var loadedModelName: String = "Nenhum carregado"
    @Published public private(set) var lastLoadDurationMs: Double?
    @Published public private(set) var lastTTFTMs: Double?
    @Published public private(set) var lastError: String?
    @Published public var selectedModelID: String = UserDefaults.standard.string(forKey: "wisdai.voice.selectedLocalGGUF") ?? VoiceModelCatalog.qwen3SmallID {
        didSet {
            UserDefaults.standard.set(selectedModelID, forKey: "wisdai.voice.selectedLocalGGUF")
        }
    }

    private var process: Process?
    private var activePort: UInt16 = 0
    private var idleUnloadTask: Task<Void, Never>?
    private let assetManager: VoiceModelAssetManager

    public init(assetManager: VoiceModelAssetManager) {
        self.assetManager = assetManager
    }

    deinit {
        process?.terminate()
    }

    public var isSelectedModelReadyOnDisk: Bool {
        resolveModelAndBinary(preferredModelID: selectedModelID) != nil
    }

    public func resolveModelAndBinary(preferredModelID: String?) -> (serverURL: URL, binDir: URL, ggufURL: URL, descriptor: LocalVoiceModelDescriptor)? {
        guard let runtimeDesc = VoiceModelCatalog.descriptor(id: VoiceModelCatalog.llamaRuntimeID),
              assetManager.isModelInstalledOnDisk(runtimeDesc) else {
            return nil
        }
        let runtimeRoot = assetManager.storageRootURL(for: runtimeDesc)
        guard let serverBin = assetManager.findBinaryNamed("llama-server", under: runtimeRoot) else {
            return nil
        }

        let llmCandidates: [LocalVoiceModelDescriptor] = {
            var list: [LocalVoiceModelDescriptor] = []
            if let preferredModelID, let p = VoiceModelCatalog.descriptor(id: preferredModelID), p.category == .llm, p.isDownloadable {
                list.append(p)
            }
            for item in VoiceModelCatalog.availableLocalModels where item.category == .llm && item.isDownloadable && item.id != preferredModelID {
                list.append(item)
            }
            return list
        }()

        for desc in llmCandidates {
            if assetManager.isModelInstalledOnDisk(desc), let gguf = assetManager.entryPointURL(for: desc) {
                return (serverBin, serverBin.deletingLastPathComponent(), gguf, desc)
            }
        }
        return nil
    }

    public func ensureServerReady(modelID: String? = nil) async throws -> Int {
        let targetID = modelID ?? selectedModelID
        guard let resolved = resolveModelAndBinary(preferredModelID: targetID) else {
            throw VoiceGatewayError.protocolError("Runtime llama.cpp Metal ou modelo GGUF local não instalado em Armazenamento/Modelos.")
        }

        if isRunning, loadedModelID == resolved.descriptor.id, activePort > 0, await probeHealth(port: activePort) {
            scheduleIdleUnload()
            return Int(activePort)
        }

        unloadModel()
        isLoadingModel = true
        assetManager.setRuntimeActivity(modelID: resolved.descriptor.id, state: .loading)
        lastError = nil

        let port = Self.findFreeLoopbackPort()
        guard port > 0 else {
            isLoadingModel = false
            let msg = "Não foi possível reservar porta loopback para llama-server."
            lastError = msg
            assetManager.setRuntimeActivity(modelID: resolved.descriptor.id, state: .error, error: msg)
            throw VoiceGatewayError.protocolError(msg)
        }

        let t0 = DispatchTime.now().uptimeNanoseconds
        let proc = Process()
        proc.executableURL = resolved.serverURL
        let ctxSize = assetManager.hardwareProfile == .low8GB ? "2048" : "4096"
        let threads = assetManager.hardwareProfile == .low8GB ? "4" : "6"
        proc.arguments = [
            "-m", resolved.ggufURL.path,
            "--host", "127.0.0.1",
            "--port", "\(port)",
            "-ngl", "99",
            "--ctx-size", ctxSize,
            "--threads", threads,
            "--no-webui"
        ]
        var env = ProcessInfo.processInfo.environment
        env["DYLD_LIBRARY_PATH"] = resolved.binDir.path
        proc.environment = env
        let errPipe = Pipe()
        proc.standardError = errPipe
        proc.standardOutput = Pipe()

        do {
            try proc.run()
        } catch {
            isLoadingModel = false
            lastError = error.localizedDescription
            assetManager.setRuntimeActivity(modelID: resolved.descriptor.id, state: .error, error: error.localizedDescription)
            throw error
        }

        self.process = proc
        self.activePort = port

        // Poll /health for up to 30 seconds
        for _ in 0..<120 {
            if !proc.isRunning {
                let stderrData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errTxt = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "encerrado"
                isLoadingModel = false
                let msg = "llama-server encerrou durante carga (\(proc.terminationStatus)): \(String(errTxt.suffix(240)))"
                lastError = msg
                assetManager.setRuntimeActivity(modelID: resolved.descriptor.id, state: .error, error: msg)
                throw VoiceGatewayError.protocolError(msg)
            }
            if await probeHealth(port: port) {
                let loadMs = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000.0
                isLoadingModel = false
                isRunning = true
                loadedModelID = resolved.descriptor.id
                loadedModelName = resolved.descriptor.displayName
                lastLoadDurationMs = loadMs
                assetManager.setRuntimeActivity(modelID: resolved.descriptor.id, state: .operational)
                scheduleIdleUnload()
                return Int(port)
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        unloadModel()
        let timeoutMsg = "Timeout ao aguardar carregamento do modelo \(resolved.descriptor.displayName)."
        lastError = timeoutMsg
        assetManager.setRuntimeActivity(modelID: resolved.descriptor.id, state: .error, error: timeoutMsg)
        throw VoiceGatewayError.protocolError(timeoutMsg)
    }

    public func unloadModel() {
        idleUnloadTask?.cancel()
        idleUnloadTask = nil
        if let proc = process, proc.isRunning {
            proc.terminate()
        }
        process = nil
        activePort = 0
        isRunning = false
        isLoadingModel = false
        if let oldID = loadedModelID {
            assetManager.setRuntimeActivity(modelID: oldID, state: nil)
        }
        loadedModelID = nil
        loadedModelName = "Nenhum carregado"
    }

    private func scheduleIdleUnload() {
        idleUnloadTask?.cancel()
        idleUnloadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 240_000_000_000)
            guard !Task.isCancelled else { return }
            self?.unloadModel()
        }
    }

    private func probeHealth(port: UInt16) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.0
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    public func streamChatCompletion(
        systemPrompt: String,
        recentHistory: [(role: String, text: String)],
        userText: String,
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        let port = try await ensureServerReady()
        guard let url = URL(string: "http://127.0.0.1:\(port)/v1/chat/completions") else {
            throw VoiceGatewayError.protocolError("Endpoint loopback inválido.")
        }

        var messages: [[String: String]] = [["role": "system", "content": systemPrompt]]
        for item in recentHistory.suffix(8) {
            let mappedRole = item.role == "user" ? "user" : "assistant"
            let clean = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty {
                messages.append(["role": mappedRole, "content": clean])
            }
        }
        // Soft disable verbose reasoning blocks on Qwen3 models so spoken responses stay crisp and low-latency.
        let userContent = selectedModelID.contains("qwen3") ? "/no_think\n\(userText)" : userText
        messages.append(["role": "user", "content": userContent])

        return try await OpenAILoopbackSSEClient.streamCompletion(
            endpointURL: url,
            modelName: loadedModelName,
            messages: messages,
            timeoutSeconds: 45,
            onTTFT: { [weak self] ttftMs in
                self?.lastTTFTMs = ttftMs
            },
            onDelta: onDelta
        )
    }

    private static func findFreeLoopbackPort() -> UInt16 {
        let sock = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return 0 }
        defer { Darwin.close(sock) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        let bindRes = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(sock, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindRes == 0 else { return 0 }
        var boundAddr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameRes = withUnsafeMutablePointer(to: &boundAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                getsockname(sock, sa, &len)
            }
        }
        guard nameRes == 0 else { return 0 }
        return UInt16(bigEndian: boundAddr.sin_port)
    }
}

// MARK: - Local MLX Loopback Client (Pure Loopback http://127.0.0.1)

@MainActor
public final class LocalMLXClientRuntime: ObservableObject {
    @Published public var port: Int = UserDefaults.standard.integer(forKey: "wisdai.voice.mlxPort") == 0
        ? 8080
        : UserDefaults.standard.integer(forKey: "wisdai.voice.mlxPort") {
        didSet { UserDefaults.standard.set(port, forKey: "wisdai.voice.mlxPort") }
    }
    @Published public private(set) var isServerReachable: Bool = false
    @Published public private(set) var activeModelName: String = "mlx-local"
    @Published public private(set) var lastTTFTMs: Double?
    @Published public private(set) var lastError: String?

    public func probeAvailability() async -> Bool {
        guard (1024...65535).contains(port),
              let url = URL(string: "http://127.0.0.1:\(port)/v1/models") else {
            isServerReachable = false
            lastError = "Porta MLX inválida."
            return false
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.5
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                isServerReachable = false
                lastError = "Servidor MLX loopback não respondeu HTTP 200."
                return false
            }
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = obj["data"] as? [[String: Any]],
               let firstID = models.first?["id"] as? String {
                activeModelName = firstID
            }
            isServerReachable = true
            lastError = nil
            return true
        } catch {
            isServerReachable = false
            lastError = "Nenhum servidor mlx_lm.server ativo em 127.0.0.1:\(port)."
            return false
        }
    }

    public func streamChatCompletion(
        systemPrompt: String,
        recentHistory: [(role: String, text: String)],
        userText: String,
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        guard await probeAvailability(),
              let url = URL(string: "http://127.0.0.1:\(port)/v1/chat/completions") else {
            throw VoiceGatewayError.protocolError(lastError ?? "Servidor MLX local indisponível em 127.0.0.1:\(port).")
        }
        var messages: [[String: String]] = [["role": "system", "content": systemPrompt]]
        for item in recentHistory.suffix(8) {
            let mappedRole = item.role == "user" ? "user" : "assistant"
            let clean = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty { messages.append(["role": mappedRole, "content": clean]) }
        }
        messages.append(["role": "user", "content": userText])

        return try await OpenAILoopbackSSEClient.streamCompletion(
            endpointURL: url,
            modelName: activeModelName,
            messages: messages,
            timeoutSeconds: 45,
            onTTFT: { [weak self] ms in self?.lastTTFTMs = ms },
            onDelta: onDelta
        )
    }
}

// MARK: - Shared Loopback SSE Client (Zero Duplication Between llama.cpp & MLX)

private enum OpenAILoopbackSSEClient {
    @MainActor
    static func streamCompletion(
        endpointURL: URL,
        modelName: String,
        messages: [[String: String]],
        timeoutSeconds: TimeInterval,
        onTTFT: @escaping @MainActor (Double) -> Void,
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        var req = URLRequest(url: endpointURL)
        req.httpMethod = "POST"
        req.timeoutInterval = timeoutSeconds
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let bodyObj: [String: Any] = [
            "model": modelName,
            "messages": messages,
            "stream": true,
            "temperature": 0.65,
            "max_tokens": 380
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: bodyObj)

        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpCookieStorage = nil
        cfg.urlCredentialStorage = nil
        let session = URLSession(configuration: cfg)
        defer { session.invalidateAndCancel() }

        let t0 = DispatchTime.now().uptimeNanoseconds
        let (bytes, response) = try await session.bytes(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw VoiceGatewayError.protocolError("Erro HTTP \(code) no servidor LLM local.")
        }

        var fullRaw = ""
        var emittedCleanCount = 0
        var recordedTTFT = false

        for try await line in bytes.lines {
            if Task.isCancelled { break }
            guard line.hasPrefix("data:") else { continue }
            let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = obj["choices"] as? [[String: Any]],
                  let deltaObj = choices.first?["delta"] as? [String: Any],
                  let token = deltaObj["content"] as? String,
                  !token.isEmpty else {
                continue
            }

            fullRaw += token
            let visible = stripThinkBlocksIncremental(fullRaw)
            if visible.count > emittedCleanCount {
                let startIdx = visible.index(visible.startIndex, offsetBy: emittedCleanCount)
                let newChunk = String(visible[startIdx...])
                emittedCleanCount = visible.count
                if !recordedTTFT {
                    recordedTTFT = true
                    let ttft = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000.0
                    onTTFT(ttft)
                }
                if !newChunk.isEmpty {
                    onDelta(newChunk)
                }
            }
        }

        return stripThinkBlocksFinal(fullRaw).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripThinkBlocksIncremental(_ raw: String) -> String {
        if let openRange = raw.range(of: "<think>") {
            if let closeRange = raw.range(of: "</think>", range: openRange.upperBound..<raw.endIndex) {
                let before = raw[..<openRange.lowerBound]
                let after = raw[closeRange.upperBound...]
                return String(before + after).trimmingCharacters(in: .newlines)
            }
            return String(raw[..<openRange.lowerBound])
        }
        return raw.replacingOccurrences(of: "</think>", with: "")
    }

    private static func stripThinkBlocksFinal(_ raw: String) -> String {
        let stripped = raw.replacingOccurrences(of: "<think>[\\s\\S]*?</think>", with: "", options: .regularExpression)
        return stripped.replacingOccurrences(of: "</?think>", with: "", options: .regularExpression)
    }
}

// MARK: - Native Speech-to-Speech Hardware & Runtime Eligibility Probe (Phase 5)

public struct NativeS2SReadinessSnapshot: Equatable, Sendable {
    public let isSupportedOnThisMac: Bool
    public let recommendedProfileName: String
    public let blockerReason: String?
    public let inspectedModules: [String]
}

public enum NativeS2SRuntimeProbe {
    public static func evaluate(hardwareTier: VoiceHardwareTier) -> NativeS2SReadinessSnapshot {
        let ramGB = hardwareTier.resolvedRAMGB()
        if ramGB < 14.0 {
            return NativeS2SReadinessSnapshot(
                isSupportedOnThisMac: false,
                recommendedProfileName: hardwareTier.displayName,
                blockerReason: String(format: "Memória RAM efetiva (~%.0f GB) insuficiente para S2S nativo em execução simultânea (Kyutai Moshi MLX Q4 requer ~5 GB livres + sistema e idioma principal em inglês; MiniCPM-o/PersonaPlex requerem 24–32+ GB). Modo Híbrido Neural ativo.", ramGB),
                inspectedModules: []
            )
        }
        // Honest runtime check: inspect whether user installed local MLX / moshi_mlx in standard Python environments
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidateBins = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "\(home)/.local/bin/moshi_mlx",
            "\(home)/.venv/bin/python3"
        ]
        let found = candidateBins.filter { FileManager.default.isExecutableFile(atPath: $0) }
        return NativeS2SReadinessSnapshot(
            isSupportedOnThisMac: false,
            recommendedProfileName: hardwareTier.displayName,
            blockerReason: found.isEmpty
                ? "Nenhum runtime S2S local (mlx / moshi_mlx / MiniCPM-o) detectado neste Mac. Utilize o modo Híbrido Neural Local."
                : "Ambiente Python detectado (\(found.joined(separator: ", "))), porém pesos S2S locais (Moshi MLX / MiniCPM-o) ainda requerem instalação e servidor dedicado.",
            inspectedModules: found
        )
    }
}

// MARK: - Audition & Sample Audio Preview Player (Settings Lab)

@MainActor
public final class VoiceAudioPreviewPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published public private(set) var isPlaying: Bool = false
    @Published public private(set) var activeLabel: String = ""
    @Published public private(set) var lastPlaybackError: String?

    private var player: AVAudioPlayer?

    public func playFloatSamples(_ samples: [Float], sampleRate: Int = 24_000, label: String) {
        stop()
        guard !samples.isEmpty else {
            lastPlaybackError = "Buffer de áudio vazio."
            return
        }
        let pcm = AudioPCMConverter.floatsToPCM16Data(samples)
        let wav = CodexVoiceAudioCues.makeWAVContainer(pcm16Mono: pcm, sampleRate: sampleRate, channels: 1)
        playWAVData(wav, label: label)
    }

    public func playWAVData(_ wavData: Data, label: String) {
        stop()
        do {
            let p = try AVAudioPlayer(data: wavData)
            p.delegate = self
            p.prepareToPlay()
            if p.play() {
                player = p
                activeLabel = label
                isPlaying = true
                lastPlaybackError = nil
            } else {
                lastPlaybackError = "AVAudioPlayer não iniciou reprodução."
            }
        } catch {
            lastPlaybackError = error.localizedDescription
        }
    }

    public func saveWAV(samples: [Float], sampleRate: Int = 24_000, to url: URL) throws {
        let pcm = AudioPCMConverter.floatsToPCM16Data(samples)
        let wav = CodexVoiceAudioCues.makeWAVContainer(pcm16Mono: pcm, sampleRate: sampleRate, channels: 1)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try wav.write(to: url, options: [.atomic])
    }

    public func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        activeLabel = ""
    }

    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.isPlaying = false
            self?.activeLabel = ""
            self?.player = nil
        }
    }
}

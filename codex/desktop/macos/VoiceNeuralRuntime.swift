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

private struct SherpaTtsFunctions {
    let ortHandle: UnsafeMutableRawPointer?
    let sherpaHandle: UnsafeMutableRawPointer
    let createTts: FnCreateOfflineTts
    let destroyTts: FnDestroyOfflineTts
    let sampleRateFn: FnOfflineTtsSampleRate
    let numSpeakersFn: FnOfflineTtsNumSpeakers
    let genWithCfgFn: FnOfflineTtsGenerateWithConfig
    let destroyAudioFn: FnDestroyGeneratedAudio
}

private enum SherpaDynamicBridge {
    static func open(runtimeDir: URL) throws -> SherpaTtsFunctions {
        let fm = FileManager.default
        let libs = (try? fm.contentsOfDirectory(at: runtimeDir, includingPropertiesForKeys: nil)) ?? []
        var ortHandle: UnsafeMutableRawPointer? = nil
        if let ortURL = libs.first(where: { $0.lastPathComponent.hasPrefix("libonnxruntime") && $0.pathExtension == "dylib" }) {
            ortHandle = dlopen(ortURL.path, RTLD_NOW | RTLD_GLOBAL | RTLD_NODELETE)
        }
        let sherpaURL = runtimeDir.appendingPathComponent("libsherpa-onnx-c-api.dylib")
        guard let sherpaHandle = dlopen(sherpaURL.path, RTLD_NOW | RTLD_LOCAL | RTLD_NODELETE) else {
            let err = dlerror().map { String(cString: $0) } ?? "dlopen falhou"
            throw VoiceGatewayError.protocolError("Falha ao carregar libsherpa-onnx-c-api.dylib: \(err)")
        }
        func sym<T>(_ name: String) throws -> T {
            guard let ptr = dlsym(sherpaHandle, name) else {
                throw VoiceGatewayError.protocolError("Símbolo C ausente em libsherpa-onnx-c-api.dylib: \(name)")
            }
            return unsafeBitCast(ptr, to: T.self)
        }
        return SherpaTtsFunctions(
            ortHandle: ortHandle,
            sherpaHandle: sherpaHandle,
            createTts: try sym("SherpaOnnxCreateOfflineTts"),
            destroyTts: try sym("SherpaOnnxDestroyOfflineTts"),
            sampleRateFn: try sym("SherpaOnnxOfflineTtsSampleRate"),
            numSpeakersFn: try sym("SherpaOnnxOfflineTtsNumSpeakers"),
            genWithCfgFn: try sym("SherpaOnnxOfflineTtsGenerateWithConfig"),
            destroyAudioFn: try sym("SherpaOnnxDestroyOfflineTtsGeneratedAudio")
        )
    }
}

public struct NeuralSynthesisExecutionInfo: Equatable, Sendable {
    public let engineID: String
    public let modelID: String
    public let speakerID: String
    public let numericSID: Int32
    public let langCode: String
    public let sampleRateHz: Int
    public let synthMs: Double
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
    private var lastExecutionInfoSnapshot: NeuralSynthesisExecutionInfo?

    private let appSupportVoiceRoot: URL

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        self.appSupportVoiceRoot = appSupport.appendingPathComponent("WisdAI/Voice", isDirectory: true)
    }

    deinit {
        lastIdleUnloadWorkItem?.cancel()
        lastIdleUnloadWorkItem = nil
        let old = stateLock.withLock { () -> LoadedHandles? in
            let current = loaded
            loaded = nil
            diagnosticsSnapshot.isLoaded = false
            return current
        }
        if let old {
            synthQueue.async {
                old.destroyTts(old.ttsPointer)
            }
        }
    }

    public var isReadyOnDisk: Bool {
        resolveInstalledPaths() != nil
    }

    public func currentDiagnostics() -> KokoroEngineDiagnosticsSnapshot {
        stateLock.withLock { diagnosticsSnapshot }
    }

    public func lastExecutionInfo() -> NeuralSynthesisExecutionInfo? {
        stateLock.withLock { lastExecutionInfoSnapshot }
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

    public static func normalizeForEspeakG2P(_ text: String, langCode: String) -> String {
        var out = text.replacingOccurrences(of: "…", with: "...")
            .replacingOccurrences(of: "—", with: ", ")
        if langCode == "pt-br" {
            if let rx = try? NSRegularExpression(pattern: "\\bh+m+\\b", options: [.caseInsensitive]) {
                let range = NSRange(out.startIndex..<out.endIndex, in: out)
                out = rx.stringByReplacingMatches(in: out, range: range, withTemplate: "hum")
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
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
                if language == .portugueseBR, let exactStyle = KokoroVoicePreset(rawValue: persona.kokoroStyleVectorID) {
                    return exactStyle
                }
                return KokoroVoicePreset.defaultPreset(for: persona, language: language)
            }
        }
        if cleaned.contains("jarvis") {
            return KokoroVoicePreset.defaultPreset(for: .jarvis, language: language)
        }
        if cleaned.contains("ultron") {
            return KokoroVoicePreset.defaultPreset(for: .ultronBR, language: language)
        }
        if cleaned.contains("mascul") || cleaned.contains("homem") || cleaned.contains("male") || cleaned.contains("atlas") || cleaned.contains("alex") {
            return KokoroVoicePreset.defaultPreset(for: .atlas, language: language)
        }
        return KokoroVoicePreset.defaultPreset(for: .aurora, language: language)
    }

    public func preload(language: VoiceLanguageVariant = .portugueseBR) async throws -> KokoroEngineDiagnosticsSnapshot {
        guard let preset = Self.resolvePreset(language: language, voicePreference: "persona:jarvis") ?? KokoroVoicePreset.defaultPreset(for: .jarvis, language: language) else {
            throw VoiceGatewayError.protocolError("Kokoro-82M suporta apenas PT-BR, EN-GB, EN-US e ES-ES (não suporta pt-PT nativo).")
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
        let fns = try SherpaDynamicBridge.open(runtimeDir: paths.runtimeDir)

        let arena = CStringArena()
        let voicesPath = paths.modelDir.appendingPathComponent("voices.bin").path
        let tokensPath = paths.modelDir.appendingPathComponent("tokens.txt").path
        let dataDirPath = paths.modelDir.appendingPathComponent("espeak-ng-data").path
        let lexiconUS = paths.modelDir.appendingPathComponent("lexicon-us-en.txt")
        let lexiconGB = paths.modelDir.appendingPathComponent("lexicon-gb-en.txt")

        var config = SherpaOfflineTtsConfigC()
        config.model.num_threads = 4
        config.model.debug = 0
        config.model.provider = arena.cString("cpu")
        config.model.kokoro.model = arena.cString(paths.modelFile.path)
        config.model.kokoro.voices = arena.cString(voicesPath)
        config.model.kokoro.tokens = arena.cString(tokensPath)
        config.model.kokoro.data_dir = arena.cString(dataDirPath)
        if langCode == "en-us" && fm.fileExists(atPath: lexiconUS.path) {
            config.model.kokoro.lexicon = arena.cString(lexiconUS.path)
        } else if langCode == "en-GB-x-rp" && fm.fileExists(atPath: lexiconGB.path) {
            config.model.kokoro.lexicon = arena.cString(lexiconGB.path)
        }
        config.model.kokoro.length_scale = 1.0
        config.model.kokoro.lang = arena.cString(langCode)
        config.max_num_sentences = 1
        config.silence_scale = 0.2

        let ttsPtr = withUnsafePointer(to: &config) { ptr in
            fns.createTts(ptr)
        }
        guard let ttsPtr else {
            throw VoiceGatewayError.protocolError("SherpaOnnxCreateOfflineTts retornou NULL para modelo \(paths.modelID) (lang=\(langCode)).")
        }

        let sr = Int(fns.sampleRateFn(ttsPtr))
        let spk = Int(fns.numSpeakersFn(ttsPtr))
        let loadMs = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000.0
        let handles = LoadedHandles(
            ortHandle: fns.ortHandle,
            sherpaHandle: fns.sherpaHandle,
            createTts: fns.createTts,
            destroyTts: fns.destroyTts,
            sampleRateFn: fns.sampleRateFn,
            numSpeakersFn: fns.numSpeakersFn,
            generateWithConfigFn: fns.genWithCfgFn,
            destroyAudioFn: fns.destroyAudioFn,
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

    public func unloadSynchronously() {
        synthQueue.sync {
            self.unloadSync()
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
        try await synthesizeChunk(
            text,
            language: language,
            voicePreference: voicePreference,
            rate: rate,
            silenceScale: 0.20,
            onAudioFloats24k: onAudioFloats24k
        )
    }

    public func synthesizeChunk(
        _ text: String,
        language: VoiceLanguageVariant,
        voicePreference: String,
        rate: Float,
        silenceScale: Float,
        onAudioFloats24k: @escaping @Sendable ([Float], String) -> Void
    ) async throws {
        guard let preset = Self.resolvePreset(language: language, voicePreference: voicePreference) else {
            throw VoiceGatewayError.protocolError("Kokoro-82M suporta apenas PT-BR, EN-GB, EN-US e ES-ES (não suporta pt-PT nativo).")
        }
        let clean = Self.normalizeForEspeakG2P(
            text.trimmingCharacters(in: .whitespacesAndNewlines),
            langCode: preset.kokoroLangCode
        )
        guard !clean.isEmpty else { return }

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
                    genCfg.silence_scale = min(0.60, max(0.10, silenceScale))
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
                    let execInfo = NeuralSynthesisExecutionInfo(
                        engineID: self.providerID,
                        modelID: handles.modelID,
                        speakerID: preset.rawValue,
                        numericSID: preset.speakerID,
                        langCode: handles.langCode,
                        sampleRateHz: handles.sampleRate,
                        synthMs: elapsedMs
                    )
                    self.stateLock.withLock {
                        self.diagnosticsSnapshot.lastSynthesisMs = elapsedMs
                        self.diagnosticsSnapshot.lastError = nil
                        self.lastExecutionInfoSnapshot = execInfo
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
        rate: Float = 1.0,
        silenceScale: Float = 0.20
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
            rate: rate,
            silenceScale: silenceScale
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

// MARK: - Supertonic-3 Flow Matching Neural TTS Provider (ONNX 44.1 kHz via sherpa-onnx C ABI)

public final class SupertonicNeuralTTSProvider: StreamingTextToSpeechProvider, @unchecked Sendable {
    public let providerID = "supertonic_3_local_onnx"
    public let requiresPaidOptIn = false

    private struct LoadedSupertonicHandles {
        let fns: SherpaTtsFunctions
        let ttsPointer: OpaquePointer
        let modelID: String
        let sampleRate: Int
        let numSpeakers: Int
    }

    private let synthQueue = DispatchQueue(label: "local.wisdai.voice.supertonic3", qos: .userInitiated)
    private let stateLock = NSLock()
    private var loaded: LoadedSupertonicHandles?
    private var cancelledEpoch: UInt64 = 0
    private var lastIdleUnloadWorkItem: DispatchWorkItem?
    private var defaultFlowSteps: Int = 8
    private var diagnosticsSnapshot: KokoroEngineDiagnosticsSnapshot = KokoroEngineDiagnosticsSnapshot(
        isLoaded: false,
        activeModelID: nil,
        loadedLangCode: nil,
        loadLatencyMs: nil,
        lastSynthesisMs: nil,
        sampleRateHz: 44_100,
        numSpeakers: 0,
        lastError: nil
    )
    private var lastExecutionInfoSnapshot: NeuralSynthesisExecutionInfo?
    private let appSupportVoiceRoot: URL

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        self.appSupportVoiceRoot = appSupport.appendingPathComponent("WisdAI/Voice", isDirectory: true)
    }

    deinit {
        lastIdleUnloadWorkItem?.cancel()
        lastIdleUnloadWorkItem = nil
        let old = stateLock.withLock { () -> LoadedSupertonicHandles? in
            let current = loaded
            loaded = nil
            diagnosticsSnapshot.isLoaded = false
            return current
        }
        if let old {
            synthQueue.async { old.fns.destroyTts(old.ttsPointer) }
        }
    }

    public func setDefaultFlowMatchingSteps(_ steps: Int) {
        stateLock.withLock { defaultFlowSteps = min(12, max(4, steps)) }
    }

    public var isReadyOnDisk: Bool {
        resolveInstalledPaths() != nil
    }

    public func currentDiagnostics() -> KokoroEngineDiagnosticsSnapshot {
        stateLock.withLock { diagnosticsSnapshot }
    }

    public func lastExecutionInfo() -> NeuralSynthesisExecutionInfo? {
        stateLock.withLock { lastExecutionInfoSnapshot }
    }

    public func resolveInstalledPaths() -> (runtimeDir: URL, modelDir: URL, modelID: String)? {
        let fm = FileManager.default
        let rtRoot = appSupportVoiceRoot
            .appendingPathComponent("Runtimes/\(VoiceModelCatalog.sherpaRuntimeID)/sherpa-onnx-v1.13.8-osx-arm64-shared-lib/lib", isDirectory: true)
        guard fm.fileExists(atPath: rtRoot.appendingPathComponent("libsherpa-onnx-c-api.dylib").path) else {
            return nil
        }
        let modelDir = appSupportVoiceRoot
            .appendingPathComponent("Models/\(VoiceModelCatalog.supertonic3Int8ModelID)/sherpa-onnx-supertonic-3-tts-int8-2026-05-11", isDirectory: true)
        let requiredFiles = [
            "duration_predictor.int8.onnx",
            "text_encoder.int8.onnx",
            "vector_estimator.int8.onnx",
            "vocoder.int8.onnx",
            "tts.json",
            "unicode_indexer.bin",
            "voice.bin"
        ]
        for file in requiredFiles {
            if !fm.fileExists(atPath: modelDir.appendingPathComponent(file).path) {
                return nil
            }
        }
        return (rtRoot, modelDir, VoiceModelCatalog.supertonic3Int8ModelID)
    }

    public static func normalizeForSupertonic(_ text: String, langTag: String) -> String {
        var out = text.replacingOccurrences(of: "…", with: ", ")
            .replacingOccurrences(of: "...", with: ", ")
            .replacingOccurrences(of: "—", with: ", ")
            .replacingOccurrences(of: "–", with: ", ")
        if langTag == "pt" {
            if let rx = try? NSRegularExpression(pattern: "\\bh+m+\\b", options: [.caseInsensitive]) {
                let range = NSRange(out.startIndex..<out.endIndex, in: out)
                out = rx.stringByReplacingMatches(in: out, range: range, withTemplate: "Hum")
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func resolvePreset(voicePreference: String) -> SupertonicVoicePreset {
        let cleaned = voicePreference.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let exact = SupertonicVoicePreset.from(identifier: cleaned) {
            return exact
        }
        if cleaned.hasPrefix("persona:") {
            let rawPersona = String(cleaned.dropFirst("persona:".count))
            if let persona = WisdVoicePersona(rawValue: rawPersona) {
                return SupertonicVoicePreset.defaultPreset(for: persona)
            }
        }
        if cleaned.contains("jarvis") { return .m4 }
        if cleaned.contains("ultron") || cleaned.contains("atlas") || cleaned.contains("pm_santa") || cleaned.contains("bm_lewis") { return .m5 }
        if cleaned.contains("pm_alex") || cleaned.contains("bm_") || cleaned.contains("am_") || cleaned.contains("male") || cleaned.contains("homem") {
            return .m4
        }
        if cleaned.contains("aria") { return .f4 }
        return .f1
    }

    public func preload() async throws -> KokoroEngineDiagnosticsSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            synthQueue.async {
                do {
                    _ = try self.ensureLoadedSync()
                    continuation.resume(returning: self.currentDiagnostics())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func ensureLoadedSync() throws -> LoadedSupertonicHandles {
        if let existing = stateLock.withLock({ loaded }) {
            scheduleIdleUnload()
            return existing
        }
        guard let paths = resolveInstalledPaths() else {
            throw VoiceGatewayError.protocolError("Pesos Supertonic-3 ou runtime sherpa-onnx não instalados em Application Support.")
        }
        let t0 = DispatchTime.now().uptimeNanoseconds
        let fns = try SherpaDynamicBridge.open(runtimeDir: paths.runtimeDir)
        let arena = CStringArena()
        var config = SherpaOfflineTtsConfigC()
        config.model.num_threads = 4
        config.model.debug = 0
        config.model.provider = arena.cString("cpu")
        config.model.supertonic.duration_predictor = arena.cString(paths.modelDir.appendingPathComponent("duration_predictor.int8.onnx").path)
        config.model.supertonic.text_encoder = arena.cString(paths.modelDir.appendingPathComponent("text_encoder.int8.onnx").path)
        config.model.supertonic.vector_estimator = arena.cString(paths.modelDir.appendingPathComponent("vector_estimator.int8.onnx").path)
        config.model.supertonic.vocoder = arena.cString(paths.modelDir.appendingPathComponent("vocoder.int8.onnx").path)
        config.model.supertonic.tts_json = arena.cString(paths.modelDir.appendingPathComponent("tts.json").path)
        config.model.supertonic.unicode_indexer = arena.cString(paths.modelDir.appendingPathComponent("unicode_indexer.bin").path)
        config.model.supertonic.voice_style = arena.cString(paths.modelDir.appendingPathComponent("voice.bin").path)
        config.max_num_sentences = 1
        config.silence_scale = 0.2

        let ttsPtr = withUnsafePointer(to: &config) { fns.createTts($0) }
        guard let ttsPtr else {
            throw VoiceGatewayError.protocolError("SherpaOnnxCreateOfflineTts retornou NULL para Supertonic-3.")
        }
        let sr = Int(fns.sampleRateFn(ttsPtr))
        let spk = Int(fns.numSpeakersFn(ttsPtr))
        let loadMs = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000.0
        let h = LoadedSupertonicHandles(
            fns: fns,
            ttsPointer: ttsPtr,
            modelID: paths.modelID,
            sampleRate: sr > 0 ? sr : 44_100,
            numSpeakers: spk
        )
        stateLock.withLock {
            loaded = h
            diagnosticsSnapshot = KokoroEngineDiagnosticsSnapshot(
                isLoaded: true,
                activeModelID: paths.modelID,
                loadedLangCode: "multilang(31)",
                loadLatencyMs: loadMs,
                lastSynthesisMs: diagnosticsSnapshot.lastSynthesisMs,
                sampleRateHz: h.sampleRate,
                numSpeakers: spk,
                lastError: nil
            )
        }
        scheduleIdleUnload()
        return h
    }

    public func unload() {
        synthQueue.async { [weak self] in self?.unloadSync() }
    }

    public func unloadSynchronously() {
        synthQueue.sync { self.unloadSync() }
    }

    private func unloadSync() {
        lastIdleUnloadWorkItem?.cancel()
        lastIdleUnloadWorkItem = nil
        let old = stateLock.withLock { () -> LoadedSupertonicHandles? in
            let cur = loaded
            loaded = nil
            diagnosticsSnapshot.isLoaded = false
            return cur
        }
        if let old { old.fns.destroyTts(old.ttsPointer) }
    }

    private func scheduleIdleUnload() {
        lastIdleUnloadWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.unloadSync() }
        lastIdleUnloadWorkItem = work
        synthQueue.asyncAfter(deadline: .now() + 240.0, execute: work)
    }

    public func synthesizeChunk(
        _ text: String,
        language: VoiceLanguageVariant,
        voicePreference: String,
        rate: Float,
        onAudioFloats24k: @escaping @Sendable ([Float], String) -> Void
    ) async throws {
        let steps = stateLock.withLock { defaultFlowSteps }
        try await synthesizeChunk(
            text,
            language: language,
            voicePreference: voicePreference,
            rate: rate,
            silenceScale: 0.20,
            flowSteps: steps,
            targetSampleRate: 24_000,
            onAudioFloats: onAudioFloats24k
        )
    }

    public func synthesizeChunk(
        _ text: String,
        language: VoiceLanguageVariant,
        voicePreference: String,
        rate: Float,
        silenceScale: Float,
        flowSteps: Int,
        targetSampleRate: Int = 24_000,
        onAudioFloats: @escaping @Sendable ([Float], String) -> Void
    ) async throws {
        let preset = Self.resolvePreset(voicePreference: voicePreference)
        let langTag = preset.supertonicLangCode(for: language)
        let clean = Self.normalizeForSupertonic(
            text.trimmingCharacters(in: .whitespacesAndNewlines),
            langTag: langTag
        )
        guard !clean.isEmpty else { return }
        let startEpoch = stateLock.withLock { cancelledEpoch }
        let clampedSteps = Int32(min(12, max(4, flowSteps)))

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            synthQueue.async { [weak self] in
                guard let self else { continuation.resume(); return }
                do {
                    guard !Task.isCancelled, self.stateLock.withLock({ self.cancelledEpoch == startEpoch }) else {
                        continuation.resume()
                        return
                    }
                    let handles = try self.ensureLoadedSync()
                    let t0 = DispatchTime.now().uptimeNanoseconds

                    let arena = CStringArena()
                    guard let cText = arena.cString(clean),
                          let cExtra = arena.cString("{\"lang\":\"\(langTag)\"}") else {
                        throw VoiceGatewayError.protocolError("Falha ao alocar parâmetros UTF-8 do Supertonic-3.")
                    }

                    var genCfg = SherpaGenerationConfigC()
                    genCfg.silence_scale = min(0.60, max(0.10, silenceScale))
                    genCfg.speed = min(1.30, max(0.75, rate))
                    genCfg.sid = preset.speakerID
                    genCfg.num_steps = clampedSteps
                    genCfg.extra = cExtra

                    final class SupertonicLabelState: @unchecked Sendable {
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
                    let labelState = SupertonicLabelState(text: clean)
                    let streamResampler = (handles.sampleRate != targetSampleRate)
                        ? StreamingSincResampler(fromSampleRate: Double(handles.sampleRate), toSampleRate: Double(targetSampleRate))
                        : nil
                    let ctx = KokoroGenerationContext(
                        sampleRate: handles.sampleRate,
                        cancelCheck: { self.stateLock.withLock { self.cancelledEpoch != startEpoch } },
                        chunkHandler: { rawSamples, _ in
                            let converted = streamResampler?.process(rawSamples, isFinal: false) ?? rawSamples
                            guard !converted.isEmpty else { return }
                            onAudioFloats(converted, labelState.claimLabel())
                        }
                    )

                    let audioPtr = withUnsafePointer(to: &genCfg) { cfgPtr in
                        handles.fns.genWithCfgFn(
                            handles.ttsPointer,
                            cText,
                            cfgPtr,
                            kokoroProgressTrampoline,
                            Unmanaged.passUnretained(ctx).toOpaque()
                        )
                    }
                    if let audioPtr {
                        defer { handles.fns.destroyAudioFn(audioPtr) }
                        let cancelled = self.stateLock.withLock { self.cancelledEpoch != startEpoch }
                        if !cancelled {
                            if ctx.streamedSamplesCount == 0 {
                                let audio = audioPtr.assumingMemoryBound(to: SherpaGeneratedAudioC.self).pointee
                                if audio.n > 0, let ptr = audio.samples {
                                    let raw = Array(UnsafeBufferPointer(start: ptr, count: Int(audio.n)))
                                    let sr = audio.sample_rate > 0 ? Int(audio.sample_rate) : handles.sampleRate
                                    let out: [Float]
                                    if sr != targetSampleRate {
                                        let singleResampler = StreamingSincResampler(fromSampleRate: Double(sr), toSampleRate: Double(targetSampleRate))
                                        out = singleResampler.process(raw, isFinal: true)
                                    } else {
                                        out = raw
                                    }
                                    if !out.isEmpty { onAudioFloats(out, clean) }
                                }
                            } else if let streamResampler {
                                // Flush final Blackman-sinc history tail cleanly without chunk discontinuities
                                let tail = streamResampler.process([], isFinal: true)
                                if !tail.isEmpty { onAudioFloats(tail, "") }
                            }
                        }
                    }

                    let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000.0
                    let execInfo = NeuralSynthesisExecutionInfo(
                        engineID: self.providerID,
                        modelID: handles.modelID,
                        speakerID: preset.rawValue,
                        numericSID: preset.speakerID,
                        langCode: langTag,
                        sampleRateHz: targetSampleRate,
                        synthMs: elapsedMs
                    )
                    self.stateLock.withLock {
                        self.diagnosticsSnapshot.lastSynthesisMs = elapsedMs
                        self.diagnosticsSnapshot.loadedLangCode = langTag
                        self.diagnosticsSnapshot.lastError = nil
                        self.lastExecutionInfoSnapshot = execInfo
                    }
                    self.scheduleIdleUnload()
                    continuation.resume()
                } catch {
                    self.stateLock.withLock { self.diagnosticsSnapshot.lastError = error.localizedDescription }
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func synthesizeStandaloneSamples(
        text: String,
        language: VoiceLanguageVariant,
        preset: SupertonicVoicePreset,
        rate: Float = 0.98,
        flowSteps: Int = 8,
        silenceScale: Float = 0.20,
        targetSampleRate: Int = 44_100
    ) async throws -> (samples: [Float], sampleRate: Int, synthMs: Double) {
        final class Box: @unchecked Sendable {
            private let lock = NSLock()
            private var samples: [Float] = []
            func append(_ c: [Float]) { lock.withLock { samples.append(contentsOf: c) } }
            func snap() -> [Float] { lock.withLock { samples } }
        }
        let box = Box()
        let t0 = DispatchTime.now().uptimeNanoseconds
        try await synthesizeChunk(
            text,
            language: language,
            voicePreference: preset.rawValue,
            rate: rate,
            silenceScale: silenceScale,
            flowSteps: flowSteps,
            targetSampleRate: targetSampleRate
        ) { floats, _ in
            box.append(floats)
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000.0
        return (box.snap(), targetSampleRate, elapsed)
    }

    public func cancelAll() {
        stateLock.withLock { cancelledEpoch &+= 1 }
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
    nonisolated(unsafe) private var activePIDForDeinit: pid_t = 0
    private var activePort: UInt16 = 0
    private var idleUnloadTask: Task<Void, Never>?
    private let assetManager: VoiceModelAssetManager

    public init(assetManager: VoiceModelAssetManager) {
        self.assetManager = assetManager
    }

    deinit {
        if activePIDForDeinit > 0 {
            kill(activePIDForDeinit, SIGTERM)
        }
    }

    public var currentProcessID: pid_t? {
        guard let proc = process, proc.isRunning else { return nil }
        return proc.processIdentifier
    }

    nonisolated public static func isStrictLoopbackURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased() else {
            return false
        }
        return host == "127.0.0.1" || host == "::1"
    }

    public static func sanitizedSubprocessEnvironment(dyldLibraryPath: String, baseEnv: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var clean: [String: String] = [
            "PATH": baseEnv["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin",
            "DYLD_LIBRARY_PATH": dyldLibraryPath
        ]
        for key in ["HOME", "TMPDIR", "USER", "LOGNAME", "LANG", "LC_ALL"] {
            if let val = baseEnv[key], !val.isEmpty {
                clean[key] = val
            }
        }
        return clean
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
        var serverArgs = [
            "-m", resolved.ggufURL.path,
            "--host", "127.0.0.1",
            "--port", "\(port)",
            "-ngl", "99",
            "--ctx-size", ctxSize,
            "--threads", threads,
            "--no-webui"
        ]
        if resolved.descriptor.id.contains("qwen3") {
            serverArgs.append(contentsOf: ["--reasoning", "off", "--reasoning-budget", "0"])
        }
        proc.arguments = serverArgs
        proc.environment = Self.sanitizedSubprocessEnvironment(dyldLibraryPath: resolved.binDir.path)
        let errPipe = Pipe()
        proc.standardError = errPipe
        proc.standardOutput = FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            isLoadingModel = false
            lastError = error.localizedDescription
            assetManager.setRuntimeActivity(modelID: resolved.descriptor.id, state: .error, error: error.localizedDescription)
            throw error
        }

        self.process = proc
        self.activePIDForDeinit = proc.processIdentifier
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
        if let proc = process {
            let pid = proc.processIdentifier
            if proc.isRunning {
                proc.terminate()
                let deadline = DispatchTime.now().uptimeNanoseconds + 350_000_000
                while proc.isRunning && DispatchTime.now().uptimeNanoseconds < deadline {
                    usleep(20_000)
                }
                if proc.isRunning && pid > 0 {
                    kill(pid, SIGKILL)
                    proc.waitUntilExit()
                }
            }
        }
        activePIDForDeinit = 0
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
        guard let url = URL(string: "http://127.0.0.1:\(port)/health"),
              Self.isStrictLoopbackURL(url) else { return false }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.connectionProxyDictionary = [:]
        cfg.httpCookieStorage = nil
        cfg.urlCredentialStorage = nil
        cfg.urlCache = nil
        let session = URLSession(configuration: cfg)
        defer { session.invalidateAndCancel() }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.0
        do {
            let (_, resp) = try await session.data(for: req)
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
              let url = URL(string: "http://127.0.0.1:\(port)/v1/models"),
              LocalLlamaServerBrainRuntime.isStrictLoopbackURL(url) else {
            isServerReachable = false
            lastError = "Porta MLX inválida."
            return false
        }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.connectionProxyDictionary = [:]
        cfg.httpCookieStorage = nil
        cfg.urlCredentialStorage = nil
        cfg.urlCache = nil
        let session = URLSession(configuration: cfg)
        defer { session.invalidateAndCancel() }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.5
        do {
            let (data, resp) = try await session.data(for: req)
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
        guard LocalLlamaServerBrainRuntime.isStrictLoopbackURL(endpointURL) else {
            throw VoiceGatewayError.protocolError("Bloqueio de segurança: endpoint local deve estar estritamente em loopback 127.0.0.1 / ::1.")
        }
        var req = URLRequest(url: endpointURL)
        req.httpMethod = "POST"
        req.timeoutInterval = timeoutSeconds
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let bodyObj: [String: Any] = [
            "model": modelName,
            "messages": messages,
            "stream": true,
            "temperature": 0.5,
            "top_p": 0.9,
            "max_tokens": 440
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: bodyObj)

        let cfg = URLSessionConfiguration.ephemeral
        cfg.connectionProxyDictionary = [:]
        cfg.httpCookieStorage = nil
        cfg.urlCredentialStorage = nil
        cfg.urlCache = nil
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

// MARK: - Section 10: Real Alternative VITS/Piper Local C-ABI Engine & Expressive MLX-Audio Loopback Client

public final class SherpaVitsPiperTTSProvider: StreamingTextToSpeechProvider, @unchecked Sendable {
    public let providerID = "sherpa_vits_piper_local_onnx"
    public let requiresPaidOptIn = false

    private struct LoadedVitsHandles {
        let ortHandle: UnsafeMutableRawPointer?
        let sherpaHandle: UnsafeMutableRawPointer
        let destroyTts: FnDestroyOfflineTts
        let sampleRateFn: FnOfflineTtsSampleRate
        let generateWithConfigFn: FnOfflineTtsGenerateWithConfig
        let destroyAudioFn: FnDestroyGeneratedAudio
        let ttsPointer: OpaquePointer
        let modelID: String
        let sampleRate: Int
    }

    private let queue = DispatchQueue(label: "local.wisdai.voice.pipervits", qos: .userInitiated)
    private let lock = NSLock()
    private var loaded: LoadedVitsHandles?
    private var cancelledEpoch: UInt64 = 0
    private let appSupportVoiceRoot: URL

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        self.appSupportVoiceRoot = appSupport.appendingPathComponent("WisdAI/Voice", isDirectory: true)
    }

    deinit {
        let old = lock.withLock { () -> LoadedVitsHandles? in
            let current = loaded
            loaded = nil
            return current
        }
        if let old {
            queue.async {
                old.destroyTts(old.ttsPointer)
            }
        }
    }

    public func resolveModelPaths(for language: VoiceLanguageVariant) -> (runtimeDir: URL, modelDir: URL, onnxFile: URL, tokensFile: URL, espeakDir: URL, modelID: String)? {
        let fm = FileManager.default
        let rtDir = appSupportVoiceRoot
            .appendingPathComponent("Runtimes/\(VoiceModelCatalog.sherpaRuntimeID)/sherpa-onnx-v1.13.8-osx-arm64-shared-lib/lib", isDirectory: true)
        guard fm.fileExists(atPath: rtDir.appendingPathComponent("libsherpa-onnx-c-api.dylib").path) else {
            return nil
        }

        let dirNames: [String] = {
            switch language {
            case .portuguesePT:
                return ["vits-piper-pt_PT-tugao-medium", "vits-piper-pt_PT-dii-high", "vits-piper-pt_PT-miro-high"]
            case .portugueseBR:
                return ["vits-piper-pt_BR-faber-medium", "vits-piper-pt_BR-cadu-medium", "vits-piper-pt_BR-edresson-low"]
            case .englishGB:
                return ["vits-piper-en_GB-alan-medium", "vits-piper-en_GB-southern_english_male-medium", "vits-piper-en_GB-cori-medium"]
            case .englishUS:
                return ["vits-piper-en_US-lessac-medium", "vits-piper-en_US-amy-medium"]
            case .spanishES:
                return ["vits-piper-es_ES-davefx-medium"]
            }
        }()

        let modelsBase = appSupportVoiceRoot.appendingPathComponent("Models", isDirectory: true)
        for name in dirNames {
            let folder = modelsBase.appendingPathComponent(name, isDirectory: true)
            guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { continue }
            let searchDir: URL = {
                if items.contains(where: { $0.pathExtension == "onnx" }) { return folder }
                if let nested = items.first(where: { $0.hasDirectoryPath }) { return nested }
                return folder
            }()
            guard let inner = try? fm.contentsOfDirectory(at: searchDir, includingPropertiesForKeys: nil),
                  let onnx = inner.first(where: { $0.pathExtension == "onnx" }),
                  let tokens = inner.first(where: { $0.lastPathComponent == "tokens.txt" }) else {
                continue
            }
            let espeak = inner.first(where: { $0.lastPathComponent == "espeak-ng-data" }) ?? searchDir.appendingPathComponent("espeak-ng-data")
            guard fm.fileExists(atPath: espeak.path) else { continue }
            return (rtDir, searchDir, onnx, tokens, espeak, name)
        }
        return nil
    }

    public func isReadyOnDisk(for language: VoiceLanguageVariant = .portugueseBR) -> Bool {
        resolveModelPaths(for: language) != nil
    }

    public func synthesizeChunk(
        _ text: String,
        language: VoiceLanguageVariant,
        voicePreference: String,
        rate: Float,
        onAudioFloats24k: @escaping @Sendable ([Float], String) -> Void
    ) async throws {
        try await synthesizeChunk(
            text,
            language: language,
            voicePreference: voicePreference,
            rate: rate,
            silenceScale: 0.20,
            onAudioFloats24k: onAudioFloats24k
        )
    }

    public func synthesizeChunk(
        _ text: String,
        language: VoiceLanguageVariant,
        voicePreference: String,
        rate: Float,
        silenceScale: Float,
        onAudioFloats24k: @escaping @Sendable ([Float], String) -> Void
    ) async throws {
        let clean = KokoroNeuralTTSProvider.normalizeForEspeakG2P(
            text.trimmingCharacters(in: .whitespacesAndNewlines),
            langCode: language.rawValue.lowercased()
        )
        guard !clean.isEmpty else { return }
        let startEpoch = lock.withLock { cancelledEpoch }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self else { continuation.resume(); return }
                do {
                    guard !Task.isCancelled, self.lock.withLock({ self.cancelledEpoch == startEpoch }) else {
                        continuation.resume()
                        return
                    }
                    let handles = try self.ensureLoadedSync(language: language)
                    var genCfg = SherpaGenerationConfigC()
                    genCfg.silence_scale = min(0.60, max(0.10, silenceScale))
                    genCfg.speed = min(1.35, max(0.70, rate))
                    genCfg.sid = 0

                    let arena = CStringArena()
                    guard let cText = arena.cString(clean) else {
                        throw VoiceGatewayError.protocolError("Falha ao alocar texto UTF-8 para Piper VITS.")
                    }
                    let audioPtr = withUnsafePointer(to: &genCfg) { cfgPtr in
                        handles.generateWithConfigFn(handles.ttsPointer, cText, cfgPtr, nil, nil)
                    }
                    if let audioPtr {
                        defer { handles.destroyAudioFn(audioPtr) }
                        if !self.lock.withLock({ self.cancelledEpoch != startEpoch }) {
                            let audio = audioPtr.assumingMemoryBound(to: SherpaGeneratedAudioC.self).pointee
                            if audio.n > 0, let ptr = audio.samples {
                                let raw = Array(UnsafeBufferPointer(start: ptr, count: Int(audio.n)))
                                let sr = audio.sample_rate > 0 ? Double(audio.sample_rate) : Double(handles.sampleRate)
                                let out24k = abs(sr - 24_000) < 1.0 ? raw : AudioPCMConverter.resampleLinear(samples: raw, fromSampleRate: sr, toSampleRate: 24_000)
                                if !out24k.isEmpty {
                                    onAudioFloats24k(out24k, clean)
                                }
                            }
                        }
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func ensureLoadedSync(language: VoiceLanguageVariant) throws -> LoadedVitsHandles {
        guard let paths = resolveModelPaths(for: language) else {
            throw VoiceGatewayError.protocolError("Pesos Piper VITS para \(language.displayName) não encontrados em Models/vits-piper-*. Utilize Kokoro-82M ou Apple Natural.")
        }
        if let existing = lock.withLock({ loaded }), existing.modelID == paths.modelID {
            return existing
        }
        unloadSync()

        let fm = FileManager.default
        let libs = (try? fm.contentsOfDirectory(at: paths.runtimeDir, includingPropertiesForKeys: nil)) ?? []
        var ortHandle: UnsafeMutableRawPointer? = nil
        if let ortURL = libs.first(where: { $0.lastPathComponent.hasPrefix("libonnxruntime") && $0.pathExtension == "dylib" }) {
            ortHandle = dlopen(ortURL.path, RTLD_NOW | RTLD_GLOBAL | RTLD_NODELETE)
        }
        let sherpaURL = paths.runtimeDir.appendingPathComponent("libsherpa-onnx-c-api.dylib")
        guard let sherpaHandle = dlopen(sherpaURL.path, RTLD_NOW | RTLD_LOCAL | RTLD_NODELETE) else {
            throw VoiceGatewayError.protocolError("Falha ao abrir libsherpa-onnx-c-api.dylib para Piper VITS.")
        }
        func sym<T>(_ name: String) throws -> T {
            guard let p = dlsym(sherpaHandle, name) else {
                throw VoiceGatewayError.protocolError("Símbolo C ausente: \(name)")
            }
            return unsafeBitCast(p, to: T.self)
        }

        let createFn: FnCreateOfflineTts = try sym("SherpaOnnxCreateOfflineTts")
        let destroyFn: FnDestroyOfflineTts = try sym("SherpaOnnxDestroyOfflineTts")
        let srFn: FnOfflineTtsSampleRate = try sym("SherpaOnnxOfflineTtsSampleRate")
        let genFn: FnOfflineTtsGenerateWithConfig = try sym("SherpaOnnxOfflineTtsGenerateWithConfig")
        let destroyAudioFn: FnDestroyGeneratedAudio = try sym("SherpaOnnxDestroyOfflineTtsGeneratedAudio")

        let arena = CStringArena()
        var cfg = SherpaOfflineTtsConfigC()
        cfg.model.num_threads = 2
        cfg.model.debug = 0
        cfg.model.provider = arena.cString("cpu")
        cfg.model.vits.model = arena.cString(paths.onnxFile.path)
        cfg.model.vits.tokens = arena.cString(paths.tokensFile.path)
        cfg.model.vits.data_dir = arena.cString(paths.espeakDir.path)
        cfg.model.vits.length_scale = 1.0
        cfg.max_num_sentences = 1
        cfg.silence_scale = 0.2

        guard let ttsPtr = withUnsafePointer(to: &cfg, { createFn($0) }) else {
            throw VoiceGatewayError.protocolError("SherpaOnnxCreateOfflineTts recusou modelo Piper VITS (\(paths.modelID)).")
        }
        let sr = Int(srFn(ttsPtr))
        let h = LoadedVitsHandles(
            ortHandle: ortHandle,
            sherpaHandle: sherpaHandle,
            destroyTts: destroyFn,
            sampleRateFn: srFn,
            generateWithConfigFn: genFn,
            destroyAudioFn: destroyAudioFn,
            ttsPointer: ttsPtr,
            modelID: paths.modelID,
            sampleRate: sr > 0 ? sr : 22_050
        )
        lock.withLock { loaded = h }
        return h
    }

    private func unloadSync() {
        let old = lock.withLock { () -> LoadedVitsHandles? in
            let cur = loaded
            loaded = nil
            return cur
        }
        if let old { old.destroyTts(old.ttsPointer) }
    }

    public func cancelAll() {
        lock.withLock { cancelledEpoch &+= 1 }
    }
}

/// Real local loopback adapter (`http://127.0.0.1:<port>/v1/audio/speech`) for user-started `mlx-audio`
/// servers hosting expressive models such as Chatterbox Multilingual MLX Q4, CosyVoice2/3, or Dia.
@MainActor
public final class LocalExpressiveTTSLoopbackClient: ObservableObject, StreamingTextToSpeechProvider, @unchecked Sendable {
    public let providerID = "local_mlx_audio_loopback_tts"
    public let requiresPaidOptIn = false

    @Published public var port: Int = UserDefaults.standard.integer(forKey: "wisdai.voice.mlxTTSPort") == 0
        ? 8000
        : UserDefaults.standard.integer(forKey: "wisdai.voice.mlxTTSPort") {
        didSet {
            UserDefaults.standard.set(port, forKey: "wisdai.voice.mlxTTSPort")
            configLock.withLock { runtimePort = port }
        }
    }
    @Published public private(set) var isServerReachable: Bool = false
    @Published public private(set) var activeModelName: String = "Não detectado em 127.0.0.1" {
        didSet {
            configLock.withLock { runtimeModelName = activeModelName }
        }
    }
    @Published public private(set) var lastError: String?

    private let configLock = NSLock()
    nonisolated(unsafe) private var runtimePort: Int
    nonisolated(unsafe) private var runtimeModelName: String = "Não detectado em 127.0.0.1"

    public init() {
        let initialPort = UserDefaults.standard.integer(forKey: "wisdai.voice.mlxTTSPort")
        self.runtimePort = initialPort == 0 ? 8000 : initialPort
    }

    public func probeServer() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/v1/models"),
              LocalLlamaServerBrainRuntime.isStrictLoopbackURL(url) else {
            isServerReachable = false
            lastError = "Porta/URL loopback inválida."
            return false
        }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.connectionProxyDictionary = [:]
        cfg.httpCookieStorage = nil
        cfg.urlCredentialStorage = nil
        cfg.urlCache = nil
        let session = URLSession(configuration: cfg)
        defer { session.invalidateAndCancel() }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.2
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                isServerReachable = false
                lastError = "Servidor mlx-audio HTTP \(code)."
                return false
            }
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let list = obj["data"] as? [[String: Any]],
               let firstID = list.first?["id"] as? String {
                activeModelName = firstID
            } else {
                activeModelName = "mlx-audio@127.0.0.1:\(port)"
            }
            isServerReachable = true
            lastError = nil
            return true
        } catch {
            isServerReachable = false
            activeModelName = "Não detectado em 127.0.0.1:\(port)"
            lastError = "Nenhum servidor mlx-audio ativo na porta \(port)."
            return false
        }
    }

    nonisolated public func synthesizeChunk(
        _ text: String,
        language: VoiceLanguageVariant,
        voicePreference: String,
        rate: Float,
        onAudioFloats24k: @escaping @Sendable ([Float], String) -> Void
    ) async throws {
        let (targetPort, targetModel) = configLock.withLock { (runtimePort, runtimeModelName) }
        guard let url = URL(string: "http://127.0.0.1:\(targetPort)/v1/audio/speech"),
              LocalLlamaServerBrainRuntime.isStrictLoopbackURL(url) else {
            throw VoiceGatewayError.protocolError("Bloqueio de segurança: servidor TTS local deve estar estritamente em 127.0.0.1.")
        }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = [
            "model": targetModel,
            "input": clean,
            "voice": voicePreference,
            "speed": min(1.30, max(0.75, Double(rate))),
            "stream": true,
            "response_format": "pcm",
            "lang_code": language.bcp47LanguagePrefix
        ]
        if voicePreference.lowercased().contains("ultron") {
            payload["instructions"] = "Mature Brazilian Portuguese male AI voice, deep resonant baritone, calm theatrical elegance, crisp diction, intelligent and subtly ironic."
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let cfg = URLSessionConfiguration.ephemeral
        cfg.connectionProxyDictionary = [:]
        cfg.httpCookieStorage = nil
        cfg.urlCredentialStorage = nil
        cfg.urlCache = nil
        let session = URLSession(configuration: cfg)
        defer { session.invalidateAndCancel() }

        let (bytes, response) = try await session.bytes(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw VoiceGatewayError.protocolError("Servidor TTS loopback retornou HTTP \(code).")
        }

        var pending = Data()
        var labelled = false
        for try await b in bytes {
            if Task.isCancelled { break }
            pending.append(b)
            if pending.count >= 4_800 {
                let evenCount = pending.count - (pending.count % 2)
                let floats = AudioPCMConverter.pcm16DataToFloats(pending.prefix(evenCount))
                pending.removeFirst(evenCount)
                if !floats.isEmpty {
                    onAudioFloats24k(floats, labelled ? "" : clean)
                    labelled = true
                }
            }
        }
        let tailEven = pending.count - (pending.count % 2)
        if tailEven > 0 && !Task.isCancelled {
            let floats = AudioPCMConverter.pcm16DataToFloats(pending.prefix(tailEven))
            if !floats.isEmpty {
                onAudioFloats24k(floats, labelled ? "" : clean)
            }
        }
    }

    nonisolated public func cancelAll() {
        // Cooperative async Task cancellation terminates the loopback HTTP stream immediately.
    }
}

// MARK: - Section 11: Honest Local Speech-to-Speech Abstraction & Loopback Transport

public final class LocalMultimodalS2SLoopbackTransport: RealtimeSpeechToSpeechTransport, @unchecked Sendable {
    public let providerID: String
    public let inputSampleRateHz: Double = 24_000
    public let outputSampleRateHz: Double = 24_000

    private let endpointURL: URL
    private let lock = NSLock()
    private var session: URLSession?
    private var wsTask: URLSessionWebSocketTask?
    private var rxTask: Task<Void, Never>?
    private var onEventCB: (@Sendable (RealtimeGatewayEvent) -> Void)?

    public init(port: Int = 8998, providerID: String = "local_s2s_loopback") {
        self.providerID = providerID
        self.endpointURL = URL(string: "ws://127.0.0.1:\(port)/api/chat")!
    }

    public func connect(config: VoiceSessionConfig, resumptionHandle: String?, onEvent: @escaping @Sendable (RealtimeGatewayEvent) -> Void) async throws {
        guard endpointURL.host == "127.0.0.1" || endpointURL.host == "::1" else {
            throw VoiceGatewayError.protocolError("Bloqueio de segurança: Speech-to-Speech local aceita apenas loopback.")
        }
        await disconnect()
        let cfg = URLSessionConfiguration.ephemeral
        cfg.connectionProxyDictionary = [:]
        cfg.httpCookieStorage = nil
        cfg.urlCredentialStorage = nil
        let urlSession = URLSession(configuration: cfg)
        var req = URLRequest(url: endpointURL)
        req.timeoutInterval = 3.0

        let task = urlSession.webSocketTask(with: req)
        lock.withLock {
            self.session = urlSession
            self.wsTask = task
            self.onEventCB = onEvent
        }
        task.resume()

        // Verify live WebSocket handshake instead of assuming daemon presence.
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            task.sendPing { err in
                if let err {
                    cont.resume(throwing: VoiceGatewayError.networkConnectionFailed("Servidor Speech-to-Speech local offline em \(self.endpointURL.absoluteString): \(err.localizedDescription)"))
                } else {
                    cont.resume()
                }
            }
        }
        onEvent(.sessionReady(sessionId: "local-s2s-\(UUID().uuidString.prefix(8))"))

        rxTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let msg = try await task.receive()
                    guard let self else { break }
                    let cb = self.lock.withLock { self.onEventCB }
                    switch msg {
                    case .data(let rawPCM):
                        if !rawPCM.isEmpty {
                            cb?(.assistantAudioDelta(itemId: "s2s", pcm16: rawPCM, sampleRate: 24_000))
                        }
                    case .string(let txt):
                        if let data = txt.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let kind = json["type"] as? String {
                            if kind == "transcript_delta", let delta = json["text"] as? String {
                                cb?(.assistantTranscriptDelta(itemId: "s2s", text: delta))
                            } else if kind == "turn_done" {
                                cb?(.assistantTurnCompleted(itemId: "s2s", finalText: json["text"] as? String ?? ""))
                            }
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    self?.lock.withLock { self?.onEventCB }?(.disconnected(reason: error.localizedDescription))
                    break
                }
            }
        }
    }

    public func sendAudioPCM16(_ pcm16Data: Data) async {
        let task = lock.withLock { wsTask }
        try? await task?.send(.data(pcm16Data))
    }

    public func commitInputAudio() async {
        let task = lock.withLock { wsTask }
        try? await task?.send(.string("{\"type\":\"commit\"}"))
    }

    public func triggerResponse(promptText: String?) async {}
    public func injectContextUpdate(_ text: String, triggerReply: Bool) async {}
    public func cancelActiveResponse() async {
        let task = lock.withLock { wsTask }
        try? await task?.send(.string("{\"type\":\"cancel\"}"))
    }
    public func truncateAssistantItem(itemId: String, audioEndMs: Int) async {}

    public func disconnect() async {
        let (task, sess, rx) = lock.withLock { () -> (URLSessionWebSocketTask?, URLSession?, Task<Void, Never>?) in
            let t = wsTask; let s = session; let r = rxTask
            wsTask = nil; session = nil; rxTask = nil; onEventCB = nil
            return (t, s, r)
        }
        rx?.cancel()
        task?.cancel(with: .normalClosure, reason: nil)
        sess?.invalidateAndCancel()
    }
}

public struct NativeS2SReadinessSnapshot: Equatable, Sendable {
    public let isSupportedOnThisMac: Bool
    public let recommendedProfileName: String
    public let blockerReason: String?
    public let inspectedModules: [String]
}

public enum NativeS2SRuntimeProbe {
    public static func evaluate(hardwareTier: VoiceHardwareTier, liveS2SLoopbackReachable: Bool = false) -> NativeS2SReadinessSnapshot {
        let ramGB = hardwareTier.resolvedRAMGB()
        if ramGB < 14.0 {
            return NativeS2SReadinessSnapshot(
                isSupportedOnThisMac: false,
                recommendedProfileName: hardwareTier.displayName,
                blockerReason: String(format: "Memória RAM efetiva (~%.0f GB) insuficiente para S2S nativo em execução simultânea (Moshi MLX Q4 requer ~5–8 GB livres + sistema e idioma principal em inglês; MiniCPM-o/PersonaPlex requerem 24–32+ GB). Modo Híbrido Neural V3 ativo.", ramGB),
                inspectedModules: []
            )
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidateBins = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "\(home)/.local/bin/moshi_mlx",
            "\(home)/.venv/bin/python3"
        ]
        let found = candidateBins.filter { FileManager.default.isExecutableFile(atPath: $0) }
        if liveS2SLoopbackReachable {
            return NativeS2SReadinessSnapshot(
                isSupportedOnThisMac: true,
                recommendedProfileName: hardwareTier.displayName,
                blockerReason: nil,
                inspectedModules: found
            )
        }
        return NativeS2SReadinessSnapshot(
            isSupportedOnThisMac: false,
            recommendedProfileName: hardwareTier.displayName,
            blockerReason: found.isEmpty
                ? "Nenhum servidor Speech-to-Speech local respondendo em loopback (127.0.0.1:8998) nem runtime moshi_mlx/MiniCPM-o instalado. Modo Híbrido Neural ativo."
                : "Ambiente Python detectado (\(found.joined(separator: ", "))), porém o servidor Speech-to-Speech local (127.0.0.1:8998) não respondeu ao handshake ao vivo.",
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

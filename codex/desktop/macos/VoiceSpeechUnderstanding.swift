import AVFoundation
import Foundation
import Speech

// MARK: - Bounded Authorization Guard (Eliminates Infinite "Conectando voz" Hangs)

public enum BoundedVoicePermissions {
    public static func requestMicrophoneAuthorized(timeoutSeconds: Double = 2.0) async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await raceTimeout(seconds: timeoutSeconds, defaultValue: false) {
                await AVCaptureDevice.requestAccess(for: .audio)
            }
        @unknown default:
            return false
        }
    }

    public static func requestSpeechRecognizerAuthorized(timeoutSeconds: Double = 2.0) async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await raceTimeout(seconds: timeoutSeconds, defaultValue: false) {
                await withCheckedContinuation { continuation in
                    SFSpeechRecognizer.requestAuthorization { newStatus in
                        continuation.resume(returning: newStatus == .authorized)
                    }
                }
            }
        @unknown default:
            return false
        }
    }

    private static func raceTimeout<T: Sendable>(
        seconds: Double,
        defaultValue: T,
        operation: @escaping @Sendable () async -> T
    ) async -> T {
        await withTaskGroup(of: T.self) { group in
            group.addTask {
                await operation()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(max(0.2, seconds) * 1_000_000_000))
                return defaultValue
            }
            let first = await group.next() ?? defaultValue
            group.cancelAll()
            return first
        }
    }
}

// MARK: - Software Acoustic Echo Reference Suppressor (Section 10)

/// Supplements hardware VoiceProcessingIO AEC by checking whether incoming mic energy is dominated by
/// WisdAI's own active playback envelope on the jitter buffer, suppressing self-feedback loops.
public final class AcousticEchoSuppressor: @unchecked Sendable {
    private let lock = NSLock()
    private var recentSpeakerRMS: Float = 0
    private var lastSpeakerActiveNs: UInt64 = 0

    public init() {}

    public func updateSpeakerEnvelope(bufferedMs: Double, micRMS: Float, isAssistantSpeaking: Bool) {
        let nowNs = DispatchTime.now().uptimeNanoseconds
        lock.withLock {
            if isAssistantSpeaking && bufferedMs > 15.0 {
                recentSpeakerRMS = max(recentSpeakerRMS * 0.7, micRMS)
                lastSpeakerActiveNs = nowNs
            } else if bufferedMs <= 5.0 {
                recentSpeakerRMS *= 0.5
            }
        }
    }

    public func shouldSuppressAsSelfEcho(
        micRMS: Float,
        lowEnergy: Float,
        isAssistantSpeaking: Bool
    ) -> Bool {
        guard isAssistantSpeaking else { return false }
        return lock.withLock {
            let nowNs = DispatchTime.now().uptimeNanoseconds
            let speakerActiveRecently = lastSpeakerActiveNs > 0 && (nowNs &- lastSpeakerActiveNs) < 350_000_000
            guard speakerActiveRecently else { return false }
            // Near-field human user interruption sits noticeably higher and carries strong vocal body compared to bleed/tail echo.
            if micRMS < max(0.052, recentSpeakerRMS * 0.85) && lowEnergy < 0.08 {
                return true
            }
            return false
        }
    }

    public func reset() {
        lock.withLock {
            recentSpeakerRMS = 0
            lastSpeakerActiveNs = 0
        }
    }
}

// MARK: - macOS 26+ On-Device SpeechAnalyzer + SpeechTranscriber (Zero 60s Limit, Zero Cloud Lock)

@available(macOS 26.0, *)
public final class SpeechAnalyzerOnDeviceSTTProvider: StreamingSpeechToTextProvider, @unchecked Sendable {
    public let providerID = "apple_speech_analyzer_on_device"
    public let requiresNetworkConsent = false

    private let lock = NSLock()
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var targetFormat: AVAudioFormat?
    private var resultTask: Task<Void, Never>?
    private var analyzerTask: Task<Void, Never>?
    private var committedPrefix: String = ""
    private var activeVolatileText: String = ""
    private var isStopped: Bool = true

    public init() {}

    public static func supportsLocaleOnDevice(_ language: VoiceLanguageVariant) async -> Bool {
        let installed = await SpeechTranscriber.installedLocales
        let prefix = language.bcp47LanguagePrefix.lowercased()
        let exact = language.appleLocaleIdentifier.replacingOccurrences(of: "-", with: "_").lowercased()
        return installed.contains { loc in
            let id = loc.identifier.replacingOccurrences(of: "-", with: "_").lowercased()
            return id == exact || id.hasPrefix(prefix)
        }
    }

    public func start(
        language: VoiceLanguageVariant,
        policy: VoicePolicyPreferences,
        onPartial: @escaping @Sendable (String) -> Void,
        onFinal: @escaping @Sendable (String) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) async throws {
        stop()

        let locale = Locale(identifier: language.appleLocaleIdentifier)
        let installed = await SpeechTranscriber.installedLocales
        let resolvedLocale: Locale = {
            let wantNorm = locale.identifier.replacingOccurrences(of: "-", with: "_").lowercased()
            if let exactMatch = installed.first(where: { $0.identifier.replacingOccurrences(of: "-", with: "_").lowercased() == wantNorm }) {
                return exactMatch
            }
            if let familyMatch = installed.first(where: { $0.identifier.lowercased().hasPrefix(language.bcp47LanguagePrefix) }) {
                return familyMatch
            }
            return locale
        }()

        let newTranscriber = SpeechTranscriber(
            locale: resolvedLocale,
            preset: .progressiveTranscription
        )
        let bestFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [newTranscriber])
            ?? AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let newAnalyzer = SpeechAnalyzer(modules: [newTranscriber])

        lock.withLock {
            self.transcriber = newTranscriber
            self.analyzer = newAnalyzer
            self.targetFormat = bestFormat
            self.inputContinuation = continuation
            self.committedPrefix = ""
            self.activeVolatileText = ""
            self.isStopped = false
        }

        let rTask = Task { [weak self] in
            do {
                for try await result in newTranscriber.results {
                    guard let self else { break }
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    let (combined, finalized) = self.lock.withLock { () -> (String, Bool) in
                        guard !self.isStopped else { return ("", false) }
                        if result.isFinal {
                            if !text.isEmpty {
                                self.committedPrefix = [self.committedPrefix, text]
                                    .filter { !$0.isEmpty }
                                    .joined(separator: " ")
                            }
                            self.activeVolatileText = ""
                            return (self.committedPrefix, true)
                        } else {
                            self.activeVolatileText = text
                            let full = [self.committedPrefix, self.activeVolatileText]
                                .filter { !$0.isEmpty }
                                .joined(separator: " ")
                            return (full, false)
                        }
                    }
                    guard !combined.isEmpty else { continue }
                    if finalized {
                        onFinal(combined)
                    } else {
                        onPartial(combined)
                    }
                }
            } catch {
                if self?.lock.withLock({ self?.isStopped }) == false {
                    onError(error.localizedDescription)
                }
            }
        }

        let aTask = Task { [weak self] in
            do {
                try await newAnalyzer.start(inputSequence: stream)
            } catch {
                if self?.lock.withLock({ self?.isStopped }) == false {
                    onError(error.localizedDescription)
                }
            }
        }

        lock.withLock {
            self.resultTask = rTask
            self.analyzerTask = aTask
        }
    }

    public func feedAudioBuffer(_ buffer: AVAudioPCMBuffer, monoFloats: [Float], sampleRate: Double) {
        let (cont, fmt, stopped) = lock.withLock { (inputContinuation, targetFormat, isStopped) }
        guard !stopped, let cont, let fmt, !monoFloats.isEmpty else { return }

        let targetRate = fmt.sampleRate > 0 ? fmt.sampleRate : 16_000
        let resampled = abs(sampleRate - targetRate) < 1.0
            ? monoFloats
            : AudioPCMConverter.resampleLinear(samples: monoFloats, fromSampleRate: sampleRate, toSampleRate: targetRate)
        guard !resampled.isEmpty else { return }

        let pcm16Data = AudioPCMConverter.floatsToPCM16Data(resampled)
        let frameCount = AVAudioFrameCount(pcm16Data.count / MemoryLayout<Int16>.size)
        guard frameCount > 0,
              pcm16Data.count > 0,
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frameCount) else { return }
        pcmBuffer.frameLength = frameCount

        if fmt.commonFormat == .pcmFormatInt16,
           let dst = pcmBuffer.int16ChannelData?[0],
           pcmBuffer.audioBufferList.pointee.mBuffers.mDataByteSize > 0 {
            pcm16Data.withUnsafeBytes { raw in
                if let src = raw.bindMemory(to: Int16.self).baseAddress {
                    dst.update(from: src, count: Int(frameCount))
                }
            }
            cont.yield(AnalyzerInput(buffer: pcmBuffer))
        } else if fmt.commonFormat == .pcmFormatFloat32,
                  let dst = pcmBuffer.floatChannelData?[0],
                  pcmBuffer.audioBufferList.pointee.mBuffers.mDataByteSize > 0 {
            resampled.withUnsafeBufferPointer { raw in
                if let src = raw.baseAddress {
                    dst.update(from: src, count: Int(frameCount))
                }
            }
            cont.yield(AnalyzerInput(buffer: pcmBuffer))
        }
    }

    public func commitCurrentUtterance() -> String {
        lock.withLock {
            let full = [committedPrefix, activeVolatileText]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            committedPrefix = ""
            activeVolatileText = ""
            return full
        }
    }

    public func resetUtteranceBuffer() {
        lock.withLock {
            committedPrefix = ""
            activeVolatileText = ""
        }
    }

    public func stop() {
        let (cont, rTask, aTask) = lock.withLock { () -> (AsyncStream<AnalyzerInput>.Continuation?, Task<Void, Never>?, Task<Void, Never>?) in
            isStopped = true
            let c = inputContinuation
            let r = resultTask
            let a = analyzerTask
            inputContinuation = nil
            resultTask = nil
            analyzerTask = nil
            analyzer = nil
            transcriber = nil
            committedPrefix = ""
            activeVolatileText = ""
            return (c, r, a)
        }
        cont?.finish()
        rTask?.cancel()
        aTask?.cancel()
    }
}

// MARK: - Unified Local-First Speech Coordinator

public final class UnifiedLocalSTTCoordinator: StreamingSpeechToTextProvider, @unchecked Sendable {
    public let providerID = "wisdai_local_speech_coordinator"
    public private(set) var requiresNetworkConsent = false

    private let legacyAppleSTT = AppleSpeechStreamingSTTProvider()
    private var activeBackend: StreamingSpeechToTextProvider?

    public init() {}

    public func start(
        language: VoiceLanguageVariant,
        policy: VoicePolicyPreferences,
        onPartial: @escaping @Sendable (String) -> Void,
        onFinal: @escaping @Sendable (String) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) async throws {
        stop()

        if #available(macOS 26.0, *) {
            if await SpeechAnalyzerOnDeviceSTTProvider.supportsLocaleOnDevice(language) {
                let analyzerProvider = SpeechAnalyzerOnDeviceSTTProvider()
                do {
                    try await analyzerProvider.start(
                        language: language,
                        policy: policy,
                        onPartial: onPartial,
                        onFinal: onFinal,
                        onError: onError
                    )
                    activeBackend = analyzerProvider
                    requiresNetworkConsent = false
                    return
                } catch {
                    // Fall through cleanly to bounded SFSpeechRecognizer if SpeechAnalyzer asset init fails
                }
            }
        }

        // Bounded SFSpeechRecognizer fallback (never blocks forever in .connecting)
        let speechAuth = await BoundedVoicePermissions.requestSpeechRecognizerAuthorized(timeoutSeconds: 2.0)
        guard speechAuth else {
            throw VoiceGatewayError.protocolError("Ative o Reconhecimento de Fala nos Ajustes do macOS para usar este idioma sem modelo SpeechAnalyzer local.")
        }
        try await legacyAppleSTT.start(
            language: language,
            policy: policy,
            onPartial: onPartial,
            onFinal: onFinal,
            onError: onError
        )
        activeBackend = legacyAppleSTT
        requiresNetworkConsent = legacyAppleSTT.requiresNetworkConsent
    }

    public func feedAudioBuffer(_ buffer: AVAudioPCMBuffer, monoFloats: [Float], sampleRate: Double) {
        activeBackend?.feedAudioBuffer(buffer, monoFloats: monoFloats, sampleRate: sampleRate)
    }

    public func commitCurrentUtterance() -> String {
        if #available(macOS 26.0, *),
           let modern = activeBackend as? SpeechAnalyzerOnDeviceSTTProvider {
            return modern.commitCurrentUtterance()
        }
        if let legacy = activeBackend as? AppleSpeechStreamingSTTProvider {
            return legacy.commitCurrentUtterance()
        }
        return ""
    }

    public func resetUtteranceBuffer() {
        if #available(macOS 26.0, *),
           let modern = activeBackend as? SpeechAnalyzerOnDeviceSTTProvider {
            modern.resetUtteranceBuffer()
            return
        }
        if let legacy = activeBackend as? AppleSpeechStreamingSTTProvider {
            legacy.resetUtteranceBuffer()
        }
    }

    public func stop() {
        activeBackend?.stop()
        activeBackend = nil
    }
}

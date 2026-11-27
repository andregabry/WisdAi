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

// MARK: - Software Acoustic Echo Reference Suppressor (Section 10 & V2 Hangover Gate)

/// Supplements hardware VoiceProcessingIO AEC by tracking BOTH rendered playback RMS from
/// AdaptiveJitterBuffer and an acoustic room-reverb hangover window (~420ms), preventing
/// speaker output from feeding back as self-triggered ASR turns while still allowing genuine barge-in.
public final class AcousticEchoSuppressor: @unchecked Sendable {
    private let lock = NSLock()
    private var recentSpeakerRMS: Float = 0
    private var recentPlaybackRefRMS: Float = 0
    private var lastSpeakerActiveNs: UInt64 = 0
    private let hangoverNs: UInt64 = 420_000_000

    public init() {}

    public func updateSpeakerEnvelope(bufferedMs: Double, micRMS: Float, isAssistantSpeaking: Bool) {
        updatePlaybackReference(
            bufferedMs: bufferedMs,
            playbackRMS: micRMS,
            renderAgeMs: bufferedMs > 15.0 ? 0.0 : 999.0,
            micRMS: micRMS,
            isAssistantSpeaking: isAssistantSpeaking
        )
    }

    public func updatePlaybackReference(
        bufferedMs: Double,
        playbackRMS: Float,
        renderAgeMs: Double,
        micRMS: Float,
        isAssistantSpeaking: Bool
    ) {
        let nowNs = DispatchTime.now().uptimeNanoseconds
        lock.withLock {
            let activeRender = playbackRMS > 0.006 && renderAgeMs < 140.0
            if (isAssistantSpeaking && bufferedMs > 12.0) || activeRender {
                recentPlaybackRefRMS = max(recentPlaybackRefRMS * 0.72, playbackRMS)
                recentSpeakerRMS = max(recentSpeakerRMS * 0.72, max(micRMS, playbackRMS * 0.55))
                lastSpeakerActiveNs = nowNs
            } else if bufferedMs <= 5.0 && !activeRender {
                recentSpeakerRMS *= 0.65
                recentPlaybackRefRMS *= 0.65
            }
        }
    }

    public var isInEchoOrHangoverWindow: Bool {
        let nowNs = DispatchTime.now().uptimeNanoseconds
        return lock.withLock {
            lastSpeakerActiveNs > 0 && (nowNs &- lastSpeakerActiveNs) < hangoverNs
        }
    }

    public func shouldSuppressAsSelfEcho(
        micRMS: Float,
        lowEnergy: Float,
        isAssistantSpeaking: Bool
    ) -> Bool {
        let nowNs = DispatchTime.now().uptimeNanoseconds
        return lock.withLock {
            let speakerActiveRecently = lastSpeakerActiveNs > 0 && (nowNs &- lastSpeakerActiveNs) < hangoverNs
            guard isAssistantSpeaking || speakerActiveRecently else { return false }
            let bleedCeiling = max(0.052, max(recentSpeakerRMS * 0.85, recentPlaybackRefRMS * 0.52))
            // Near-field human user interruption sits noticeably higher and carries strong vocal body compared to bleed/tail echo.
            if micRMS < bleedCeiling && lowEnergy < 0.08 {
                return true
            }
            return false
        }
    }

    public func reset() {
        lock.withLock {
            recentSpeakerRMS = 0
            recentPlaybackRefRMS = 0
            lastSpeakerActiveNs = 0
        }
    }
}

// MARK: - macOS 26+ On-Device SpeechAnalyzer + SpeechTranscriber (Epoch-Isolated, Zero Carryover)

@available(macOS 26.0, *)
public final class SpeechAnalyzerOnDeviceSTTProvider: StreamingSpeechToTextProvider, @unchecked Sendable {
    public let providerID = "apple_speech_analyzer_on_device"
    public let requiresNetworkConsent = false

    private let lock = NSLock()
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var targetFormat: AVAudioFormat?
    private var resolvedLocale: Locale = Locale(identifier: "pt-BR")
    private var resultTask: Task<Void, Never>?
    private var analyzerTask: Task<Void, Never>?
    private var committedPrefix: String = ""
    private var activeVolatileText: String = ""
    private var currentSampleOffset: CMTimeValue = 0
    private var utteranceEpoch: UInt64 = 0
    private var isStopped: Bool = true
    private var onPartialCB: (@Sendable (String) -> Void)?
    private var onFinalCB: (@Sendable (String) -> Void)?
    private var onErrorCB: (@Sendable (String) -> Void)?

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
        let pickedLocale: Locale = {
            let wantNorm = locale.identifier.replacingOccurrences(of: "-", with: "_").lowercased()
            if let exactMatch = installed.first(where: { $0.identifier.replacingOccurrences(of: "-", with: "_").lowercased() == wantNorm }) {
                return exactMatch
            }
            if let familyMatch = installed.first(where: { $0.identifier.lowercased().hasPrefix(language.bcp47LanguagePrefix) }) {
                return familyMatch
            }
            return locale
        }()

        let probeTranscriber = SpeechTranscriber(
            locale: pickedLocale,
            preset: .timeIndexedProgressiveTranscription
        )
        let bestFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [probeTranscriber])
            ?? AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)

        lock.withLock {
            self.resolvedLocale = pickedLocale
            self.targetFormat = bestFormat
            self.onPartialCB = onPartial
            self.onFinalCB = onFinal
            self.onErrorCB = onError
            self.isStopped = false
            self.utteranceEpoch &+= 1
        }
        startIsolatedSegment()
    }

    private func startIsolatedSegment() {
        let oldState = lock.withLock { () -> (SpeechAnalyzer?, AsyncStream<AnalyzerInput>.Continuation?, Task<Void, Never>?, Task<Void, Never>?, Locale, UInt64, Bool) in
            let prevA = self.analyzer
            let prevC = self.inputContinuation
            let prevR = self.resultTask
            let prevAT = self.analyzerTask
            self.analyzer = nil
            self.inputContinuation = nil
            self.resultTask = nil
            self.analyzerTask = nil
            self.committedPrefix = ""
            self.activeVolatileText = ""
            self.currentSampleOffset = 0
            return (prevA, prevC, prevR, prevAT, self.resolvedLocale, self.utteranceEpoch, self.isStopped)
        }

        oldState.1?.finish()
        oldState.2?.cancel()
        oldState.3?.cancel()
        if let prevAnalyzer = oldState.0 {
            Task.detached(priority: .utility) {
                await prevAnalyzer.cancelAndFinishNow()
            }
        }

        guard !oldState.6 else { return }

        let epoch = oldState.5
        let newTranscriber = SpeechTranscriber(
            locale: oldState.4,
            preset: .timeIndexedProgressiveTranscription
        )
        let options = SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .processLifetime)
        let newAnalyzer = SpeechAnalyzer(modules: [newTranscriber], options: options)
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()

        let rTask = Task { [weak self] in
            do {
                for try await result in newTranscriber.results {
                    guard let self else { break }
                    let raw = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    // Discard punctuation-only or zero-alphanumeric phantom segments
                    let hasSemanticChars = raw.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) })
                    let (combined, finalized, partialCB, finalCB) = self.lock.withLock { () -> (String, Bool, (@Sendable (String) -> Void)?, (@Sendable (String) -> Void)?) in
                        guard !self.isStopped, self.utteranceEpoch == epoch else {
                            return ("", false, nil, nil)
                        }
                        if result.isFinal {
                            if hasSemanticChars {
                                self.committedPrefix = [self.committedPrefix, raw]
                                    .filter { !$0.isEmpty }
                                    .joined(separator: " ")
                            }
                            self.activeVolatileText = ""
                            return (self.committedPrefix, true, self.onPartialCB, self.onFinalCB)
                        } else {
                            if hasSemanticChars {
                                self.activeVolatileText = raw
                            }
                            let full = [self.committedPrefix, self.activeVolatileText]
                                .filter { !$0.isEmpty }
                                .joined(separator: " ")
                            return (full, false, self.onPartialCB, self.onFinalCB)
                        }
                    }
                    guard !combined.isEmpty else { continue }
                    if finalized {
                        finalCB?(combined)
                    } else {
                        partialCB?(combined)
                    }
                }
            } catch {
                let errCB = self?.lock.withLock { () -> (@Sendable (String) -> Void)? in
                    guard let self, !self.isStopped, self.utteranceEpoch == epoch else { return nil }
                    return self.onErrorCB
                }
                errCB?(error.localizedDescription)
            }
        }

        let aTask = Task { [weak self] in
            do {
                try await newAnalyzer.start(inputSequence: stream)
            } catch {
                let errCB = self?.lock.withLock { () -> (@Sendable (String) -> Void)? in
                    guard let self, !self.isStopped, self.utteranceEpoch == epoch else { return nil }
                    return self.onErrorCB
                }
                errCB?(error.localizedDescription)
            }
        }

        let stillSameEpoch = lock.withLock { () -> Bool in
            guard !self.isStopped, self.utteranceEpoch == epoch else { return false }
            self.transcriber = newTranscriber
            self.analyzer = newAnalyzer
            self.inputContinuation = continuation
            self.resultTask = rTask
            self.analyzerTask = aTask
            return true
        }
        if !stillSameEpoch {
            continuation.finish()
            rTask.cancel()
            aTask.cancel()
            Task.detached(priority: .utility) {
                await newAnalyzer.cancelAndFinishNow()
            }
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

        let frameCount = AVAudioFrameCount(resampled.count)
        guard frameCount > 0,
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frameCount) else { return }
        pcmBuffer.frameLength = frameCount

        let bufferTS = lock.withLock { () -> CMTime in
            let ts = CMTime(value: currentSampleOffset, timescale: CMTimeScale(targetRate))
            currentSampleOffset += CMTimeValue(frameCount)
            return ts
        }

        if fmt.commonFormat == .pcmFormatInt16,
           let dst = pcmBuffer.int16ChannelData?[0],
           pcmBuffer.audioBufferList.pointee.mBuffers.mDataByteSize > 0 {
            let pcm16Data = AudioPCMConverter.floatsToPCM16Data(resampled)
            guard pcm16Data.count >= Int(frameCount) * MemoryLayout<Int16>.size else { return }
            pcm16Data.withUnsafeBytes { raw in
                if let src = raw.bindMemory(to: Int16.self).baseAddress {
                    dst.update(from: src, count: Int(frameCount))
                }
            }
            cont.yield(AnalyzerInput(buffer: pcmBuffer, bufferStartTime: bufferTS))
        } else if fmt.commonFormat == .pcmFormatFloat32,
                  let dst = pcmBuffer.floatChannelData?[0],
                  pcmBuffer.audioBufferList.pointee.mBuffers.mDataByteSize > 0 {
            resampled.withUnsafeBufferPointer { raw in
                if let src = raw.baseAddress {
                    dst.update(from: src, count: Int(frameCount))
                }
            }
            cont.yield(AnalyzerInput(buffer: pcmBuffer, bufferStartTime: bufferTS))
        }
    }

    public func commitCurrentUtterance() -> String {
        let joined = lock.withLock { () -> String in
            let out = [committedPrefix, activeVolatileText]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            committedPrefix = ""
            activeVolatileText = ""
            utteranceEpoch &+= 1
            return out
        }
        // Rotate SpeechTranscriber into a clean CMTime=0 segment so prior speech or punctuation NEVER leaks forward.
        if lock.withLock({ !isStopped }) {
            startIsolatedSegment()
        }
        return joined
    }

    public func resetUtteranceBuffer() {
        lock.withLock {
            committedPrefix = ""
            activeVolatileText = ""
            utteranceEpoch &+= 1
        }
        if lock.withLock({ !isStopped }) {
            startIsolatedSegment()
        }
    }

    public func stop() {
        let (oldAnalyzer, cont, rTask, aTask) = lock.withLock { () -> (SpeechAnalyzer?, AsyncStream<AnalyzerInput>.Continuation?, Task<Void, Never>?, Task<Void, Never>?) in
            isStopped = true
            utteranceEpoch &+= 1
            let a = analyzer
            let c = inputContinuation
            let r = resultTask
            let at = analyzerTask
            inputContinuation = nil
            resultTask = nil
            analyzerTask = nil
            analyzer = nil
            transcriber = nil
            onPartialCB = nil
            onFinalCB = nil
            onErrorCB = nil
            committedPrefix = ""
            activeVolatileText = ""
            return (a, c, r, at)
        }
        cont?.finish()
        rTask?.cancel()
        aTask?.cancel()
        if let oldAnalyzer {
            Task.detached(priority: .utility) {
                await oldAnalyzer.cancelAndFinishNow()
            }
        }
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

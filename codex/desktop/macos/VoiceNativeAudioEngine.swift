import Accelerate
import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation
import os

// MARK: - Hardware Memory Profiles (Section 17)

public enum HardwareMemoryProfile: String, CaseIterable, Codable, Sendable {
    case low8GB
    case balanced16GB
    case performance24GB
    case studio32GBPlus

    public static func detect(physicalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory) -> HardwareMemoryProfile {
        let gib = Double(physicalMemoryBytes) / 1_073_741_824.0
        if gib <= 10.5 { return .low8GB }
        if gib <= 20.0 { return .balanced16GB }
        if gib <= 28.0 { return .performance24GB }
        return .studio32GBPlus
    }

    public var displayName: String {
        switch self {
        case .low8GB: return "Compacto (8 GB RAM)"
        case .balanced16GB: return "Equilibrado (16 GB RAM)"
        case .performance24GB: return "Desempenho (24 GB RAM)"
        case .studio32GBPlus: return "Estúdio (32+ GB RAM)"
        }
    }

    public var maxCaptureRingSeconds: Double {
        switch self {
        case .low8GB: return 2.0
        case .balanced16GB: return 4.0
        case .performance24GB: return 6.0
        case .studio32GBPlus: return 8.0
        }
    }

    public var maxOutputJitterSeconds: Double {
        switch self {
        case .low8GB: return 6.0
        case .balanced16GB: return 12.0
        case .performance24GB: return 20.0
        case .studio32GBPlus: return 30.0
        }
    }

    public var maxInMemoryTurns: Int {
        switch self {
        case .low8GB: return 24
        case .balanced16GB: return 48
        case .performance24GB: return 80
        case .studio32GBPlus: return 120
        }
    }

    public var compactionTriggerTurns: Int {
        switch self {
        case .low8GB: return 14
        case .balanced16GB: return 24
        case .performance24GB: return 40
        case .studio32GBPlus: return 64
        }
    }

    public var allowsHeavyLocalModels: Bool {
        switch self {
        case .low8GB: return false
        case .balanced16GB, .performance24GB, .studio32GBPlus: return true
        }
    }
}

// MARK: - CoreAudio Device Registry & Bluetooth Awareness

public enum AudioDeviceTransportKind: String, Codable, Sendable {
    case builtIn
    case bluetooth
    case usb
    case continuityOrVirtual
    case unknown

    public var displayLabel: String {
        switch self {
        case .builtIn: return "Integrado"
        case .bluetooth: return "Bluetooth"
        case .usb: return "USB"
        case .continuityOrVirtual: return "Continuidade / Virtual"
        case .unknown: return "Áudio"
        }
    }
}

public struct AudioDeviceDescriptor: Identifiable, Equatable, Hashable, Sendable {
    public let id: AudioDeviceID
    public let uid: String
    public let name: String
    public let transport: AudioDeviceTransportKind
    public let inputChannels: Int
    public let outputChannels: Int
    public let nominalSampleRate: Double
    public let isDefaultInput: Bool
    public let isDefaultOutput: Bool

    public var isBluetooth: Bool { transport == .bluetooth }
}

public enum SystemMicrophoneIsolationMode: String, Sendable {
    case standard
    case voiceIsolation
    case wideSpectrum
    case unavailable

    public var displayLabel: String {
        switch self {
        case .voiceIsolation: return "Isolamento de Voz (macOS)"
        case .wideSpectrum: return "Espectro Amplo"
        case .standard: return "Padrão"
        case .unavailable: return "Indisponível"
        }
    }
}

public enum CoreAudioDeviceCatalog {
    public static func enumerateDevices() -> [AudioDeviceDescriptor] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
              size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.stride
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else {
            return []
        }

        let defaultIn = defaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice)
        let defaultOut = defaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice)

        return ids.compactMap { devID in
            let inCh = channelCount(deviceID: devID, scope: kAudioDevicePropertyScopeInput)
            let outCh = channelCount(deviceID: devID, scope: kAudioDevicePropertyScopeOutput)
            guard inCh > 0 || outCh > 0 else { return nil }
            let name = stringProperty(deviceID: devID, selector: kAudioObjectPropertyName) ?? "Dispositivo \(devID)"
            let uid = stringProperty(deviceID: devID, selector: kAudioDevicePropertyDeviceUID) ?? "dev-\(devID)"
            let rate = nominalSampleRate(deviceID: devID)
            if name.hasPrefix("CADefaultDeviceAggregate") || uid.hasPrefix("CADefaultDeviceAggregate") || !isDeviceAlive(deviceID: devID) || rate <= 0 {
                return nil
            }
            let transport = transportKind(deviceID: devID, name: name)
            return AudioDeviceDescriptor(
                id: devID,
                uid: uid,
                name: name,
                transport: transport,
                inputChannels: inCh,
                outputChannels: outCh,
                nominalSampleRate: rate,
                isDefaultInput: devID == defaultIn,
                isDefaultOutput: devID == defaultOut
            )
        }
    }

    public static func isDeviceAlive(deviceID: AudioDeviceID) -> Bool {
        guard deviceID != 0 else { return false }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var alive: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &alive) == noErr else {
            return false
        }
        return alive != 0
    }

    public static func defaultDeviceID(selector: AudioObjectPropertySelector) -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr else {
            return 0
        }
        return deviceID
    }

    public static func currentSystemMicrophoneMode() -> SystemMicrophoneIsolationMode {
        if #available(macOS 14.0, *) {
            switch AVCaptureDevice.activeMicrophoneMode {
            case .voiceIsolation: return .voiceIsolation
            case .wideSpectrum: return .wideSpectrum
            case .standard: return .standard
            @unknown default: return .standard
            }
        }
        return .unavailable
    }

    public static func outputDeviceLatencyMs(deviceID: AudioDeviceID?) -> Double {
        let targetID: AudioDeviceID = {
            if let deviceID, deviceID != 0 { return deviceID }
            return defaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice)
        }()
        guard targetID != 0 else { return 0 }
        func uint32Prop(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope) -> UInt32 {
            var addr = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: scope,
                mElement: kAudioObjectPropertyElementMain
            )
            var val: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            let status = AudioObjectGetPropertyData(targetID, &addr, 0, nil, &size, &val)
            return status == noErr ? val : 0
        }
        let devLatency = uint32Prop(kAudioDevicePropertyLatency, scope: kAudioDevicePropertyScopeOutput)
        let safety = uint32Prop(kAudioDevicePropertySafetyOffset, scope: kAudioDevicePropertyScopeOutput)
        let ioFrames = uint32Prop(kAudioDevicePropertyBufferFrameSize, scope: kAudioObjectPropertyScopeOutput)
        let sr = nominalSampleRate(deviceID: targetID)
        guard sr > 0 else { return 0 }
        let totalFrames = Double(devLatency + safety + ioFrames)
        return (totalFrames / sr) * 1000.0
    }

    private static func stringProperty(deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        guard status == noErr, let cfStr = value?.takeUnretainedValue() else { return nil }
        return cfStr as String
    }

    public static func nominalSampleRate(deviceID: AudioDeviceID) -> Double {
        guard deviceID != 0 else { return 0 }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &rate) == noErr, rate > 0 else {
            return 0
        }
        return rate
    }

    public static func channelCount(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let bufferList = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func transportKind(deviceID: AudioDeviceID, name: String) -> AudioDeviceTransportKind {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var code: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &code) == noErr {
            switch code {
            case kAudioDeviceTransportTypeBuiltIn: return .builtIn
            case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
            case kAudioDeviceTransportTypeUSB: return .usb
            case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate:
                return .continuityOrVirtual
            default:
                break
            }
        }
        let lower = name.lowercased()
        if lower.contains("iphone") || lower.contains("virtual") { return .continuityOrVirtual }
        if lower.contains("airpods") || lower.contains("bluetooth") { return .bluetooth }
        return .unknown
    }
}

// MARK: - Non-Allocating Audio Ring Buffer (Capture & Backpressure)

public final class PreallocatedFloatRingBuffer: @unchecked Sendable {
    private let capacity: Int
    private let storage: UnsafeMutablePointer<Float>
    private var lock = os_unfair_lock_s()
    private var readIndex: Int = 0
    private var writeIndex: Int = 0
    private var count: Int = 0
    public private(set) var droppedSamples: UInt64 = 0
    public private(set) var totalWrittenSamples: UInt64 = 0

    public init(capacitySamples: Int) {
        self.capacity = max(1024, capacitySamples)
        self.storage = UnsafeMutablePointer<Float>.allocate(capacity: self.capacity)
        self.storage.initialize(repeating: 0, count: self.capacity)
    }

    deinit {
        storage.deinitialize(count: capacity)
        storage.deallocate()
    }

    @discardableResult
    public func push(samples: UnsafePointer<Float>, count inputCount: Int) -> Int {
        guard inputCount > 0 else { return 0 }
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        var offset = 0
        var toWrite = inputCount
        if toWrite > capacity {
            droppedSamples &+= UInt64(toWrite - capacity)
            offset = toWrite - capacity
            toWrite = capacity
        }
        let overflow = (count + toWrite) - capacity
        if overflow > 0 {
            readIndex = (readIndex + overflow) % capacity
            count -= overflow
            droppedSamples &+= UInt64(overflow)
        }
        let firstPart = min(toWrite, capacity - writeIndex)
        storage.advanced(by: writeIndex).update(from: samples.advanced(by: offset), count: firstPart)
        let secondPart = toWrite - firstPart
        if secondPart > 0 {
            storage.update(from: samples.advanced(by: offset + firstPart), count: secondPart)
        }
        writeIndex = (writeIndex + toWrite) % capacity
        count += toWrite
        totalWrittenSamples &+= UInt64(toWrite)
        return toWrite
    }

    public func pop(into destination: UnsafeMutablePointer<Float>, maxCount: Int) -> Int {
        guard maxCount > 0 else { return 0 }
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        let actual = min(maxCount, count)
        guard actual > 0 else { return 0 }
        let firstPart = min(actual, capacity - readIndex)
        destination.update(from: storage.advanced(by: readIndex), count: firstPart)
        let secondPart = actual - firstPart
        if secondPart > 0 {
            destination.advanced(by: firstPart).update(from: storage, count: secondPart)
        }
        readIndex = (readIndex + actual) % capacity
        count -= actual
        return actual
    }

    public func flush() {
        os_unfair_lock_lock(&lock)
        readIndex = 0
        writeIndex = 0
        count = 0
        os_unfair_lock_unlock(&lock)
    }

    public var availableSamples: Int {
        os_unfair_lock_lock(&lock)
        let current = count
        os_unfair_lock_unlock(&lock)
        return current
    }
}

// MARK: - Adaptive Bounded Jitter Buffer & Exact Spoken Ledger

public struct JitterBufferFlushSnapshot: Equatable, Sendable {
    public let playedMilliseconds: Double
    public let heardTranscriptPrefix: String
    public let unplayedTranscriptTail: String
    public let discardedBufferedSamples: Int
    public let flushTimestampUptimeNs: UInt64

    public init(
        playedMilliseconds: Double,
        heardTranscriptPrefix: String,
        unplayedTranscriptTail: String,
        discardedBufferedSamples: Int,
        flushTimestampUptimeNs: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) {
        self.playedMilliseconds = playedMilliseconds
        self.heardTranscriptPrefix = heardTranscriptPrefix
        self.unplayedTranscriptTail = unplayedTranscriptTail
        self.discardedBufferedSamples = discardedBufferedSamples
        self.flushTimestampUptimeNs = flushTimestampUptimeNs
    }
}

public enum JitterPushStatus: Equatable, Sendable {
    case queued
    case trimmedOverflow(droppedSamples: Int)
    case rejectedEmpty
}

public final class AdaptiveJitterBuffer: @unchecked Sendable {
    private struct SpokenSpan {
        let startSample: UInt64
        let endSample: UInt64
        let text: String
    }

    public let sampleRate: Double
    public let capacitySamples: Int
    private let storage: UnsafeMutablePointer<Float>
    private var lock = os_unfair_lock_s()

    private var readIndex: Int = 0
    private var writeIndex: Int = 0
    private var bufferedCount: Int = 0

    private var totalQueuedSamples: UInt64 = 0
    private var totalPlayedSamples: UInt64 = 0
    private var lastEnqueueUptimeNs: UInt64 = 0
    private var ewmaArrivalJitterMs: Double = 0
    private var spans: [SpokenSpan] = []

    public private(set) var basePrebufferMs: Double = 40.0
    public private(set) var targetPrebufferMs: Double = 40.0
    public private(set) var underrunCount: UInt64 = 0
    public private(set) var overflowDropCount: UInt64 = 0
    private var isBuffering: Bool = true
    private var fadeInRemaining: Int = 0
    private var lastRenderedRMS: Float = 0
    private var lastRenderUptimeNs: UInt64 = 0
    private var hasRecordedFirstRenderForResponse: Bool = false
    private var firstRenderUptimeNsForResponse: UInt64 = 0
    private var lastFlushUptimeNs: UInt64 = 0
    private var firstSilentRenderAfterFlushUptimeNs: UInt64 = 0

    public init(sampleRate: Double = 24_000, maxDurationSeconds: Double = 6.0, basePrebufferMs: Double = 40.0) {
        self.sampleRate = max(8_000, sampleRate)
        self.capacitySamples = max(4_800, Int(self.sampleRate * maxDurationSeconds))
        let clampedBase = max(5.0, min(120.0, basePrebufferMs))
        self.basePrebufferMs = clampedBase
        self.targetPrebufferMs = clampedBase
        self.storage = UnsafeMutablePointer<Float>.allocate(capacity: self.capacitySamples)
        self.storage.initialize(repeating: 0, count: self.capacitySamples)
    }

    deinit {
        storage.deinitialize(count: capacitySamples)
        storage.deallocate()
    }

    @discardableResult
    public func pushFloatSamples(
        _ samples: [Float],
        transcriptText: String? = nil,
        uptimeNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) -> JitterPushStatus {
        guard !samples.isEmpty else { return .rejectedEmpty }

        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        updateAdaptiveWindowLocked(sampleCount: samples.count, nowNs: uptimeNanoseconds)

        var dropped = 0
        let incomingCount = samples.count
        var sliceStart = 0
        if incomingCount >= capacitySamples {
            let excess = incomingCount - capacitySamples
            sliceStart = excess
            dropped += excess
            overflowDropCount &+= UInt64(excess)
        }
        let writeCount = incomingCount - sliceStart
        let overflow = (bufferedCount + writeCount) - capacitySamples
        if overflow > 0 {
            readIndex = (readIndex + overflow) % capacitySamples
            bufferedCount -= overflow
            dropped += overflow
            overflowDropCount &+= UInt64(overflow)
        }

        let fadeSamples = min(writeCount, Int(sampleRate * 0.0025))
        samples.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress?.advanced(by: sliceStart) else { return }
            let firstPart = min(writeCount, capacitySamples - writeIndex)
            storage.advanced(by: writeIndex).update(from: base, count: firstPart)
            let secondPart = writeCount - firstPart
            if secondPart > 0 {
                storage.update(from: base.advanced(by: firstPart), count: secondPart)
            }
        }
        if isBuffering && fadeSamples > 0 {
            fadeInRemaining = fadeSamples
        }
        writeIndex = (writeIndex + writeCount) % capacitySamples
        bufferedCount += writeCount

        let spanStart = totalQueuedSamples
        let spanEnd = spanStart + UInt64(writeCount)
        totalQueuedSamples = spanEnd
        if let transcriptText, !transcriptText.isEmpty {
            spans.append(SpokenSpan(startSample: spanStart, endSample: spanEnd, text: transcriptText))
        }

        if dropped > 0 {
            return .trimmedOverflow(droppedSamples: dropped)
        }
        return .queued
    }

    @discardableResult
    public func pushPCM16Data(
        _ data: Data,
        transcriptText: String? = nil,
        uptimeNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) -> JitterPushStatus {
        let floatSamples = AudioPCMConverter.pcm16DataToFloats(data)
        return pushFloatSamples(floatSamples, transcriptText: transcriptText, uptimeNanoseconds: uptimeNanoseconds)
    }

    /// Pulls samples for the real-time CoreAudio render callback without allocating heap memory.
    public func renderPull(into output: UnsafeMutablePointer<Float>, frameCount: Int, outputLevelOut: UnsafeMutablePointer<Float>? = nil) -> Int {
        guard frameCount > 0 else { return 0 }
        os_unfair_lock_lock(&lock)

        let prebufferSamples = Int((targetPrebufferMs / 1000.0) * sampleRate)
        if isBuffering {
            if bufferedCount < prebufferSamples && bufferedCount < frameCount {
                if bufferedCount == 0 && lastFlushUptimeNs > 0 && firstSilentRenderAfterFlushUptimeNs == 0 {
                    firstSilentRenderAfterFlushUptimeNs = DispatchTime.now().uptimeNanoseconds
                }
                os_unfair_lock_unlock(&lock)
                output.initialize(repeating: 0, count: frameCount)
                outputLevelOut?.pointee = 0
                return 0
            }
            isBuffering = false
        }

        let available = min(frameCount, bufferedCount)
        if available == 0 {
            if bufferedCount == 0 {
                underrunCount &+= 1
                targetPrebufferMs = min(160.0, targetPrebufferMs + 10.0)
                isBuffering = true
            }
            lastRenderedRMS = 0
            if lastFlushUptimeNs > 0 && firstSilentRenderAfterFlushUptimeNs == 0 {
                firstSilentRenderAfterFlushUptimeNs = DispatchTime.now().uptimeNanoseconds
            }
            os_unfair_lock_unlock(&lock)
            output.initialize(repeating: 0, count: frameCount)
            outputLevelOut?.pointee = 0
            return 0
        }

        let firstPart = min(available, capacitySamples - readIndex)
        output.update(from: storage.advanced(by: readIndex), count: firstPart)
        let secondPart = available - firstPart
        if secondPart > 0 {
            output.advanced(by: firstPart).update(from: storage, count: secondPart)
        }
        readIndex = (readIndex + available) % capacitySamples
        bufferedCount -= available
        totalPlayedSamples &+= UInt64(available)

        if available < frameCount {
            output.advanced(by: available).initialize(repeating: 0, count: frameCount - available)
            underrunCount &+= 1
            isBuffering = true
            targetPrebufferMs = min(160.0, targetPrebufferMs + 8.0)
        }

        if fadeInRemaining > 0 {
            let fadeLimit = min(available, fadeInRemaining)
            let denom = Float(max(1, fadeLimit))
            for idx in 0..<fadeLimit {
                output[idx] *= Float(idx + 1) / denom
            }
            fadeInRemaining -= fadeLimit
        }

        var rms: Float = 0
        vDSP_rmsqv(output, 1, &rms, vDSP_Length(available))
        lastRenderedRMS = rms
        let renderNowNs = DispatchTime.now().uptimeNanoseconds
        lastRenderUptimeNs = renderNowNs
        if !hasRecordedFirstRenderForResponse {
            hasRecordedFirstRenderForResponse = true
            firstRenderUptimeNsForResponse = renderNowNs
        }
        os_unfair_lock_unlock(&lock)
        outputLevelOut?.pointee = rms
        return available
    }

    public func flushAndCaptureHeardSnapshot() -> JitterBufferFlushSnapshot {
        let nowNs = DispatchTime.now().uptimeNanoseconds
        os_unfair_lock_lock(&lock)
        let discarded = bufferedCount
        let playedMs = (Double(totalPlayedSamples) / sampleRate) * 1000.0
        let (heard, unplayed) = computeHeardAndRemainderLocked(playedSamples: totalPlayedSamples)
        readIndex = 0
        writeIndex = 0
        bufferedCount = 0
        isBuffering = true
        fadeInRemaining = 0
        lastRenderedRMS = 0
        lastFlushUptimeNs = nowNs
        firstSilentRenderAfterFlushUptimeNs = 0
        spans.removeAll(keepingCapacity: false)
        totalQueuedSamples = totalPlayedSamples
        os_unfair_lock_unlock(&lock)

        return JitterBufferFlushSnapshot(
            playedMilliseconds: playedMs,
            heardTranscriptPrefix: heard,
            unplayedTranscriptTail: unplayed,
            discardedBufferedSamples: discarded,
            flushTimestampUptimeNs: nowNs
        )
    }

    public func resetForNewResponse() {
        os_unfair_lock_lock(&lock)
        readIndex = 0
        writeIndex = 0
        bufferedCount = 0
        totalQueuedSamples = 0
        totalPlayedSamples = 0
        lastEnqueueUptimeNs = 0
        ewmaArrivalJitterMs = 0
        targetPrebufferMs = basePrebufferMs
        isBuffering = true
        fadeInRemaining = 0
        lastRenderedRMS = 0
        lastRenderUptimeNs = 0
        hasRecordedFirstRenderForResponse = false
        firstRenderUptimeNsForResponse = 0
        lastFlushUptimeNs = 0
        firstSilentRenderAfterFlushUptimeNs = 0
        spans.removeAll(keepingCapacity: false)
        os_unfair_lock_unlock(&lock)
    }

    public func firstRenderTimestampNsForResponse() -> UInt64? {
        os_unfair_lock_lock(&lock)
        let ts = hasRecordedFirstRenderForResponse ? firstRenderUptimeNsForResponse : 0
        os_unfair_lock_unlock(&lock)
        return ts > 0 ? ts : nil
    }

    public func firstSilentRenderAfterFlushTimestampNs(matchingFlush flushNs: UInt64) -> UInt64? {
        os_unfair_lock_lock(&lock)
        let matches = (lastFlushUptimeNs == flushNs && firstSilentRenderAfterFlushUptimeNs >= flushNs)
        let ts = matches ? firstSilentRenderAfterFlushUptimeNs : 0
        os_unfair_lock_unlock(&lock)
        return ts > 0 ? ts : nil
    }

    public var playbackReferenceState: (bufferedMs: Double, renderedRMS: Float, renderAgeMs: Double) {
        let nowNs = DispatchTime.now().uptimeNanoseconds
        os_unfair_lock_lock(&lock)
        let bufMs = (Double(bufferedCount) / sampleRate) * 1000.0
        let rms = lastRenderedRMS
        let ageMs = lastRenderUptimeNs > 0 && nowNs >= lastRenderUptimeNs
            ? Double(nowNs - lastRenderUptimeNs) / 1_000_000.0
            : 9_999.0
        os_unfair_lock_unlock(&lock)
        return (bufMs, rms, ageMs)
    }

    public var stats: (bufferedMs: Double, playedMs: Double, targetPrebufferMs: Double, underruns: UInt64, overflows: UInt64) {
        os_unfair_lock_lock(&lock)
        let bufMs = (Double(bufferedCount) / sampleRate) * 1000.0
        let plyMs = (Double(totalPlayedSamples) / sampleRate) * 1000.0
        let target = targetPrebufferMs
        let u = underrunCount
        let o = overflowDropCount
        os_unfair_lock_unlock(&lock)
        return (bufMs, plyMs, target, u, o)
    }

    private func updateAdaptiveWindowLocked(sampleCount: Int, nowNs: UInt64) {
        if lastEnqueueUptimeNs > 0 && nowNs > lastEnqueueUptimeNs {
            let deltaMs = Double(nowNs - lastEnqueueUptimeNs) / 1_000_000.0
            let chunkDurationMs = (Double(sampleCount) / sampleRate) * 1000.0
            let jitterMs = abs(deltaMs - chunkDurationMs)
            ewmaArrivalJitterMs = (ewmaArrivalJitterMs * 0.78) + (min(jitterMs, 180.0) * 0.22)
            let desired = min(160.0, max(40.0, 40.0 + ewmaArrivalJitterMs * 1.4))
            targetPrebufferMs = (targetPrebufferMs * 0.85) + (desired * 0.15)
        }
        lastEnqueueUptimeNs = nowNs
    }

    private func computeHeardAndRemainderLocked(playedSamples: UInt64) -> (String, String) {
        guard !spans.isEmpty else { return ("", "") }
        var heardParts: [String] = []
        var remainderParts: [String] = []

        for span in spans {
            if span.endSample <= playedSamples {
                heardParts.append(span.text)
            } else if span.startSample >= playedSamples {
                remainderParts.append(span.text)
            } else {
                let len = max(1, span.endSample - span.startSample)
                let fraction = min(1.0, max(0.0, Double(playedSamples - span.startSample) / Double(len)))
                let words = span.text.split(separator: " ", omittingEmptySubsequences: true)
                if words.isEmpty {
                    let cutIdx = max(0, min(span.text.count, Int(round(Double(span.text.count) * fraction))))
                    let idx = span.text.index(span.text.startIndex, offsetBy: cutIdx)
                    let left = String(span.text[..<idx]).trimmingCharacters(in: .whitespaces)
                    let right = String(span.text[idx...]).trimmingCharacters(in: .whitespaces)
                    if !left.isEmpty { heardParts.append(left) }
                    if !right.isEmpty { remainderParts.append(right) }
                } else {
                    let heardWordCount = max(0, min(words.count, Int(round(Double(words.count) * fraction))))
                    if heardWordCount > 0 {
                        heardParts.append(words.prefix(heardWordCount).joined(separator: " "))
                    }
                    if heardWordCount < words.count {
                        remainderParts.append(words.dropFirst(heardWordCount).joined(separator: " "))
                    }
                }
            }
        }
        return (
            heardParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines),
            remainderParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

// MARK: - Sample Rate & PCM Format Conversion + Spectral Energy

public enum AudioPCMConverter {
    public static func pcm16DataToFloats(_ data: Data) -> [Float] {
        let sampleCount = data.count / MemoryLayout<Int16>.size
        guard sampleCount > 0 else { return [] }
        var floats = [Float](repeating: 0, count: sampleCount)
        data.withUnsafeBytes { raw in
            guard let ptr = raw.bindMemory(to: Int16.self).baseAddress else { return }
            vDSP_vflt16(ptr, 1, &floats, 1, vDSP_Length(sampleCount))
            var scale = Float(1.0 / 32768.0)
            vDSP_vsmul(floats, 1, &scale, &floats, 1, vDSP_Length(sampleCount))
        }
        return floats
    }

    public static func floatsToPCM16Data(_ floats: [Float]) -> Data {
        guard !floats.isEmpty else { return Data() }
        var clipped = [Float](repeating: 0, count: floats.count)
        var minVal: Float = -1.0
        var maxVal: Float = 1.0
        vDSP_vclip(floats, 1, &minVal, &maxVal, &clipped, 1, vDSP_Length(floats.count))
        var scale: Float = 32767.0
        vDSP_vsmul(clipped, 1, &scale, &clipped, 1, vDSP_Length(clipped.count))
        var int16Samples = [Int16](repeating: 0, count: clipped.count)
        vDSP_vfix16(clipped, 1, &int16Samples, 1, vDSP_Length(clipped.count))
        return int16Samples.withUnsafeBytes { Data($0) }
    }

    public static func resampleLinear(
        samples: [Float],
        fromSampleRate: Double,
        toSampleRate: Double
    ) -> [Float] {
        guard !samples.isEmpty, fromSampleRate > 0, toSampleRate > 0 else { return [] }
        if abs(fromSampleRate - toSampleRate) < 1.0 { return samples }

        let ratio = toSampleRate / fromSampleRate
        let outputCount = max(1, Int((Double(samples.count) * ratio).rounded()))
        var output = [Float](repeating: 0, count: outputCount)
        let maxSrcIdx = samples.count - 1
        let invRatio = fromSampleRate / toSampleRate

        for i in 0..<outputCount {
            let srcPos = Double(i) * invRatio
            let idx0 = min(maxSrcIdx, Int(srcPos))
            let idx1 = min(maxSrcIdx, idx0 + 1)
            let frac = Float(srcPos - Double(idx0))
            output[i] = samples[idx0] + (samples[idx1] - samples[idx0]) * frac
        }
        return output
    }

    /// Anti-aliased CoreAudio AVAudioConverter resampler (preserves studio warmth when downsampling 44.1 kHz -> 24 kHz).
    public static func resampleHighQuality(
        samples: [Float],
        fromSampleRate: Double,
        toSampleRate: Double
    ) -> [Float] {
        guard !samples.isEmpty, fromSampleRate > 0, toSampleRate > 0 else { return [] }
        if abs(fromSampleRate - toSampleRate) < 1.0 { return samples }
        guard let inFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: fromSampleRate, channels: 1, interleaved: false),
              let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: toSampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat),
              let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(samples.count)) else {
            return resampleLinear(samples: samples, fromSampleRate: fromSampleRate, toSampleRate: toSampleRate)
        }
        inBuffer.frameLength = AVAudioFrameCount(samples.count)
        if let ch = inBuffer.floatChannelData?[0] {
            samples.withUnsafeBufferPointer { src in
                if let base = src.baseAddress {
                    ch.update(from: base, count: samples.count)
                }
            }
        }
        let ratio = toSampleRate / fromSampleRate
        let outCap = max(64, AVAudioFrameCount((Double(samples.count) * ratio).rounded(.up) + 32))
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outCap) else {
            return resampleLinear(samples: samples, fromSampleRate: fromSampleRate, toSampleRate: toSampleRate)
        }
        final class FeedState: @unchecked Sendable { var fed = false }
        let feedState = FeedState()
        var convErr: NSError?
        converter.convert(to: outBuffer, error: &convErr) { _, outStatus in
            if feedState.fed {
                outStatus.pointee = .endOfStream
                return nil
            }
            feedState.fed = true
            outStatus.pointee = .haveData
            return inBuffer
        }
        if convErr == nil, outBuffer.frameLength > 0, let outPtr = outBuffer.floatChannelData?[0] {
            return Array(UnsafeBufferPointer(start: outPtr, count: Int(outBuffer.frameLength)))
        }
        return resampleLinear(samples: samples, fromSampleRate: fromSampleRate, toSampleRate: toSampleRate)
    }

    public static func mixToMono(buffer: AVAudioPCMBuffer) -> [Float] {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0, let channelData = buffer.floatChannelData else { return [] }
        let channels = Int(buffer.format.channelCount)
        if channels == 1 {
            return Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        }
        var mono = [Float](repeating: 0, count: frameCount)
        let invCh = 1.0 / Float(max(1, channels))
        for ch in 0..<channels {
            var scale = invCh
            vDSP_vsma(channelData[ch], 1, &scale, mono, 1, &mono, 1, vDSP_Length(frameCount))
        }
        return mono
    }

    public static func measureLevels(samples: [Float]) -> (rms: Float, peak: Float, low: Float, mid: Float, high: Float) {
        guard !samples.isEmpty else { return (0, 0, 0, 0, 0) }
        var rms: Float = 0
        var peak: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))

        // Fast zero-allocation time-domain 3-band approximation:
        // low-pass EWMA (low), zero-crossing / diff energy (high), mid remainder.
        var lp: Float = 0
        var hpEnergy: Float = 0
        var lpEnergy: Float = 0
        var prev: Float = samples[0]
        for s in samples {
            lp = lp * 0.88 + s * 0.12
            let diff = s - prev
            prev = s
            lpEnergy += lp * lp
            hpEnergy += diff * diff
        }
        let n = Float(samples.count)
        let low = min(1.0, sqrt(lpEnergy / n) * 4.2)
        let high = min(1.0, sqrt(hpEnergy / n) * 3.0)
        let mid = min(1.0, max(0, rms * 3.8))
        return (rms, peak, low, mid, high)
    }
}

// MARK: - Voice Engine Diagnostics, Lifecycle Authority & Status

public enum VoiceProcessingHardwareStatus: String, Sendable {
    case activeAECAndNS = "AEC + AGC + Supressão de Ruído Ativos"
    case bypassedBluetoothOrFallback = "Bypass seguro (Bluetooth / Fallback)"
    case inactive = "Inativo"
}

public enum AudioEngineLifecycleState: String, Codable, Sendable {
    case idle = "Ocioso"
    case stopping = "Encerrando"
    case validatingDevices = "Validando Dispositivos"
    case waitingHALRecovery = "Aguardando CoreAudio HAL"
    case preparingGraph = "Configurando Grafo de Áudio"
    case starting = "Iniciando Motor"
    case running = "Operacional (VPIO Full-Duplex)"
    case degradedCompatibility = "Compatibilidade Degradada (AEC Software)"
    case reconfiguring = "Reconfigurando Rota"
    case recovering = "Em Recuperação Controlada"
    case failed = "Falha de Inicialização"
}

public enum AudioEngineOperationKind: String, Codable, Sendable {
    case none = "Nenhuma"
    case validatePermissions = "Validar Permissão de Microfone"
    case validateDevices = "Validar Dispositivos e Formatos CoreAudio"
    case teardownPreviousEngine = "Encerrar Motor Anterior"
    case waitHALReady = "Aguardar Estabilização CoreAudio HAL"
    case bindAudioUnitDevice = "Aplicar Dispositivo AUHAL"
    case attachOutputSource = "Conectar AVAudioSourceNode -> MainMixer"
    case enableVoiceProcessingIO = "Ativar VoiceProcessingIO (AEC Hardware)"
    case validateEngineFormats = "Validar Formatos dos Nós"
    case installInputTap = "Instalar Tap de Captura"
    case prepareEngine = "AVAudioEngine.prepare()"
    case startEngine = "AVAudioEngine.start()"
    case installConfigObserver = "Registrar Observador de Configuração"
    case handleConfigChange = "Processar Mudança de Rota"
    case splitEngineFallback = "Modo Compatibilidade Separado (In+Out)"
    case stopEngine = "Parar e Limpar Grafo"
}

public struct AudioEngineFailureRecord: Equatable, Sendable {
    public let operation: AudioEngineOperationKind
    public let domain: String
    public let osStatus: Int32
    public let message: String
    public let timestampISO: String

    public init(operation: AudioEngineOperationKind, error: Error, timestampISO: String = ISO8601DateFormatter().string(from: Date())) {
        let ns = error as NSError
        self.operation = operation
        self.domain = ns.domain
        self.osStatus = Int32(ns.code)
        self.message = ns.localizedDescription
        self.timestampISO = timestampISO
    }

    public init(operation: AudioEngineOperationKind, domain: String, osStatus: Int32, message: String, timestampISO: String = ISO8601DateFormatter().string(from: Date())) {
        self.operation = operation
        self.domain = domain
        self.osStatus = osStatus
        self.message = message
        self.timestampISO = timestampISO
    }

    public var formattedSummary: String {
        "[\(operation.rawValue)] \(message) (domain=\(domain), OSStatus=\(osStatus))"
    }
}

public struct AudioEngineRuntimeTelemetry: Equatable, Sendable {
    public let isRunning: Bool
    public let isFullDuplex: Bool
    public let hardwareSampleRate: Double
    public let processingStatus: VoiceProcessingHardwareStatus
    public let systemMicMode: SystemMicrophoneIsolationMode
    public let inputDeviceName: String
    public let outputDeviceName: String
    public let captureDroppedSamples: UInt64
    public let outputUnderruns: UInt64
    public let outputOverflows: UInt64
    public let outputBufferedMs: Double
    public let outputTargetPrebufferMs: Double
    public let recoveryCount: Int
    public let lastFaultDescription: String?
    public let lifecycleState: AudioEngineLifecycleState
    public let audioUnitState: String
    public let inputSampleRateHz: Double
    public let inputChannels: Int
    public let outputSampleRateHz: Double
    public let outputChannels: Int
    public let vpioActive: Bool
    public let tapInstalled: Bool
    public let nodeGraphSummary: String
    public let lastOperation: AudioEngineOperationKind
    public let lastFailure: AudioEngineFailureRecord?
    public let restartCount: Int
    public let isSplitEngineCompatibility: Bool
}

// MARK: - Single Serialized Authority for Full-Duplex Native Audio Engine (CoreAudio + AVAudioEngine)

@MainActor
public final class VoiceNativeAudioEngine: ObservableObject {
    @Published public private(set) var inputDevices: [AudioDeviceDescriptor] = []
    @Published public private(set) var outputDevices: [AudioDeviceDescriptor] = []
    @Published public private(set) var selectedInputDeviceUID: String?
    @Published public private(set) var selectedOutputDeviceUID: String?
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var processingStatus: VoiceProcessingHardwareStatus = .inactive
    @Published public private(set) var systemMicrophoneMode: SystemMicrophoneIsolationMode = .standard
    @Published public private(set) var liveLevels: CodexOrbAudioLevels = .zero
    @Published public private(set) var lastFault: String?
    @Published public private(set) var lifecycleState: AudioEngineLifecycleState = .idle
    @Published public private(set) var lastOperation: AudioEngineOperationKind = .none
    @Published public private(set) var lastFailure: AudioEngineFailureRecord?
    @Published public private(set) var activeVPIOEnabled: Bool = false
    @Published public private(set) var isTapInstalled: Bool = false
    @Published public private(set) var attachedNodeGraphSummary: String = "Inativo (sem nós)"
    @Published public private(set) var audioUnitStateSummary: String = "Não inicializado"
    @Published public private(set) var restartCount: Int = 0
    @Published public private(set) var isUsingSplitEngineFallback: Bool = false

    public let memoryProfile: HardwareMemoryProfile
    public let captureRingBuffer: PreallocatedFloatRingBuffer
    public let outputJitterBuffer: AdaptiveJitterBuffer
    /// Priority-4 playback channel for <100ms cached active-listening backchannels & micro-vocalizations.
    /// Yields immediately to Priority-3 `outputJitterBuffer` (main reply) and Priority-1/2 user speech/barge-in.
    public let auxiliaryVocalizationBuffer: AdaptiveJitterBuffer

    public var onInputAudioChunk: (([Float], Double) -> Void)?
    public var onRawAudioBufferForSpeech: ((AVAudioPCMBuffer) -> Void)?
    public var onDeviceTopologyChanged: (() -> Void)?

    private var engine: AVAudioEngine?
    private var splitCaptureEngine: AVAudioEngine?
    private var outputSourceNode: AVAudioSourceNode?
    private var configObserver: NSObjectProtocol?
    private var splitCaptureConfigObserver: NSObjectProtocol?
    private var deviceListenerInstalled = false
    private var recoveryCount = 0
    private var vpioUnsupportedRoutes: Set<String> = []
    private var wantCapture = false
    private var wantPlayback = false
    private var wantVoiceProcessing = true

    // Serialized lifecycle authority state (prevents concurrent start/stop/reset/recovery races)
    private var lifecycleGeneration: UInt64 = 0
    private var captureCallbackGeneration: UInt64 = 0
    private var activeEngineHasTap = false
    private var activeEngineHasVPIO = false
    private var isApplyingInternalConfiguration = false
    private var lifecycleTailTask: Task<Void, Never>?
    private var pendingRecoveryTask: Task<Void, Never>?
    private var recentRecoveryUptimeNs: [UInt64] = []
    private var lastVPIOTeardownUptimeNs: UInt64 = 0
    private var measuredInputRateHz: Double = 0
    private var measuredInputChannels: Int = 0
    private var measuredOutputRateHz: Double = 0
    private var measuredOutputChannels: Int = 0

    private let processingQueue = DispatchQueue(label: "local.wisdai.voice.audio.dsp", qos: .userInteractive)
    private let renderOutputRate: Double = 24_000
    private let maxAutoRecoveriesInWindow = 3
    private let recoveryWindowNs: UInt64 = 12_000_000_000

    public init(memoryProfile: HardwareMemoryProfile = .detect()) {
        self.memoryProfile = memoryProfile
        self.captureRingBuffer = PreallocatedFloatRingBuffer(
            capacitySamples: Int(48_000 * memoryProfile.maxCaptureRingSeconds)
        )
        self.outputJitterBuffer = AdaptiveJitterBuffer(
            sampleRate: renderOutputRate,
            maxDurationSeconds: memoryProfile.maxOutputJitterSeconds
        )
        self.auxiliaryVocalizationBuffer = AdaptiveJitterBuffer(
            sampleRate: renderOutputRate,
            maxDurationSeconds: 2.0,
            basePrebufferMs: 10.0
        )
        refreshDevices()
        installCoreAudioDeviceObservers()
    }

    deinit {
        if let obs = configObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let splitObs = splitCaptureConfigObserver {
            NotificationCenter.default.removeObserver(splitObs)
        }
    }

    @discardableResult
    public func refreshDevices() -> Bool {
        let prevInUIDs = inputDevices.map(\.uid)
        let prevOutUIDs = outputDevices.map(\.uid)
        let prevDefIn = inputDevices.first(where: \.isDefaultInput)?.uid
        let prevDefOut = outputDevices.first(where: \.isDefaultOutput)?.uid

        let all = CoreAudioDeviceCatalog.enumerateDevices()
        inputDevices = all.filter { $0.inputChannels > 0 }
        outputDevices = all.filter { $0.outputChannels > 0 }
        systemMicrophoneMode = CoreAudioDeviceCatalog.currentSystemMicrophoneMode()

        if selectedInputDeviceUID == nil || !inputDevices.contains(where: { $0.uid == selectedInputDeviceUID }) {
            let defIn = inputDevices.first(where: \.isDefaultInput)
            if let defIn, defIn.transport != .continuityOrVirtual {
                selectedInputDeviceUID = defIn.uid
            } else {
                selectedInputDeviceUID = inputDevices.first(where: { $0.transport == .builtIn || $0.transport == .usb || $0.transport == .bluetooth })?.uid
                    ?? defIn?.uid
                    ?? inputDevices.first?.uid
            }
        }
        if selectedOutputDeviceUID == nil || !outputDevices.contains(where: { $0.uid == selectedOutputDeviceUID }) {
            let defOut = outputDevices.first(where: \.isDefaultOutput)
            if let defOut, defOut.transport != .continuityOrVirtual {
                selectedOutputDeviceUID = defOut.uid
            } else {
                selectedOutputDeviceUID = outputDevices.first(where: { $0.transport != .continuityOrVirtual })?.uid
                    ?? defOut?.uid
                    ?? outputDevices.first?.uid
            }
        }

        let newDefIn = inputDevices.first(where: \.isDefaultInput)?.uid
        let newDefOut = outputDevices.first(where: \.isDefaultOutput)?.uid
        return prevInUIDs != inputDevices.map(\.uid)
            || prevOutUIDs != outputDevices.map(\.uid)
            || prevDefIn != newDefIn
            || prevDefOut != newDefOut
    }

    public func selectInputDevice(uid: String) {
        guard !uid.isEmpty, selectedInputDeviceUID != uid else { return }
        selectedInputDeviceUID = uid
        if isRunning || lifecycleState == .recovering || lifecycleState == .reconfiguring {
            scheduleEngineRecovery(reason: "Troca de dispositivo de entrada", resetBudget: true)
        }
    }

    public func selectOutputDevice(uid: String) {
        guard !uid.isEmpty, selectedOutputDeviceUID != uid else { return }
        selectedOutputDeviceUID = uid
        if isRunning || lifecycleState == .recovering || lifecycleState == .reconfiguring {
            scheduleEngineRecovery(reason: "Troca de dispositivo de saída", resetBudget: true)
        }
    }

    public static func microphonePermissionAuthorized() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    public static func requestMicrophonePermissionIfNeeded() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    public func startFullDuplex(enableCapture: Bool = true, enablePlayback: Bool = true, enableVoiceProcessing: Bool = true) throws {
        pendingRecoveryTask?.cancel()
        pendingRecoveryTask = nil
        lifecycleGeneration &+= 1
        let expectedGen = lifecycleGeneration
        if isRunning {
            restartCount += 1
        }
        wantCapture = enableCapture
        wantPlayback = enablePlayback
        wantVoiceProcessing = enableVoiceProcessing
        try performStartupSequenceSync(
            enableCapture: enableCapture,
            enablePlayback: enablePlayback,
            enableVoiceProcessing: enableVoiceProcessing,
            expectedGeneration: expectedGen
        )
    }

    /// Serialized non-blocking startup that enforces single lifecycle ownership,
    /// pre-validates CoreAudio devices & formats, awaits HAL recovery safely,
    /// fixes VPIO graph order, and degrades cleanly to split-engine compatibility when required.
    public func startFullDuplexAsync(enableCapture: Bool = true, enablePlayback: Bool = true, enableVoiceProcessing: Bool = true) async throws {
        pendingRecoveryTask?.cancel()
        pendingRecoveryTask = nil
        lifecycleGeneration &+= 1
        let myGeneration = lifecycleGeneration
        try await runSerializedLifecycleOperation { [weak self] in
            guard let self else { throw CancellationError() }
            guard self.lifecycleGeneration == myGeneration else { throw CancellationError() }
            if self.isRunning {
                self.restartCount += 1
            }
            self.wantCapture = enableCapture
            self.wantPlayback = enablePlayback
            self.wantVoiceProcessing = enableVoiceProcessing
            try await self.performStartupSequenceAsync(
                enableCapture: enableCapture,
                enablePlayback: enablePlayback,
                enableVoiceProcessing: enableVoiceProcessing,
                expectedGeneration: myGeneration
            )
        }
    }

    private func runSerializedLifecycleOperation(_ work: @escaping @MainActor () async throws -> Void) async throws {
        let previous = lifecycleTailTask
        var capturedError: Error?
        let next = Task { @MainActor in
            if let previous {
                _ = await previous.result
            }
            do {
                try await work()
            } catch {
                capturedError = error
            }
        }
        lifecycleTailTask = next
        await next.value
        if let capturedError {
            throw capturedError
        }
    }

    private func validateHardwarePreconditions(
        enableCapture: Bool,
        enablePlayback: Bool
    ) throws -> (inputDev: AudioDeviceDescriptor?, outputDev: AudioDeviceDescriptor?) {
        if enableCapture {
            lastOperation = .validatePermissions
            guard Self.microphonePermissionAuthorized() else {
                let err = NSError(
                    domain: "VoiceNativeAudioEngine",
                    code: -12937,
                    userInfo: [NSLocalizedDescriptionKey: "Permissão de microfone macOS não autorizada."]
                )
                recordFailure(operation: .validatePermissions, error: err)
                throw err
            }
        }

        lastOperation = .validateDevices
        lifecycleState = .validatingDevices
        _ = refreshDevices()

        let activeOutDev = outputDevices.first(where: { $0.uid == selectedOutputDeviceUID }) ?? outputDevices.first(where: \.isDefaultOutput)
        let activeInDev = inputDevices.first(where: { $0.uid == selectedInputDeviceUID }) ?? inputDevices.first(where: \.isDefaultInput)

        if enableCapture {
            guard let inDev = activeInDev,
                  CoreAudioDeviceCatalog.isDeviceAlive(deviceID: inDev.id),
                  inDev.inputChannels > 0,
                  CoreAudioDeviceCatalog.nominalSampleRate(deviceID: inDev.id) > 0 else {
                let err = NSError(
                    domain: "VoiceNativeAudioEngine",
                    code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "Nenhum microfone ativo com formato de áudio válido foi encontrado."]
                )
                recordFailure(operation: .validateDevices, error: err)
                throw err
            }
        }
        if enablePlayback {
            guard let outDev = activeOutDev,
                  CoreAudioDeviceCatalog.isDeviceAlive(deviceID: outDev.id),
                  outDev.outputChannels > 0,
                  CoreAudioDeviceCatalog.nominalSampleRate(deviceID: outDev.id) > 0 else {
                let err = NSError(
                    domain: "VoiceNativeAudioEngine",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Nenhum dispositivo de saída de áudio ativo com formato válido foi encontrado."]
                )
                recordFailure(operation: .validateDevices, error: err)
                throw err
            }
        }
        return (activeInDev, activeOutDev)
    }

    private func recordFailure(operation: AudioEngineOperationKind, error: Error) {
        let rec = AudioEngineFailureRecord(operation: operation, error: error)
        lastFailure = rec
        lastOperation = operation
        audioUnitStateSummary = "Falha: OSStatus=\(rec.osStatus) em \(operation.rawValue)"
    }

    private func waitForHALFormatsReady(
        requireCapture: Bool,
        requirePlayback: Bool,
        maxWaitMs: Int,
        expectedGeneration: UInt64
    ) async throws {
        lastOperation = .waitHALReady
        lifecycleState = .waitingHALRecovery

        // Check if we recently tore down VPIO (which puts CoreAudio HAL output into 0Hz/0ch transiently)
        let nowNs = DispatchTime.now().uptimeNanoseconds
        let needsSettleAfterVPIO = lastVPIOTeardownUptimeNs > 0 && (nowNs &- lastVPIOTeardownUptimeNs) < 900_000_000

        let steps = max(1, maxWaitMs / 40)
        for step in 0..<steps {
            guard lifecycleGeneration == expectedGeneration, !Task.isCancelled else {
                throw CancellationError()
            }
            if step == 0 && !needsSettleAfterVPIO {
                if halProbeFormatsValid(requireCapture: requireCapture, requirePlayback: requirePlayback) {
                    return
                }
            } else if step > 0 || !needsSettleAfterVPIO {
                if halProbeFormatsValid(requireCapture: requireCapture, requirePlayback: requirePlayback) {
                    return
                }
            }
            try await Task.sleep(nanoseconds: 40_000_000)
        }
    }

    private func halProbeFormatsValid(requireCapture: Bool, requirePlayback: Bool) -> Bool {
        let probe = AVAudioEngine()
        if requirePlayback {
            let outFmt = probe.outputNode.outputFormat(forBus: 0)
            guard outFmt.sampleRate > 0 && outFmt.channelCount > 0 else { return false }
        }
        if requireCapture {
            let inFmt = probe.inputNode.outputFormat(forBus: 0)
            guard inFmt.sampleRate > 0 && inFmt.channelCount > 0 else { return false }
        }
        return true
    }

    private func performStartupSequenceSync(
        enableCapture: Bool,
        enablePlayback: Bool,
        enableVoiceProcessing: Bool,
        expectedGeneration: UInt64
    ) throws {
        teardownEnginesCleanly()
        let devs = try validateHardwarePreconditions(enableCapture: enableCapture, enablePlayback: enablePlayback)
        guard lifecycleGeneration == expectedGeneration else { throw CancellationError() }

        let activeInDev = devs.inputDev
        let activeOutDev = devs.outputDev
        let routeKey = "\(activeInDev?.uid ?? "none")|\(activeOutDev?.uid ?? "none")"
        let isBluetoothRoute = (activeInDev?.isBluetooth == true) || (activeOutDev?.isBluetooth == true)
        let isVirtualOrContinuity = (activeInDev?.transport == .continuityOrVirtual) || (activeOutDev?.transport == .continuityOrVirtual)
        let allowVP = enableVoiceProcessing && enableCapture && !isBluetoothRoute && !isVirtualOrContinuity && !vpioUnsupportedRoutes.contains(routeKey)

        if enableCapture && enablePlayback && isVirtualOrContinuity {
            do {
                try configureAndStartSplitEngines(
                    inputDev: activeInDev,
                    outputDev: activeOutDev,
                    expectedGeneration: expectedGeneration
                )
                lastFault = "Modo de compatibilidade separado (Continuity/Virtual) sem AEC hardware VPIO; supressão acústica por software ativa."
                return
            } catch {
                // Fall through to built-in fallback below
                try attemptBuiltInFallbackIfDistinct(
                    failedIn: activeInDev,
                    failedOut: activeOutDev,
                    enableCapture: enableCapture,
                    enablePlayback: enablePlayback,
                    enableVoiceProcessing: enableVoiceProcessing,
                    primaryError: error,
                    expectedGeneration: expectedGeneration
                )
                return
            }
        }

        do {
            try configureAndStartSingleEngine(
                enableCapture: enableCapture,
                enablePlayback: enablePlayback,
                tryVoiceProcessing: allowVP,
                inputDeviceID: activeInDev?.id,
                outputDeviceID: activeOutDev?.id,
                expectedGeneration: expectedGeneration
            )
            lastFailure = nil
            if !allowVP && enableVoiceProcessing && (isBluetoothRoute || vpioUnsupportedRoutes.contains(routeKey)) {
                lastFault = "AEC hardware VPIO indisponível nesta rota; modo de compatibilidade com supressão acústica por software ativo."
            } else {
                lastFault = nil
            }
        } catch {
            if allowVP {
                vpioUnsupportedRoutes.insert(routeKey)
                let firstError = error.localizedDescription
                teardownEnginesCleanly()
                Thread.sleep(forTimeInterval: 0.12)
                do {
                    try configureAndStartSingleEngine(
                        enableCapture: enableCapture,
                        enablePlayback: enablePlayback,
                        tryVoiceProcessing: false,
                        inputDeviceID: activeInDev?.id,
                        outputDeviceID: activeOutDev?.id,
                        expectedGeneration: expectedGeneration
                    )
                    lastFailure = nil
                    lastFault = "AEC hardware VPIO indisponível (\(firstError)); supressão acústica por software ativa."
                    return
                } catch let fallbackErr {
                    if enableCapture && enablePlayback {
                        teardownEnginesCleanly()
                        Thread.sleep(forTimeInterval: 0.08)
                        do {
                            try configureAndStartSplitEngines(
                                inputDev: activeInDev,
                                outputDev: activeOutDev,
                                expectedGeneration: expectedGeneration
                            )
                            lastFailure = nil
                            lastFault = "Modo de compatibilidade separado ativo após recusa duplex VPIO/AUHAL (\(fallbackErr.localizedDescription))."
                            return
                        } catch let splitErr {
                            try attemptBuiltInFallbackIfDistinct(
                                failedIn: activeInDev,
                                failedOut: activeOutDev,
                                enableCapture: enableCapture,
                                enablePlayback: enablePlayback,
                                enableVoiceProcessing: enableVoiceProcessing,
                                primaryError: splitErr,
                                expectedGeneration: expectedGeneration
                            )
                            return
                        }
                    }
                    lifecycleState = .failed
                    lastFault = "Falha VPIO (\(firstError)) e fallback (\(fallbackErr.localizedDescription))."
                    throw fallbackErr
                }
            } else if enableCapture && enablePlayback {
                teardownEnginesCleanly()
                Thread.sleep(forTimeInterval: 0.08)
                do {
                    try configureAndStartSplitEngines(
                        inputDev: activeInDev,
                        outputDev: activeOutDev,
                        expectedGeneration: expectedGeneration
                    )
                    lastFailure = nil
                    lastFault = "Modo de compatibilidade separado ativo (dispositivos independentes; AEC por software)."
                    return
                } catch let splitErr {
                    try attemptBuiltInFallbackIfDistinct(
                        failedIn: activeInDev,
                        failedOut: activeOutDev,
                        enableCapture: enableCapture,
                        enablePlayback: enablePlayback,
                        enableVoiceProcessing: enableVoiceProcessing,
                        primaryError: splitErr,
                        expectedGeneration: expectedGeneration
                    )
                    return
                }
            } else {
                lifecycleState = .failed
                lastFault = error.localizedDescription
                throw error
            }
        }
    }

    private func attemptBuiltInFallbackIfDistinct(
        failedIn: AudioDeviceDescriptor?,
        failedOut: AudioDeviceDescriptor?,
        enableCapture: Bool,
        enablePlayback: Bool,
        enableVoiceProcessing: Bool,
        primaryError: Error,
        expectedGeneration: UInt64
    ) throws {
        let builtInIn = inputDevices.first(where: { $0.transport == .builtIn }) ?? inputDevices.first(where: \.isDefaultInput)
        let builtInOut = outputDevices.first(where: { $0.transport == .builtIn }) ?? outputDevices.first(where: \.isDefaultOutput)
        let isDistinct = (builtInIn?.id != failedIn?.id) || (builtInOut?.id != failedOut?.id)
        guard isDistinct else {
            lifecycleState = .failed
            lastFault = primaryError.localizedDescription
            throw primaryError
        }
        teardownEnginesCleanly()
        do {
            try configureAndStartSingleEngine(
                enableCapture: enableCapture,
                enablePlayback: enablePlayback,
                tryVoiceProcessing: enableVoiceProcessing && enableCapture,
                inputDeviceID: builtInIn?.id,
                outputDeviceID: builtInOut?.id,
                expectedGeneration: expectedGeneration
            )
            if let uid = builtInIn?.uid { selectedInputDeviceUID = uid }
            if let uid = builtInOut?.uid { selectedOutputDeviceUID = uid }
            lastFailure = nil
            lastFault = "Dispositivo anterior recusou inicialização (\(primaryError.localizedDescription)); restaurado para hardware integrado do Mac."
        } catch {
            lifecycleState = .failed
            lastFault = error.localizedDescription
            throw error
        }
    }

    private func performStartupSequenceAsync(
        enableCapture: Bool,
        enablePlayback: Bool,
        enableVoiceProcessing: Bool,
        expectedGeneration: UInt64
    ) async throws {
        teardownEnginesCleanly()
        let devs = try validateHardwarePreconditions(enableCapture: enableCapture, enablePlayback: enablePlayback)
        guard lifecycleGeneration == expectedGeneration, !Task.isCancelled else { throw CancellationError() }

        let activeInDev = devs.inputDev
        let activeOutDev = devs.outputDev
        let routeKey = "\(activeInDev?.uid ?? "none")|\(activeOutDev?.uid ?? "none")"
        let isBluetoothRoute = (activeInDev?.isBluetooth == true) || (activeOutDev?.isBluetooth == true)
        let isVirtualOrContinuity = (activeInDev?.transport == .continuityOrVirtual) || (activeOutDev?.transport == .continuityOrVirtual)
        let allowVP = enableVoiceProcessing && enableCapture && !isBluetoothRoute && !isVirtualOrContinuity && !vpioUnsupportedRoutes.contains(routeKey)

        try await waitForHALFormatsReady(
            requireCapture: enableCapture,
            requirePlayback: enablePlayback,
            maxWaitMs: 1200,
            expectedGeneration: expectedGeneration
        )
        guard lifecycleGeneration == expectedGeneration, !Task.isCancelled else { throw CancellationError() }

        // Continuity / Virtual inputs paired with separate Mac speakers require independent engines on macOS AUHAL
        if enableCapture && enablePlayback && isVirtualOrContinuity {
            do {
                try configureAndStartSplitEngines(
                    inputDev: activeInDev,
                    outputDev: activeOutDev,
                    expectedGeneration: expectedGeneration
                )
                lastFailure = nil
                lastFault = "Modo de compatibilidade separado (Continuity/Virtual) sem AEC hardware VPIO; supressão acústica por software ativa."
                return
            } catch let splitErr {
                try attemptBuiltInFallbackIfDistinct(
                    failedIn: activeInDev,
                    failedOut: activeOutDev,
                    enableCapture: enableCapture,
                    enablePlayback: enablePlayback,
                    enableVoiceProcessing: enableVoiceProcessing,
                    primaryError: splitErr,
                    expectedGeneration: expectedGeneration
                )
                return
            }
        }

        do {
            try configureAndStartSingleEngine(
                enableCapture: enableCapture,
                enablePlayback: enablePlayback,
                tryVoiceProcessing: allowVP,
                inputDeviceID: activeInDev?.id,
                outputDeviceID: activeOutDev?.id,
                expectedGeneration: expectedGeneration
            )
            lastFailure = nil
            if !allowVP && enableVoiceProcessing && (isBluetoothRoute || vpioUnsupportedRoutes.contains(routeKey)) {
                lastFault = "AEC hardware VPIO indisponível nesta rota; supressão acústica por software ativa."
            } else {
                lastFault = nil
            }
        } catch let firstErr {
            if allowVP {
                vpioUnsupportedRoutes.insert(routeKey)
                teardownEnginesCleanly()
                try await waitForHALFormatsReady(
                    requireCapture: enableCapture,
                    requirePlayback: enablePlayback,
                    maxWaitMs: 1200,
                    expectedGeneration: expectedGeneration
                )
                guard lifecycleGeneration == expectedGeneration, !Task.isCancelled else { throw CancellationError() }
                do {
                    try configureAndStartSingleEngine(
                        enableCapture: enableCapture,
                        enablePlayback: enablePlayback,
                        tryVoiceProcessing: false,
                        inputDeviceID: activeInDev?.id,
                        outputDeviceID: activeOutDev?.id,
                        expectedGeneration: expectedGeneration
                    )
                    lastFailure = nil
                    lastFault = "AEC hardware VPIO indisponível (\(firstErr.localizedDescription)); supressão acústica por software ativa."
                    return
                } catch let fallbackErr {
                    if enableCapture && enablePlayback {
                        teardownEnginesCleanly()
                        try await waitForHALFormatsReady(
                            requireCapture: enableCapture,
                            requirePlayback: enablePlayback,
                            maxWaitMs: 900,
                            expectedGeneration: expectedGeneration
                        )
                        guard lifecycleGeneration == expectedGeneration, !Task.isCancelled else { throw CancellationError() }
                        do {
                            try configureAndStartSplitEngines(
                                inputDev: activeInDev,
                                outputDev: activeOutDev,
                                expectedGeneration: expectedGeneration
                            )
                            lastFailure = nil
                            lastFault = "Modo de compatibilidade separado ativo após recusa duplex (\(fallbackErr.localizedDescription))."
                            return
                        } catch let splitErr {
                            try attemptBuiltInFallbackIfDistinct(
                                failedIn: activeInDev,
                                failedOut: activeOutDev,
                                enableCapture: enableCapture,
                                enablePlayback: enablePlayback,
                                enableVoiceProcessing: enableVoiceProcessing,
                                primaryError: splitErr,
                                expectedGeneration: expectedGeneration
                            )
                            return
                        }
                    }
                    lifecycleState = .failed
                    lastFault = "Falha primária VPIO (\(firstErr.localizedDescription)) e falha padrão (\(fallbackErr.localizedDescription))."
                    throw fallbackErr
                }
            } else if enableCapture && enablePlayback {
                teardownEnginesCleanly()
                try await waitForHALFormatsReady(
                    requireCapture: enableCapture,
                    requirePlayback: enablePlayback,
                    maxWaitMs: 900,
                    expectedGeneration: expectedGeneration
                )
                guard lifecycleGeneration == expectedGeneration, !Task.isCancelled else { throw CancellationError() }
                do {
                    try configureAndStartSplitEngines(
                        inputDev: activeInDev,
                        outputDev: activeOutDev,
                        expectedGeneration: expectedGeneration
                    )
                    lastFailure = nil
                    lastFault = "Modo de compatibilidade separado ativo (rotas independentes; AEC por software)."
                    return
                } catch let splitErr {
                    try attemptBuiltInFallbackIfDistinct(
                        failedIn: activeInDev,
                        failedOut: activeOutDev,
                        enableCapture: enableCapture,
                        enablePlayback: enablePlayback,
                        enableVoiceProcessing: enableVoiceProcessing,
                        primaryError: splitErr,
                        expectedGeneration: expectedGeneration
                    )
                    return
                }
            } else {
                lifecycleState = .failed
                lastFault = firstErr.localizedDescription
                throw firstErr
            }
        }
    }

    public func testAudioPlaybackTone() async -> (ok: Bool, detail: String, latencyMs: Double) {
        let t0 = DispatchTime.now().uptimeNanoseconds
        let wasRunning = isRunning
        let prevCapture = wantCapture
        let prevPlayback = wantPlayback
        let prevVP = wantVoiceProcessing

        if !wasRunning || !prevPlayback {
            do {
                try await startFullDuplexAsync(enableCapture: prevCapture && wasRunning, enablePlayback: true, enableVoiceProcessing: false)
            } catch {
                return (false, "Falha ao iniciar reprodução: \(error.localizedDescription)", 0)
            }
        }

        let startPlayed = outputJitterBuffer.stats.playedMs
        let sr = 24_000.0
        let durationSec = 0.26
        let count = Int(sr * durationSec)
        var tone = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / sr
            let env = Float(min(1.0, min(t / 0.02, (durationSec - t) / 0.05)))
            let sig = sin(2.0 * .pi * 523.25 * t) * 0.55 + sin(2.0 * .pi * 659.25 * t) * 0.45
            tone[i] = Float(sig) * 0.14 * env
        }
        _ = outputJitterBuffer.pushFloatSamples(tone, transcriptText: nil)

        try? await Task.sleep(nanoseconds: 340_000_000)
        let deltaPlayed = outputJitterBuffer.stats.playedMs - startPlayed
        let latencyMs = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000.0

        if !wasRunning {
            stop()
        } else if !prevPlayback {
            try? await startFullDuplexAsync(enableCapture: prevCapture, enablePlayback: prevPlayback, enableVoiceProcessing: prevVP)
        }

        let outName = outputDevices.first(where: { $0.uid == selectedOutputDeviceUID })?.name ?? "Saída padrão"
        if deltaPlayed >= 40.0 {
            return (true, String(format: "Áudio reproduzido em '%@' (%.0f ms renderizados).", outName, deltaPlayed), latencyMs)
        }
        return (false, "Buffer enviado mas callback CoreAudio em '\(outName)' não drenou frames (playedMs=+\(String(format: "%.1f", deltaPlayed))).", latencyMs)
    }

    public func testMicrophoneSignalProbe(durationSeconds: Double = 0.85) async -> (ok: Bool, peakRMS: Float, framesCaptured: Int, detail: String) {
        let wasRunning = isRunning
        let prevCapture = wantCapture
        let prevPlayback = wantPlayback
        let prevVP = wantVoiceProcessing

        if !wasRunning || !prevCapture {
            do {
                try await startFullDuplexAsync(enableCapture: true, enablePlayback: prevPlayback && wasRunning, enableVoiceProcessing: false)
            } catch {
                return (false, 0, 0, "Falha ao abrir captura do microfone: \(error.localizedDescription)")
            }
        }

        let initialSamples = captureRingBuffer.totalWrittenSamples
        var peak: Float = liveLevels.micLevel
        let steps = max(4, Int(durationSeconds / 0.08))
        for _ in 0..<steps {
            try? await Task.sleep(nanoseconds: 80_000_000)
            peak = max(peak, liveLevels.micLevel)
        }
        let deltaSamples = Int(captureRingBuffer.totalWrittenSamples &- initialSamples)
        let inName = inputDevices.first(where: { $0.uid == selectedInputDeviceUID })?.name ?? "Microfone padrão"

        if !wasRunning {
            stop()
        } else if !prevCapture {
            try? await startFullDuplexAsync(enableCapture: prevCapture, enablePlayback: prevPlayback, enableVoiceProcessing: prevVP)
        }

        if deltaSamples > 0 {
            return (true, peak, deltaSamples, "Microfone '\(inName)' ativo: \(deltaSamples) amostras capturadas (pico=\(String(format: "%.3f", peak))).")
        }
        return (false, peak, 0, "Nenhuma amostra recebida do microfone '\(inName)' durante \(String(format: "%.1fs", durationSeconds)).")
    }

    public func stop() {
        pendingRecoveryTask?.cancel()
        pendingRecoveryTask = nil
        lifecycleGeneration &+= 1
        wantCapture = false
        wantPlayback = false
        lifecycleState = .stopping
        lastOperation = .stopEngine
        teardownEnginesCleanly()
        captureRingBuffer.flush()
        _ = outputJitterBuffer.flushAndCaptureHeardSnapshot()
        _ = auxiliaryVocalizationBuffer.flushAndCaptureHeardSnapshot()
        processingStatus = .inactive
        activeVPIOEnabled = false
        isTapInstalled = false
        isUsingSplitEngineFallback = false
        attachedNodeGraphSummary = "Inativo (sem nós)"
        audioUnitStateSummary = "Parado"
        lifecycleState = .idle
        liveLevels = .zero
    }

    @discardableResult
    public func bargeInFlushPlayback() -> JitterBufferFlushSnapshot {
        _ = auxiliaryVocalizationBuffer.flushAndCaptureHeardSnapshot()
        return outputJitterBuffer.flushAndCaptureHeardSnapshot()
    }

    public func flushAuxiliaryVocalizationOnly() {
        _ = auxiliaryVocalizationBuffer.flushAndCaptureHeardSnapshot()
    }

    /// Enqueues a pre-warmed cached vocalization (Priority 4) without resetting main reply history.
    /// Returns false if main assistant response audio is currently buffered/active (no overlap permitted).
    @discardableResult
    public func enqueueAuxiliaryVocalization(_ samples24k: [Float], label: String? = nil) -> Bool {
        guard !samples24k.isEmpty else { return false }
        let mainState = outputJitterBuffer.playbackReferenceState
        guard mainState.bufferedMs <= 12.0 && mainState.renderAgeMs >= 90.0 else {
            return false
        }
        auxiliaryVocalizationBuffer.resetForNewResponse()
        _ = auxiliaryVocalizationBuffer.pushFloatSamples(samples24k, transcriptText: label)
        return true
    }

    public var isAuxiliaryPlaybackActive: Bool {
        let ref = auxiliaryVocalizationBuffer.playbackReferenceState
        return ref.bufferedMs > 2.0 || (ref.renderAgeMs < 95.0 && ref.renderedRMS > 0.002)
    }

    public var combinedPlaybackReferenceState: (bufferedMs: Double, renderedRMS: Float, renderAgeMs: Double, isAuxiliaryOnly: Bool) {
        let mainRef = outputJitterBuffer.playbackReferenceState
        let auxRef = auxiliaryVocalizationBuffer.playbackReferenceState
        let mainActive = mainRef.bufferedMs > 1.0 || mainRef.renderAgeMs < 140.0
        if mainActive || mainRef.renderedRMS >= auxRef.renderedRMS {
            return (
                bufferedMs: max(mainRef.bufferedMs, auxRef.bufferedMs),
                renderedRMS: max(mainRef.renderedRMS, auxRef.renderedRMS),
                renderAgeMs: min(mainRef.renderAgeMs, auxRef.renderAgeMs),
                isAuxiliaryOnly: !mainActive && (auxRef.bufferedMs > 1.0 || auxRef.renderAgeMs < 140.0)
            )
        }
        return (auxRef.bufferedMs, auxRef.renderedRMS, auxRef.renderAgeMs, true)
    }

    public var currentOutputHardwareLatencyMs: Double {
        let activeOutID = outputDevices.first(where: { $0.uid == selectedOutputDeviceUID })?.id
        return CoreAudioDeviceCatalog.outputDeviceLatencyMs(deviceID: activeOutID)
    }

    public func telemetrySnapshot() -> AudioEngineRuntimeTelemetry {
        let jStats = outputJitterBuffer.stats
        let inDev = inputDevices.first(where: { $0.uid == selectedInputDeviceUID })
        let outDev = outputDevices.first(where: { $0.uid == selectedOutputDeviceUID })
        let inName = inDev?.name ?? "Padrão"
        let outName = outDev?.name ?? "Padrão"
        let liveOutRate = isRunning ? (measuredOutputRateHz > 0 ? measuredOutputRateHz : (outDev?.nominalSampleRate ?? 48_000)) : (outDev?.nominalSampleRate ?? 48_000)
        let liveOutCh = isRunning ? measuredOutputChannels : (outDev?.outputChannels ?? 0)
        let liveInRate = isRunning ? (measuredInputRateHz > 0 ? measuredInputRateHz : (inDev?.nominalSampleRate ?? 48_000)) : (inDev?.nominalSampleRate ?? 0)
        let liveInCh = isRunning ? measuredInputChannels : (inDev?.inputChannels ?? 0)

        return AudioEngineRuntimeTelemetry(
            isRunning: isRunning,
            isFullDuplex: wantCapture && wantPlayback,
            hardwareSampleRate: liveOutRate,
            processingStatus: processingStatus,
            systemMicMode: systemMicrophoneMode,
            inputDeviceName: inName,
            outputDeviceName: outName,
            captureDroppedSamples: captureRingBuffer.droppedSamples,
            outputUnderruns: jStats.underruns,
            outputOverflows: jStats.overflows,
            outputBufferedMs: jStats.bufferedMs,
            outputTargetPrebufferMs: jStats.targetPrebufferMs,
            recoveryCount: recoveryCount,
            lastFaultDescription: lastFault,
            lifecycleState: lifecycleState,
            audioUnitState: audioUnitStateSummary,
            inputSampleRateHz: liveInRate,
            inputChannels: liveInCh,
            outputSampleRateHz: liveOutRate,
            outputChannels: liveOutCh,
            vpioActive: activeVPIOEnabled,
            tapInstalled: isTapInstalled,
            nodeGraphSummary: attachedNodeGraphSummary,
            lastOperation: lastOperation,
            lastFailure: lastFailure,
            restartCount: restartCount,
            isSplitEngineCompatibility: isUsingSplitEngineFallback
        )
    }

    private func makeOutputSourceNode(sourceFmt: AVAudioFormat) -> AVAudioSourceNode {
        let jitterRef = outputJitterBuffer
        let auxJitterRef = auxiliaryVocalizationBuffer
        var scratch = [Float](repeating: 0, count: 4096)
        var auxScratch = [Float](repeating: 0, count: 4096)

        return AVAudioSourceNode(format: sourceFmt) { _, _, frameCount, audioBufferList -> OSStatus in
            let frames = Int(frameCount)
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let firstBuf = abl.first, let outPtr = firstBuf.mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            let needed = min(frames, scratch.count)
            var rms: Float = 0
            let pulledMain = scratch.withUnsafeMutableBufferPointer { buf in
                guard let base = buf.baseAddress else { return 0 }
                return jitterRef.renderPull(into: base, frameCount: needed, outputLevelOut: &rms)
            }
            if pulledMain > 0 {
                // Priority 3 (main reply) strictly suppresses Priority 4 (auxiliary backchannel).
                if auxJitterRef.stats.bufferedMs > 0 {
                    _ = auxJitterRef.flushAndCaptureHeardSnapshot()
                }
                outPtr.update(from: scratch, count: pulledMain)
                if frames > pulledMain {
                    outPtr.advanced(by: pulledMain).initialize(repeating: 0, count: frames - pulledMain)
                }
                return noErr
            }

            var auxRms: Float = 0
            let pulledAux = auxScratch.withUnsafeMutableBufferPointer { buf in
                guard let base = buf.baseAddress else { return 0 }
                return auxJitterRef.renderPull(into: base, frameCount: needed, outputLevelOut: &auxRms)
            }
            if pulledAux > 0 {
                outPtr.update(from: auxScratch, count: pulledAux)
            }
            if frames > pulledAux {
                outPtr.advanced(by: pulledAux).initialize(repeating: 0, count: frames - pulledAux)
            }
            return noErr
        }
    }

    private func installCaptureTap(on inputNode: AVAudioInputNode, captureGen: UInt64) {
        let ringRef = captureRingBuffer
        let dspQueue = processingQueue

        // Guard against format-mismatch NSException by passing nil when tapping hardware bus.
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let chData = buffer.floatChannelData else { return }
            let n = Int(buffer.frameLength)
            guard n > 0 else { return }
            ringRef.push(samples: chData[0], count: n)

            let copied = AudioPCMConverter.mixToMono(buffer: buffer)
            let sr = buffer.format.sampleRate
            dspQueue.async { [weak self] in
                let levels = AudioPCMConverter.measureLevels(samples: copied)
                let jBuffered = self?.outputJitterBuffer.stats.bufferedMs ?? 0
                let outActiveLevel: Float = jBuffered > 1.0 ? max(0.18, levels.mid) : 0
                let normMic = min(1.0, levels.rms * 5.2)
                let orb = CodexOrbAudioLevels(
                    overall: max(normMic, outActiveLevel),
                    low: levels.low,
                    mid: levels.mid,
                    high: levels.high,
                    micLevel: normMic
                )
                Task { @MainActor [weak self] in
                    guard let self,
                          self.isRunning,
                          self.captureCallbackGeneration == captureGen else { return }
                    self.liveLevels = orb
                    // Always update VAD + echo reference BEFORE forwarding raw audio to STT.
                    self.onInputAudioChunk?(copied, sr)
                    self.onRawAudioBufferForSpeech?(buffer)
                }
            }
        }
    }

    private func configureAndStartSingleEngine(
        enableCapture: Bool,
        enablePlayback: Bool,
        tryVoiceProcessing: Bool,
        inputDeviceID: AudioDeviceID?,
        outputDeviceID: AudioDeviceID?,
        expectedGeneration: UInt64
    ) throws {
        guard lifecycleGeneration == expectedGeneration else { throw CancellationError() }

        lifecycleState = .preparingGraph
        let newEngine = AVAudioEngine()
        var vpEnabled = false
        var installedTap = false

        func cleanupFailedEngine() {
            if installedTap {
                newEngine.inputNode.removeTap(onBus: 0)
            }
            newEngine.stop()
            if vpEnabled {
                try? newEngine.inputNode.setVoiceProcessingEnabled(false)
                lastVPIOTeardownUptimeNs = DispatchTime.now().uptimeNanoseconds
            }
            newEngine.reset()
        }

        let systemDefaultOut = CoreAudioDeviceCatalog.defaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice)
        let systemDefaultIn = CoreAudioDeviceCatalog.defaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice)

        if enablePlayback, let outID = outputDeviceID, outID != 0, outID != systemDefaultOut {
            lastOperation = .bindAudioUnitDevice
            let st = applyAudioUnitDevice(outID, to: newEngine.outputNode)
            if st != noErr {
                let err = NSError(domain: NSOSStatusErrorDomain, code: Int(st), userInfo: [NSLocalizedDescriptionKey: "Falha ao selecionar dispositivo de saída no AudioUnit (OSStatus \(st))."])
                recordFailure(operation: .bindAudioUnitDevice, error: err)
                cleanupFailedEngine()
                throw err
            }
        }
        if enableCapture, let inID = inputDeviceID, inID != 0, inID != systemDefaultIn {
            lastOperation = .bindAudioUnitDevice
            let st = applyAudioUnitDevice(inID, to: newEngine.inputNode)
            if st != noErr {
                let err = NSError(domain: NSOSStatusErrorDomain, code: Int(st), userInfo: [NSLocalizedDescriptionKey: "Falha ao selecionar microfone no AudioUnit (OSStatus \(st))."])
                recordFailure(operation: .bindAudioUnitDevice, error: err)
                cleanupFailedEngine()
                throw err
            }
        }

        // CRITICAL macOS CoreAudio/AVFAudio graph rule:
        // Attach & connect output AVAudioSourceNode -> mainMixerNode FIRST before calling
        // `inputNode.setVoiceProcessingEnabled(true)` so VPIO builds its aggregate output graph
        // with valid connected mixer routing instead of failing kAudioUnitErr_FailedInitialization (-10875).
        var attachedSource: AVAudioSourceNode?
        if enablePlayback {
            lastOperation = .attachOutputSource
            guard let sourceFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: renderOutputRate, channels: 1, interleaved: false) else {
                let err = NSError(domain: "VoiceNativeAudioEngine", code: -2, userInfo: [NSLocalizedDescriptionKey: "Formato de saída inválido."])
                recordFailure(operation: .attachOutputSource, error: err)
                cleanupFailedEngine()
                throw err
            }
            let sourceNode = makeOutputSourceNode(sourceFmt: sourceFmt)
            newEngine.attach(sourceNode)
            newEngine.connect(sourceNode, to: newEngine.mainMixerNode, format: sourceFmt)
            _ = newEngine.outputNode.outputFormat(forBus: 0)
            attachedSource = sourceNode
        }

        if enableCapture && tryVoiceProcessing {
            lastOperation = .enableVoiceProcessingIO
            do {
                isApplyingInternalConfiguration = true
                defer { isApplyingInternalConfiguration = false }
                try newEngine.inputNode.setVoiceProcessingEnabled(true)
                newEngine.inputNode.isVoiceProcessingAGCEnabled = true
                newEngine.inputNode.isVoiceProcessingBypassed = false
                vpEnabled = true
            } catch {
                try? newEngine.inputNode.setVoiceProcessingEnabled(false)
                lastVPIOTeardownUptimeNs = DispatchTime.now().uptimeNanoseconds
                recordFailure(operation: .enableVoiceProcessingIO, error: error)
                cleanupFailedEngine()
                throw error
            }
        }

        lastOperation = .validateEngineFormats
        var outFmtSampleRate: Double = 0
        var outFmtChannels: Int = 0
        if enablePlayback {
            let outFmt = newEngine.outputNode.outputFormat(forBus: 0)
            let mixFmt = newEngine.mainMixerNode.outputFormat(forBus: 0)
            guard outFmt.sampleRate > 0, outFmt.channelCount > 0,
                  mixFmt.sampleRate > 0, mixFmt.channelCount > 0 else {
                let err = NSError(domain: "VoiceNativeAudioEngine", code: -2, userInfo: [NSLocalizedDescriptionKey: "Formato de saída CoreAudio inválido (\(outFmt.sampleRate) Hz / \(outFmt.channelCount) ch)."])
                recordFailure(operation: .validateEngineFormats, error: err)
                cleanupFailedEngine()
                throw err
            }
            outFmtSampleRate = outFmt.sampleRate
            outFmtChannels = Int(outFmt.channelCount)
        }

        var inFmtSampleRate: Double = 0
        var inFmtChannels: Int = 0
        if enableCapture {
            let inputNode = newEngine.inputNode
            let hwFormat = inputNode.outputFormat(forBus: 0)
            guard hwFormat.sampleRate > 0 && hwFormat.channelCount > 0 else {
                let err = NSError(domain: "VoiceNativeAudioEngine", code: -3, userInfo: [NSLocalizedDescriptionKey: "Dispositivo de microfone sem formato válido (\(hwFormat.sampleRate) Hz / \(hwFormat.channelCount) ch)."])
                recordFailure(operation: .validateEngineFormats, error: err)
                cleanupFailedEngine()
                throw err
            }
            inFmtSampleRate = hwFormat.sampleRate
            inFmtChannels = Int(hwFormat.channelCount)

            lastOperation = .installInputTap
            captureCallbackGeneration &+= 1
            installCaptureTap(on: inputNode, captureGen: captureCallbackGeneration)
            installedTap = true
        }

        if let obs = configObserver {
            NotificationCenter.default.removeObserver(obs)
            configObserver = nil
        }

        do {
            lifecycleState = .starting
            isApplyingInternalConfiguration = true
            defer { isApplyingInternalConfiguration = false }
            lastOperation = .prepareEngine
            newEngine.prepare()
            lastOperation = .startEngine
            try newEngine.start()
        } catch {
            recordFailure(operation: lastOperation, error: error)
            cleanupFailedEngine()
            throw error
        }

        // IMPORTANT: Register observer with `queue: nil` ONLY AFTER `start()` succeeds.
        // Using `queue: .main` caused an ABBA deadlock between `AVAudioEngine dealloc` (`_dispatch_sync_f_slow`)
        // on the main thread and `IOUnitConfigurationChanged` (`-[NSOperation waitUntilFinished]`) on CoreAudio's engine queue.
        lastOperation = .installConfigObserver
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: newEngine,
            queue: nil
        ) { [weak self, weak newEngine] _ in
            DispatchQueue.main.async {
                guard let self,
                      let newEngine,
                      !self.isApplyingInternalConfiguration,
                      self.engine === newEngine,
                      self.lifecycleState != .stopping,
                      self.lifecycleState != .failed else { return }
                self.scheduleEngineRecovery(reason: "Alteração de rota/hardware de áudio", resetBudget: false)
            }
        }

        self.engine = newEngine
        self.splitCaptureEngine = nil
        self.outputSourceNode = attachedSource
        self.activeEngineHasTap = installedTap
        self.activeEngineHasVPIO = vpEnabled
        self.isUsingSplitEngineFallback = false
        self.isRunning = true
        self.activeVPIOEnabled = vpEnabled
        self.isTapInstalled = installedTap
        self.measuredInputRateHz = inFmtSampleRate
        self.measuredInputChannels = inFmtChannels
        self.measuredOutputRateHz = outFmtSampleRate
        self.measuredOutputChannels = outFmtChannels
        self.audioUnitStateSummary = vpEnabled ? "Initialized/Running (VPIO OSStatus=0)" : "Initialized/Running (AUHAL OSStatus=0)"
        self.attachedNodeGraphSummary = [
            enablePlayback ? "SourceNode(24kHz)->MainMixer->OutputNode(\(Int(outFmtSampleRate))Hz/\(outFmtChannels)ch)" : nil,
            enableCapture ? "InputTap(\(Int(inFmtSampleRate))Hz/\(inFmtChannels)ch)" : nil,
            vpEnabled ? "[VPIO=ON]" : (enableCapture ? "[VPIO=Bypass/SoftwareAEC]" : nil)
        ].compactMap { $0 }.joined(separator: " + ")

        if !enableCapture {
            self.processingStatus = .inactive
            self.lifecycleState = .running
        } else if vpEnabled {
            self.processingStatus = .activeAECAndNS
            self.lifecycleState = .running
        } else {
            self.processingStatus = .bypassedBluetoothOrFallback
            self.lifecycleState = wantVoiceProcessing ? .degradedCompatibility : .running
        }
    }

    private func configureAndStartSplitEngines(
        inputDev: AudioDeviceDescriptor?,
        outputDev: AudioDeviceDescriptor?,
        expectedGeneration: UInt64
    ) throws {
        guard lifecycleGeneration == expectedGeneration else { throw CancellationError() }
        lastOperation = .splitEngineFallback
        lifecycleState = .preparingGraph

        let playbackEng = AVAudioEngine()
        let captureEng = AVAudioEngine()
        var tapInstalledOnSplit = false

        func cleanupBoth() {
            if tapInstalledOnSplit {
                captureEng.inputNode.removeTap(onBus: 0)
            }
            captureEng.stop()
            captureEng.reset()
            playbackEng.stop()
            playbackEng.reset()
        }

        let systemDefaultOut = CoreAudioDeviceCatalog.defaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice)
        let systemDefaultIn = CoreAudioDeviceCatalog.defaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice)

        if let outID = outputDev?.id, outID != 0, outID != systemDefaultOut {
            let st = applyAudioUnitDevice(outID, to: playbackEng.outputNode)
            if st != noErr {
                let err = NSError(domain: NSOSStatusErrorDomain, code: Int(st), userInfo: [NSLocalizedDescriptionKey: "Split playback device bind falhou (OSStatus \(st))."])
                recordFailure(operation: .splitEngineFallback, error: err)
                cleanupBoth()
                throw err
            }
        }
        guard let sourceFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: renderOutputRate, channels: 1, interleaved: false) else {
            let err = NSError(domain: "VoiceNativeAudioEngine", code: -2, userInfo: [NSLocalizedDescriptionKey: "Formato de saída inválido em modo separado."])
            recordFailure(operation: .splitEngineFallback, error: err)
            cleanupBoth()
            throw err
        }
        let sourceNode = makeOutputSourceNode(sourceFmt: sourceFmt)
        playbackEng.attach(sourceNode)
        playbackEng.connect(sourceNode, to: playbackEng.mainMixerNode, format: sourceFmt)

        let outFmt = playbackEng.outputNode.outputFormat(forBus: 0)
        guard outFmt.sampleRate > 0 && outFmt.channelCount > 0 else {
            let err = NSError(domain: "VoiceNativeAudioEngine", code: -2, userInfo: [NSLocalizedDescriptionKey: "Saída sem formato válido em modo separado."])
            recordFailure(operation: .splitEngineFallback, error: err)
            cleanupBoth()
            throw err
        }

        do {
            isApplyingInternalConfiguration = true
            defer { isApplyingInternalConfiguration = false }
            playbackEng.prepare()
            try playbackEng.start()
        } catch {
            recordFailure(operation: .splitEngineFallback, error: error)
            cleanupBoth()
            throw error
        }

        if let inID = inputDev?.id, inID != 0, inID != systemDefaultIn {
            let st = applyAudioUnitDevice(inID, to: captureEng.inputNode)
            if st != noErr {
                let err = NSError(domain: NSOSStatusErrorDomain, code: Int(st), userInfo: [NSLocalizedDescriptionKey: "Split capture device bind falhou (OSStatus \(st))."])
                recordFailure(operation: .splitEngineFallback, error: err)
                cleanupBoth()
                throw err
            }
        }
        let hwFormat = captureEng.inputNode.outputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0 && hwFormat.channelCount > 0 else {
            let err = NSError(domain: "VoiceNativeAudioEngine", code: -3, userInfo: [NSLocalizedDescriptionKey: "Entrada sem formato válido em modo separado."])
            recordFailure(operation: .splitEngineFallback, error: err)
            cleanupBoth()
            throw err
        }

        captureCallbackGeneration &+= 1
        installCaptureTap(on: captureEng.inputNode, captureGen: captureCallbackGeneration)
        tapInstalledOnSplit = true

        do {
            isApplyingInternalConfiguration = true
            defer { isApplyingInternalConfiguration = false }
            captureEng.prepare()
            try captureEng.start()
        } catch {
            recordFailure(operation: .splitEngineFallback, error: error)
            cleanupBoth()
            throw error
        }

        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: playbackEng,
            queue: nil
        ) { [weak self, weak playbackEng] _ in
            DispatchQueue.main.async {
                guard let self,
                      let playbackEng,
                      !self.isApplyingInternalConfiguration,
                      self.engine === playbackEng,
                      self.lifecycleState != .stopping,
                      self.lifecycleState != .failed else { return }
                self.scheduleEngineRecovery(reason: "Alteração na rota de saída (modo separado)", resetBudget: false)
            }
        }
        splitCaptureConfigObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: captureEng,
            queue: nil
        ) { [weak self, weak captureEng] _ in
            DispatchQueue.main.async {
                guard let self,
                      let captureEng,
                      !self.isApplyingInternalConfiguration,
                      self.splitCaptureEngine === captureEng,
                      self.lifecycleState != .stopping,
                      self.lifecycleState != .failed else { return }
                self.scheduleEngineRecovery(reason: "Alteração na rota de entrada (modo separado)", resetBudget: false)
            }
        }

        self.engine = playbackEng
        self.splitCaptureEngine = captureEng
        self.outputSourceNode = sourceNode
        self.activeEngineHasTap = true
        self.activeEngineHasVPIO = false
        self.isUsingSplitEngineFallback = true
        self.isRunning = true
        self.activeVPIOEnabled = false
        self.isTapInstalled = true
        self.measuredInputRateHz = hwFormat.sampleRate
        self.measuredInputChannels = Int(hwFormat.channelCount)
        self.measuredOutputRateHz = outFmt.sampleRate
        self.measuredOutputChannels = Int(outFmt.channelCount)
        self.processingStatus = .bypassedBluetoothOrFallback
        self.lifecycleState = .degradedCompatibility
        self.audioUnitStateSummary = "SplitEngine Running (Playback AU + Capture AU OSStatus=0)"
        self.attachedNodeGraphSummary = "SplitOut(SourceNode->Mixer->\(Int(outFmt.sampleRate))Hz/\(outFmt.channelCount)ch) + SplitIn(Tap \(Int(hwFormat.sampleRate))Hz/\(hwFormat.channelCount)ch) [VPIO=OFF/SoftwareAEC]"
    }

    @discardableResult
    private func applyAudioUnitDevice(_ deviceID: AudioDeviceID, to node: AVAudioIONode) -> OSStatus {
        guard let unit = node.audioUnit else { return -10875 }
        var dev = deviceID
        return AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &dev,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
    }

    private func teardownEnginesCleanly() {
        lastOperation = .teardownPreviousEngine
        captureCallbackGeneration &+= 1
        // Remove NotificationCenter observers FIRST so engine dealloc never deadlocks on IOUnitConfigurationChanged.
        if let obs = configObserver {
            NotificationCenter.default.removeObserver(obs)
            configObserver = nil
        }
        if let splitObs = splitCaptureConfigObserver {
            NotificationCenter.default.removeObserver(splitObs)
            splitCaptureConfigObserver = nil
        }

        let prevConfigFlag = isApplyingInternalConfiguration
        isApplyingInternalConfiguration = true
        defer { isApplyingInternalConfiguration = prevConfigFlag }

        let hadTap = activeEngineHasTap
        let hadVPIO = activeEngineHasVPIO
        let wasSplit = isUsingSplitEngineFallback

        if let splitCap = splitCaptureEngine {
            if hadTap {
                splitCap.inputNode.removeTap(onBus: 0)
            }
            splitCap.stop()
            splitCap.reset()
        }

        if let eng = engine {
            if !wasSplit && hadTap {
                eng.inputNode.removeTap(onBus: 0)
            }
            eng.stop()
            if hadVPIO {
                try? eng.inputNode.setVoiceProcessingEnabled(false)
                lastVPIOTeardownUptimeNs = DispatchTime.now().uptimeNanoseconds
            }
            eng.reset()
        }

        outputSourceNode = nil
        splitCaptureEngine = nil
        engine = nil
        activeEngineHasTap = false
        activeEngineHasVPIO = false
        isUsingSplitEngineFallback = false
        isTapInstalled = false
        activeVPIOEnabled = false
        isRunning = false
        measuredInputRateHz = 0
        measuredInputChannels = 0
        measuredOutputRateHz = 0
        measuredOutputChannels = 0
    }

    private func scheduleEngineRecovery(reason: String, resetBudget: Bool = false) {
        guard wantCapture || wantPlayback else { return }
        pendingRecoveryTask?.cancel()

        let nowNs = DispatchTime.now().uptimeNanoseconds
        if resetBudget {
            recentRecoveryUptimeNs.removeAll()
        } else {
            recentRecoveryUptimeNs = recentRecoveryUptimeNs.filter { nowNs >= $0 && (nowNs &- $0) <= recoveryWindowNs }
            if recentRecoveryUptimeNs.count >= maxAutoRecoveriesInWindow {
                lifecycleGeneration &+= 1
                teardownEnginesCleanly()
                lifecycleState = .failed
                let err = NSError(
                    domain: "VoiceNativeAudioEngine",
                    code: -10875,
                    userInfo: [NSLocalizedDescriptionKey: "Limite de recuperações automáticas atingido (\(maxAutoRecoveriesInWindow) tentativas em 12s) após: \(reason)."]
                )
                recordFailure(operation: .handleConfigChange, error: err)
                lastFault = err.localizedDescription
                onDeviceTopologyChanged?()
                return
            }
            recentRecoveryUptimeNs.append(nowNs)
        }

        let scheduledCapture = wantCapture
        let scheduledPlayback = wantPlayback
        let scheduledVP = wantVoiceProcessing
        let scheduledEpoch = lifecycleGeneration

        pendingRecoveryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard let self,
                  !Task.isCancelled,
                  self.lifecycleGeneration == scheduledEpoch,
                  self.wantCapture || self.wantPlayback else { return }

            self.recoveryCount += 1
            self.restartCount += 1
            self.lifecycleState = .recovering
            self.lastOperation = .handleConfigChange
            self.lastFault = "Recuperação automática (\(self.recoveryCount)): \(reason)"

            do {
                try await self.runSerializedLifecycleOperation { [weak self] in
                    guard let self,
                          !Task.isCancelled,
                          self.lifecycleGeneration == scheduledEpoch,
                          self.wantCapture || self.wantPlayback else { return }
                    try await self.performStartupSequenceAsync(
                        enableCapture: scheduledCapture,
                        enablePlayback: scheduledPlayback,
                        enableVoiceProcessing: scheduledVP,
                        expectedGeneration: scheduledEpoch
                    )
                }
            } catch is CancellationError {
                // Superseded by newer explicit start/stop
            } catch {
                self.lifecycleState = .failed
                self.isRunning = false
                self.lastFault = "Falha na recuperação automática: \(error.localizedDescription)"
            }
            self.onDeviceTopologyChanged?()
        }
    }

    private func installCoreAudioDeviceObservers() {
        guard !deviceListenerInstalled else { return }
        deviceListenerInstalled = true
        let selectors: [AudioObjectPropertySelector] = [
            kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyDefaultInputDevice,
            kAudioHardwarePropertyDefaultOutputDevice
        ]
        for sel in selectors {
            var addr = AudioObjectPropertyAddress(
                mSelector: sel,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let changed = self.refreshDevices()
                    if changed && self.isRunning && !self.isApplyingInternalConfiguration {
                        self.onDeviceTopologyChanged?()
                    }
                }
            }
        }
    }
}

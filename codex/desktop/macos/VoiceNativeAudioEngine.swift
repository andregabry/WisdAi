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

    private static func nominalSampleRate(deviceID: AudioDeviceID) -> Double {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var rate: Float64 = 48_000
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &rate) == noErr, rate > 0 else {
            return 48_000
        }
        return rate
    }

    private static func channelCount(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
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

    public private(set) var targetPrebufferMs: Double = 40.0
    public private(set) var underrunCount: UInt64 = 0
    public private(set) var overflowDropCount: UInt64 = 0
    private var isBuffering: Bool = true
    private var fadeInRemaining: Int = 0

    public init(sampleRate: Double = 24_000, maxDurationSeconds: Double = 6.0) {
        self.sampleRate = max(8_000, sampleRate)
        self.capacitySamples = max(4_800, Int(self.sampleRate * maxDurationSeconds))
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
        os_unfair_lock_unlock(&lock)

        var rms: Float = 0
        vDSP_rmsqv(output, 1, &rms, vDSP_Length(available))
        outputLevelOut?.pointee = rms
        return available
    }

    public func flushAndCaptureHeardSnapshot() -> JitterBufferFlushSnapshot {
        os_unfair_lock_lock(&lock)
        let discarded = bufferedCount
        let playedMs = (Double(totalPlayedSamples) / sampleRate) * 1000.0
        let (heard, unplayed) = computeHeardAndRemainderLocked(playedSamples: totalPlayedSamples)
        readIndex = 0
        writeIndex = 0
        bufferedCount = 0
        isBuffering = true
        fadeInRemaining = 0
        spans.removeAll(keepingCapacity: false)
        totalQueuedSamples = totalPlayedSamples
        os_unfair_lock_unlock(&lock)

        return JitterBufferFlushSnapshot(
            playedMilliseconds: playedMs,
            heardTranscriptPrefix: heard,
            unplayedTranscriptTail: unplayed,
            discardedBufferedSamples: discarded
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
        targetPrebufferMs = 40.0
        isBuffering = true
        fadeInRemaining = 0
        spans.removeAll(keepingCapacity: false)
        os_unfair_lock_unlock(&lock)
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

// MARK: - Voice Engine Diagnostics & Status

public enum VoiceProcessingHardwareStatus: String, Sendable {
    case activeAECAndNS = "AEC + AGC + Supressão de Ruído Ativos"
    case bypassedBluetoothOrFallback = "Bypass seguro (Bluetooth / Fallback)"
    case inactive = "Inativo"
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
}

// MARK: - Full-Duplex Native Audio Engine (CoreAudio + AVAudioEngine)

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

    public let memoryProfile: HardwareMemoryProfile
    public let captureRingBuffer: PreallocatedFloatRingBuffer
    public let outputJitterBuffer: AdaptiveJitterBuffer

    public var onInputAudioChunk: (([Float], Double) -> Void)?
    public var onRawAudioBufferForSpeech: ((AVAudioPCMBuffer) -> Void)?
    public var onDeviceTopologyChanged: (() -> Void)?

    private var engine: AVAudioEngine?
    private var outputSourceNode: AVAudioSourceNode?
    private var configObserver: NSObjectProtocol?
    private var deviceListenerInstalled = false
    private var recoveryCount = 0
    private var vpioUnsupportedRoutes: Set<String> = []
    private var wantCapture = false
    private var wantPlayback = false
    private var wantVoiceProcessing = true
    private var pendingReconnectWorkItem: DispatchWorkItem?

    private let processingQueue = DispatchQueue(label: "local.wisdai.voice.audio.dsp", qos: .userInteractive)
    private let renderOutputRate: Double = 24_000

    public init(memoryProfile: HardwareMemoryProfile = .detect()) {
        self.memoryProfile = memoryProfile
        self.captureRingBuffer = PreallocatedFloatRingBuffer(
            capacitySamples: Int(48_000 * memoryProfile.maxCaptureRingSeconds)
        )
        self.outputJitterBuffer = AdaptiveJitterBuffer(
            sampleRate: renderOutputRate,
            maxDurationSeconds: memoryProfile.maxOutputJitterSeconds
        )
        refreshDevices()
        installCoreAudioDeviceObservers()
    }

    deinit {
        if let obs = configObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    public func refreshDevices() {
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
    }

    public func selectInputDevice(uid: String) {
        selectedInputDeviceUID = uid
        if isRunning {
            scheduleEngineRecovery(reason: "Troca de dispositivo de entrada")
        }
    }

    public func selectOutputDevice(uid: String) {
        selectedOutputDeviceUID = uid
        if isRunning {
            scheduleEngineRecovery(reason: "Troca de dispositivo de saída")
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
        wantCapture = enableCapture
        wantPlayback = enablePlayback
        wantVoiceProcessing = enableVoiceProcessing
        stopEngineOnly()
        refreshDevices()

        let activeOutDev = outputDevices.first(where: { $0.uid == selectedOutputDeviceUID }) ?? outputDevices.first(where: \.isDefaultOutput)
        let activeInDev = inputDevices.first(where: { $0.uid == selectedInputDeviceUID }) ?? inputDevices.first(where: \.isDefaultInput)
        let routeKey = "\(activeInDev?.uid ?? "none")|\(activeOutDev?.uid ?? "none")"
        let isBluetoothRoute = (activeInDev?.isBluetooth == true) || (activeOutDev?.isBluetooth == true)
        let isVirtualOrContinuity = (activeInDev?.transport == .continuityOrVirtual)
        let allowVP = enableVoiceProcessing && enableCapture && !isBluetoothRoute && !isVirtualOrContinuity && !vpioUnsupportedRoutes.contains(routeKey)

        do {
            try configureAndStartEngine(
                enableCapture: enableCapture,
                enablePlayback: enablePlayback,
                tryVoiceProcessing: allowVP,
                inputDeviceID: activeInDev?.id,
                outputDeviceID: activeOutDev?.id
            )
            if !allowVP && enableVoiceProcessing && vpioUnsupportedRoutes.contains(routeKey) {
                lastFault = "AEC hardware VPIO indisponível neste hardware; supressão acústica por software ativa."
            } else {
                lastFault = nil
            }
        } catch {
            if allowVP {
                vpioUnsupportedRoutes.insert(routeKey)
                let firstError = error.localizedDescription
                do {
                    try configureAndStartEngine(
                        enableCapture: enableCapture,
                        enablePlayback: enablePlayback,
                        tryVoiceProcessing: false,
                        inputDeviceID: activeInDev?.id,
                        outputDeviceID: activeOutDev?.id
                    )
                    lastFault = "AEC hardware indisponível (\(firstError)); supressão acústica por software ativa."
                } catch {
                    lastFault = "Falha primária VPIO (\(firstError)) e falha padrão (\(error.localizedDescription))."
                    throw error
                }
            } else {
                lastFault = error.localizedDescription
                throw error
            }
        }
    }

    /// Non-blocking async startup that awaits CoreAudio HAL output format recovery (~430ms after any VPIO teardown)
    /// without ever blocking the Main Thread.
    public func startFullDuplexAsync(enableCapture: Bool = true, enablePlayback: Bool = true, enableVoiceProcessing: Bool = true) async throws {
        wantCapture = enableCapture
        wantPlayback = enablePlayback
        wantVoiceProcessing = enableVoiceProcessing
        stopEngineOnly()
        refreshDevices()

        let activeOutDev = outputDevices.first(where: { $0.uid == selectedOutputDeviceUID }) ?? outputDevices.first(where: \.isDefaultOutput)
        let activeInDev = inputDevices.first(where: { $0.uid == selectedInputDeviceUID }) ?? inputDevices.first(where: \.isDefaultInput)
        let routeKey = "\(activeInDev?.uid ?? "none")|\(activeOutDev?.uid ?? "none")"
        let isBluetoothRoute = (activeInDev?.isBluetooth == true) || (activeOutDev?.isBluetooth == true)
        let isVirtualOrContinuity = (activeInDev?.transport == .continuityOrVirtual)
        let allowVP = enableVoiceProcessing && enableCapture && !isBluetoothRoute && !isVirtualOrContinuity && !vpioUnsupportedRoutes.contains(routeKey)

        if enablePlayback {
            await waitForValidOutputHWFormat(maxWaitMs: 750)
        }

        do {
            try configureAndStartEngine(
                enableCapture: enableCapture,
                enablePlayback: enablePlayback,
                tryVoiceProcessing: allowVP,
                inputDeviceID: activeInDev?.id,
                outputDeviceID: activeOutDev?.id
            )
            if !allowVP && enableVoiceProcessing && vpioUnsupportedRoutes.contains(routeKey) {
                lastFault = "AEC hardware VPIO indisponível nesta rota; supressão acústica por software ativa."
            } else if !isBluetoothRoute && !isVirtualOrContinuity {
                lastFault = nil
            }
        } catch {
            if allowVP {
                vpioUnsupportedRoutes.insert(routeKey)
                let firstError = error.localizedDescription
                if enablePlayback {
                    await waitForValidOutputHWFormat(maxWaitMs: 750)
                }
                do {
                    try configureAndStartEngine(
                        enableCapture: enableCapture,
                        enablePlayback: enablePlayback,
                        tryVoiceProcessing: false,
                        inputDeviceID: activeInDev?.id,
                        outputDeviceID: activeOutDev?.id
                    )
                    lastFault = "AEC hardware indisponível (\(firstError)); supressão acústica por software ativa."
                } catch {
                    lastFault = "Falha primária VPIO (\(firstError)) e falha padrão (\(error.localizedDescription))."
                    throw error
                }
            } else {
                lastFault = error.localizedDescription
                throw error
            }
        }
    }

    private func waitForValidOutputHWFormat(maxWaitMs: Int) async {
        let steps = max(1, maxWaitMs / 35)
        for _ in 0..<steps {
            let probe = AVAudioEngine()
            let fmt = probe.outputNode.outputFormat(forBus: 0)
            if fmt.sampleRate > 0 && fmt.channelCount > 0 {
                return
            }
            try? await Task.sleep(nanoseconds: 35_000_000)
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
        wantCapture = false
        wantPlayback = false
        pendingReconnectWorkItem?.cancel()
        pendingReconnectWorkItem = nil
        stopEngineOnly()
        captureRingBuffer.flush()
        _ = outputJitterBuffer.flushAndCaptureHeardSnapshot()
        processingStatus = .inactive
        liveLevels = .zero
    }

    @discardableResult
    public func bargeInFlushPlayback() -> JitterBufferFlushSnapshot {
        return outputJitterBuffer.flushAndCaptureHeardSnapshot()
    }

    public func telemetrySnapshot() -> AudioEngineRuntimeTelemetry {
        let jStats = outputJitterBuffer.stats
        let inName = inputDevices.first(where: { $0.uid == selectedInputDeviceUID })?.name ?? "Padrão"
        let outName = outputDevices.first(where: { $0.uid == selectedOutputDeviceUID })?.name ?? "Padrão"
        return AudioEngineRuntimeTelemetry(
            isRunning: isRunning,
            isFullDuplex: wantCapture && wantPlayback,
            hardwareSampleRate: engine?.outputNode.outputFormat(forBus: 0).sampleRate ?? 48_000,
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
            lastFaultDescription: lastFault
        )
    }

    private func configureAndStartEngine(
        enableCapture: Bool,
        enablePlayback: Bool,
        tryVoiceProcessing: Bool,
        inputDeviceID: AudioDeviceID?,
        outputDeviceID: AudioDeviceID?
    ) throws {
        let newEngine = AVAudioEngine()
        var vpEnabled = false

        let systemDefaultOut = CoreAudioDeviceCatalog.defaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice)
        let systemDefaultIn = CoreAudioDeviceCatalog.defaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice)

        if enablePlayback, let outID = outputDeviceID, outID != 0, outID != systemDefaultOut {
            applyAudioUnitDevice(outID, to: newEngine.outputNode)
        }
        if enableCapture, let inID = inputDeviceID, inID != 0, inID != systemDefaultIn {
            applyAudioUnitDevice(inID, to: newEngine.inputNode)
        }

        if enableCapture && tryVoiceProcessing {
            do {
                try newEngine.inputNode.setVoiceProcessingEnabled(true)
                newEngine.inputNode.isVoiceProcessingAGCEnabled = true
                newEngine.inputNode.isVoiceProcessingBypassed = false
                vpEnabled = true
            } catch {
                try? newEngine.inputNode.setVoiceProcessingEnabled(false)
                vpEnabled = false
            }
        }

        if enablePlayback {
            let jitterRef = outputJitterBuffer
            guard let sourceFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: renderOutputRate, channels: 1, interleaved: false) else {
                throw NSError(domain: "VoiceNativeAudioEngine", code: -2, userInfo: [NSLocalizedDescriptionKey: "Formato de saída inválido."])
            }
            var scratch = [Float](repeating: 0, count: 4096)
            var lastPullRms: Float = 0

            let sourceNode = AVAudioSourceNode(format: sourceFmt) { _, _, frameCount, audioBufferList -> OSStatus in
                let frames = Int(frameCount)
                let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
                guard let firstBuf = abl.first, let outPtr = firstBuf.mData?.assumingMemoryBound(to: Float.self) else {
                    return noErr
                }
                let needed = min(frames, scratch.count)
                var rms: Float = 0
                let pulled = scratch.withUnsafeMutableBufferPointer { buf in
                    guard let base = buf.baseAddress else { return 0 }
                    return jitterRef.renderPull(into: base, frameCount: needed, outputLevelOut: &rms)
                }
                if pulled > 0 {
                    outPtr.update(from: scratch, count: pulled)
                }
                if frames > pulled {
                    outPtr.advanced(by: pulled).initialize(repeating: 0, count: frames - pulled)
                }
                lastPullRms = rms
                return noErr
            }
            self.outputSourceNode = sourceNode
            newEngine.attach(sourceNode)
            newEngine.connect(sourceNode, to: newEngine.mainMixerNode, format: sourceFmt)
            _ = lastPullRms
        }

        if enableCapture {
            let inputNode = newEngine.inputNode
            let hwFormat = inputNode.outputFormat(forBus: 0)
            guard hwFormat.sampleRate > 0 && hwFormat.channelCount > 0 else {
                throw NSError(domain: "VoiceNativeAudioEngine", code: -3, userInfo: [NSLocalizedDescriptionKey: "Dispositivo de microfone sem formato válido."])
            }
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
                        guard let self, self.isRunning else { return }
                        self.liveLevels = orb
                        self.onRawAudioBufferForSpeech?(buffer)
                        self.onInputAudioChunk?(copied, sr)
                    }
                }
            }
        }

        if let obs = configObserver {
            NotificationCenter.default.removeObserver(obs)
            configObserver = nil
        }

        do {
            newEngine.prepare()
            try newEngine.start()
        } catch {
            if enableCapture {
                newEngine.inputNode.removeTap(onBus: 0)
            }
            if vpEnabled {
                try? newEngine.inputNode.setVoiceProcessingEnabled(false)
            }
            newEngine.stop()
            newEngine.reset()
            throw error
        }

        // IMPORTANT: Register observer with `queue: nil` ONLY AFTER `start()` succeeds.
        // Using `queue: .main` caused an ABBA deadlock between `AVAudioEngine dealloc` (`_dispatch_sync_f_slow`)
        // on the main thread and `IOUnitConfigurationChanged` (`-[NSOperation waitUntilFinished]`) on CoreAudio's engine queue.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: newEngine,
            queue: nil
        ) { [weak self, weak newEngine] _ in
            DispatchQueue.main.async {
                guard let self, let newEngine, self.engine === newEngine else { return }
                self.scheduleEngineRecovery(reason: "Alteração de rota/hardware de áudio")
            }
        }

        self.engine = newEngine
        self.isRunning = true
        if !enableCapture {
            self.processingStatus = .inactive
        } else {
            self.processingStatus = vpEnabled ? .activeAECAndNS : .bypassedBluetoothOrFallback
        }
    }

    private func applyAudioUnitDevice(_ deviceID: AudioDeviceID, to node: AVAudioIONode) {
        guard let unit = node.audioUnit else { return }
        var dev = deviceID
        AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &dev,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
    }

    private func stopEngineOnly() {
        // Remove NotificationCenter observer FIRST so engine dealloc never deadlocks on IOUnitConfigurationChanged.
        if let obs = configObserver {
            NotificationCenter.default.removeObserver(obs)
            configObserver = nil
        }
        if let eng = engine {
            if wantCapture {
                eng.inputNode.removeTap(onBus: 0)
            }
            eng.stop()
            eng.reset()
        }
        outputSourceNode = nil
        engine = nil
        isRunning = false
    }

    private func scheduleEngineRecovery(reason: String) {
        guard wantCapture || wantPlayback else { return }
        pendingReconnectWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.wantCapture || self.wantPlayback else { return }
                self.recoveryCount += 1
                self.lastFault = "Recuperação automática: \(reason)"
                try? await self.startFullDuplexAsync(
                    enableCapture: self.wantCapture,
                    enablePlayback: self.wantPlayback,
                    enableVoiceProcessing: self.wantVoiceProcessing
                )
                self.onDeviceTopologyChanged?()
            }
        }
        pendingReconnectWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
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
                    self.refreshDevices()
                    if self.isRunning {
                        self.onDeviceTopologyChanged?()
                    }
                }
            }
        }
    }
}

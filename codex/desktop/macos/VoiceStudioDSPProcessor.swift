import Accelerate
import Foundation

// MARK: - Voice Acoustic DSP Parameters & Non-Destructive Studio Processing Chain

public struct VoiceDSPParameters: Equatable, Codable, Sendable {
    public var toneSemitones: Double      // -4.0 ... +4.0 (0.0 = untouched natural voice)
    public var metallicIntensity: Double  // 0.0 ... 1.0 (0.0 = clean bypass)
    public var resonance: Double          // 0.0 ... 1.0 (0.0 = clean bypass)
    public var expressivityAmount: Double // 0.0 ... 1.0
    public var outputVolume: Double       // 0.25 ... 1.50 (1.0 = unity, protected by limiter)

    public init(
        toneSemitones: Double = 0.0,
        metallicIntensity: Double = 0.0,
        resonance: Double = 0.0,
        expressivityAmount: Double = 0.55,
        outputVolume: Double = 1.0
    ) {
        self.toneSemitones = min(4.0, max(-4.0, toneSemitones))
        self.metallicIntensity = min(1.0, max(0.0, metallicIntensity))
        self.resonance = min(1.0, max(0.0, resonance))
        self.expressivityAmount = min(1.0, max(0.0, expressivityAmount))
        self.outputVolume = min(1.50, max(0.25, outputVolume))
    }

    public static let clean = VoiceDSPParameters(
        toneSemitones: 0.0,
        metallicIntensity: 0.0,
        resonance: 0.0,
        expressivityAmount: 0.55,
        outputVolume: 1.0
    )

    public static let ultronBRDefault = VoiceDSPParameters(
        toneSemitones: 0.0,
        metallicIntensity: 0.24,
        resonance: 0.48,
        expressivityAmount: 0.78,
        outputVolume: 1.08
    )

    public var requiresColorationDSP: Bool {
        abs(toneSemitones) > 0.04 || metallicIntensity > 0.01 || resonance > 0.01
    }

    public var isIdentityClean: Bool {
        !requiresColorationDSP && abs(outputVolume - 1.0) <= 0.01
    }
}

// MARK: - Stateful Double-Precision Biquad Filter

private struct StudioBiquad {
    private var b0: Double = 1
    private var b1: Double = 0
    private var b2: Double = 0
    private var a1: Double = 0
    private var a2: Double = 0
    private var z1: Double = 0
    private var z2: Double = 0

    mutating func reset() {
        z1 = 0
        z2 = 0
    }

    mutating func configureHighPass(sampleRate: Double, freqHz: Double, q: Double = 0.7071) {
        let w0 = 2.0 * Double.pi * min(freqHz, sampleRate * 0.45) / max(1.0, sampleRate)
        let cosW0 = cos(w0)
        let sinW0 = sin(w0)
        let alpha = sinW0 / (2.0 * max(0.1, q))
        let a0 = 1.0 + alpha
        b0 = ((1.0 + cosW0) * 0.5) / a0
        b1 = (-(1.0 + cosW0)) / a0
        b2 = ((1.0 + cosW0) * 0.5) / a0
        a1 = (-2.0 * cosW0) / a0
        a2 = (1.0 - alpha) / a0
    }

    mutating func configurePeakingEQ(sampleRate: Double, freqHz: Double, q: Double, gainDB: Double) {
        if abs(gainDB) < 0.01 {
            b0 = 1; b1 = 0; b2 = 0; a1 = 0; a2 = 0
            return
        }
        let a = pow(10.0, gainDB / 40.0)
        let w0 = 2.0 * Double.pi * min(freqHz, sampleRate * 0.45) / max(1.0, sampleRate)
        let cosW0 = cos(w0)
        let sinW0 = sin(w0)
        let alpha = sinW0 / (2.0 * max(0.1, q))
        let a0 = 1.0 + alpha / a
        b0 = (1.0 + alpha * a) / a0
        b1 = (-2.0 * cosW0) / a0
        b2 = (1.0 - alpha * a) / a0
        a1 = (-2.0 * cosW0) / a0
        a2 = (1.0 - alpha / a) / a0
    }

    @inline(__always)
    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }
}

// MARK: - Subtle Metallic Titanium Chassis Resonator (No Harsh Ring-Mod / Vocoder)

private final class SubtleMetallicResonator {
    private var delay1: [Double]
    private var delay2: [Double]
    private var idx1: Int = 0
    private var idx2: Int = 0
    private var hp1: StudioBiquad = StudioBiquad()
    private var damp1: Double = 0
    private var damp2: Double = 0

    init(sampleRate: Double) {
        let len1 = max(16, Int((0.00142 * sampleRate).rounded())) // ~704 Hz acoustic titanium micro-cavity
        let len2 = max(23, Int((0.00227 * sampleRate).rounded())) // ~440 Hz secondary early reflection
        self.delay1 = [Double](repeating: 0, count: len1)
        self.delay2 = [Double](repeating: 0, count: len2)
        self.hp1.configureHighPass(sampleRate: sampleRate, freqHz: 780.0, q: 0.707)
    }

    func reset() {
        for i in delay1.indices { delay1[i] = 0 }
        for i in delay2.indices { delay2[i] = 0 }
        idx1 = 0
        idx2 = 0
        hp1.reset()
        damp1 = 0
        damp2 = 0
    }

    @inline(__always)
    func process(_ x: Double, intensity: Double) -> Double {
        guard intensity > 0.005 else { return x }
        let excited = hp1.process(x)
        let fb = 0.22 + 0.24 * intensity // Gentle feedback <= 0.46 so consonants never smear

        let d1 = delay1[idx1]
        damp1 = damp1 * 0.42 + d1 * 0.58 // Warm damping above 5 kHz avoids harsh metallic shriek
        let y1 = -fb * excited + damp1
        delay1[idx1] = excited + fb * damp1
        idx1 += 1
        if idx1 >= delay1.count { idx1 = 0 }

        let d2 = delay2[idx2]
        damp2 = damp2 * 0.45 + d2 * 0.55
        let y2 = -fb * 0.85 * excited + damp2
        delay2[idx2] = excited + fb * 0.85 * damp2
        idx2 += 1
        if idx2 >= delay2.count { idx2 = 0 }

        let wet = 0.5 * (y1 + y2)
        let mix = min(0.26, intensity * 0.24)
        return x + mix * wet
    }
}

// MARK: - Clean WSOLA Time-Domain Pitch Shifter (Preserves Glottal Periodicity Without FFT Buzz)

private final class StreamingWSOLAPitchShifter {
    private let sampleRate: Double
    private var ratio: Double // pitchRatio = 2^(semitones/12)
    private var inputBuffer: [Float] = []
    private let analysisWindow: Int
    private let synthesisHop: Int
    private var olaRing: [Float]
    private var olaWeight: [Float]
    private var hanning: [Float]
    private var inputCursor: Double = 0
    private var outPending: [Float] = []

    init(sampleRate: Double, pitchRatio: Double) {
        self.sampleRate = sampleRate
        self.ratio = pitchRatio
        let win = max(256, Int((0.024 * sampleRate).rounded())) // 24 ms window
        self.analysisWindow = win
        self.synthesisHop = max(64, win / 4) // 75% overlap
        self.olaRing = [Float](repeating: 0, count: win * 4)
        self.olaWeight = [Float](repeating: 0, count: win * 4)
        var w = [Float](repeating: 0, count: win)
        for i in 0..<win {
            w[i] = Float(0.5 * (1.0 - cos(2.0 * Double.pi * Double(i) / Double(win - 1))))
        }
        self.hanning = w
    }

    func reset() {
        inputBuffer.removeAll(keepingCapacity: true)
        for i in olaRing.indices { olaRing[i] = 0; olaWeight[i] = 0 }
        inputCursor = 0
        outPending.removeAll(keepingCapacity: true)
    }

    func process(_ samples: [Float], pitchRatio: Double, flushTail: Bool = false) -> [Float] {
        guard !samples.isEmpty || flushTail else { return [] }
        self.ratio = pitchRatio
        if abs(pitchRatio - 1.0) < 0.003 && inputBuffer.isEmpty {
            return samples
        }
        if !samples.isEmpty {
            inputBuffer.append(contentsOf: samples)
        }
        if flushTail {
            inputBuffer.append(contentsOf: [Float](repeating: 0, count: analysisWindow))
        }

        // First resample input time-scale inversely by `ratio` (so WSOLA preserves original duration at new pitch),
        // OR run overlap-add frame pull at `hop * ratio` then linear/cubic resample back.
        // Cleanest artifact-free streaming approach:
        // Step 1: Time-stretch chunk by `1 / ratio` using WSOLA pitch-aligned overlap-add
        let stepIn = Double(synthesisHop) / max(0.5, min(2.0, pitchRatio))
        let searchRadius = max(32, Int((0.004 * sampleRate).rounded()))
        var stretched: [Float] = []
        stretched.reserveCapacity(samples.count + synthesisHop)

        let neededInput = Int(ceil(Double(analysisWindow) * max(1.0, pitchRatio))) + analysisWindow + searchRadius + 16
        while Int(inputCursor) + analysisWindow + searchRadius + 4 < inputBuffer.count || (flushTail && Int(inputCursor) + analysisWindow < inputBuffer.count) {
            let nominal = Int(inputCursor.rounded())
            var bestStart = nominal
            if stretched.count >= analysisWindow / 2 && nominal > searchRadius && nominal + analysisWindow + searchRadius < inputBuffer.count {
                // Find local maximum autocorrelation match against recent stretched tail
                let tailRefStart = stretched.count - min(stretched.count, 96)
                var bestCorr: Float = -Float.greatestFiniteMagnitude
                let minCand = max(0, nominal - searchRadius)
                let maxCand = min(inputBuffer.count - analysisWindow - 1, nominal + searchRadius)
                var cand = minCand
                while cand <= maxCand {
                    var dot: Float = 0
                    let refLen = stretched.count - tailRefStart
                    for k in stride(from: 0, to: min(refLen, 64), by: 2) {
                        dot += stretched[tailRefStart + k] * inputBuffer[cand + k]
                    }
                    if dot > bestCorr {
                        bestCorr = dot
                        bestStart = cand
                    }
                    cand += 2
                }
            }

            // Add windowed grain into OLA accumulator and emit synthesisHop
            let safeStart = min(max(0, bestStart), max(0, inputBuffer.count - analysisWindow))
            if safeStart + analysisWindow <= inputBuffer.count {
                for i in 0..<analysisWindow {
                    let s = inputBuffer[safeStart + i] * hanning[i]
                    olaRing[i] += s
                    olaWeight[i] += hanning[i]
                }
                for i in 0..<synthesisHop {
                    let norm = olaWeight[i] > 1e-4 ? (olaRing[i] / olaWeight[i]) : olaRing[i]
                    stretched.append(norm)
                }
                // Shift OLA buffer left by synthesisHop
                let keep = olaRing.count - synthesisHop
                for i in 0..<keep {
                    olaRing[i] = olaRing[i + synthesisHop]
                    olaWeight[i] = olaWeight[i + synthesisHop]
                }
                for i in keep..<olaRing.count {
                    olaRing[i] = 0
                    olaWeight[i] = 0
                }
            }
            inputCursor += stepIn
        }

        // Trim consumed prefix from inputBuffer safely
        let trimCount = max(0, Int(inputCursor) - analysisWindow)
        if trimCount > 2048 && trimCount < inputBuffer.count {
            inputBuffer.removeFirst(trimCount)
            inputCursor -= Double(trimCount)
        }
        _ = neededInput

        guard !stretched.isEmpty else { return [] }
        // Step 2: Resample `stretched` by `pitchRatio` (cubic Hermite interpolation) to shift pitch back to exact duration
        let outCount = max(1, Int((Double(stretched.count) / pitchRatio).rounded()))
        var out = [Float](repeating: 0, count: outCount)
        let maxIdx = stretched.count - 1
        for i in 0..<outCount {
            let pos = Double(i) * pitchRatio
            let idx = min(maxIdx, Int(pos))
            let frac = Float(pos - Double(idx))
            let y0 = stretched[max(0, idx - 1)]
            let y1 = stretched[idx]
            let y2 = stretched[min(maxIdx, idx + 1)]
            let y3 = stretched[min(maxIdx, idx + 2)]
            // Catmull-Rom cubic spline
            let c0 = y1
            let c1 = 0.5 * (y2 - y0)
            let c2 = y0 - 2.5 * y1 + 2.0 * y2 - 0.5 * y3
            let c3 = 0.5 * (y3 - y0) + 1.5 * (y1 - y2)
            out[i] = ((c3 * frac + c2) * frac + c1) * frac + c0
        }
        return out
    }
}

// MARK: - Stateful Non-Destructive Studio DSP Processor

public final class VoiceStudioDSPProcessor: @unchecked Sendable {
    private let sampleRate: Double
    private var dcBlocker = StudioBiquad()
    private var chestLowEQ = StudioBiquad()
    private var boxCutEQ = StudioBiquad()
    private var formantBodyEQ = StudioBiquad()
    private var clarityPresenceEQ = StudioBiquad()
    private var metallicResonator: SubtleMetallicResonator
    private var pitchShifter: StreamingWSOLAPitchShifter?
    private var compEnvelope: Double = 0
    private var configuredParams: VoiceDSPParameters = .clean

    public init(sampleRate: Double = 24_000) {
        self.sampleRate = max(8_000, sampleRate)
        self.metallicResonator = SubtleMetallicResonator(sampleRate: self.sampleRate)
        self.dcBlocker.configureHighPass(sampleRate: self.sampleRate, freqHz: 26.0, q: 0.707)
        configureFilters(for: .clean)
    }

    public func reset() {
        dcBlocker.reset()
        chestLowEQ.reset()
        boxCutEQ.reset()
        formantBodyEQ.reset()
        clarityPresenceEQ.reset()
        metallicResonator.reset()
        pitchShifter?.reset()
        compEnvelope = 0
    }

    private func configureFilters(for params: VoiceDSPParameters) {
        configuredParams = params
        // Controlled sub-bass chest warmth (+0 .. +5.5 dB around 115 Hz)
        chestLowEQ.configurePeakingEQ(sampleRate: sampleRate, freqHz: 115.0, q: 0.85, gainDB: params.resonance * 5.2)
        // Subtle boxiness cleanup around 285 Hz so bass boost never turns muddy
        boxCutEQ.configurePeakingEQ(sampleRate: sampleRate, freqHz: 285.0, q: 1.15, gainDB: -params.resonance * 1.8)
        // Mature vocal-tract body formant peaking (490 Hz)
        formantBodyEQ.configurePeakingEQ(sampleRate: sampleRate, freqHz: 490.0, q: 1.35, gainDB: params.resonance * 2.1)
        // Crisp consonant articulation presence (2.9 kHz)
        let presenceGain = (params.resonance * 1.6) + (params.metallicIntensity * 1.8)
        clarityPresenceEQ.configurePeakingEQ(sampleRate: sampleRate, freqHz: 2950.0, q: 1.0, gainDB: presenceGain)

        if abs(params.toneSemitones) > 0.04 {
            let ratio = pow(2.0, params.toneSemitones / 12.0)
            if pitchShifter == nil {
                pitchShifter = StreamingWSOLAPitchShifter(sampleRate: sampleRate, pitchRatio: ratio)
            }
        } else {
            pitchShifter = nil
        }
    }

    /// Processes a chunk non-destructively while keeping streaming filter/compressor state intact across chunks.
    public func process(
        _ input: [Float],
        parameters: VoiceDSPParameters,
        isFinalChunk: Bool = false
    ) -> [Float] {
        guard !input.isEmpty else { return [] }
        if parameters != configuredParams {
            configureFilters(for: parameters)
        }

        // Fast transparent path for clean voices (JARVIS clean, Aurora, Atlas, Aria):
        // ONLY removes sub-audible DC offset (fixes Kokoro +0.025..+0.030 DC click) + soft safety ceiling.
        if parameters.isIdentityClean {
            var out = [Float](repeating: 0, count: input.count)
            for i in input.indices {
                let cleaned = dcBlocker.process(Double(input[i]))
                out[i] = Float(min(0.98, max(-0.98, cleaned)))
            }
            return out
        }

        // 1. Optional gentle pitch shift (only when explicitly tuned away from 0.0 semitones)
        let pitchOut: [Float]
        if let shifter = pitchShifter, abs(parameters.toneSemitones) > 0.04 {
            let ratio = pow(2.0, parameters.toneSemitones / 12.0)
            let shifted = shifter.process(input, pitchRatio: ratio, flushTail: isFinalChunk)
            pitchOut = shifted.isEmpty ? input : shifted
        } else {
            pitchOut = input
        }

        let applyColoration = parameters.requiresColorationDSP
        let satMix = applyColoration ? min(0.14, 0.04 + 0.08 * max(parameters.resonance, parameters.metallicIntensity)) : 0.0
        let satDrive = 1.0 + 0.85 * max(parameters.resonance, parameters.metallicIntensity)

        // Moderate dynamic compressor constants (threshold ~0.20, ratio 2.2:1)
        let attackCoeff = exp(-1.0 / (0.006 * sampleRate))
        let releaseCoeff = exp(-1.0 / (0.095 * sampleRate))
        let threshold = 0.20
        let ratio = 2.2
        let makeup = applyColoration ? (1.0 + 0.16 * parameters.resonance) : 1.0
        let ceiling = 0.891 // -1.0 dBFS lookahead soft brickwall limiter

        var out = [Float](repeating: 0, count: pitchOut.count)
        for i in pitchOut.indices {
            var s = dcBlocker.process(Double(pitchOut[i]))

            if applyColoration {
                // Parametric EQ + Formant shaping
                s = chestLowEQ.process(s)
                s = boxCutEQ.process(s)
                s = formantBodyEQ.process(s)
                s = clarityPresenceEQ.process(s)

                // Subtle acoustic metallic chassis resonance (no ring-mod / no harsh vocoder)
                if parameters.metallicIntensity > 0.01 {
                    s = metallicResonator.process(s, intensity: parameters.metallicIntensity)
                }

                // Subtle asymmetric harmonic saturation for analog cinema density
                if satMix > 0.001 {
                    let warm = tanh(s * satDrive + 0.025 * s * s) / tanh(satDrive)
                    s = s * (1.0 - satMix) + warm * satMix
                }

                // Moderate dynamic compression
                let absS = abs(s)
                if absS > compEnvelope {
                    compEnvelope = attackCoeff * compEnvelope + (1.0 - attackCoeff) * absS
                } else {
                    compEnvelope = releaseCoeff * compEnvelope + (1.0 - releaseCoeff) * absS
                }
                if compEnvelope > threshold {
                    let overDB = 20.0 * log10(compEnvelope / threshold)
                    let compressedDB = overDB * (1.0 / ratio - 1.0)
                    let compGain = pow(10.0, compressedDB / 20.0)
                    s *= compGain
                }
                s *= makeup
            }

            // Output volume scaling + soft-knee brickwall limiter (-1.0 dBFS, zero digital clipping)
            s *= parameters.outputVolume
            if abs(s) > ceiling * 0.82 {
                let sign: Double = s >= 0 ? 1.0 : -1.0
                let kneeStart = ceiling * 0.82
                let excess = abs(s) - kneeStart
                let span = ceiling - kneeStart
                s = sign * (kneeStart + span * tanh(excess / max(0.01, span)))
            }
            out[i] = Float(min(ceiling, max(-ceiling, s)))
        }
        return out
    }
}

// MARK: - Stateful Windowed-Sinc Streaming Resampler (Linear-Phase, Zero Chunk Clicks)

public final class StreamingSincResampler: @unchecked Sendable {
    private let fromRate: Double
    private let toRate: Double
    private let ratio: Double
    private let halfTaps: Int = 12
    private var history: [Float] = []
    private var fracPos: Double = 0

    public init(fromSampleRate: Double, toSampleRate: Double) {
        self.fromRate = max(8_000, fromSampleRate)
        self.toRate = max(8_000, toSampleRate)
        self.ratio = self.fromRate / self.toRate
        self.history = [Float](repeating: 0, count: self.halfTaps)
    }

    public func reset() {
        history = [Float](repeating: 0, count: halfTaps)
        fracPos = 0
    }

    public func process(_ chunk: [Float], isFinal: Bool = false) -> [Float] {
        guard !chunk.isEmpty else { return [] }
        if abs(fromRate - toRate) < 1.0 { return chunk }

        var buf = history + chunk
        if isFinal {
            buf.append(contentsOf: [Float](repeating: 0, count: halfTaps))
        }
        let cutoff = min(0.92, (toRate / fromRate) * 0.94)
        let availableEnd = Double(buf.count - halfTaps - 1)
        guard availableEnd > fracPos else {
            history = Array(buf.suffix(halfTaps * 2))
            return []
        }

        var out: [Float] = []
        out.reserveCapacity(Int((Double(chunk.count) / ratio).rounded()) + 8)

        var pos = fracPos + Double(halfTaps)
        let limit = Double(buf.count - halfTaps - 1)
        while pos < limit {
            let center = Int(pos)
            let frac = pos - Double(center)
            var acc: Double = 0
            var wsum: Double = 0
            for k in (-halfTaps)...halfTaps {
                let x = Double(k) - frac
                let sincVal: Double
                if abs(x) < 1e-6 {
                    sincVal = cutoff
                } else {
                    let arg = Double.pi * x * cutoff
                    sincVal = sin(arg) / (Double.pi * x)
                }
                // Blackman window over [-halfTaps, halfTaps]
                let n = Double(k + halfTaps) / Double(2 * halfTaps)
                let win = 0.42 - 0.50 * cos(2.0 * Double.pi * n) + 0.08 * cos(4.0 * Double.pi * n)
                let coeff = sincVal * win
                acc += Double(buf[center + k]) * coeff
                wsum += coeff
            }
            let sample = Float(wsum > 1e-6 ? acc / wsum : acc)
            out.append(sample)
            pos += ratio
        }

        let consumedFromChunk = Int(floor(pos)) - history.count
        fracPos = (pos - floor(pos))
        if consumedFromChunk >= 0 && consumedFromChunk < chunk.count {
            let histStart = max(0, min(buf.count - 1, Int(floor(pos)) - halfTaps))
            history = Array(buf[histStart...(buf.count - 1)])
        } else {
            history = Array(buf.suffix(halfTaps))
            fracPos = 0
        }
        return out
    }
}


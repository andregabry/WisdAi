import Accelerate
import CryptoKit
import Foundation

// MARK: - Section 5: Vocalization Cache Engine (<100ms Decision-to-Playback, Zero Cross-Voice Reuse)

public enum VocalizationIntonation: String, Codable, Sendable {
    case engaged
    case reflective
    case warm
    case brief
}

public struct VocalizationVariantSpec: Equatable, Hashable, Codable, Sendable {
    public let vocalization: VocalizationKind
    public let intonation: VocalizationIntonation
    public let rateScale: Float
    public let silenceScale: Float
    public let defaultIntensityGain: Float

    public var variantTag: String {
        "\(vocalization.rawValue)_\(intonation.rawValue)"
    }
}

public struct VocalizationIdentityContext: Equatable, Hashable, Sendable {
    public let engineID: String
    public let voicePreference: String
    public let language: VoiceLanguageVariant

    public var signature: String {
        "\(engineID)|\(voicePreference.lowercased())|\(language.rawValue)"
    }

    public var signatureHash: String {
        let digest = SHA256.hash(data: Data(signature.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}

public struct CachedVocalizationClip: Sendable {
    public let kind: VocalizationKind
    public let intonation: VocalizationIntonation
    public let voiceSignature: String
    public let text: String
    public let communicativeIntent: String
    public let samples24k: [Float]
    public let sampleRate: Int
    public let durationMs: Double
    public let generationLatencyMs: Double
    public let defaultGain: Float
    public var lastUsedNs: UInt64

    public var memoryBytes: Int {
        samples24k.count * MemoryLayout<Float>.stride
    }

    public func scaledSamples(forIntensity intensity: Float) -> [Float] {
        let clampedGain = min(0.95, max(0.18, intensity * defaultGain / 0.35))
        guard abs(clampedGain - 1.0) > 0.02, !samples24k.isEmpty else {
            return samples24k
        }
        var out = [Float](repeating: 0, count: samples24k.count)
        var gain = clampedGain
        vDSP_vsmul(samples24k, 1, &gain, &out, 1, vDSP_Length(samples24k.count))
        return out
    }
}

public typealias VocalizationPCMGenerator = @Sendable (
    _ text: String,
    _ language: VoiceLanguageVariant,
    _ voicePreference: String,
    _ rate: Float,
    _ silenceScale: Float
) async throws -> [Float]

@MainActor
public final class VocalizationCacheEngine: ObservableObject {
    @Published public private(set) var activeSignature: String = ""
    @Published public private(set) var cachedClipsCount: Int = 0
    @Published public private(set) var cacheMemoryMB: Double = 0
    @Published public private(set) var hitCount: Int = 0
    @Published public private(set) var missCount: Int = 0
    @Published public private(set) var isPrewarming: Bool = false
    @Published public private(set) var lastGenerationSummary: String = "Cache vazio"
    @Published public private(set) var lastPlaybackLatencyMs: Double = 0

    private let lock = NSLock()
    private var clipsByTag: [String: CachedVocalizationClip] = [:]
    private var generationEpoch: UInt64 = 0
    private var activeContext: VocalizationIdentityContext?
    private var prewarmTask: Task<Void, Never>?
    private let diskRootDirectory: URL
    private let maxMemoryBytes: Int

    public init(hardwareProfile: HardwareMemoryProfile = .detect(), storageDirectory: URL? = nil) {
        self.maxMemoryBytes = hardwareProfile == .low8GB ? (10 * 1024 * 1024) : (24 * 1024 * 1024)
        if let storageDirectory {
            self.diskRootDirectory = storageDirectory
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
            self.diskRootDirectory = support.appendingPathComponent("WisdAI/Voice/VocalizationCache", isDirectory: true)
        }
    }

    public static func defaultPrewarmSpecs(for profile: VoiceBehaviorProfile) -> [VocalizationVariantSpec] {
        // Prioritize compact backchannels + contextual lead-ins for 8 GB efficiency, plus rich variants.
        var specs: [VocalizationVariantSpec] = [
            VocalizationVariantSpec(vocalization: .uhum, intonation: .brief, rateScale: 1.05, silenceScale: 0.16, defaultIntensityGain: 0.34),
            VocalizationVariantSpec(vocalization: .uhum, intonation: .warm, rateScale: 0.96, silenceScale: 0.22, defaultIntensityGain: 0.38),
            VocalizationVariantSpec(vocalization: .aham, intonation: .engaged, rateScale: 1.04, silenceScale: 0.16, defaultIntensityGain: 0.36),
            VocalizationVariantSpec(vocalization: .sei, intonation: .brief, rateScale: 1.02, silenceScale: 0.18, defaultIntensityGain: 0.33),
            VocalizationVariantSpec(vocalization: .entendi, intonation: .engaged, rateScale: 1.02, silenceScale: 0.18, defaultIntensityGain: 0.36),
            VocalizationVariantSpec(vocalization: .certo, intonation: .brief, rateScale: 1.04, silenceScale: 0.16, defaultIntensityGain: 0.35),
            VocalizationVariantSpec(vocalization: .ahSim, intonation: .warm, rateScale: 1.05, silenceScale: 0.18, defaultIntensityGain: 0.42),
            VocalizationVariantSpec(vocalization: .interessante, intonation: .engaged, rateScale: 0.99, silenceScale: 0.22, defaultIntensityGain: 0.40),
            VocalizationVariantSpec(vocalization: .hmm, intonation: .reflective, rateScale: 0.90, silenceScale: 0.30, defaultIntensityGain: 0.44),
            VocalizationVariantSpec(vocalization: .olha, intonation: .engaged, rateScale: 1.02, silenceScale: 0.18, defaultIntensityGain: 0.48),
            VocalizationVariantSpec(vocalization: .boaPergunta, intonation: .warm, rateScale: 0.97, silenceScale: 0.22, defaultIntensityGain: 0.50)
        ]
        if profile.profilePreset == .professional {
            specs = specs.filter { $0.vocalization == .certo || $0.vocalization == .entendi || $0.vocalization == .hmm }
        }
        return specs
    }

    /// Invalidates all in-memory clips immediately whenever voice identity, language, or TTS engine changes.
    @discardableResult
    public func syncIdentityContext(_ context: VocalizationIdentityContext) -> Bool {
        let changed: Bool = lock.withLock {
            guard activeContext?.signature != context.signature else { return false }
            activeContext = context
            clipsByTag.removeAll(keepingCapacity: false)
            generationEpoch &+= 1
            return true
        }
        if changed {
            prewarmTask?.cancel()
            prewarmTask = nil
            isPrewarming = false
            activeSignature = context.signature
            refreshPublishedStats()
            // Restore pre-rendered disk clips ONLY for this exact matching voice/engine/language hash.
            loadPersistedClipsForCurrentContext(context)
        }
        return changed
    }

    public func invalidateAll(reason: String = "Alteração de identidade vocal") {
        prewarmTask?.cancel()
        prewarmTask = nil
        lock.withLock {
            clipsByTag.removeAll(keepingCapacity: false)
            generationEpoch &+= 1
        }
        isPrewarming = false
        lastGenerationSummary = "Cache invalidada (\(reason))"
        refreshPublishedStats()
    }

    public func trimOnMemoryPressure(_ level: VoiceMemoryPressureLevel) {
        switch level {
        case .normal:
            return
        case .warning:
            lock.withLock {
                let keepKinds: Set<VocalizationKind> = [.uhum, .aham, .certo, .entendi, .hmm]
                clipsByTag = clipsByTag.filter { keepKinds.contains($0.value.kind) }
            }
            refreshPublishedStats()
        case .critical:
            lock.withLock {
                clipsByTag.removeAll(keepingCapacity: false)
                generationEpoch &+= 1
            }
            refreshPublishedStats()
        }
    }

    /// Fast O(1) lock lookup preserving strict voice identity match.
    public func acquireClip(
        kind: VocalizationKind,
        preferredIntonation: VocalizationIntonation? = nil,
        expectedContext: VocalizationIdentityContext
    ) -> CachedVocalizationClip? {
        let nowNs = DispatchTime.now().uptimeNanoseconds
        let result: CachedVocalizationClip? = lock.withLock {
            guard activeContext?.signature == expectedContext.signature else {
                return nil
            }
            if let pref = preferredIntonation,
               let exact = clipsByTag["\(kind.rawValue)_\(pref.rawValue)"],
               exact.voiceSignature == expectedContext.signature {
                var updated = exact
                updated.lastUsedNs = nowNs
                clipsByTag["\(kind.rawValue)_\(pref.rawValue)"] = updated
                return updated
            }
            if let match = clipsByTag.first(where: { $0.value.kind == kind && $0.value.voiceSignature == expectedContext.signature }) {
                var updated = match.value
                updated.lastUsedNs = nowNs
                clipsByTag[match.key] = updated
                return updated
            }
            return nil
        }

        if result != nil {
            hitCount += 1
        } else {
            missCount += 1
        }
        return result
    }

    public func recordDeliveredDecisionLatencyMs(_ ms: Double) {
        lastPlaybackLatencyMs = ms
    }

    public func storeClip(_ clip: CachedVocalizationClip, expectedEpoch: UInt64) {
        let tag = "\(clip.kind.rawValue)_\(clip.intonation.rawValue)"
        lock.withLock {
            guard generationEpoch == expectedEpoch,
                  activeContext?.signature == clip.voiceSignature,
                  !clip.samples24k.isEmpty else {
                return
            }
            clipsByTag[tag] = clip
            enforceMemoryBudgetLocked()
        }
        refreshPublishedStats()
    }

    public func startBackgroundPrewarm(
        context: VocalizationIdentityContext,
        profile: VoiceBehaviorProfile,
        generator: @escaping VocalizationPCMGenerator
    ) {
        _ = syncIdentityContext(context)
        let specs = Self.defaultPrewarmSpecs(for: profile)
        let missingSpecs: [VocalizationVariantSpec] = lock.withLock {
            specs.filter { clipsByTag[$0.variantTag] == nil }
        }
        guard !missingSpecs.isEmpty else {
            lastGenerationSummary = "Cache pronta (\(cachedClipsCount) variações · \(context.voicePreference))"
            return
        }

        prewarmTask?.cancel()
        let expectedEpoch = lock.withLock { generationEpoch }
        isPrewarming = true

        prewarmTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            var generatedCount = 0
            for spec in missingSpecs {
                if Task.isCancelled { break }
                let stillValid = await MainActor.run {
                    self.lock.withLock { self.generationEpoch == expectedEpoch && self.activeContext?.signature == context.signature }
                }
                if !stillValid { break }

                let phrase = spec.vocalization.spokenText(for: context.language)
                let t0 = DispatchTime.now().uptimeNanoseconds
                do {
                    let rawSamples = try await generator(
                        phrase,
                        context.language,
                        context.voicePreference,
                        spec.rateScale,
                        spec.silenceScale
                    )
                    if Task.isCancelled { break }
                    let trimmed = Self.trimEdgeSilence(rawSamples, threshold: 0.004, sampleRate: 24_000)
                    guard !trimmed.isEmpty else { continue }
                    let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000.0
                    let durMs = (Double(trimmed.count) / 24_000.0) * 1000.0
                    let clip = CachedVocalizationClip(
                        kind: spec.vocalization,
                        intonation: spec.intonation,
                        voiceSignature: context.signature,
                        text: phrase,
                        communicativeIntent: spec.vocalization.communicativeIntent,
                        samples24k: trimmed,
                        sampleRate: 24_000,
                        durationMs: durMs,
                        generationLatencyMs: elapsedMs,
                        defaultGain: spec.defaultIntensityGain,
                        lastUsedNs: DispatchTime.now().uptimeNanoseconds
                    )
                    await MainActor.run {
                        self.storeClip(clip, expectedEpoch: expectedEpoch)
                        self.saveClipToDisk(clip, context: context, variantTag: spec.variantTag)
                    }
                    generatedCount += 1
                    try? await Task.sleep(nanoseconds: 25_000_000) // Yield smoothly between clips
                } catch {
                    continue
                }
            }

            let finalGeneratedCount = generatedCount
            await MainActor.run {
                self.isPrewarming = false
                if self.lock.withLock({ self.generationEpoch == expectedEpoch }) {
                    self.lastGenerationSummary = "Cache pronta: \(self.cachedClipsCount) amostras em \(context.voicePreference) (novas: \(finalGeneratedCount))"
                }
            }
        }
    }

    nonisolated public static func trimEdgeSilence(_ samples: [Float], threshold: Float = 0.004, sampleRate: Int = 24_000) -> [Float] {
        guard !samples.isEmpty else { return [] }
        let padSamples = max(120, sampleRate / 60) // Keep ~16ms gentle fade padding
        guard let firstNonSilent = samples.firstIndex(where: { abs($0) >= threshold }),
              let lastNonSilent = samples.lastIndex(where: { abs($0) >= threshold }) else {
            return samples
        }
        let start = max(0, firstNonSilent - padSamples)
        let end = min(samples.count - 1, lastNonSilent + padSamples)
        guard start <= end else { return samples }
        var slice = Array(samples[start...end])
        let fadeLen = min(slice.count / 4, max(48, sampleRate / 120))
        if fadeLen > 1 {
            for i in 0..<fadeLen {
                let f = Float(i + 1) / Float(fadeLen)
                slice[i] *= f
                slice[slice.count - 1 - i] *= f
            }
        }
        return slice
    }

    private func enforceMemoryBudgetLocked() {
        var total = clipsByTag.values.reduce(0) { $0 + $1.memoryBytes }
        while total > maxMemoryBytes && !clipsByTag.isEmpty {
            guard let oldestKey = clipsByTag.min(by: { $0.value.lastUsedNs < $1.value.lastUsedNs })?.key else {
                break
            }
            if let removed = clipsByTag.removeValue(forKey: oldestKey) {
                total -= removed.memoryBytes
            }
        }
    }

    private func refreshPublishedStats() {
        let (count, bytes) = lock.withLock { () -> (Int, Int) in
            let total = clipsByTag.values.reduce(0) { $0 + $1.memoryBytes }
            return (clipsByTag.count, total)
        }
        cachedClipsCount = count
        cacheMemoryMB = Double(bytes) / (1024.0 * 1024.0)
    }

    private func loadPersistedClipsForCurrentContext(_ context: VocalizationIdentityContext) {
        let dir = diskRootDirectory.appendingPathComponent(context.signatureHash, isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path),
              let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return
        }
        let specs = VocalizationVariantSpecDefaults.allLookup
        let expectedEpoch = lock.withLock { generationEpoch }
        for url in files where url.pathExtension.lowercased() == "pcm24" {
            let tag = url.deletingPathExtension().lastPathComponent
            guard let meta = specs[tag],
                  let data = try? Data(contentsOf: url),
                  data.count >= 400 else { continue }
            let floats = AudioPCMConverter.pcm16DataToFloats(data)
            let clip = CachedVocalizationClip(
                kind: meta.vocalization,
                intonation: meta.intonation,
                voiceSignature: context.signature,
                text: meta.vocalization.spokenText(for: context.language),
                communicativeIntent: meta.vocalization.communicativeIntent,
                samples24k: floats,
                sampleRate: 24_000,
                durationMs: (Double(floats.count) / 24_000.0) * 1000.0,
                generationLatencyMs: 0,
                defaultGain: meta.defaultIntensityGain,
                lastUsedNs: DispatchTime.now().uptimeNanoseconds
            )
            storeClip(clip, expectedEpoch: expectedEpoch)
        }
    }

    private func saveClipToDisk(_ clip: CachedVocalizationClip, context: VocalizationIdentityContext, variantTag: String) {
        let dir = diskRootDirectory.appendingPathComponent(context.signatureHash, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fileURL = dir.appendingPathComponent("\(variantTag).pcm24", isDirectory: false)
        let pcm16 = AudioPCMConverter.floatsToPCM16Data(clip.samples24k)
        try? pcm16.write(to: fileURL, options: [.atomic])
    }
}

private enum VocalizationVariantSpecDefaults {
    static let allLookup: [String: VocalizationVariantSpec] = {
        var map: [String: VocalizationVariantSpec] = [:]
        for v in VocalizationKind.allCases {
            for into in [VocalizationIntonation.brief, .engaged, .reflective, .warm] {
                let spec = VocalizationVariantSpec(
                    vocalization: v,
                    intonation: into,
                    rateScale: into == .reflective ? 0.90 : (into == .brief ? 1.04 : 1.0),
                    silenceScale: into == .reflective ? 0.28 : 0.18,
                    defaultIntensityGain: v.isBackchannelCandidate ? 0.36 : 0.48
                )
                map[spec.variantTag] = spec
            }
        }
        return map
    }()
}

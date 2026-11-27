import Darwin
import Foundation
#if canImport(Metal)
import Metal
#endif
import os
import SQLite3

// MARK: - Log & Telemetry Privacy Redactor (Sections 12 & 18)

public enum VoiceLogRedactor {
    private static let patterns: [(regex: NSRegularExpression, replacement: String)] = {
        let defs: [(String, String)] = [
            ("sk-[A-Za-z0-9_-]{8,}", "[REDACTED_OPENAI_KEY]"),
            ("AIza[A-Za-z0-9_-]{12,}", "[REDACTED_GOOGLE_KEY]"),
            ("Bearer\\s+[A-Za-z0-9._\\-]{8,}", "Bearer [REDACTED_TOKEN]"),
            ("Token\\s+[A-Za-z0-9._\\-]{8,}", "Token [REDACTED_TOKEN]"),
            ("xi-api-key[\"':=\\s]+[A-Za-z0-9._\\-]{8,}", "xi-api-key: [REDACTED]"),
            ("[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}", "[REDACTED_EMAIL]"),
            ("/Users/[^/\\s]+", "~")
        ]
        return defs.compactMap { pattern, rep in
            let opts: NSRegularExpression.Options = pattern.contains("@") ? [.caseInsensitive] : []
            guard let rx = try? NSRegularExpression(pattern: pattern, options: opts) else { return nil }
            return (rx, rep)
        }
    }()

    public static func redact(_ text: String) -> String {
        var result = text
        for entry in patterns {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = entry.regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: entry.replacement)
        }
        return result
    }
}

// MARK: - Tiered Hybrid Memory & Cross-Provider Portability (Section 15)

public struct VoiceTurnRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let role: String // "user" or "assistant"
    public let text: String
    public let providerID: String
    public let wasInterruptedByBargeIn: Bool
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        role: String,
        text: String,
        providerID: String,
        wasInterruptedByBargeIn: Bool = false,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.providerID = providerID
        self.wasInterruptedByBargeIn = wasInterruptedByBargeIn
        self.timestamp = timestamp
    }
}

public struct VoiceWorkspaceContextSnapshot: Equatable, Codable, Sendable {
    public var projectName: String?
    public var workspaceDirectoryDisplay: String? // Redacted relative/tilde path
    public var securityModeName: String
    public var activeExecutionAgent: String
    public var activeTasksCount: Int

    public static let empty = VoiceWorkspaceContextSnapshot(
        projectName: nil,
        workspaceDirectoryDisplay: nil,
        securityModeName: "Somente leitura",
        activeExecutionAgent: "WisdAI",
        activeTasksCount: 0
    )
}

public struct PersistentVoicePreferencesMemory: Equatable, Codable, Sendable {
    public var preferredAddressName: String
    public var learnedPreferences: [String]
    public var lastUpdated: Date

    public static let empty = PersistentVoicePreferencesMemory(
        preferredAddressName: "",
        learnedPreferences: [],
        lastUpdated: Date()
    )
}

public struct PortableVoiceContextSnapshot: Equatable, Codable, Sendable {
    public let exportedAt: Date
    public let sourceProviderID: String
    public let targetProviderID: String
    public let prosodicAudioContinuityPreserved: Bool // Always false across distinct vendors
    public let compactedSummary: String
    public let recentTurns: [CodexContinuityItem]
    public let workspaceContext: VoiceWorkspaceContextSnapshot

    public func renderPortableSystemContext() -> String {
        var sections: [String] = []
        if let project = workspaceContext.projectName, !project.isEmpty {
            sections.append("Workspace project: \(project) (mode: \(workspaceContext.securityModeName), agent: \(workspaceContext.activeExecutionAgent)).")
        }
        if !compactedSummary.isEmpty {
            sections.append("Compacted prior conversation summary:\n\(compactedSummary)")
        }
        if !recentTurns.isEmpty {
            let tail = recentTurns.suffix(12).map { item in
                let who = item.role == "user" ? "User" : "Assistant"
                return "\(who): \(item.text)"
            }.joined(separator: "\n")
            sections.append("Recent verbatim turns:\n\(tail)")
        }
        return sections.joined(separator: "\n\n")
    }
}

@MainActor
public final class VoiceMemoryStore: ObservableObject {
    @Published public private(set) var sessionTurns: [VoiceTurnRecord] = []
    @Published public private(set) var compactedSummary: String = ""
    @Published public private(set) var compactionCount: Int = 0
    @Published public private(set) var workspaceContext: VoiceWorkspaceContextSnapshot = .empty
    @Published public private(set) var persistentMemory: PersistentVoicePreferencesMemory = .empty

    public let hardwareProfile: HardwareMemoryProfile
    private let persistentStorageURL: URL

    public init(
        hardwareProfile: HardwareMemoryProfile = .detect(),
        persistentStorageURL: URL? = nil
    ) {
        self.hardwareProfile = hardwareProfile
        if let persistentStorageURL {
            self.persistentStorageURL = persistentStorageURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
            self.persistentStorageURL = support
                .appendingPathComponent("WisdAI/Voice", isDirectory: true)
                .appendingPathComponent("persistent_preferences.json", isDirectory: false)
        }
        loadPersistentIfPermitted(policy: VoicePolicyPreferences.load())
    }

    public func updateWorkspaceContext(_ context: VoiceWorkspaceContextSnapshot) {
        workspaceContext = VoiceWorkspaceContextSnapshot(
            projectName: context.projectName,
            workspaceDirectoryDisplay: context.workspaceDirectoryDisplay.map { VoiceLogRedactor.redact($0) },
            securityModeName: context.securityModeName,
            activeExecutionAgent: context.activeExecutionAgent,
            activeTasksCount: context.activeTasksCount
        )
    }

    public func seedFromHistoryItems(_ items: [CodexContinuityItem], providerID: String) {
        let seeded: [VoiceTurnRecord] = items
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .suffix(hardwareProfile.maxInMemoryTurns)
            .map { item in
                VoiceTurnRecord(
                    role: item.role == "user" ? "user" : "assistant",
                    text: item.text,
                    providerID: providerID
                )
            }
        sessionTurns = seeded
        compactedSummary = ""
        compactIfNeeded()
    }

    public func appendUserTurn(_ text: String, providerID: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        sessionTurns.append(VoiceTurnRecord(role: "user", text: clean, providerID: providerID))
        compactIfNeeded()
    }

    public func appendAssistantTurn(
        _ heardText: String,
        providerID: String,
        wasInterruptedByBargeIn: Bool = false
    ) {
        let clean = heardText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let recorded = wasInterruptedByBargeIn ? "\(clean) [interrompido pelo usuário]" : clean
        sessionTurns.append(
            VoiceTurnRecord(
                role: "assistant",
                text: recorded,
                providerID: providerID,
                wasInterruptedByBargeIn: wasInterruptedByBargeIn
            )
        )
        compactIfNeeded()
    }

    /// Progressive compaction keeps memory footprint bounded for 8 GB/16 GB/24 GB/32 GB devices.
    public func compactIfNeeded() {
        let trigger = hardwareProfile.compactionTriggerTurns
        let keepRecent = max(6, trigger / 2)
        guard sessionTurns.count > trigger else { return }

        let overflowCount = sessionTurns.count - keepRecent
        guard overflowCount > 0 else { return }
        let evicted = Array(sessionTurns.prefix(overflowCount))
        sessionTurns = Array(sessionTurns.suffix(keepRecent))

        var bullets: [String] = []
        if !compactedSummary.isEmpty {
            bullets.append(compactedSummary)
        }
        for turn in evicted {
            let roleTag = turn.role == "user" ? "Usuário" : "Assistente"
            let condensed = turn.text
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let clipped = condensed.count > 160 ? String(condensed.prefix(157)) + "…" : condensed
            bullets.append("• \(roleTag): \(clipped)")
        }

        var merged = bullets.joined(separator: "\n")
        let maxSummaryChars = hardwareProfile == .low8GB ? 1800 : 3600
        if merged.count > maxSummaryChars {
            merged = String(merged.suffix(maxSummaryChars))
            if let newlineIdx = merged.firstIndex(of: "\n") {
                merged = String(merged[merged.index(after: newlineIdx)...])
            }
        }
        compactedSummary = merged
        compactionCount += 1
    }

    public func exportPortableSnapshot(targetProviderID: String) -> PortableVoiceContextSnapshot {
        let sourceID = sessionTurns.last?.providerID ?? "none"
        let continuity = sessionTurns.suffix(12).map {
            CodexContinuityItem(role: $0.role, text: $0.text)
        }
        return PortableVoiceContextSnapshot(
            exportedAt: Date(),
            sourceProviderID: sourceID,
            targetProviderID: targetProviderID,
            prosodicAudioContinuityPreserved: false,
            compactedSummary: compactedSummary,
            recentTurns: continuity,
            workspaceContext: workspaceContext
        )
    }

    public func recordPersistentPreference(_ note: String, policy: VoicePolicyPreferences) {
        guard policy.allowPersistentVoiceMemory else { return }
        let clean = VoiceLogRedactor.redact(note.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !clean.isEmpty else { return }
        if !persistentMemory.learnedPreferences.contains(clean) {
            persistentMemory.learnedPreferences.append(clean)
            if persistentMemory.learnedPreferences.count > 24 {
                persistentMemory.learnedPreferences.removeFirst(persistentMemory.learnedPreferences.count - 24)
            }
            persistentMemory.lastUpdated = Date()
            savePersistentIfPermitted(policy: policy)
        }
    }

    public func loadPersistentIfPermitted(policy: VoicePolicyPreferences) {
        guard policy.allowPersistentVoiceMemory else {
            persistentMemory = .empty
            return
        }
        guard let data = try? Data(contentsOf: persistentStorageURL),
              let decoded = try? JSONDecoder().decode(PersistentVoicePreferencesMemory.self, from: data) else {
            persistentMemory = .empty
            return
        }
        persistentMemory = decoded
    }

    public func savePersistentIfPermitted(policy: VoicePolicyPreferences) {
        guard policy.allowPersistentVoiceMemory else { return }
        let dir = persistentStorageURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard let data = try? JSONEncoder().encode(persistentMemory) else { return }
        try? data.write(to: persistentStorageURL, options: [.atomic])
    }

    public func clearPersistentMemory() {
        persistentMemory = .empty
        try? FileManager.default.removeItem(at: persistentStorageURL)
    }

    public func resetSessionMemory() {
        sessionTurns = []
        compactedSummary = ""
    }
}

// MARK: - Real Latency, Audio & Resource Telemetry (Sections 14, 17, 19)

public struct LatencySummaryStats: Equatable, Sendable {
    public let count: Int
    public let latestMs: Double
    public let p50Ms: Double
    public let p95Ms: Double

    public static let empty = LatencySummaryStats(count: 0, latestMs: 0, p50Ms: 0, p95Ms: 0)

    public static func compute(from samples: [Double]) -> LatencySummaryStats {
        guard !samples.isEmpty else { return .empty }
        let sorted = samples.sorted()
        let p50Idx = Int(Double(sorted.count - 1) * 0.50)
        let p95Idx = Int(Double(sorted.count - 1) * 0.95)
        return LatencySummaryStats(
            count: sorted.count,
            latestMs: samples.last ?? 0,
            p50Ms: sorted[p50Idx],
            p95Ms: sorted[p95Idx]
        )
    }
}

public enum VoiceComponentKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case interface
    case permissions
    case audioCapture
    case audioPlayback
    case vad
    case stt
    case llm
    case tts
    case agentOrchestrator

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .interface: return "Interface de Voz"
        case .permissions: return "Permissões macOS"
        case .audioCapture: return "Captura (Microfone)"
        case .audioPlayback: return "Reprodução (Áudio)"
        case .vad: return "VAD Semântico"
        case .stt: return "Reconhecimento (STT)"
        case .llm: return "Cérebro Local (LLM)"
        case .tts: return "Síntese Vocal (TTS)"
        case .agentOrchestrator: return "Agentes Externos"
        }
    }
}

public enum VoiceComponentHealthState: String, Codable, Sendable {
    case idle = "Inativo"
    case initializing = "Inicializando"
    case ready = "Operacional"
    case degraded = "Degradado (Fallback Seguro)"
    case unavailable = "Indisponível / Não Instalado"
    case error = "Erro"
}

public struct VoiceComponentStatusSnapshot: Identifiable, Equatable, Sendable {
    public var id: String { kind.rawValue }
    public let kind: VoiceComponentKind
    public var state: VoiceComponentHealthState
    public var activeEngineOrModel: String
    public var latencyMs: Double?
    public var lastError: String?
    public var dependencyHint: String?
    public var updatedAt: Date

    public init(
        kind: VoiceComponentKind,
        state: VoiceComponentHealthState = .idle,
        activeEngineOrModel: String = "—",
        latencyMs: Double? = nil,
        lastError: String? = nil,
        dependencyHint: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.kind = kind
        self.state = state
        self.activeEngineOrModel = activeEngineOrModel
        self.latencyMs = latencyMs
        self.lastError = lastError
        self.dependencyHint = dependencyHint
        self.updatedAt = updatedAt
    }
}

public struct ProcessResourceSnapshot: Equatable, Sendable {
    public let residentMemoryMB: Double
    public let cpuPercent: Double
    public let physicalRAMGB: Double
    public let gpuName: String
    public let gpuMaxRecommendedMB: UInt64
    public let cpuCoreCount: Int
}

public struct VoiceDiagnosticEvent: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let category: String
    public let message: String
}

public enum ProcessResourceProbe {
    private static let detectedGPU: (name: String, maxMB: UInt64) = {
        #if canImport(Metal)
        if let dev = MTLCreateSystemDefaultDevice() {
            return (dev.name, UInt64(dev.recommendedMaxWorkingSetSize / (1024 * 1024)))
        }
        #endif
        return ("Apple Silicon / Sistema", 0)
    }()

    public static func sample() -> ProcessResourceSnapshot {
        var vmInfo = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<natural_t>.stride)
        let memStatus = withUnsafeMutablePointer(to: &vmInfo) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }
        let footprintBytes: UInt64 = memStatus == KERN_SUCCESS ? vmInfo.phys_footprint : 0
        let memMB = Double(footprintBytes) / (1024.0 * 1024.0)

        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        var totalCPUPercent: Double = 0
        if task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS,
           let list = threadList {
            defer {
                let size = vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride)
                vm_deallocate(mach_task_self_, vm_address_t(bitPattern: list), size)
            }
            for i in 0..<Int(threadCount) {
                var thInfo = thread_basic_info()
                var thCount = mach_msg_type_number_t(THREAD_INFO_MAX)
                let kr = withUnsafeMutablePointer(to: &thInfo) { ptr in
                    ptr.withMemoryRebound(to: integer_t.self, capacity: Int(thCount)) { intPtr in
                        thread_info(list[i], thread_flavor_t(THREAD_BASIC_INFO), intPtr, &thCount)
                    }
                }
                if kr == KERN_SUCCESS && (thInfo.flags & TH_FLAGS_IDLE) == 0 {
                    totalCPUPercent += (Double(thInfo.cpu_usage) / Double(TH_USAGE_SCALE)) * 100.0
                }
            }
        }

        let totalGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
        return ProcessResourceSnapshot(
            residentMemoryMB: memMB,
            cpuPercent: totalCPUPercent,
            physicalRAMGB: totalGB,
            gpuName: detectedGPU.name,
            gpuMaxRecommendedMB: detectedGPU.maxMB,
            cpuCoreCount: ProcessInfo.processInfo.activeProcessorCount
        )
    }
}

@MainActor
public final class VoiceTelemetryRecorder: ObservableObject {
    @Published public private(set) var sttStats: LatencySummaryStats = .empty
    @Published public private(set) var llmFirstChunkStats: LatencySummaryStats = .empty
    @Published public private(set) var ttsFirstAudioStats: LatencySummaryStats = .empty
    @Published public private(set) var e2eResponseStats: LatencySummaryStats = .empty
    @Published public private(set) var bargeInStopStats: LatencySummaryStats = .empty
    @Published public private(set) var reconnectCount: Int = 0
    @Published public private(set) var activeProviderLabel: String = "Apple Speech + Natural PCM"
    @Published public private(set) var resourceSnapshot: ProcessResourceSnapshot = ProcessResourceProbe.sample()
    @Published public private(set) var diagnosticLogs: [VoiceDiagnosticEvent] = []

    private var sttSamples: [Double] = []
    private var llmSamples: [Double] = []
    private var ttsSamples: [Double] = []
    private var e2eSamples: [Double] = []
    private var bargeInSamples: [Double] = []
    private let maxSamples = 64

    public init() {}

    public func setActiveProviderLabel(_ label: String) {
        activeProviderLabel = VoiceLogRedactor.redact(label)
    }

    public func recordSTTLatency(ms: Double) {
        appendSample(ms, into: &sttSamples)
        sttStats = LatencySummaryStats.compute(from: sttSamples)
    }

    public func recordLLMFirstChunkLatency(ms: Double) {
        appendSample(ms, into: &llmSamples)
        llmFirstChunkStats = LatencySummaryStats.compute(from: llmSamples)
    }

    public func recordTTSFirstAudioLatency(ms: Double) {
        appendSample(ms, into: &ttsSamples)
        ttsFirstAudioStats = LatencySummaryStats.compute(from: ttsSamples)
    }

    public func recordEndToEndResponseLatency(ms: Double) {
        appendSample(ms, into: &e2eSamples)
        e2eResponseStats = LatencySummaryStats.compute(from: e2eSamples)
    }

    public func recordBargeInStopLatency(ms: Double) {
        appendSample(ms, into: &bargeInSamples)
        bargeInStopStats = LatencySummaryStats.compute(from: bargeInSamples)
        log(category: "BargeIn", message: String(format: "Interrupção concluída em %.1f ms", ms))
    }

    public func recordReconnect(reason: String) {
        reconnectCount += 1
        log(category: "Reconnect", message: reason)
    }

    public func refreshResources() {
        resourceSnapshot = ProcessResourceProbe.sample()
    }

    public func log(category: String, message: String) {
        let safeMsg = VoiceLogRedactor.redact(message)
        diagnosticLogs.append(VoiceDiagnosticEvent(timestamp: Date(), category: category, message: safeMsg))
        if diagnosticLogs.count > 120 {
            diagnosticLogs.removeFirst(diagnosticLogs.count - 120)
        }
    }

    private func appendSample(_ value: Double, into array: inout [Double]) {
        guard value >= 0, value.isFinite else { return }
        array.append(value)
        if array.count > maxSamples {
            array.removeFirst(array.count - maxSamples)
        }
    }
}


// MARK: - Standalone Local Knowledge Store (SQLite FTS5 + OpenJarvis-Inspired Trust Tiers)

public enum VoiceMemoryTrustTier: String, Codable, Sendable {
    case trusted
    case auto
    case untrusted

    public var isRecallable: Bool {
        self == .trusted || self == .auto
    }
}

public struct VoiceKnowledgeRecord: Identifiable, Equatable, Sendable {
    public let id: String
    public let content: String
    public let source: String
    public let projectScope: String
    public let trustTier: VoiceMemoryTrustTier
    public let score: Double
    public let createdAt: TimeInterval
}

public final class VoiceSQLiteKnowledgeStore: @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSLock()
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(databaseURL: URL? = nil) {
        let url: URL
        if let databaseURL {
            url = databaseURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
            let dir = support.appendingPathComponent("WisdAI/Voice", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            url = dir.appendingPathComponent("voice_knowledge_fts.sqlite")
        }
        if sqlite3_open(url.path, &db) == SQLITE_OK {
            createSchema()
        }
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    private func createSchema() {
        let sql = """
        PRAGMA journal_mode=WAL;
        CREATE TABLE IF NOT EXISTS voice_facts (
            id TEXT PRIMARY KEY,
            content TEXT NOT NULL,
            source TEXT NOT NULL,
            project_scope TEXT NOT NULL,
            trust_tier TEXT NOT NULL,
            created_at REAL NOT NULL
        );
        CREATE VIRTUAL TABLE IF NOT EXISTS voice_facts_fts USING fts5(
            fact_id UNINDEXED,
            content,
            source,
            project_scope UNINDEXED,
            tokenize='unicode61'
        );
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    /// Quarantine heuristic prevents untrusted prompt-injection snippets from re-entering model context.
    public static func classifyTrustTier(for text: String, explicitTrusted: Bool = false) -> VoiceMemoryTrustTier {
        if explicitTrusted { return .trusted }
        let lower = text.lowercased()
        let injectionSignals = [
            "ignore previous instructions", "ignore as instruções anteriores",
            "system prompt:", "execute rm -rf", "<system>", "assistant override"
        ]
        if injectionSignals.contains(where: { lower.contains($0) }) {
            return .untrusted
        }
        return .auto
    }

    @discardableResult
    public func storeFact(
        _ text: String,
        source: String = "voice_session",
        projectScope: String = "global",
        explicitTrusted: Bool = false
    ) -> VoiceKnowledgeRecord? {
        let clean = VoiceLogRedactor.redact(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !clean.isEmpty else { return nil }
        let tier = Self.classifyTrustTier(for: clean, explicitTrusted: explicitTrusted)
        let id = UUID().uuidString
        let now = Date().timeIntervalSince1970

        lock.lock()
        defer { lock.unlock() }
        guard let db else { return nil }

        let insertSQL = "INSERT OR REPLACE INTO voice_facts (id, content, source, project_scope, trust_tier, created_at) VALUES (?, ?, ?, ?, ?, ?);"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 2, clean, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 3, source, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 4, projectScope, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 5, tier.rawValue, -1, Self.sqliteTransient)
            sqlite3_bind_double(stmt, 6, now)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }

        if tier.isRecallable {
            let ftsSQL = "INSERT INTO voice_facts_fts (fact_id, content, source, project_scope) VALUES (?, ?, ?, ?);"
            var ftsStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, ftsSQL, -1, &ftsStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(ftsStmt, 1, id, -1, Self.sqliteTransient)
                sqlite3_bind_text(ftsStmt, 2, clean, -1, Self.sqliteTransient)
                sqlite3_bind_text(ftsStmt, 3, source, -1, Self.sqliteTransient)
                sqlite3_bind_text(ftsStmt, 4, projectScope, -1, Self.sqliteTransient)
                sqlite3_step(ftsStmt)
                sqlite3_finalize(ftsStmt)
            }
        }
        return VoiceKnowledgeRecord(
            id: id,
            content: clean,
            source: source,
            projectScope: projectScope,
            trustTier: tier,
            score: 1.0,
            createdAt: now
        )
    }

    public func searchRecallableFacts(query: String, projectScope: String, limit: Int = 5) -> [VoiceKnowledgeRecord] {
        let tokens = query
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 }
        guard !tokens.isEmpty else { return [] }
        let matchExpr = tokens.prefix(6).joined(separator: " OR ")

        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }

        let sql = """
        SELECT vf.id, vf.content, vf.source, vf.project_scope, vf.trust_tier, vf.created_at, bm25(voice_facts_fts) as rank
        FROM voice_facts_fts fts
        JOIN voice_facts vf ON vf.id = fts.fact_id
        WHERE voice_facts_fts MATCH ?
          AND (vf.project_scope = ? OR vf.project_scope = 'global')
          AND vf.trust_tier IN ('trusted', 'auto')
        ORDER BY rank ASC
        LIMIT ?;
        """
        var stmt: OpaquePointer?
        var out: [VoiceKnowledgeRecord] = []
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, matchExpr, -1, Self.sqliteTransient)
            sqlite3_bind_text(stmt, 2, projectScope, -1, Self.sqliteTransient)
            sqlite3_bind_int(stmt, 3, Int32(max(1, min(limit, 20))))
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                let content = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                let source = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
                let scope = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? "global"
                let tierRaw = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? "auto"
                let ts = sqlite3_column_double(stmt, 5)
                let bm25Rank = sqlite3_column_double(stmt, 6)
                out.append(VoiceKnowledgeRecord(
                    id: id,
                    content: content,
                    source: source,
                    projectScope: scope,
                    trustTier: VoiceMemoryTrustTier(rawValue: tierRaw) ?? .auto,
                    score: max(0.0, 1.0 / (1.0 + abs(bm25Rank))),
                    createdAt: ts
                ))
            }
            sqlite3_finalize(stmt)
        }
        return out
    }

    public func clearAllFacts() {
        lock.lock()
        defer { lock.unlock() }
        sqlite3_exec(db, "DELETE FROM voice_facts; DELETE FROM voice_facts_fts;", nil, nil, nil)
    }
}

// MARK: - macOS System Memory Pressure Watcher (Section 14 & 17)

public enum VoiceMemoryPressureLevel: String, Sendable {
    case normal = "Normal"
    case warning = "Atenção"
    case critical = "Crítica"
}

@MainActor
public final class VoiceMemoryPressureWatcher: ObservableObject {
    @Published public private(set) var level: VoiceMemoryPressureLevel = .normal
    private var source: DispatchSourceMemoryPressure?

    public init(onPressure: (@MainActor @Sendable (VoiceMemoryPressureLevel) -> Void)? = nil) {
        let src = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let mask = src.data
                let next: VoiceMemoryPressureLevel = mask.contains(.critical) ? .critical : (mask.contains(.warning) ? .warning : .normal)
                self.level = next
                onPressure?(next)
            }
        }
        src.resume()
        self.source = src
    }
}

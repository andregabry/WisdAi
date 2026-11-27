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
            ("sk-ant-[A-Za-z0-9_-]{8,}", "[REDACTED_ANTHROPIC_KEY]"),
            ("sk-[A-Za-z0-9_-]{8,}", "[REDACTED_OPENAI_KEY]"),
            ("AIza[A-Za-z0-9_-]{12,}", "[REDACTED_GOOGLE_KEY]"),
            ("ghp_[A-Za-z0-9]{16,}", "[REDACTED_GITHUB_TOKEN]"),
            ("github_pat_[A-Za-z0-9_]{20,}", "[REDACTED_GITHUB_PAT]"),
            ("hf_[A-Za-z0-9]{16,}", "[REDACTED_HF_TOKEN]"),
            ("xox[baprs]-[A-Za-z0-9-]{12,}", "[REDACTED_SLACK_TOKEN]"),
            ("AKIA[0-9A-Z]{16}", "[REDACTED_AWS_KEY]"),
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
    public var workspaceDirectoryDisplay: String? // Redacted relative/tilde path for UI
    public var securityModeName: String
    public var activeExecutionAgent: String
    public var activeTasksCount: Int
    public var projectID: UUID?
    public var workspaceID: String?
    public var absoluteDirectoryPath: String?
    public var resolvedProject: ResolvedProjectContext?
    public var selectedProviderID: String?
    public var selectedModelID: String?
    public var selectedEffortTitle: String?
    public var activeSessionID: String?

    public init(
        projectName: String?,
        workspaceDirectoryDisplay: String?,
        securityModeName: String,
        activeExecutionAgent: String,
        activeTasksCount: Int,
        projectID: UUID? = nil,
        workspaceID: String? = nil,
        absoluteDirectoryPath: String? = nil,
        resolvedProject: ResolvedProjectContext? = nil,
        selectedProviderID: String? = nil,
        selectedModelID: String? = nil,
        selectedEffortTitle: String? = nil,
        activeSessionID: String? = nil
    ) {
        self.projectName = projectName
        self.workspaceDirectoryDisplay = workspaceDirectoryDisplay
        self.securityModeName = securityModeName
        self.activeExecutionAgent = activeExecutionAgent
        self.activeTasksCount = activeTasksCount
        self.projectID = projectID
        self.workspaceID = workspaceID
        self.absoluteDirectoryPath = absoluteDirectoryPath
        self.resolvedProject = resolvedProject
        self.selectedProviderID = selectedProviderID
        self.selectedModelID = selectedModelID
        self.selectedEffortTitle = selectedEffortTitle
        self.activeSessionID = activeSessionID
    }

    public static let empty = VoiceWorkspaceContextSnapshot(
        projectName: nil,
        workspaceDirectoryDisplay: nil,
        securityModeName: "Somente leitura",
        activeExecutionAgent: "WisdAI",
        activeTasksCount: 0
    )

    public func renderDetailedContextBlock() -> String {
        var lines: [String] = []
        if let project = projectName, !project.isEmpty {
            let dirNote = resolvedProject?.directoryValidationError
                ?? absoluteDirectoryPath
                ?? workspaceDirectoryDisplay
                ?? "(não especificado)"
            lines.append("Projeto ativo: \(project) | Diretório: \(dirNote)")
        } else if let dirErr = resolvedProject?.directoryValidationError {
            lines.append("Diretório associado inacessível: \(dirErr)")
        } else if let abs = absoluteDirectoryPath, !abs.isEmpty {
            lines.append("Diretório ativo: \(abs)")
        }
        if let rp = resolvedProject {
            if let branch = rp.gitBranch, !branch.isEmpty {
                let status = rp.gitWorkingTreeStatus ?? "desconhecido"
                let repo = rp.gitRepositoryName ?? rp.projectName ?? "git"
                lines.append("Git: \(repo) · branch \(branch) · working tree: \(status)")
            }
            if !rp.projectConfigHighlights.isEmpty {
                lines.append("Arquivos de configuração raiz: \(rp.projectConfigHighlights.joined(separator: ", "))")
            }
        }
        let modelNote = selectedModelID.map { " | Modelo: \($0)" } ?? ""
        let effortNote = selectedEffortTitle.map { " | Esforço: \($0)" } ?? ""
        let providerNote = selectedProviderID.map { " (\($0))" } ?? ""
        lines.append("Agente selecionado: \(activeExecutionAgent)\(providerNote)\(modelNote)\(effortNote) | Permissões: \(securityModeName) | Tarefas ativas: \(activeTasksCount)")
        return lines.joined(separator: "\n")
    }
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
        let detailBlock = workspaceContext.renderDetailedContextBlock()
        if !detailBlock.isEmpty {
            sections.append(detailBlock)
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
        var copy = context
        copy.workspaceDirectoryDisplay = context.workspaceDirectoryDisplay.map { VoiceLogRedactor.redact($0) }
        workspaceContext = copy
    }

    public func seedFromHistoryItems(_ items: [CodexContinuityItem], providerID: String) {
        let filtered = VoiceMemoryHygieneAnalyzer.filterCleanContextItems(items)
        let seeded: [VoiceTurnRecord] = filtered
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

    public static func physicalFootprintMB(forPID pid: pid_t) -> Double {
        guard pid > 0 else { return 0 }
        var info = rusage_info_current()
        let rc = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rPtr in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, rPtr)
            }
        }
        guard rc == 0 else { return 0 }
        return Double(info.ri_phys_footprint) / (1024.0 * 1024.0)
    }
}

public enum VoicePipelineTraceStage: String, CaseIterable, Codable, Sendable {
    case microphone = "1. Microfone"
    case acousticProcessing = "2. Processamento Acústico"
    case partialSTT = "3. Transcrição Parcial"
    case finalSTT = "4. Transcrição Final"
    case retrievedContext = "5. Contexto Recuperado"
    case systemPrompt = "6. System Prompt"
    case conversationalModel = "7. Modelo Conversacional"
    case textReply = "8. Resposta Textual"
    case speechAdaptation = "9. Adaptação Oral"
    case vocalSynthesis = "10. Síntese Vocal"
    case playback = "11. Reprodução"
}

public struct VoicePipelineTraceEvent: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let stage: VoicePipelineTraceStage
    public let sessionToken: String
    public let turnEpoch: UInt64
    public let payload: String
}

@MainActor
public final class VoiceTelemetryRecorder: ObservableObject {
    @Published public private(set) var sttStats: LatencySummaryStats = .empty
    @Published public private(set) var sttSettlingStats: LatencySummaryStats = .empty
    @Published public private(set) var llmFirstChunkStats: LatencySummaryStats = .empty
    @Published public private(set) var firstClauseStats: LatencySummaryStats = .empty
    @Published public private(set) var ttsFirstAudioStats: LatencySummaryStats = .empty
    @Published public private(set) var ttsTotalSynthesisStats: LatencySummaryStats = .empty
    @Published public private(set) var firstAudiblePlaybackStats: LatencySummaryStats = .empty
    @Published public private(set) var e2eFromSpeechEndAudibleStats: LatencySummaryStats = .empty
    @Published public private(set) var e2eResponseStats: LatencySummaryStats = .empty
    @Published public private(set) var bargeInStopStats: LatencySummaryStats = .empty
    @Published public private(set) var bargeInAudibleStopStats: LatencySummaryStats = .empty
    @Published public private(set) var vocalizationCacheLatencyStats: LatencySummaryStats = .empty
    @Published public private(set) var backchannelsEmittedCount: Int = 0
    @Published public private(set) var backchannelsSuppressedCount: Int = 0
    @Published public private(set) var lastPlannedBehaviorSummary: String = "Aguardando turno"
    @Published public private(set) var lastAcousticContextSummary: String = "Pitch/Ritmo indisponíveis"
    @Published public private(set) var reconnectCount: Int = 0
    @Published public private(set) var activeProviderLabel: String = "Apple Speech + Natural PCM"
    @Published public private(set) var resourceSnapshot: ProcessResourceSnapshot = ProcessResourceProbe.sample()
    @Published public private(set) var llamaServerMemoryMB: Double = 0
    @Published public private(set) var totalVoiceStackMemoryMB: Double = ProcessResourceProbe.sample().residentMemoryMB
    @Published public private(set) var diagnosticLogs: [VoiceDiagnosticEvent] = []
    /// Disabled by default per privacy policy; local-only in-memory pipeline trace when explicitly enabled by user.
    @Published public var enablePipelineDiagnosticsTrace: Bool = false {
        didSet {
            if !enablePipelineDiagnosticsTrace {
                pipelineTraceEvents.removeAll(keepingCapacity: false)
            }
        }
    }
    @Published public private(set) var pipelineTraceEvents: [VoicePipelineTraceEvent] = []

    private var sttSamples: [Double] = []
    private var sttSettlingSamples: [Double] = []
    private var llmSamples: [Double] = []
    private var firstClauseSamples: [Double] = []
    private var ttsSamples: [Double] = []
    private var ttsTotalSynthSamples: [Double] = []
    private var firstAudibleSamples: [Double] = []
    private var e2eSpeechEndAudibleSamples: [Double] = []
    private var e2eSamples: [Double] = []
    private var bargeInSamples: [Double] = []
    private var bargeInAudibleSamples: [Double] = []
    private var vocalizationLatencySamples: [Double] = []
    private let maxSamples = 64

    public init() {}

    public func setActiveProviderLabel(_ label: String) {
        activeProviderLabel = VoiceLogRedactor.redact(label)
    }

    public func recordPipelineTrace(
        stage: VoicePipelineTraceStage,
        sessionToken: String,
        turnEpoch: UInt64,
        detail: String
    ) {
        guard enablePipelineDiagnosticsTrace else { return }
        let safeDetail = VoiceLogRedactor.redact(String(detail.prefix(500)))
        pipelineTraceEvents.append(VoicePipelineTraceEvent(
            timestamp: Date(),
            stage: stage,
            sessionToken: sessionToken,
            turnEpoch: turnEpoch,
            payload: safeDetail
        ))
        if pipelineTraceEvents.count > 220 {
            pipelineTraceEvents.removeFirst(pipelineTraceEvents.count - 220)
        }
    }

    public func clearPipelineTrace() {
        pipelineTraceEvents.removeAll(keepingCapacity: false)
    }

    public func recordSTTLatency(ms: Double, settlingMs: Double? = nil) {
        appendSample(ms, into: &sttSamples)
        sttStats = LatencySummaryStats.compute(from: sttSamples)
        if let settlingMs {
            appendSample(settlingMs, into: &sttSettlingSamples)
            sttSettlingStats = LatencySummaryStats.compute(from: sttSettlingSamples)
        }
    }

    public func recordLLMFirstChunkLatency(ms: Double) {
        appendSample(ms, into: &llmSamples)
        llmFirstChunkStats = LatencySummaryStats.compute(from: llmSamples)
    }

    public func recordFirstClauseLatency(ms: Double) {
        appendSample(ms, into: &firstClauseSamples)
        firstClauseStats = LatencySummaryStats.compute(from: firstClauseSamples)
    }

    public func recordTTSFirstAudioLatency(ms: Double) {
        appendSample(ms, into: &ttsSamples)
        ttsFirstAudioStats = LatencySummaryStats.compute(from: ttsSamples)
    }

    public func recordTTSTotalSynthesisLatency(ms: Double) {
        appendSample(ms, into: &ttsTotalSynthSamples)
        ttsTotalSynthesisStats = LatencySummaryStats.compute(from: ttsTotalSynthSamples)
    }

    public func recordFirstAudiblePlaybackLatency(fromCommitMs: Double, fromSpeechEndMs: Double? = nil) {
        appendSample(fromCommitMs, into: &firstAudibleSamples)
        firstAudiblePlaybackStats = LatencySummaryStats.compute(from: firstAudibleSamples)
        if let fromSpeechEndMs {
            appendSample(fromSpeechEndMs, into: &e2eSpeechEndAudibleSamples)
            e2eFromSpeechEndAudibleStats = LatencySummaryStats.compute(from: e2eSpeechEndAudibleSamples)
        }
    }

    public func recordEndToEndResponseLatency(ms: Double) {
        appendSample(ms, into: &e2eSamples)
        e2eResponseStats = LatencySummaryStats.compute(from: e2eSamples)
    }

    public func recordBargeInStopLatency(ms: Double) {
        appendSample(ms, into: &bargeInSamples)
        bargeInStopStats = LatencySummaryStats.compute(from: bargeInSamples)
        log(category: "BargeIn", message: String(format: "Flush de buffer concluído em %.2f ms", ms))
    }

    public func recordBargeInAudibleStopLatency(ms: Double) {
        appendSample(ms, into: &bargeInAudibleSamples)
        bargeInAudibleStopStats = LatencySummaryStats.compute(from: bargeInAudibleSamples)
        log(category: "BargeInAudível", message: String(format: "Interrupção efetivamente audível concluída em %.1f ms", ms))
    }

    public func recordVocalizationPlaybackLatency(ms: Double, vocalizationTag: String) {
        appendSample(ms, into: &vocalizationLatencySamples)
        vocalizationCacheLatencyStats = LatencySummaryStats.compute(from: vocalizationLatencySamples)
        backchannelsEmittedCount += 1
        log(category: "EscutaAtiva", message: String(format: "Vocalização '%@' entregue em %.1f ms (cache local)", vocalizationTag, ms))
    }

    public func recordSuppressedBackchannel() {
        backchannelsSuppressedCount += 1
    }

    public func updateBehaviorTelemetry(planSummary: String, acousticSummary: String) {
        lastPlannedBehaviorSummary = planSummary
        lastAcousticContextSummary = acousticSummary
    }

    public func recordReconnect(reason: String) {
        reconnectCount += 1
        log(category: "Reconnect", message: reason)
    }

    public func refreshResources(llamaServerPID: pid_t? = nil) {
        let appSnap = ProcessResourceProbe.sample()
        resourceSnapshot = appSnap
        let llamaMB = llamaServerPID.map { ProcessResourceProbe.physicalFootprintMB(forPID: $0) } ?? 0
        llamaServerMemoryMB = llamaMB
        totalVoiceStackMemoryMB = appSnap.residentMemoryMB + llamaMB
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

    public func listAllFacts(limit: Int = 200) -> [VoiceKnowledgeRecord] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        let sql = """
        SELECT id, content, source, project_scope, trust_tier, created_at
        FROM voice_facts
        ORDER BY created_at DESC
        LIMIT ?;
        """
        var stmt: OpaquePointer?
        var out: [VoiceKnowledgeRecord] = []
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(max(1, min(limit, 500))))
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                let content = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                let source = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
                let scope = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? "global"
                let tierRaw = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? "auto"
                let ts = sqlite3_column_double(stmt, 5)
                out.append(VoiceKnowledgeRecord(
                    id: id,
                    content: content,
                    source: source,
                    projectScope: scope,
                    trustTier: VoiceMemoryTrustTier(rawValue: tierRaw) ?? .auto,
                    score: 1.0,
                    createdAt: ts
                ))
            }
            sqlite3_finalize(stmt)
        }
        return out
    }

    @discardableResult
    public func deleteFacts(withIDs ids: [String]) -> Int {
        guard !ids.isEmpty else { return 0 }
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return 0 }
        var removed = 0
        for id in ids {
            var stmt1: OpaquePointer?
            if sqlite3_prepare_v2(db, "DELETE FROM voice_facts WHERE id = ?;", -1, &stmt1, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt1, 1, id, -1, Self.sqliteTransient)
                if sqlite3_step(stmt1) == SQLITE_DONE {
                    removed += Int(sqlite3_changes(db))
                }
                sqlite3_finalize(stmt1)
            }
            var stmt2: OpaquePointer?
            if sqlite3_prepare_v2(db, "DELETE FROM voice_facts_fts WHERE fact_id = ?;", -1, &stmt2, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt2, 1, id, -1, Self.sqliteTransient)
                sqlite3_step(stmt2)
                sqlite3_finalize(stmt2)
            }
        }
        return removed
    }
}

// MARK: - Memory Contamination Inspection & Safe Selective Cleanup (Phase 2)

public enum VoiceMemoryContaminationSource: String, Codable, Sendable {
    case continuityStore = "Continuidade de Voz (~/.codex)"
    case knowledgeFTS5 = "Banco FTS5 Local"
    case chatHistorySQLite = "Histórico do Chat (SQLite)"
}

public struct VoiceMemoryContaminationCandidate: Identifiable, Equatable, Sendable {
    public let id: String
    public let source: VoiceMemoryContaminationSource
    public let threadOrScope: String
    public let roleOrTier: String
    public let text: String
    public let reason: String
}

public enum VoiceMemoryHygieneAnalyzer {
    public static func normalizeForComparison(_ text: String) -> String {
        let lower = text.lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "pt_BR"))
        let tokens = lower.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return tokens.joined(separator: " ")
    }

    public static func isZeroSemanticFragment(_ text: String) -> Bool {
        normalizeForComparison(text).isEmpty
    }

    /// Identifies structurally contaminated sequences (e.g. ASR progressive drift "X" -> "X Y" -> "X Y." -> "X Y. .",
    /// adjacent duplicate fragments, or quarantined prompt-injection entries) without using any hardcoded topic blacklist.
    public static func detectContaminatedIndices(in items: [CodexContinuityItem]) -> [Int: String] {
        var flagged: [Int: String] = [:]
        guard !items.isEmpty else { return flagged }

        var userIndices: [Int] = []
        for idx in items.indices where items[idx].role == "user" {
            userIndices.append(idx)
        }

        // 1. Structural incremental drift / cumulative re-emission & duplicate fragments across consecutive user turns
        var normCounts: [String: Int] = [:]
        for uIdx in userIndices {
            let text = items[uIdx].text
            if isZeroSemanticFragment(text) {
                flagged[uIdx] = "Fragmento sem conteúdo semântico (apenas pontuação/ruído)"
                continue
            }
            let norm = normalizeForComparison(text)
            normCounts[norm, default: 0] += 1
        }

        for i in 0..<userIndices.count {
            let curIdx = userIndices[i]
            let curNorm = normalizeForComparison(items[curIdx].text)
            let curWordCount = curNorm.split(separator: " ").count
            guard !curNorm.isEmpty else { continue }

            if i > 0 {
                let prevIdx = userIndices[i - 1]
                let prevNorm = normalizeForComparison(items[prevIdx].text)
                let prevTrim = items[prevIdx].text.trimmingCharacters(in: .whitespacesAndNewlines)
                let curTrim = items[curIdx].text.trimmingCharacters(in: .whitespacesAndNewlines)

                if curNorm == prevNorm {
                    let msg = "Reemissão duplicada / pontuação residual de turno anterior de ASR"
                    flagged[prevIdx] = flagged[prevIdx] ?? msg
                    flagged[curIdx] = msg
                    if curIdx + 1 < items.count && items[curIdx + 1].role == "assistant" {
                        flagged[curIdx + 1] = "Resposta automática a reemissão duplicada de ASR"
                    }
                    if prevIdx + 1 < items.count && items[prevIdx + 1].role == "assistant" {
                        flagged[prevIdx + 1] = flagged[prevIdx + 1] ?? "Resposta associada a loop de reemissão ASR"
                    }
                } else if !prevNorm.isEmpty && curNorm.hasPrefix(prevNorm) && prevNorm.split(separator: " ").count <= 3 && curWordCount <= 5 && curTrim != prevTrim {
                    let msg = "Deriva cumulativa de buffer ASR sem reset de segmento"
                    flagged[prevIdx] = flagged[prevIdx] ?? msg
                    flagged[curIdx] = msg
                    if curIdx + 1 < items.count && items[curIdx + 1].role == "assistant" {
                        flagged[curIdx + 1] = "Resposta a deriva cumulativa de buffer ASR"
                    }
                    if prevIdx + 1 < items.count && items[prevIdx + 1].role == "assistant" {
                        flagged[prevIdx + 1] = flagged[prevIdx + 1] ?? "Resposta associada a segmento ASR aberto"
                    }
                }
            }

            if (normCounts[curNorm] ?? 0) >= 3 && curWordCount <= 4 {
                flagged[curIdx] = flagged[curIdx] ?? "Fragmento curto repetido \(normCounts[curNorm] ?? 0)x em sequência"
            }
        }
        return flagged
    }

    /// Prevents runaway ASR drift / noise fragments in seed history from poisoning fresh local sessions,
    /// without touching legitimate stored files unless explicitly reviewed & deleted by user.
    public static func filterCleanContextItems(_ items: [CodexContinuityItem]) -> [CodexContinuityItem] {
        let dirty = detectContaminatedIndices(in: items)
        return items.enumerated().compactMap { idx, item in
            if dirty[idx] != nil { return nil }
            let trimmed = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if VoiceSQLiteKnowledgeStore.classifyTrustTier(for: trimmed, explicitTrusted: false) == .untrusted {
                return nil
            }
            return item
        }
    }

    public static func scan(
        knowledgeStore: VoiceSQLiteKnowledgeStore,
        continuityStore: CodexRealtimeContinuityStore,
        additionalChatThreads: [(threadID: String, items: [CodexContinuityItem])] = []
    ) -> [VoiceMemoryContaminationCandidate] {
        var candidates: [VoiceMemoryContaminationCandidate] = []

        // 1. Continuity JSON (~/.codex/realtime-voice-continuity.json)
        for (threadID, items) in continuityStore.allThreads().sorted(by: { $0.key < $1.key }) {
            let dirty = detectContaminatedIndices(in: items)
            for idx in dirty.keys.sorted() {
                let item = items[idx]
                candidates.append(VoiceMemoryContaminationCandidate(
                    id: "cont|\(threadID)|\(idx)|\(item.text.hashValue)",
                    source: .continuityStore,
                    threadOrScope: threadID,
                    roleOrTier: item.role,
                    text: item.text,
                    reason: dirty[idx] ?? "Anomalia estrutural de transcrição"
                ))
            }
        }

        // 2. Chat history SQLite threads (if provided by host workspace/ChatStorage)
        for (threadID, items) in additionalChatThreads.sorted(by: { $0.threadID < $1.threadID }) {
            let dirty = detectContaminatedIndices(in: items)
            for idx in dirty.keys.sorted() {
                let item = items[idx]
                candidates.append(VoiceMemoryContaminationCandidate(
                    id: "chat|\(threadID)|\(idx)|\(item.text.hashValue)",
                    source: .chatHistorySQLite,
                    threadOrScope: threadID,
                    roleOrTier: item.role,
                    text: item.text,
                    reason: dirty[idx] ?? "Anomalia estrutural de transcrição"
                ))
            }
        }

        // 3. Local SQLite FTS5 voice_facts
        let facts = knowledgeStore.listAllFacts(limit: 250)
        var seenNorm: [String: Int] = [:]
        for f in facts {
            seenNorm[normalizeForComparison(f.content), default: 0] += 1
        }
        for fact in facts {
            if fact.trustTier == .untrusted {
                candidates.append(VoiceMemoryContaminationCandidate(
                    id: "fts|\(fact.id)",
                    source: .knowledgeFTS5,
                    threadOrScope: fact.projectScope,
                    roleOrTier: "\(fact.source) [\(fact.trustTier.rawValue)]",
                    text: fact.content,
                    reason: "Marcado em quarentena (.untrusted / suspeita de prompt injection)"
                ))
            } else if fact.source == "user_voice" || isZeroSemanticFragment(fact.content) || ((seenNorm[normalizeForComparison(fact.content)] ?? 0) >= 2 && !fact.content.isEmpty) {
                let words = normalizeForComparison(fact.content).split(separator: " ").count
                if fact.source == "user_voice" && words <= 5 {
                    candidates.append(VoiceMemoryContaminationCandidate(
                        id: "fts|\(fact.id)",
                        source: .knowledgeFTS5,
                        threadOrScope: fact.projectScope,
                        roleOrTier: "\(fact.source) [\(fact.trustTier.rawValue)]",
                        text: fact.content,
                        reason: "Transcrição bruta curta armazenada antes da correção de higiene"
                    ))
                }
            }
        }
        return candidates
    }

    @discardableResult
    public static func removeReviewedCandidates(
        _ selected: [VoiceMemoryContaminationCandidate],
        knowledgeStore: VoiceSQLiteKnowledgeStore,
        continuityStore: CodexRealtimeContinuityStore,
        chatHistoryRemover: ((_ threadID: String, _ matchingNormalizedTexts: Set<String>) -> Int)? = nil
    ) -> Int {
        var removedCount = 0
        let ftsIDs = selected
            .filter { $0.source == .knowledgeFTS5 && $0.id.hasPrefix("fts|") }
            .map { String($0.id.dropFirst(4)) }
        removedCount += knowledgeStore.deleteFacts(withIDs: ftsIDs)

        let byThread = Dictionary(grouping: selected.filter { $0.source == .continuityStore }, by: \.threadOrScope)
        for (threadID, group) in byThread {
            let texts = Set(group.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) })
            removedCount += continuityStore.removeMatchingItems(threadId: threadID, matchingNormalizedTexts: texts)
        }

        if let chatHistoryRemover {
            let chatByThread = Dictionary(grouping: selected.filter { $0.source == .chatHistorySQLite }, by: \.threadOrScope)
            for (threadID, group) in chatByThread {
                let texts = Set(group.map { normalizeForComparison($0.text) })
                removedCount += chatHistoryRemover(threadID, texts)
            }
        }
        return removedCount
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

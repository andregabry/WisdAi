import Foundation

// MARK: - Unified Message Input Metadata & Outcomes (P0 Architecture Fix)

public enum MessageInputSource: String, Codable, Sendable {
    case text
    case voice
    case voiceIntervention
    case recovery
    case scheduled

    public var displayName: String {
        switch self {
        case .text: return "texto"
        case .voice: return "voz"
        case .voiceIntervention: return "voz (intervenção)"
        case .recovery: return "recuperação"
        case .scheduled: return "agendada"
        }
    }
}

public struct UnifiedMessageMetadata: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let messageID: UUID
    public let conversationID: String
    public let projectID: UUID?
    public let projectName: String?
    public let workspaceID: String?
    public let workingDirectory: String
    public let additionalDirectories: [String]
    public let agentID: String
    public let agentDisplayName: String
    public let providerID: String
    public let accountID: UUID?
    public let modelID: String
    public let reasoningEffort: String
    public let reasoningEffortTitle: String
    public let sessionID: String?
    public let inputSource: MessageInputSource
    public let permissionsMode: Int
    public let sandboxPolicy: String
    public let approvalPolicy: String
    public let attachments: [String]
    public let conversationHistoryCount: Int
    public let createdAt: Date

    public init(
        messageID: UUID = UUID(),
        conversationID: String,
        projectID: UUID? = nil,
        projectName: String? = nil,
        workspaceID: String? = nil,
        workingDirectory: String,
        additionalDirectories: [String] = [],
        agentID: String,
        agentDisplayName: String,
        providerID: String,
        accountID: UUID? = nil,
        modelID: String,
        reasoningEffort: String,
        reasoningEffortTitle: String,
        sessionID: String? = nil,
        inputSource: MessageInputSource,
        permissionsMode: Int,
        sandboxPolicy: String,
        approvalPolicy: String,
        attachments: [String] = [],
        conversationHistoryCount: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = messageID
        self.messageID = messageID
        self.conversationID = conversationID
        self.projectID = projectID
        self.projectName = projectName
        self.workspaceID = workspaceID
        self.workingDirectory = workingDirectory
        self.additionalDirectories = additionalDirectories
        self.agentID = agentID
        self.agentDisplayName = agentDisplayName
        self.providerID = providerID
        self.accountID = accountID
        self.modelID = modelID
        self.reasoningEffort = reasoningEffort
        self.reasoningEffortTitle = reasoningEffortTitle
        self.sessionID = sessionID
        self.inputSource = inputSource
        self.permissionsMode = permissionsMode
        self.sandboxPolicy = sandboxPolicy
        self.approvalPolicy = approvalPolicy
        self.attachments = attachments
        self.conversationHistoryCount = conversationHistoryCount
        self.createdAt = createdAt
    }
}

public enum UnifiedSubmissionOutcome: Equatable, Sendable {
    case started(metadata: UnifiedMessageMetadata)
    case queued(metadata: UnifiedMessageMetadata, position: Int)
    case awaitingUserApproval(reason: String, metadata: UnifiedMessageMetadata)
    case blockedDirectory(error: String, directoryPath: String)
    case unavailable(reason: String)
}

// MARK: - Validated Project Context & Git Inspection

public struct ResolvedProjectContext: Equatable, Codable, Sendable {
    public var projectID: UUID?
    public var projectName: String?
    public var absoluteDirectoryPath: String?
    public var additionalPaths: [String]
    public var directoryExists: Bool
    public var directoryAccessible: Bool
    public var directoryValidationError: String?
    public var isGitRepository: Bool
    public var gitRepositoryName: String?
    public var gitBranch: String?
    public var gitWorkingTreeStatus: String?
    public var projectConfigHighlights: [String]
    public var contextualVocabulary: [String]

    public static let empty = ResolvedProjectContext(
        projectID: nil,
        projectName: nil,
        absoluteDirectoryPath: nil,
        additionalPaths: [],
        directoryExists: false,
        directoryAccessible: false,
        directoryValidationError: nil,
        isGitRepository: false,
        gitRepositoryName: nil,
        gitBranch: nil,
        gitWorkingTreeStatus: nil,
        projectConfigHighlights: [],
        contextualVocabulary: ContextualTranscriptNormalizer.defaultEcosystemVocabulary
    )

    public var hasValidWorkspaceDirectory: Bool {
        guard let p = absoluteDirectoryPath, !p.isEmpty else { return false }
        return directoryExists && directoryAccessible
    }
}

public enum ProjectContextResolver {
    public static func validateDirectorySync(path: String?) -> (exists: Bool, accessible: Bool, error: String?) {
        guard let raw = path?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return (false, false, nil)
        }
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: raw, isDirectory: &isDir)
        guard exists else {
            return (false, false, "O diretório do projeto '\(raw)' não existe neste Mac.")
        }
        guard isDir.boolValue else {
            return (true, false, "O caminho associado '\(raw)' não é um diretório válido.")
        }
        let readable = FileManager.default.isReadableFile(atPath: raw)
        guard readable else {
            return (true, false, "Sem permissão de leitura no diretório '\(raw)'.")
        }
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: raw)
        } catch {
            return (true, false, "Diretório '\(raw)' inacessível: \(error.localizedDescription)")
        }
        return (true, true, nil)
    }

    /// Resolves directory validity, Git repository state, project metadata files, and STT vocabulary.
    public static func resolve(
        projectID: UUID?,
        projectName: String?,
        directoryPath: String?,
        additionalPaths: [String] = [],
        configuredProjects: [ProjectItem] = [],
        inspectGit: Bool = true
    ) -> ResolvedProjectContext {
        let matchedItem: ProjectItem? = {
            if let pid = projectID, let found = configuredProjects.first(where: { $0.id == pid }) {
                return found
            }
            if let dir = directoryPath, !dir.isEmpty {
                return configuredProjects.first(where: { $0.matchesPath(dir) })
            }
            if let pName = projectName, !pName.isEmpty {
                return configuredProjects.first(where: { $0.name.caseInsensitiveCompare(pName) == .orderedSame })
            }
            return nil
        }()

        let resolvedID = projectID ?? matchedItem?.id
        let resolvedDir = (directoryPath?.isEmpty == false) ? directoryPath : matchedItem?.path
        let resolvedName: String? = {
            if let explicit = projectName?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
                return explicit
            }
            if let itemName = matchedItem?.name, !itemName.isEmpty {
                return itemName
            }
            if let dir = resolvedDir, !dir.isEmpty {
                return URL(fileURLWithPath: dir).lastPathComponent
            }
            return nil
        }()
        let mergedExtra = additionalPaths.isEmpty ? (matchedItem?.additionalPaths ?? []) : additionalPaths

        let validation = validateDirectorySync(path: resolvedDir)
        var vocab = Set(ContextualTranscriptNormalizer.defaultEcosystemVocabulary)
        for proj in configuredProjects where !proj.name.isEmpty {
            vocab.insert(proj.name)
        }
        if let resolvedName, !resolvedName.isEmpty {
            vocab.insert(resolvedName)
        }

        guard let validPath = resolvedDir, validation.exists && validation.accessible else {
            return ResolvedProjectContext(
                projectID: resolvedID,
                projectName: resolvedName,
                absoluteDirectoryPath: resolvedDir,
                additionalPaths: mergedExtra,
                directoryExists: validation.exists,
                directoryAccessible: validation.accessible,
                directoryValidationError: validation.error,
                isGitRepository: false,
                gitRepositoryName: nil,
                gitBranch: nil,
                gitWorkingTreeStatus: nil,
                projectConfigHighlights: [],
                contextualVocabulary: vocab.sorted()
            )
        }

        let topItems = (try? FileManager.default.contentsOfDirectory(atPath: validPath)) ?? []
        let candidateConfigs = [
            "AGENTS.md", "CLAUDE.md", "README.md", "package.json", "Package.swift",
            "Cargo.toml", "pyproject.toml", "Info.plist", "tsconfig.json", "docker-compose.yml"
        ]
        let foundConfigs = candidateConfigs.filter { topItems.contains($0) }

        if topItems.contains("package.json") {
            vocab.formUnion(["TypeScript", "JavaScript", "Node.js", "Electron", "React"])
        }
        if topItems.contains("Info.plist") || topItems.contains("Package.swift") || topItems.contains(where: { $0.hasSuffix(".xcodeproj") }) {
            vocab.formUnion(["Swift", "SwiftUI", "macOS", "CoreAudio", "AVAudioEngine"])
        }
        if topItems.contains("pyproject.toml") || topItems.contains("requirements.txt") {
            vocab.formUnion(["Python", "pytest"])
        }

        var isGit = false
        var branch: String?
        var repoName: String?
        var treeStatus: String?

        if inspectGit && FileManager.default.fileExists(atPath: URL(fileURLWithPath: validPath).appendingPathComponent(".git").path) {
            isGit = true
            branch = runQuickCommand("/usr/bin/git", args: ["-C", validPath, "rev-parse", "--abbrev-ref", "HEAD"])?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let remote = runQuickCommand("/usr/bin/git", args: ["-C", validPath, "remote", "get-url", "origin"])?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !remote.isEmpty {
                let last = remote.split(separator: "/").last.map(String.init) ?? remote
                repoName = last.replacingOccurrences(of: ".git", with: "")
            } else {
                repoName = resolvedName
            }
            if let porcelain = runQuickCommand("/usr/bin/git", args: ["-C", validPath, "status", "--porcelain"]) {
                let lines = porcelain.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                if lines.isEmpty {
                    treeStatus = "limpo"
                } else {
                    let untracked = lines.filter { $0.hasPrefix("??") }.count
                    let modified = lines.count - untracked
                    var parts: [String] = []
                    if modified > 0 { parts.append("\(modified) modificado(s)") }
                    if untracked > 0 { parts.append("\(untracked) não rastreado(s)") }
                    treeStatus = parts.joined(separator: ", ")
                }
            }
        }

        return ResolvedProjectContext(
            projectID: resolvedID,
            projectName: resolvedName,
            absoluteDirectoryPath: validPath,
            additionalPaths: mergedExtra,
            directoryExists: true,
            directoryAccessible: true,
            directoryValidationError: nil,
            isGitRepository: isGit,
            gitRepositoryName: repoName,
            gitBranch: branch,
            gitWorkingTreeStatus: treeStatus,
            projectConfigHighlights: foundConfigs,
            contextualVocabulary: vocab.sorted()
        )
    }

    private static func runQuickCommand(_ executable: String, args: [String], timeoutSec: Double = 1.0) -> String? {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return nil }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        proc.standardInput = FileHandle.nullDevice
        do {
            try proc.run()
        } catch {
            return nil
        }
        let deadline = Date().addingTimeInterval(timeoutSec)
        while proc.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.015)
        }
        if proc.isRunning {
            proc.terminate()
            return nil
        }
        guard proc.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Structured Execution Event Bus (Section 8)

public enum ExecutionEventKind: String, Codable, Sendable, CaseIterable {
    case taskReceived = "task.received"
    case taskQueued = "task.queued"
    case taskStarted = "task.started"
    case agentConnected = "agent.connected"
    case toolStarted = "tool.started"
    case toolCompleted = "tool.completed"
    case fileRead = "file.read"
    case fileModified = "file.modified"
    case commandStarted = "command.started"
    case commandCompleted = "command.completed"
    case testStarted = "test.started"
    case testCompleted = "test.completed"
    case approvalRequired = "approval.required"
    case taskBlocked = "task.blocked"
    case taskFailed = "task.failed"
    case taskCompleted = "task.completed"
    case taskCancelled = "task.cancelled"
}

public struct ExecutionEvent: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let conversationID: String
    public let turnID: String
    public let projectID: UUID?
    public let projectName: String?
    public let workingDirectory: String?
    public let agentName: String
    public let modelID: String
    public let kind: ExecutionEventKind
    public let title: String
    public let detail: String?
    public let filePath: String?
    public let lineRange: String?
    public let commandLine: String?
    public let exitCode: Int?
    public let durationSeconds: Double?
    public let succeeded: Bool?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        conversationID: String,
        turnID: String = "",
        projectID: UUID? = nil,
        projectName: String? = nil,
        workingDirectory: String? = nil,
        agentName: String,
        modelID: String,
        kind: ExecutionEventKind,
        title: String,
        detail: String? = nil,
        filePath: String? = nil,
        lineRange: String? = nil,
        commandLine: String? = nil,
        exitCode: Int? = nil,
        durationSeconds: Double? = nil,
        succeeded: Bool? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.conversationID = conversationID
        self.turnID = turnID
        self.projectID = projectID
        self.projectName = projectName
        self.workingDirectory = workingDirectory
        self.agentName = agentName
        self.modelID = modelID
        self.kind = kind
        self.title = title
        self.detail = detail
        self.filePath = filePath
        self.lineRange = lineRange
        self.commandLine = commandLine
        self.exitCode = exitCode
        self.durationSeconds = durationSeconds
        self.succeeded = succeeded
    }
}

public struct CommandExecutionRecord: Equatable, Codable, Sendable {
    public let commandLine: String
    public var exitCode: Int?
    public var finished: Bool
    public let timestamp: Date
}

public struct TestExecutionRecord: Equatable, Codable, Sendable {
    public let commandOrSuite: String
    public var passed: Bool?
    public var finished: Bool
    public let timestamp: Date
}

public struct ActiveTaskExecutionSnapshot: Equatable, Codable, Sendable {
    public let conversationID: String
    public var turnID: String
    public var prompt: String
    public var projectName: String?
    public var workingDirectory: String?
    public var agentName: String
    public var modelID: String
    public var reasoningEffort: String
    public var status: String // queued, running, waiting_approval, blocked, failed, completed, cancelled
    public var startedAt: Date
    public var lastEventAt: Date
    public var currentPhase: String
    public var currentDetail: String?
    public var filesRead: [String]
    public var filesModified: [String]
    public var commandsRun: [CommandExecutionRecord]
    public var testsRun: [TestExecutionRecord]
    public var toolsInvoked: [String]
    public var pendingApprovalDescription: String?
    public var errorDetail: String?
    public var finalReportMarkdown: String?
    public var queuedCount: Int

    public var elapsedSeconds: Int {
        max(0, Int(Date().timeIntervalSince(startedAt).rounded()))
    }
}

@MainActor
public final class ExecutionEventBus: ObservableObject {
    @Published public private(set) var recentEvents: [ExecutionEvent] = []
    @Published public private(set) var snapshotsByConversation: [String: ActiveTaskExecutionSnapshot] = [:]
    @Published public private(set) var metadataByConversation: [String: UnifiedMessageMetadata] = [:]

    public var onEventPublished: ((ExecutionEvent, ActiveTaskExecutionSnapshot) -> Void)?
    private let maxEventsPerBuffer = 250

    public init() {}

    public func metadata(for conversationID: String?) -> UnifiedMessageMetadata? {
        guard let conversationID, !conversationID.isEmpty else { return nil }
        return metadataByConversation[conversationID]
    }

    public func registerTaskMetadata(_ metadata: UnifiedMessageMetadata, prompt: String, queuePosition: Int = 0) {
        metadataByConversation[metadata.conversationID] = metadata
        var snap = snapshotsByConversation[metadata.conversationID] ?? ActiveTaskExecutionSnapshot(
            conversationID: metadata.conversationID,
            turnID: "",
            prompt: prompt,
            projectName: metadata.projectName,
            workingDirectory: metadata.workingDirectory,
            agentName: metadata.agentDisplayName,
            modelID: metadata.modelID,
            reasoningEffort: metadata.reasoningEffortTitle,
            status: queuePosition > 0 ? "queued" : "running",
            startedAt: Date(),
            lastEventAt: Date(),
            currentPhase: queuePosition > 0 ? "Na fila (\(queuePosition))" : "Iniciando tarefa",
            currentDetail: metadata.workingDirectory,
            filesRead: [],
            filesModified: [],
            commandsRun: [],
            testsRun: [],
            toolsInvoked: [],
            pendingApprovalDescription: nil,
            errorDetail: nil,
            finalReportMarkdown: nil,
            queuedCount: queuePosition
        )
        if queuePosition == 0 {
            snap.prompt = prompt
            snap.projectName = metadata.projectName
            snap.workingDirectory = metadata.workingDirectory
            snap.agentName = metadata.agentDisplayName
            snap.modelID = metadata.modelID
            snap.reasoningEffort = metadata.reasoningEffortTitle
            snap.status = "running"
            snap.startedAt = Date()
            snap.lastEventAt = Date()
            snap.currentPhase = "Conectando ao agente"
            snap.filesRead = []
            snap.filesModified = []
            snap.commandsRun = []
            snap.testsRun = []
            snap.toolsInvoked = []
            snap.pendingApprovalDescription = nil
            snap.errorDetail = nil
            snap.finalReportMarkdown = nil
        } else {
            snap.queuedCount = queuePosition
        }
        snapshotsByConversation[metadata.conversationID] = snap
    }

    public func publish(_ event: ExecutionEvent) {
        recentEvents.append(event)
        if recentEvents.count > maxEventsPerBuffer {
            recentEvents.removeFirst(recentEvents.count - maxEventsPerBuffer)
        }

        var snap = snapshotsByConversation[event.conversationID] ?? ActiveTaskExecutionSnapshot(
            conversationID: event.conversationID,
            turnID: event.turnID,
            prompt: event.title,
            projectName: event.projectName,
            workingDirectory: event.workingDirectory,
            agentName: event.agentName,
            modelID: event.modelID,
            reasoningEffort: "",
            status: "running",
            startedAt: event.timestamp,
            lastEventAt: event.timestamp,
            currentPhase: event.title,
            currentDetail: event.detail,
            filesRead: [],
            filesModified: [],
            commandsRun: [],
            testsRun: [],
            toolsInvoked: [],
            pendingApprovalDescription: nil,
            errorDetail: nil,
            finalReportMarkdown: nil,
            queuedCount: 0
        )

        if !event.turnID.isEmpty { snap.turnID = event.turnID }
        snap.lastEventAt = event.timestamp
        snap.currentPhase = event.title
        if let det = event.detail, !det.isEmpty {
            snap.currentDetail = det
        }

        switch event.kind {
        case .taskReceived, .taskStarted, .agentConnected:
            snap.status = "running"
            snap.pendingApprovalDescription = nil
        case .taskQueued:
            snap.queuedCount += 1
        case .fileRead:
            if let path = event.filePath, !path.isEmpty {
                let label = event.lineRange.map { "\(URL(fileURLWithPath: path).lastPathComponent)\($0)" }
                    ?? URL(fileURLWithPath: path).lastPathComponent
                if !snap.filesRead.contains(label) {
                    snap.filesRead.append(label)
                }
            }
        case .fileModified:
            if let path = event.filePath, !path.isEmpty {
                let label = URL(fileURLWithPath: path).lastPathComponent
                if !snap.filesModified.contains(label) {
                    snap.filesModified.append(label)
                }
            }
        case .commandStarted:
            if let cmd = event.commandLine, !cmd.isEmpty {
                snap.commandsRun.append(CommandExecutionRecord(commandLine: cmd, exitCode: nil, finished: false, timestamp: event.timestamp))
            }
        case .commandCompleted:
            if let cmd = event.commandLine,
               let idx = snap.commandsRun.lastIndex(where: { !$0.finished && $0.commandLine == cmd }) {
                snap.commandsRun[idx].finished = true
                snap.commandsRun[idx].exitCode = event.exitCode
            } else if let idx = snap.commandsRun.indices.last {
                snap.commandsRun[idx].finished = true
                snap.commandsRun[idx].exitCode = event.exitCode
            }
        case .testStarted:
            let suite = event.commandLine ?? event.detail ?? event.title
            snap.testsRun.append(TestExecutionRecord(commandOrSuite: suite, passed: nil, finished: false, timestamp: event.timestamp))
        case .testCompleted:
            if let idx = snap.testsRun.indices.last {
                snap.testsRun[idx].finished = true
                snap.testsRun[idx].passed = event.succeeded
            }
        case .toolStarted, .toolCompleted:
            if !event.title.isEmpty && !snap.toolsInvoked.contains(event.title) {
                snap.toolsInvoked.append(event.title)
            }
        case .approvalRequired:
            snap.status = "waiting_approval"
            snap.pendingApprovalDescription = event.detail ?? event.title
        case .taskBlocked:
            snap.status = "blocked"
            snap.errorDetail = event.detail ?? event.title
        case .taskFailed:
            snap.status = "failed"
            snap.errorDetail = event.detail ?? event.title
        case .taskCompleted:
            snap.status = "completed"
            snap.pendingApprovalDescription = nil
            snap.finalReportMarkdown = event.detail
        case .taskCancelled:
            snap.status = "cancelled"
            snap.pendingApprovalDescription = nil
        }

        snapshotsByConversation[event.conversationID] = snap
        onEventPublished?(event, snap)
    }

    public func events(for conversationID: String) -> [ExecutionEvent] {
        recentEvents.filter { $0.conversationID == conversationID }
    }

    public func snapshot(for conversationID: String?) -> ActiveTaskExecutionSnapshot? {
        if let cid = conversationID, let s = snapshotsByConversation[cid] {
            return s
        }
        return snapshotsByConversation.values.first(where: { $0.status == "running" || $0.status == "waiting_approval" })
    }

    /// Generates an evidence-backed, non-fabricated verbal answer about live execution state.
    public func formatGroundedProgressAnswer(
        for question: String,
        conversationID: String?,
        projectName: String?,
        language: VoiceLanguageVariant
    ) -> String {
        let lower = question.lowercased()
        let isEn = language.bcp47LanguagePrefix == "en"
        guard let snap = snapshot(for: conversationID) else {
            let proj = projectName.map { isEn ? " in \($0)" : " no projeto \($0)" } ?? ""
            return isEn
                ? "No agent task is running right now\(proj). Say what you want to analyze, test, or modify and I'll dispatch it immediately."
                : "Nenhuma tarefa está em execução agora\(proj). Se quiser auditar o código, rodar testes ou alterar algo, pode pedir que eu executo agora."
        }

        if lower.contains("arquivo") || lower.contains("ficheiro") || lower.contains("lendo") || lower.contains("analisando") || lower.contains("file") {
            if !snap.filesRead.isEmpty || !snap.filesModified.isEmpty {
                let readSample = snap.filesRead.suffix(5).joined(separator: ", ")
                let modSample = snap.filesModified.suffix(4).joined(separator: ", ")
                if isEn {
                    var msg = "\(snap.agentName) has inspected \(snap.filesRead.count) file(s)"
                    if !readSample.isEmpty { msg += ", including \(readSample)" }
                    if !snap.filesModified.isEmpty { msg += ", and modified \(modSample)" }
                    return msg + "."
                }
                var msg = "\(snap.agentName) já analisou \(snap.filesRead.count) arquivo(s)"
                if !readSample.isEmpty { msg += ", incluindo \(readSample)" }
                if !snap.filesModified.isEmpty { msg += ", e editou \(modSample)" }
                return msg + "."
            }
            return isEn
                ? "\(snap.agentName) (\(snap.modelID)) is in stage '\(snap.currentPhase)' and has not reported individual file reads yet."
                : "\(snap.agentName) usando \(snap.modelID) está na etapa '\(snap.currentPhase)' e ainda não confirmou leitura de arquivos individuais."
        }

        if lower.contains("quanto falta") || lower.contains("quanto tempo") || lower.contains("demor") || lower.contains("how long") || lower.contains("eta") {
            let runningCmd = snap.commandsRun.last(where: { !$0.finished })?.commandLine
            if snap.status == "waiting_approval" {
                return isEn
                    ? "Execution is paused waiting for your approval on screen: \(snap.pendingApprovalDescription ?? "pending action")."
                    : "A tarefa está aguardando sua aprovação na tela para prosseguir: \(snap.pendingApprovalDescription ?? "operação pendente")."
            }
            let waitReason: String = {
                if let cmd = runningCmd {
                    return isEn ? "running command \(cmd)" : "executando um comando no terminal"
                }
                if !snap.filesRead.isEmpty {
                    return isEn ? "analyzing \(snap.filesRead.count) project files with effort \(snap.reasoningEffort)" : "analisando o código com \(snap.agentName) no esforço \(snap.reasoningEffort)"
                }
                return snap.currentPhase
            }()
            return isEn
                ? "I can't estimate the exact remaining time. \(snap.agentName) (\(snap.modelID)) has been running for \(snap.elapsedSeconds) seconds while \(waitReason)."
                : "Não é possível estimar exatamente quanto tempo falta. O agente \(snap.agentName) com \(snap.modelID) está executando há \(snap.elapsedSeconds) segundos, atualmente \(waitReason)."
        }

        if lower.contains("encontrou") || lower.contains("problema") || lower.contains("erro") || lower.contains("found") {
            if snap.status == "completed" {
                return isEn
                    ? "The task just finished after reading \(snap.filesRead.count) files and running \(snap.commandsRun.count) commands. Let me summarize the verified result."
                    : "A tarefa foi concluída após analisar \(snap.filesRead.count) arquivo(s) e executar \(snap.commandsRun.count) comando(s). O relatório completo está no chat."
            }
            if snap.status == "failed" || snap.status == "blocked" {
                return isEn
                    ? "The execution hit an error: \(snap.errorDetail ?? "unspecified failure")."
                    : "A execução encontrou um bloqueio real: \(snap.errorDetail ?? "erro não especificado")."
            }
            return isEn
                ? "\(snap.agentName) is still investigating (\(snap.elapsedSeconds)s elapsed, stage: \(snap.currentPhase)). No final root cause has been confirmed yet."
                : "\(snap.agentName) ainda está analisando há \(snap.elapsedSeconds) segundos na etapa \(snap.currentPhase). Ainda não há conclusão final confirmada."
        }

        var parts: [String] = []
        if isEn {
            parts.append("\(snap.agentName) (\(snap.modelID)) is \(snap.status == "running" ? "running" : snap.status) for \(snap.elapsedSeconds)s: \(snap.currentPhase).")
            if !snap.filesRead.isEmpty { parts.append("Files read: \(snap.filesRead.suffix(3).joined(separator: ", ")).") }
            if !snap.testsRun.isEmpty {
                let doneTests = snap.testsRun.filter(\.finished).count
                parts.append("Tests recorded: \(snap.testsRun.count) (\(doneTests) finished).")
            }
            if let approval = snap.pendingApprovalDescription { parts.append("Waiting for your approval: \(approval).") }
        } else {
            let statusDesc = snap.status == "running" ? "em execução" : (snap.status == "waiting_approval" ? "aguardando sua aprovação" : snap.status)
            parts.append("\(snap.agentName) com \(snap.modelID) está \(statusDesc) há \(snap.elapsedSeconds) segundos, na etapa \(snap.currentPhase).")
            if !snap.filesRead.isEmpty {
                parts.append("Arquivos já analisados: \(snap.filesRead.suffix(3).joined(separator: ", ")).")
            }
            if !snap.commandsRun.isEmpty {
                parts.append("Comandos iniciados: \(snap.commandsRun.count).")
            }
            if let approval = snap.pendingApprovalDescription, !approval.isEmpty {
                parts.append("Há uma solicitação de aprovação pendente na tela.")
            }
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - Contextual Vocabulary & Conservative Post-ASR Normalizer (Section 12)

public struct NormalizedTranscriptResult: Equatable, Sendable {
    public let originalTranscript: String
    public let normalizedTranscript: String
    public let appliedReplacements: [String]

    public var wasModified: Bool { originalTranscript != normalizedTranscript }
}

public enum ContextualTranscriptNormalizer {
    public static let defaultEcosystemVocabulary: [String] = [
        "WisdAI", "WisdMeet", "WisdFin", "WisdKids", "WisdPlay",
        "Codex", "Claude Code", "Antigravity", "Gemini", "OpenAI", "Anthropic",
        "JARVIS", "Ultron BR", "auditoria", "branch", "commit", "git", "stack trace"
    ]

    /// Conservative unambiguous phonetic replacements preserving original ASR text separately for audit logs.
    private static let conservativePhraseRules: [(pattern: String, replacement: String)] = [
        ("\\b(?:whit\\s+meet|white\\s+meet|whisd\\s+meet|with\\s+meet|wist\\s+meet|wis\\s+meet|wisd\\s+meet|wisdmit|u[ií]sd\\s*m[ií]t)\\b", "WisdMeet"),
        ("\\b(?:u[ií]sd[eê]?i?[-\\s]?[aá]i|wiz\\s+day|wis\\s+day|wisd\\s+a\\.?\\s*i\\.?|is\\s+da[ií])\\b", "WisdAI"),
        ("\\b(?:wiz\\s+fin|wis\\s+fin|wisd\\s+fin)\\b", "WisdFin"),
        ("\\b(?:wiz\\s+kids|wis\\s+kids|wisd\\s+kids)\\b", "WisdKids"),
        ("\\b(?:wiz\\s+play|wis\\s+play|wisd\\s+play)\\b", "WisdPlay"),
        ("\\b(?:anti[-\\s]+gravity|antigravidade)\\b", "Antigravity"),
        ("\\b(?:code[-\\s]+ex|codex\\s+c\\s+l\\s+i)\\b", "Codex"),
        ("\\b(?:cloud\\s+code|claud\\s+code|claude\\s+c[oó]digo)\\b", "Claude Code")
    ]

    public static func normalize(
        _ rawTranscript: String,
        activeProjectName: String? = nil
    ) -> NormalizedTranscriptResult {
        let trimmed = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return NormalizedTranscriptResult(originalTranscript: rawTranscript, normalizedTranscript: "", appliedReplacements: [])
        }
        var current = trimmed
        var changes: [String] = []

        for rule in conservativePhraseRules {
            guard let rx = try? NSRegularExpression(pattern: rule.pattern, options: [.caseInsensitive]) else { continue }
            let nsRange = NSRange(current.startIndex..<current.endIndex, in: current)
            let matches = rx.matches(in: current, range: nsRange)
            if !matches.isEmpty {
                for m in matches {
                    if let r = Range(m.range, in: current) {
                        changes.append("\(current[r]) -> \(rule.replacement)")
                    }
                }
                current = rx.stringByReplacingMatches(in: current, options: [], range: nsRange, withTemplate: rule.replacement)
            }
        }

        // Only if the user is actively inside a single unambiguous project (e.g. WisdMeet) and ASR emitted
        // "projeto em" / "projeto e m" immediately after an audit/analysis phrase, restore the active project name.
        if let proj = activeProjectName, proj.caseInsensitiveCompare("WisdMeet") == .orderedSame {
            let scopedPattern = "\\bprojeto\\s+(?:e\\s+m|em|it)\\b"
            if let rx = try? NSRegularExpression(pattern: scopedPattern, options: [.caseInsensitive]) {
                let nsRange = NSRange(current.startIndex..<current.endIndex, in: current)
                if rx.firstMatch(in: current, range: nsRange) != nil {
                    changes.append("projeto <phonetic> -> projeto WisdMeet")
                    current = rx.stringByReplacingMatches(in: current, options: [], range: nsRange, withTemplate: "projeto WisdMeet")
                }
            }
        }

        return NormalizedTranscriptResult(
            originalTranscript: trimmed,
            normalizedTranscript: current,
            appliedReplacements: changes
        )
    }
}

// MARK: - Voice Presentation Engine & Grounded Oral Summarizer (Sections 11 & 14)

public enum VoicePresentationEngine {
    /// Summarizes a full grounded technical markdown report for natural human speech while preserving the full report untouched in chat.
    public static func composeSpokenSummary(
        fullMarkdownText: String,
        snapshot: ActiveTaskExecutionSnapshot?,
        profile: VoiceBehaviorProfile,
        hadWaitNotice: Bool,
        customDictionary: TechnicalPronunciationDictionary? = nil
    ) -> String {
        let isEn = profile.languageVariant.bcp47LanguagePrefix == "en"
        let cleanRaw = fullMarkdownText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip large non-oral technical structures before summary extraction: fenced code, JSON blocks, stack traces, tables, raw paths.
        var stripped = cleanRaw
        if let codeRx = try? NSRegularExpression(pattern: "```[\\s\\S]*?```", options: []) {
            stripped = codeRx.stringByReplacingMatches(in: stripped, range: NSRange(stripped.startIndex..<stripped.endIndex, in: stripped), withTemplate: " ")
        }
        if let jsonBlockRx = try? NSRegularExpression(pattern: "\\{[\\s\\S]{40,}?\\}", options: []) {
            stripped = jsonBlockRx.stringByReplacingMatches(in: stripped, range: NSRange(stripped.startIndex..<stripped.endIndex, in: stripped), withTemplate: " ")
        }

        var narrativeLines: [String] = []
        var fallbackLines: [String] = []
        for rawLine in stripped.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            // Skip Markdown table rows, stack-trace frames, raw log timestamps, standalone JSON/array fragments.
            if line.hasPrefix("|") && line.filter({ $0 == "|" }).count >= 2 { continue }
            if line.hasPrefix("at ") || line.contains("Error:") && line.contains(".swift:") && line.contains("(") { continue }
            if line.range(of: "^\\d{4}-\\d{2}-\\d{2}[T ]\\d{2}:\\d{2}", options: .regularExpression) != nil { continue }
            if (line.hasPrefix("{") || line.hasPrefix("[")) && line.count > 24 { continue }
            // Skip pure Markdown headings without sentence punctuation
            if line.hasPrefix("#") { continue }

            // Condense markdown file links [name.ext](file:///long/path#L10-L20) -> name.ext
            if let linkRx = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^\\)]+)\\)", options: []) {
                line = linkRx.stringByReplacingMatches(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line), withTemplate: "$1")
            }
            // Replace long POSIX paths (/Users/.../foo/bar.ts:12-30) with concise basename (bar.ts) so TTS stays natural.
            if let pathRx = try? NSRegularExpression(pattern: "(?:/[A-Za-z0-9._-]+){3,}(?:#L\\d+(?:-L?\\d+)?)?", options: []) {
                let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
                let matches = pathRx.matches(in: line, range: nsRange).reversed()
                for match in matches {
                    if let r = Range(match.range, in: line) {
                        let fullPath = String(line[r])
                        let base = URL(fileURLWithPath: fullPath.components(separatedBy: "#").first ?? fullPath).lastPathComponent
                        line.replaceSubrange(r, with: base.isEmpty ? "o arquivo" : base)
                    }
                }
            }
            // Remove noisy line-number parentheticals and range annotations from speech: "(linhas 1–32)", "(lines 10-20)"
            if let lineRangeRx = try? NSRegularExpression(pattern: "\\((?:linhas?|lines?)\\s+\\d+[\\s\\-–—a-zA-Z0-9]*\\)", options: [.caseInsensitive]) {
                line = lineRangeRx.stringByReplacingMatches(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line), withTemplate: "")
            }
            line = Self.formatFilenamesForSpeech(line, isEnglish: isEn)

            let isEnumeratedItem = line.range(of: "^(?:\\d+[\\.)]|[-•*])\\s+", options: .regularExpression) != nil
                || line.lowercased().hasPrefix("arquivos lidos:")
                || line.lowercased().hasPrefix("files read:")
            if isEnumeratedItem {
                fallbackLines.append(line)
            } else {
                narrativeLines.append(line)
            }
        }

        let selectedLines = !narrativeLines.isEmpty ? Array(narrativeLines.prefix(3)) : Array(fallbackLines.prefix(2))
        let joined = selectedLines.joined(separator: " ")
        let adapted = NaturalSpeechComposer.compose(
            joined,
            plan: nil,
            profile: profile,
            capabilities: EngineProsodyCapabilities.forEngine(.supertonic3, isKokoroActive: false, isSupertonicActive: true),
            customDictionary: customDictionary
        ).spokenText

        let maxOralChars = profile.detailLevel == .brief ? 220 : (profile.detailLevel == .balanced ? 300 : 480)
        var concise = stripRepetitiveOpeners(adapted)
        if concise.count > maxOralChars {
            let prefix = String(concise.prefix(maxOralChars))
            let cutoff = prefix.lastIndex(where: { $0 == "." || $0 == "!" || $0 == "?" }) ?? prefix.lastIndex(of: " ") ?? prefix.endIndex
            concise = String(prefix[..<cutoff]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !concise.isEmpty && !".!?".contains(concise.last!) {
                concise += "."
            }
        }

        if concise.isEmpty, let snap = snapshot {
            let filesNote = snap.filesRead.isEmpty ? "" : (isEn ? " analyzing \(snap.filesRead.count) files" : " analisando \(snap.filesRead.count) arquivos")
            concise = isEn
                ? "\(snap.agentName) finished the task\(filesNote). The full technical report is ready in the chat."
                : "\(snap.agentName) concluiu a execução\(filesNote). O relatório técnico completo está disponível no chat."
        } else if cleanRaw.count > concise.count + 160 && !concise.lowercased().contains("no chat") && !concise.lowercased().contains("in the chat") {
            let detailCue = isEn ? " The complete technical details are in the chat." : " Todos os detalhes técnicos e caminhos estão no chat."
            concise += detailCue
        }

        if hadWaitNotice {
            let lower = concise.lowercased()
            let alreadyDonePrefix = lower.hasPrefix("pronto") || lower.hasPrefix("conclu") || lower.hasPrefix("terminei") || lower.hasPrefix("feito") || lower.hasPrefix("done") || lower.hasPrefix("finished")
            if !alreadyDonePrefix {
                concise = (isEn ? "Done, the task finished. " : "Pronto, concluí a análise. ") + concise
            }
        }
        return concise
    }

    private static func formatFilenamesForSpeech(_ text: String, isEnglish: Bool) -> String {
        var out = text
        let dotWord = isEnglish ? " dot " : " ponto "
        let exactFiles: [(String, String)] = [
            ("\\bREADME\\.md\\b", isEnglish ? "readme file" : "arquivo rídmi"),
            ("\\bPackage\\.swift\\b", isEnglish ? "Package dot swift" : "Package ponto swift"),
            ("\\B\\.git\\b", isEnglish ? "dot git" : "ponto git")
        ]
        for (pat, rep) in exactFiles {
            if let rx = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]) {
                out = rx.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..<out.endIndex, in: out), withTemplate: rep)
            }
        }
        if let extRx = try? NSRegularExpression(pattern: "\\b([A-Za-z0-9_\\-]+)\\.(swift|ts|tsx|js|jsx|py|json|ya?ml|sh|md|txt)\\b", options: [.caseInsensitive]) {
            out = extRx.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..<out.endIndex, in: out), withTemplate: "$1\(dotWord)$2")
        }
        return out.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func stripRepetitiveOpeners(_ text: String) -> String {
        var working = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let bannedOpeners = [
            "hmm...", "hmm…", "hmm,", "hmm ", "hum...", "hum…", "hum,",
            "ah...", "ah,", "ah!", "ah ",
            "entendi...", "entendi,", "entendi.", "entendi!",
            "claro!", "claro,", "certamente!", "certamente,", "com certeza!"
        ]
        var removedAny = true
        while removedAny {
            removedAny = false
            let lower = working.lowercased()
            for opener in bannedOpeners where lower.hasPrefix(opener) {
                working = String(working.dropFirst(opener.count))
                while let ch = working.first, ch.isWhitespace || ".,!…-–—:;".contains(ch) {
                    working.removeFirst()
                }
                removedAny = true
                break
            }
        }
        if let first = working.first {
            return first.uppercased() + working.dropFirst()
        }
        return working
    }
}

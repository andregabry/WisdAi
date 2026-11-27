import AppKit
import AVFoundation
import Combine
import SQLite3
import SwiftUI
import UniformTypeIdentifiers

typealias JSON = [String: Any]

struct Conversation: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var cwd: String
    var agyConversationId: String?
    var lastUpdated: Date?

    init(id: String, title: String, cwd: String, agyConversationId: String? = nil, lastUpdated: Date? = Date()) {
        self.id = id
        self.title = title
        self.cwd = cwd
        self.agyConversationId = agyConversationId
        self.lastUpdated = lastUpdated
    }

    init?(_ value: [String: Any]) {
        guard let id = value["id"] as? String, let cwd = value["cwd"] as? String else { return nil }
        self.id = id
        self.cwd = cwd
        let name = (value["title"] as? String) ?? (value["name"] as? String) ?? (value["preview"] as? String) ?? ""
        self.title = name.isEmpty ? "Nova conversa" : name
        self.agyConversationId = value["agyConversationId"] as? String
        self.lastUpdated = Date()
    }
}

struct PlanStep: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var status: String // "pending", "in_progress", "done", "skipped", "failed"
}

struct Message: Identifiable, Codable {
    var id: UUID = UUID()
    var author: String
    var text: String
    var kind: Kind = .text
    var detail: String?
    var status: String?
    var exitCode: Int?
    var turnId: String?
    var target: String?
    var output: String?
    var durationSeconds: Double?
    var subKind: String?
    var steps: [PlanStep]?

    enum Kind: String, Codable {
        case text, reasoning, command, fileChange, tool, web, plan

        var isAction: Bool {
            switch self {
            case .command, .fileChange, .tool, .web: return true
            case .text, .reasoning, .plan: return false
            }
        }
    }

    init(
        id: UUID = UUID(),
        author: String,
        text: String,
        kind: Kind = .text,
        detail: String? = nil,
        status: String? = nil,
        exitCode: Int? = nil,
        turnId: String? = nil,
        target: String? = nil,
        output: String? = nil,
        durationSeconds: Double? = nil,
        subKind: String? = nil,
        steps: [PlanStep]? = nil
    ) {
        self.id = id
        self.author = author
        self.text = text
        self.kind = kind
        self.detail = detail
        self.status = status
        self.exitCode = exitCode
        self.turnId = turnId
        self.target = target
        self.output = output
        self.durationSeconds = durationSeconds
        self.subKind = subKind
        self.steps = steps
    }
}

// MARK: - Banco de Dados Interno SQLite para Histórico de Chats e Mensagens

private let sqliteTransientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class ChatStorage {
    static let shared = ChatStorage()
    private var db: OpaquePointer?
    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let legacyDirectory: URL

    init(inMemory: Bool = ProcessInfo.processInfo.processName.contains("Smoke")) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.legacyDirectory = appSupport.appendingPathComponent("WisdAI/Chats", isDirectory: true)
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601

        let dbPath: String
        if inMemory {
            dbPath = ":memory:"
        } else {
            let dbDir = appSupport.appendingPathComponent("WisdAI/Database", isDirectory: true)
            try? FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
            dbPath = dbDir.appendingPathComponent("wisdai_history.sqlite").path
        }

        var handle: OpaquePointer?
        if sqlite3_open_v2(dbPath, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK {
            self.db = handle
            initializeSchema()
            if !inMemory {
                migrateLegacyJSONIfNeeded()
            }
        }
    }

    deinit {
        lock.lock()
        if let db {
            sqlite3_close_v2(db)
        }
        lock.unlock()
    }

    private func initializeSchema() {
        let schemaSQL = """
        PRAGMA journal_mode = WAL;
        PRAGMA synchronous = NORMAL;
        PRAGMA foreign_keys = ON;

        CREATE TABLE IF NOT EXISTS conversations (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            cwd TEXT NOT NULL,
            agy_conversation_id TEXT,
            last_updated REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS messages (
            id TEXT PRIMARY KEY,
            thread_id TEXT NOT NULL,
            seq INTEGER NOT NULL,
            author TEXT NOT NULL,
            text TEXT NOT NULL,
            kind TEXT NOT NULL,
            detail TEXT,
            status TEXT,
            exit_code INTEGER,
            turn_id TEXT,
            target TEXT,
            output TEXT,
            duration_seconds REAL,
            sub_kind TEXT,
            steps_json TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_messages_thread_seq ON messages(thread_id, seq);

        CREATE TABLE IF NOT EXISTS app_state (
            key TEXT PRIMARY KEY,
            value TEXT
        );
        """
        executeSQL(schemaSQL)
    }

    private func executeSQL(_ sql: String) {
        guard let db else { return }
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func bindOptionalText(_ stmt: OpaquePointer?, index: Int32, value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, sqliteTransientDestructor)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func readOptionalText(_ stmt: OpaquePointer?, col: Int32) -> String? {
        guard sqlite3_column_type(stmt, col) != SQLITE_NULL,
              let ptr = sqlite3_column_text(stmt, col) else { return nil }
        return String(cString: ptr)
    }

    private func migrateLegacyJSONIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }

        var count: Int32 = 0
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM conversations;", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = sqlite3_column_int(stmt, 0)
            }
            sqlite3_finalize(stmt)
        }
        guard count == 0 else { return }

        let indexURL = legacyDirectory.appendingPathComponent("conversations_index.json")
        guard let idxData = try? Data(contentsOf: indexURL),
              let convs = try? decoder.decode([Conversation].self, from: idxData),
              !convs.isEmpty else { return }

        lock.unlock()
        saveConversations(convs)
        for conv in convs {
            let file = legacyDirectory.appendingPathComponent("\(conv.id).json")
            if let data = try? Data(contentsOf: file),
               let msgs = try? decoder.decode([Message].self, from: data),
               !msgs.isEmpty {
                saveMessages(msgs, for: conv.id)
            }
        }
        lock.lock()
    }

    func loadConversations() -> [Conversation] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }

        let sql = "SELECT id, title, cwd, agy_conversation_id, last_updated FROM conversations ORDER BY last_updated DESC;"
        var stmt: OpaquePointer?
        var list: [Conversation] = []
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let id = readOptionalText(stmt, col: 0) else { continue }
                let title = readOptionalText(stmt, col: 1) ?? "Nova conversa"
                let cwd = readOptionalText(stmt, col: 2) ?? ""
                let agyId = readOptionalText(stmt, col: 3)
                let ts = sqlite3_column_double(stmt, 4)
                list.append(Conversation(
                    id: id,
                    title: title,
                    cwd: cwd,
                    agyConversationId: agyId,
                    lastUpdated: ts > 0 ? Date(timeIntervalSince1970: ts) : Date()
                ))
            }
            sqlite3_finalize(stmt)
        }
        return list
    }

    func upsertConversation(_ conv: Conversation) {
        saveConversations([conv])
    }

    func saveConversations(_ conversations: [Conversation]) {
        guard !conversations.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }

        executeSQL("BEGIN IMMEDIATE;")
        let sql = """
        INSERT INTO conversations (id, title, cwd, agy_conversation_id, last_updated)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            title = CASE WHEN excluded.title != '' THEN excluded.title ELSE conversations.title END,
            cwd = CASE WHEN excluded.cwd != '' THEN excluded.cwd ELSE conversations.cwd END,
            agy_conversation_id = COALESCE(excluded.agy_conversation_id, conversations.agy_conversation_id),
            last_updated = MAX(conversations.last_updated, excluded.last_updated);
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            for conv in conversations {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                bindOptionalText(stmt, index: 1, value: conv.id)
                bindOptionalText(stmt, index: 2, value: conv.title)
                bindOptionalText(stmt, index: 3, value: conv.cwd)
                bindOptionalText(stmt, index: 4, value: conv.agyConversationId)
                sqlite3_bind_double(stmt, 5, (conv.lastUpdated ?? Date()).timeIntervalSince1970)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
        executeSQL("COMMIT;")
    }

    func loadMessages(for threadID: String) -> [Message] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }

        let sql = """
        SELECT id, author, text, kind, detail, status, exit_code, turn_id, target, output, duration_seconds, sub_kind, steps_json
        FROM messages WHERE thread_id = ? ORDER BY seq ASC;
        """
        var stmt: OpaquePointer?
        var list: [Message] = []
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindOptionalText(stmt, index: 1, value: threadID)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let idStr = readOptionalText(stmt, col: 0) ?? ""
                let msgID = UUID(uuidString: idStr) ?? UUID()
                let author = readOptionalText(stmt, col: 1) ?? "WisdAI"
                let text = readOptionalText(stmt, col: 2) ?? ""
                let kindRaw = readOptionalText(stmt, col: 3) ?? "text"
                let kind = Message.Kind(rawValue: kindRaw) ?? .text
                let detail = readOptionalText(stmt, col: 4)
                let status = readOptionalText(stmt, col: 5)
                let exitCode: Int? = sqlite3_column_type(stmt, 6) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 6))
                let turnId = readOptionalText(stmt, col: 7)
                let target = readOptionalText(stmt, col: 8)
                let output = readOptionalText(stmt, col: 9)
                let duration: Double? = sqlite3_column_type(stmt, 10) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 10)
                let subKind = readOptionalText(stmt, col: 11)
                var steps: [PlanStep]? = nil
                if let stepsStr = readOptionalText(stmt, col: 12),
                   let data = stepsStr.data(using: .utf8) {
                    steps = try? decoder.decode([PlanStep].self, from: data)
                }

                list.append(Message(
                    id: msgID,
                    author: author,
                    text: text,
                    kind: kind,
                    detail: detail,
                    status: status,
                    exitCode: exitCode,
                    turnId: turnId,
                    target: target,
                    output: output,
                    durationSeconds: duration,
                    subKind: subKind,
                    steps: steps
                ))
            }
            sqlite3_finalize(stmt)
        }
        return list
    }

    func saveMessages(_ messages: [Message], for threadID: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }

        executeSQL("BEGIN IMMEDIATE;")
        var delStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM messages WHERE thread_id = ?;", -1, &delStmt, nil) == SQLITE_OK {
            bindOptionalText(delStmt, index: 1, value: threadID)
            sqlite3_step(delStmt)
            sqlite3_finalize(delStmt)
        }

        let insertSQL = """
        INSERT OR REPLACE INTO messages
        (id, thread_id, seq, author, text, kind, detail, status, exit_code, turn_id, target, output, duration_seconds, sub_kind, steps_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK {
            for (idx, m) in messages.enumerated() {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                bindOptionalText(stmt, index: 1, value: m.id.uuidString)
                bindOptionalText(stmt, index: 2, value: threadID)
                sqlite3_bind_int(stmt, 3, Int32(idx))
                bindOptionalText(stmt, index: 4, value: m.author)
                bindOptionalText(stmt, index: 5, value: m.text)
                bindOptionalText(stmt, index: 6, value: m.kind.rawValue)
                bindOptionalText(stmt, index: 7, value: m.detail)
                bindOptionalText(stmt, index: 8, value: m.status)
                if let code = m.exitCode {
                    sqlite3_bind_int(stmt, 9, Int32(code))
                } else {
                    sqlite3_bind_null(stmt, 9)
                }
                bindOptionalText(stmt, index: 10, value: m.turnId)
                bindOptionalText(stmt, index: 11, value: m.target)
                bindOptionalText(stmt, index: 12, value: m.output)
                if let dur = m.durationSeconds {
                    sqlite3_bind_double(stmt, 13, dur)
                } else {
                    sqlite3_bind_null(stmt, 13)
                }
                bindOptionalText(stmt, index: 14, value: m.subKind)
                if let steps = m.steps,
                   let data = try? encoder.encode(steps),
                   let jsonStr = String(data: data, encoding: .utf8) {
                    bindOptionalText(stmt, index: 15, value: jsonStr)
                } else {
                    sqlite3_bind_null(stmt, 15)
                }
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
        executeSQL("COMMIT;")
    }

    func deleteThread(_ threadID: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }

        executeSQL("BEGIN IMMEDIATE;")
        for sql in ["DELETE FROM messages WHERE thread_id = ?;", "DELETE FROM conversations WHERE id = ?;"] {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                bindOptionalText(stmt, index: 1, value: threadID)
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
        }
        executeSQL("COMMIT;")
    }

    func getLastSelectedThreadId() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return nil }
        var stmt: OpaquePointer?
        var value: String?
        if sqlite3_prepare_v2(db, "SELECT value FROM app_state WHERE key = 'last_selected_thread_id';", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                value = readOptionalText(stmt, col: 0)
            }
            sqlite3_finalize(stmt)
        }
        return value
    }

    func setLastSelectedThreadId(_ threadID: String?) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        if let threadID {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO app_state (key, value) VALUES ('last_selected_thread_id', ?);", -1, &stmt, nil) == SQLITE_OK {
                bindOptionalText(stmt, index: 1, value: threadID)
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
        } else {
            executeSQL("DELETE FROM app_state WHERE key = 'last_selected_thread_id';")
        }
    }

    func checkpoint() {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }
        sqlite3_wal_checkpoint_v2(db, nil, SQLITE_CHECKPOINT_PASSIVE, nil, nil)
    }

    func listAllTextItemsForHygieneScan() -> [(threadID: String, items: [CodexContinuityItem])] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        let sql = "SELECT thread_id, author, text FROM messages WHERE kind = 'text' ORDER BY thread_id ASC, seq ASC;"
        var stmt: OpaquePointer?
        var grouped: [String: [CodexContinuityItem]] = [:]
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let tid = readOptionalText(stmt, col: 0),
                      let author = readOptionalText(stmt, col: 1),
                      let text = readOptionalText(stmt, col: 2) else { continue }
                let role = (author == "Você") ? "user" : "assistant"
                grouped[tid, default: []].append(CodexContinuityItem(role: role, text: text))
            }
            sqlite3_finalize(stmt)
        }
        return grouped.sorted(by: { $0.key < $1.key }).map { (threadID: $0.key, items: $0.value) }
    }

    @discardableResult
    func removeTextMessages(threadID: String, matchingNormalizedTexts: Set<String>) -> Int {
        guard !matchingNormalizedTexts.isEmpty else { return 0 }
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return 0 }

        var toDeleteIDs: [String] = []
        let selectSQL = "SELECT id, text FROM messages WHERE thread_id = ? AND kind = 'text';"
        var selStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, selectSQL, -1, &selStmt, nil) == SQLITE_OK {
            bindOptionalText(selStmt, index: 1, value: threadID)
            while sqlite3_step(selStmt) == SQLITE_ROW {
                guard let msgID = readOptionalText(selStmt, col: 0),
                      let text = readOptionalText(selStmt, col: 1) else { continue }
                let norm = VoiceMemoryHygieneAnalyzer.normalizeForComparison(text)
                if matchingNormalizedTexts.contains(norm) {
                    toDeleteIDs.append(msgID)
                }
            }
            sqlite3_finalize(selStmt)
        }
        guard !toDeleteIDs.isEmpty else { return 0 }

        executeSQL("BEGIN IMMEDIATE;")
        var deleted = 0
        var delStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM messages WHERE id = ?;", -1, &delStmt, nil) == SQLITE_OK {
            for msgID in toDeleteIDs {
                sqlite3_reset(delStmt)
                sqlite3_clear_bindings(delStmt)
                bindOptionalText(delStmt, index: 1, value: msgID)
                if sqlite3_step(delStmt) == SQLITE_DONE {
                    deleted += Int(sqlite3_changes(db))
                }
            }
            sqlite3_finalize(delStmt)
        }
        executeSQL("COMMIT;")
        return deleted
    }
}

struct Attachment: Identifiable {
    let id = UUID()
    let name: String
    let input: [String: Any]
    var recording: URL?
}

struct AccountChoice: Identifiable {
    let id: String
    let label: String
    let active: Bool
    let workspaceID: String
}

struct ModelChoice: Identifiable {
    let id: String
    let name: String
    let efforts: [String]
    let defaultEffort: String
    let isDefault: Bool
}

struct Approval: Identifiable {
    let id = UUID()
    let requestID: Any
    let isFileChange: Bool
    let command: String?
    let reason: String?
}

@MainActor
final class Workspace: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var messages: [Message] = []
    @Published var project: URL?
    @Published var selected: String?
    @Published var prompt = ""
    @Published var temporaryChat = false
    @Published var busy = false
    @Published var ready = false
    @Published var error: String?
    @Published var attachments: [Attachment] = []
    @Published var account = "Verificando conta…"
    @Published var plan: String?
    @Published var accountIdentity: String?
    @Published var usageWindows: [UsageWindow] = []
    @Published var creditBalance: String?
    @Published var resetCredits: Int?
    @Published var accountChoices: [AccountChoice] = []
    @Published var quota: [String] = []
    @Published var accountBusy = false
    @Published private(set) var scheduledBusy = false
    @Published var apiKeyInput = ""
    @Published var mode: Int = UserDefaults.standard.integer(forKey: "wisdcode.mode") {
        didSet { UserDefaults.standard.set(mode, forKey: "wisdcode.mode") }
    }
    @Published var models: [ModelChoice] = []
    @Published var selectedModel: String = UserDefaults.standard.string(forKey: "wisdcode.model") ?? "auto" {
        didSet { UserDefaults.standard.set(selectedModel, forKey: "wisdcode.model") }
    }
    @Published var selectedEffort: String = UserDefaults.standard.string(forKey: "wisdcode.effort") ?? "default" {
        didSet { UserDefaults.standard.set(selectedEffort, forKey: "wisdcode.effort") }
    }
    @Published var activeTasks: [String: ActiveThreadTask] = [:]
    @Published var unseenCompletedThreads: Set<String> = []
    @Published var currentActivityNote: String?
    @Published var currentActivityDetail: String?
    @Published var currentActivityKind: TaskActivityStep.StepKind = .generic
    @Published var currentActivitySteps: [TaskActivityStep] = []
    @Published var currentActionMessageId: UUID?
    @Published var taskStartedAt: Date?

    var isTaskActiveForSelectedChat: Bool {
        if let selected, let task = activeTasks[selected], !task.status.isEmpty {
            return true
        }
        return busy
    }

    var reasoningLevel: ReasoningEffortLevel {
        get { ReasoningEffortLevel.from(value: selectedEffort) }
        set { selectedEffort = newValue.effortValue }
    }

    func recordActivity(
        threadId: String?,
        note: String,
        detail: String? = nil,
        kind: TaskActivityStep.StepKind = .generic,
        appendToTranscript: Bool = false
    ) {
        if let tid = threadId, activeTasks[tid] != nil {
            activeTasks[tid]?.addStep(note, detail: detail, kind: kind)
        }
        if threadId == nil || threadId == selected {
            currentActivityNote = note
            currentActivityDetail = detail
            currentActivityKind = kind
            if let last = currentActivitySteps.indices.last {
                currentActivitySteps[last].isCompleted = true
            }
            currentActivitySteps.append(TaskActivityStep(title: note, detail: detail, isCompleted: false, kind: kind))

            if voice.isVoiceModeActive && !voice.realtimeSessionActive {
                if kind == .response {
                    cancelPendingVoiceWaitNoticeOnly()
                } else if kind == .command || kind == .fileChange || kind == .tool || kind == .search || kind == .generic {
                    scheduleVoiceWaitNotice(delay: 2.0, kind: kind)
                }
            }

            if appendToTranscript && kind != .response {
                if let prevId = currentActionMessageId, let idx = messages.firstIndex(where: { $0.id == prevId }) {
                    if messages[idx].status == "em andamento" {
                        messages[idx].status = "concluído"
                    }
                }
                let msgKind: Message.Kind = {
                    switch kind {
                    case .command: return .command
                    case .fileChange: return .fileChange
                    case .tool: return .tool
                    case .search: return .web
                    case .thinking: return .reasoning
                    case .generic: return .plan
                    case .response: return .text
                    }
                }()
                let stepMsg = Message(
                    id: UUID(),
                    author: "WisdAI",
                    text: note,
                    kind: msgKind,
                    detail: detail,
                    status: "em andamento",
                    turnId: turnID
                )
                currentActionMessageId = stepMsg.id
                messages.append(stepMsg)
                persistCurrentMessages()
            }
        }
    }

    func completeActivityStep(threadId: String?) {
        if let tid = threadId {
            activeTasks[tid]?.completeCurrentStep()
        }
        if threadId == nil || threadId == selected {
            if let last = currentActivitySteps.indices.last {
                currentActivitySteps[last].isCompleted = true
            }
            if let activeId = currentActionMessageId, let idx = messages.firstIndex(where: { $0.id == activeId }) {
                messages[idx].status = "concluído"
                currentActionMessageId = nil
                persistCurrentMessages()
            }
        }
    }

    func resetActivityState() {
        for idx in messages.indices where messages[idx].status == "em andamento" || messages[idx].status == "em execução" {
            messages[idx].status = "concluído"
        }
        currentActionMessageId = nil
        currentActivityNote = nil
        currentActivityDetail = nil
        currentActivityKind = .generic
        currentActivitySteps = []
        taskStartedAt = nil
        persistCurrentMessages()
    }
    @Published var limitAlertAccount: AIAccount?
    @Published var selectedAccount: AIAccount?
    @Published var modelsLoading = false
    @Published var quotaStore = UsageQuotaStore()
    @Published var recoveryNotices: [RecoveryCheckpoint] = []
    @Published var automaticFallback = UserDefaults.standard.object(forKey: "wisdcode.automaticFallback") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(automaticFallback, forKey: "wisdcode.automaticFallback")
            if automaticFallback { recovery.tick() }
        }
    }
    private let recoveryURL: URL
    private let transport: ((String, JSON, @escaping (JSON) -> Void) -> Void)?
    lazy var recovery = TurnRecoveryCoordinator(workspace: self, url: recoveryURL)
    private var quotaCancellable: AnyCancellable?
    private var voiceCancellable: AnyCancellable?
    private var quotaMonitorTask: Task<Void, Never>?
    private var lastAPIHeaderProbe: [UUID: Date] = [:]
    private var lastCLICatalogProbe: Date = .distantPast
    private var activeCLITurnModel: String = "auto"
    private var activeCLITurnAccountID: UUID?
    private var cliStepTokenCounts: [String: Int] = [:]
    private var cliDetectedLimit: (kind: ProviderLimit, until: Date, message: String)?
    private var cliExecutionError: String?
    private var persistDebounceTask: Task<Void, Never>?

    init(recoveryURL: URL? = nil, transport: ((String, JSON, @escaping (JSON) -> Void) -> Void)? = nil) {
        self.recoveryURL = recoveryURL ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/WisdAI/Recovery/\(Bundle.main.bundleIdentifier ?? "desktop")/checkpoints.json")
        self.transport = transport
        let savedConvs = ChatStorage.shared.loadConversations()
        self.conversations = savedConvs
        let lastId = ChatStorage.shared.getLastSelectedThreadId()
            ?? UserDefaults.standard.string(forKey: "wisdcode.desktop.lastSelectedThread")
        if let lastId,
           let conv = savedConvs.first(where: { $0.id == lastId }) ?? savedConvs.first {
            self.selected = conv.id
            self.project = conv.cwd.isEmpty ? nil : URL(fileURLWithPath: conv.cwd)
            self.messages = ChatStorage.shared.loadMessages(for: conv.id)
            UserDefaults.standard.set(conv.id, forKey: "wisdcode.desktop.lastSelectedThread")
        }
        self.quotaCancellable = quotaStore.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        self.voiceCancellable = voice.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        self.voice.orchestrator.onScanAdditionalChatThreads = {
            ChatStorage.shared.listAllTextItemsForHygieneScan()
        }
        self.voice.orchestrator.onRemoveAdditionalChatItems = { [weak self] threadID, normalizedSet in
            let removed = ChatStorage.shared.removeTextMessages(threadID: threadID, matchingNormalizedTexts: normalizedSet)
            if let self, self.selected == threadID {
                self.messages = ChatStorage.shared.loadMessages(for: threadID)
            }
            return removed
        }
        if transport == nil {
            startRealtimeQuotaMonitor()
        }
    }

    func shutdownGracefully() {
        voice.stopVoiceConversation()
        voice.orchestrator.llamaBrainRuntime.unloadModel()
        voice.orchestrator.kokoroTTS.unload()
        if let cliProc = activeCLIProcess, cliProc.isRunning {
            cliProc.terminate()
        }
        activeCLIProcess = nil
        if let appProc = process, appProc.isRunning {
            appProc.terminate()
        }
        process = nil
        persistCurrentMessages()
        ChatStorage.shared.checkpoint()
    }
    @Published var modelsNotice: String?
    private var modelRequestID = UUID()
    weak var localDataRef: DesktopLocalData?
    @Published var pendingApprovals: [Approval] = []
    @Published var recording = false
    @Published var speakReplies = false
    @Published var voice = VoiceController()
    private var loginID: String?
    private var recorder: AVAudioRecorder?
    private let speaker = AVSpeechSynthesizer()
    private var sentAttachments: [Attachment] = []
    private var process: Process?
    private var activeCLIProcess: Process?
    private var input: FileHandle?
    private var counter = 0
    private var pending: [Int: (JSON) -> Void] = [:]
    private var turnID: String?
    private var resumed: String?
    private var knownLastTurns: [String: String] = [:]
    private var loadedHistories = Set<String>()
    private var scheduledThreads: [String: (Bool, String?, String?) -> Void] = [:]
    private var streamedItems: [String: UUID] = [:]

    func connect() {
        guard process == nil else { return }
        guard let binary = Bundle.main.url(forAuxiliaryExecutable: "codex") ?? Bundle.main.url(forAuxiliaryExecutable: "WisdAI-engine") else {
            error = "Motor WisdAI ausente no aplicativo."
            ready = true
            loadModels()
            return
        }
        let child = Process()
        let outgoing = Pipe()
        let incoming = Pipe()
        child.executableURL = binary
        child.arguments = ["app-server"]
        var env = ProcessInfo.processInfo.environment
        if (env["OPENAI_API_KEY"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let keychainOpenAIKey = AccountKeychain.readProviderKey(provider: .openai)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !keychainOpenAIKey.isEmpty {
            env["OPENAI_API_KEY"] = keychainOpenAIKey
        }
        child.environment = env
        guard Bundle.main.url(forAuxiliaryExecutable: "codex-code-mode-host") != nil else {
            error = "O componente codex-code-mode-host está ausente. Use a compilação completa do aplicativo para executar tarefas locais."
            ready = true
            loadModels()
            return
        }
        child.standardInput = outgoing
        child.standardOutput = incoming
        child.standardError = FileHandle.nullDevice
        child.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.disconnected() }
        }
        do {
            try child.run()
            process = child
            input = outgoing.fileHandleForWriting
        } catch {
            self.error = error.localizedDescription
            return
        }

        let reader = incoming.fileHandleForReading
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var buffer = Data()
            while true {
                let chunk = reader.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 10) {
                    let line = Data(buffer[..<newline])
                    buffer.removeSubrange(...newline)
                    DispatchQueue.main.async { self?.receive(line) }
                }
            }
        }

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.6.1"
        request("initialize", ["clientInfo": ["name": "wisdcode-desktop", "version": appVersion], "capabilities": ["experimentalApi": true]]) { [weak self] result in
            guard let self, self.accept(result) != nil else { return }
            self.write(["method": "initialized"])
            self.ready = true
            self.recovery.restore()
            self.refresh()
            self.refreshAccount()
            self.loadModels()
        }
    }

    func ensureConversationRegistered(id: String, title: String, cwd: String) {
        guard !temporaryChat else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewTitle = trimmedTitle.isEmpty ? "Nova conversa" : String(trimmedTitle.prefix(48))
        let now = Date()

        if let idx = conversations.firstIndex(where: { $0.id == id }) {
            if conversations[idx].title.isEmpty || conversations[idx].title == "Nova conversa" {
                conversations[idx].title = previewTitle
            }
            if conversations[idx].cwd.isEmpty && !cwd.isEmpty {
                conversations[idx].cwd = cwd
            }
            conversations[idx].lastUpdated = now
            ChatStorage.shared.upsertConversation(conversations[idx])
        } else {
            let newConv = Conversation(id: id, title: previewTitle, cwd: cwd, lastUpdated: now)
            conversations.insert(newConv, at: 0)
            ChatStorage.shared.upsertConversation(newConv)
        }
        ChatStorage.shared.setLastSelectedThreadId(id)
        UserDefaults.standard.set(id, forKey: "wisdcode.desktop.lastSelectedThread")
    }

    func schedulePersistMessages() {
        persistDebounceTask?.cancel()
        persistDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self?.persistCurrentMessages()
        }
    }

    func persistCurrentMessages() {
        persistDebounceTask?.cancel()
        guard let selected = self.selected, !temporaryChat else { return }
        ChatStorage.shared.saveMessages(self.messages, for: selected)
        if let idx = self.conversations.firstIndex(where: { $0.id == selected }) {
            self.conversations[idx].lastUpdated = Date()
            ChatStorage.shared.upsertConversation(self.conversations[idx])
        } else {
            let fallbackTitle = self.messages.first(where: { $0.author == "Você" })?.text ?? "Nova conversa"
            ensureConversationRegistered(id: selected, title: fallbackTitle, cwd: self.project?.path ?? "")
        }
        ChatStorage.shared.setLastSelectedThreadId(selected)
        UserDefaults.standard.set(selected, forKey: "wisdcode.desktop.lastSelectedThread")
    }

    func refresh() {
        request("thread/list", ["limit": 50, "currentAccountOnly": true]) { [weak self] response in
            guard let self, let result = self.accept(response) else { return }
            let serverConvs = (result["data"] as? [JSON] ?? []).compactMap(Conversation.init)
            var merged = ChatStorage.shared.loadConversations()
            for sc in serverConvs {
                if let idx = merged.firstIndex(where: { $0.id == sc.id }) {
                    if merged[idx].title.isEmpty || merged[idx].title == "Nova conversa" {
                        merged[idx].title = sc.title
                    }
                    if merged[idx].cwd.isEmpty && !sc.cwd.isEmpty {
                        merged[idx].cwd = sc.cwd
                    }
                } else {
                    merged.append(sc)
                }
            }
            merged.sort { ($0.lastUpdated ?? .distantPast) > ($1.lastUpdated ?? .distantPast) }
            self.conversations = merged
            ChatStorage.shared.saveConversations(merged)
        }
    }

    func refreshAccount() {
        guard !recovery.transitioning else { return }
        request("account/read", [:]) { [weak self] response in
            guard let self, !self.recovery.transitioning else { return }
            guard let result = response["result"] as? JSON else {
                self.account = "Status da conta indisponível"
                return
            }
            if let info = result["account"] as? JSON {
                if info["type"] as? String == "apiKey" {
                    self.account = "Chave de API configurada"
                    self.plan = nil
                    self.accountIdentity = nil
                } else {
                    self.account = info["email"] as? String ?? (info["type"] as? String ?? "Conta conectada")
                    self.plan = info["planType"] as? String
                    self.accountIdentity = (result["userId"] as? String).map { user in
                        let route = (result["workspaceRouting"] as? JSON)?["chatgptAccountId"] as? String
                        return route.map { user + ":" + $0 } ?? user
                    }
                }
                if info["type"] as? String == "chatgpt" { self.refreshQuota() }
            } else {
                self.account = "Sem conta conectada"
                self.quota = []
                self.plan = nil
                self.accountIdentity = nil
                self.usageWindows = []
                self.creditBalance = nil
                self.resetCredits = nil
            }
        }
        request("accountSession/list", [:]) { [weak self] response in
            guard let self, !self.recovery.transitioning, let result = response["result"] as? JSON else { return }
            self.accountChoices = (result["sessions"] as? [JSON] ?? []).compactMap { session in
                guard let id = session["sessionId"] as? String,
                      let workspace = session["selectedWorkspaceAccountId"] as? String else { return nil }
                return AccountChoice(id: id, label: session["email"] as? String ?? "ChatGPT",
                                     active: session["isActive"] as? Bool ?? false, workspaceID: workspace)
            }
            self.localDataRef?.syncSessions(self.accountChoices)
            if let preferredActive = self.localDataRef?.activeAccount {
                self.selectedAccount = preferredActive
            } else if let openAIActive = self.localDataRef?.aiAccounts.first(where: { $0.provider == .openai && $0.isActive && $0.sessionID != nil }) {
                self.selectedAccount = openAIActive
            }
            self.loadModels()
            self.refreshQuota()
        }
    }

    /// Inicia o loop contínuo em segundo plano para manter o uso/cota de cada conta e modelo atualizado em memória em tempo real.
    func startRealtimeQuotaMonitor() {
        quotaMonitorTask?.cancel()
        quotaMonitorTask = Task { @MainActor [weak self] in
            // Pequeno atraso inicial para aguardar DesktopLocalData conectar
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            while !Task.isCancelled {
                guard let self else { break }
                self.reconcileQuotaAndExpiredLimits()
                await self.refreshAllQuotasNow(force: false)
                try? await Task.sleep(nanoseconds: 8_000_000_000) // Atualiza a cada 8 segundos
            }
        }
    }

    /// Reconcilia em memória limites expirados, janelas renovadas e cooldowns ativos do journal de recuperação.
    func reconcileQuotaAndExpiredLimits() {
        guard let local = localDataRef else { return }
        let now = Date()

        // 1. Espelha cooldowns ativos do RecoveryJournal no UsageQuotaStore
        for cooldown in recovery.journal.cooldowns where cooldown.until > now {
            let parts = cooldown.key.split(separator: ":", maxSplits: 2).map(String.init)
            if parts.count >= 2 {
                let sessionId = parts[0]
                let workspaceId = parts[1]
                if let acc = local.aiAccounts.first(where: { $0.sessionID == sessionId && $0.workspaceID == workspaceId }) {
                    if parts.count == 3 {
                        quotaStore.markModelLimited(accountID: acc.id, modelID: parts[2], until: cooldown.until, reason: "Cooldown ativo de limite")
                    } else {
                        quotaStore.markAccountLimited(accountID: acc.id, models: acc.models, until: cooldown.until, reason: "Limite da conta em cooldown")
                    }
                }
            }
        }

        // 2. Desbloqueia contas/modelos cujo horário de renovação (resetsAt / cooldownUntil) já passou
        var accountsCopy = local.aiAccounts
        let unlocked = quotaStore.reconcileExpiredLimits(now: now, accounts: &accountsCopy)
        if unlocked > 0 || accountsCopy != local.aiAccounts {
            local.aiAccounts = accountsCopy
            if let current = selectedAccount, let refreshed = local.aiAccounts.first(where: { $0.id == current.id }) {
                selectedAccount = refreshed
            }
        }
    }

    /// Atualiza imediatamente em memória o estado de cota/limites de todas as contas conectadas usando apenas endpoints de leitura.
    func refreshAllQuotasNow(force: Bool) async {
        if force { quotaStore.isRefreshing = true }
        defer { if force { quotaStore.isRefreshing = false } }

        reconcileQuotaAndExpiredLimits()

        if ready && !accountBusy && !recovery.transitioning {
            refreshQuota()
        }

        guard let local = localDataRef else { return }
        let now = Date()

        // Sondagem de headers HTTP somente-leitura para contas com chave de API salva no Keychain
        let accountsSnapshot = local.aiAccounts
        for acc in accountsSnapshot {
            let interval = now.timeIntervalSince(lastAPIHeaderProbe[acc.id] ?? .distantPast)
            guard force || interval >= 25 else { continue }
            guard acc.provider != .openai || acc.sessionID == nil else { continue }

            let key = (try? AccountKeychain.read(accountID: acc.id))
                ?? AccountKeychain.readProviderKey(provider: acc.provider)
                ?? AccountKeychain.readAccountPassword(accountID: acc.id)
            guard let key, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            // Evita chamar HTTP /models para senhas de login de CLI Google/Antigravity quando não é API Key
            if acc.provider == .gemini { continue }

            lastAPIHeaderProbe[acc.id] = now
            let modelsList = acc.models.isEmpty ? acc.provider.defaultModels : acc.models
            if let probe = await ProviderCatalogClient().probeQuotaHeaders(provider: acc.provider, key: key) {
                quotaStore.updateFromHTTPHeaders(
                    accountID: acc.id,
                    models: probe.models ?? modelsList,
                    statusCode: probe.statusCode,
                    headers: probe.headers,
                    source: "HTTP Headers"
                )
            }
        }

        // Sincroniza catálogo vivo da Antigravity CLI (sem inferência) em intervalo seguro
        if !busy && activeCLIProcess == nil && (force || now.timeIntervalSince(lastCLICatalogProbe) >= 60) {
            let geminiAccounts = accountsSnapshot.filter { $0.provider == .gemini && $0.supportsExecution }
            if !geminiAccounts.isEmpty {
                lastCLICatalogProbe = now
                if let liveModels = try? await ProviderCatalogClient.antigravityModels(), !liveModels.isEmpty {
                    for gAcc in geminiAccounts {
                        if gAcc.models != liveModels {
                            local.syncModels(accountID: gAcc.id, models: liveModels, source: "Antigravity CLI")
                        }
                    }
                    if let current = selectedAccount, let refreshed = local.aiAccounts.first(where: { $0.id == current.id }) {
                        selectedAccount = refreshed
                    }
                }
            }
        }
    }

    private func refreshQuota() {
        request("account/rateLimits/read", [:]) { [weak self] response in
            guard let self, let result = response["result"] as? JSON else { return }
            self.resetCredits = (result["rateLimitResetCredits"] as? JSON)?["availableCount"] as? Int
            self.ingestRateLimitsPayload(result)
        }
    }

    private func ingestRateLimitsPayload(_ payload: JSON) {
        if let limits = payload["rateLimits"] as? JSON {
            updateQuota(limits)
        }
        let targetAccount: AIAccount? = {
            if let accIdStr = payload["accountId"] as? String,
               let found = localDataRef?.aiAccounts.first(where: { $0.workspaceID == accIdStr || $0.sessionID == accIdStr }) {
                return found
            }
            if let activeSession = accountChoices.first(where: \.active),
               let found = localDataRef?.aiAccounts.first(where: { $0.provider == .openai && $0.sessionID == activeSession.id && $0.workspaceID == activeSession.workspaceID }) {
                return found
            }
            return selectedAccount ?? localDataRef?.aiAccounts.first(where: { $0.provider == .openai && $0.isActive })
        }()
        if let targetAccount {
            quotaStore.updateFromRateLimits(payload, account: targetAccount, fallbackModels: models.map(\.id))
        }
    }

    private func updateQuota(_ limits: JSON) {
        for key in ["primary", "secondary"] {
            if let data = limits[key] as? JSON, let used = data["usedPercent"] as? Int {
                let window = UsageWindow(id: key, used: used, minutes: data["windowDurationMins"] as? Int,
                                         reset: (data["resetsAt"] as? Double).map(Date.init(timeIntervalSince1970:)))
                usageWindows.removeAll { $0.id == key }
                usageWindows.append(window)
            }
        }
        if let credits = limits["credits"] as? JSON {
            creditBalance = credits["unlimited"] as? Bool == true ? "Ilimitado" : credits["balance"] as? String
        }

        let updates = ["primary", "secondary"].compactMap { key -> String? in
            guard let window = limits[key] as? JSON, let used = window["usedPercent"] as? Int else { return nil }
            let interval = (window["windowDurationMins"] as? Int).map { " em \($0) min" } ?? ""
            let reset = (window["resetsAt"] as? Double).map {
                " · renova " + Date(timeIntervalSince1970: $0).formatted(date: .abbreviated, time: .shortened)
            } ?? ""
            return "\(used)% usado\(interval)\(reset)"
        }
        if !updates.isEmpty { quota = updates }
    }

    func login() {
        if accountBusy, loginID != nil {
            cancelLogin()
        }
        guard activeTasks.isEmpty, !scheduledBusy, ready, !busy else { return }
        accountBusy = true
        request("account/login/start", ["type": "chatgpt"]) { [weak self] response in
            guard let self else { return }
            guard let result = self.accept(response),
                  let address = result["authUrl"] as? String, let url = URL(string: address),
                  url.scheme == "https" else {
                self.accountBusy = false
                return
            }
            self.loginID = result["loginId"] as? String
            DispatchQueue.main.async {
                if !NSWorkspace.shared.open(url) {
                    self.cancelLogin()
                    self.error = "Não foi possível abrir o navegador."
                }
            }
        }
    }

    func loginWithApiKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard activeTasks.isEmpty, !scheduledBusy, ready, !busy, !accountBusy, !key.isEmpty else { return }
        accountBusy = true
        request("account/login/start", ["type": "apiKey", "apiKey": key]) { [weak self] response in
            guard let self else { return }
            self.accountBusy = false
            if self.accept(response) != nil {
                self.apiKeyInput = ""
                self.accountChanged()
            }
        }
    }

    func cancelLogin() {
        guard let loginID else { return }
        request("account/login/cancel", ["loginId": loginID]) { [weak self] response in
            guard let self else { return }
            if self.accept(response) != nil {
                self.accountBusy = false
                self.loginID = nil
            }
        }
    }

    func switchAccount(_ choice: AccountChoice) {
        guard activeTasks.isEmpty, !scheduledBusy, !busy, !accountBusy, !recovery.isRecovering else { return }
        accountBusy = true; recovery.transitioning = true
        Task { @MainActor in
            defer { recovery.transitioning = false; accountBusy = false; refreshAccount() }
            do {
                _ = try await recoveryRPC("accountSession/switch", ["sessionId": choice.id, "accountId": choice.workspaceID, "allowBrowserLogin": false])
                let verified = try await recoveryRPC("accountSession/list", [:])
                guard let active = (verified["sessions"] as? [JSON])?.first(where: { $0["isActive"] as? Bool == true }),
                      active["sessionId"] as? String == choice.id, active["selectedWorkspaceAccountId"] as? String == choice.workspaceID else {
                    throw RecoveryFailure.message("Faça login nesta sessão antes de continuar. A troca ainda não foi confirmada.")
                }
                let catalog = try await recoveryRPC("model/list", [:])
                applyRecoverySession(verified, models: Self.parseModels(catalog))
                refresh()
            } catch { self.error = error.localizedDescription }
        }
    }

    func logout() {
        guard activeTasks.isEmpty, ready, !busy, !accountBusy, !scheduledBusy, !recovery.isRecovering else { return }
        recovery.pauseAll()
        accountBusy = true
        request("account/logout", [:]) { [weak self] response in
            guard let self else { return }
            self.accountBusy = false
            if self.accept(response) != nil {
                self.messages = []
                self.conversations = []
                self.selected = nil
                self.resumed = nil
                self.refreshAccount()
            }
        }
    }

    private func accountChanged() {
        guard !recovery.transitioning else { return }
        quota = []
        usageWindows = []
        creditBalance = nil
        resetCredits = nil
        accountIdentity = nil
        plan = nil
        resumed = nil
        models = []
        selectedAccount = nil
        selectedModel = "auto"
        refreshAccount()
        refresh()
    }

    func loadModels() {
        guard !recovery.transitioning else { return }
        let currentAcc = selectedAccount ?? localDataRef?.activeAccount
        if let acc = currentAcc, acc.provider != .openai, !acc.models.isEmpty {
            self.models = acc.models.enumerated().map { index, modelId in
                ModelChoice(id: modelId, name: AIProvider.modelDisplayName(for: modelId), efforts: ["default"], defaultEffort: "default", isDefault: index == 0)
            }
            if !acc.models.contains(selectedModel) {
                selectedModel = acc.currentModel
            }
            modelsLoading = false
            modelsNotice = nil
            return
        }
        let requestID = UUID()
        modelRequestID = requestID
        let session = accountChoices.first(where: \.active)?.id
        let routing = accountChoices.first(where: \.active)?.workspaceID
        modelsLoading = true
        modelsNotice = nil
        request("model/list", [:]) { [weak self] response in
            guard let self, !self.recovery.transitioning, self.modelRequestID == requestID,
                  self.accountChoices.first(where: \.active)?.id == session,
                  self.accountChoices.first(where: \.active)?.workspaceID == routing else { return }
            self.modelsLoading = false
            guard let result = response["result"] as? JSON else {
                self.models = []
                self.modelsNotice = (response["error"] as? JSON)?["message"] as? String ?? "Catálogo indisponível."
                return
            }
            let choices = Self.parseModels(result)
            self.models = choices
            if choices.isEmpty { self.modelsNotice = "O motor não informou modelos para esta sessão." }

            let realIds = choices.map(\.id)
            if let account = self.selectedAccount, account.sessionID == session, session != nil {
                self.localDataRef?.syncModels(accountID: account.id, models: realIds, source: "Codex model/list")
                self.selectedAccount = self.localDataRef?.aiAccounts.first { $0.id == account.id }
            }

            if self.selectedModel != "auto", !choices.contains(where: { $0.id == self.selectedModel }) {
                self.selectedModel = choices.first(where: \.isDefault)?.id ?? choices.first?.id ?? "auto"
            }
            if self.selectedEffort != "default",
               let active = choices.first(where: { $0.id == self.selectedModel }),
               !active.efforts.contains(self.selectedEffort) {
                self.selectedEffort = "default"
            }
        }
    }

    static func parseModels(_ result: JSON) -> [ModelChoice] {
        return (result["data"] as? [JSON] ?? []).compactMap { raw -> ModelChoice? in
                guard raw["hidden"] as? Bool != true,
                      let slug = (raw["model"] as? String) ?? (raw["id"] as? String) else { return nil }
                let efforts = (raw["supportedReasoningEfforts"] as? [Any] ?? []).compactMap { value -> String? in
                    if let text = value as? String { return text }
                    if let object = value as? JSON { return (object["effort"] as? String) ?? (object["id"] as? String) }
                    return nil
            }
                return ModelChoice(id: slug, name: raw["displayName"] as? String ?? slug,
                                   efforts: efforts, defaultEffort: raw["defaultReasoningEffort"] as? String ?? "medium",
                                   isDefault: raw["isDefault"] as? Bool ?? false)
        }
    }

    var currentEfforts: [String] {
        if selectedModel != "auto",
           let model = models.first(where: { $0.id == selectedModel }), !model.efforts.isEmpty {
            return model.efforts
        }
        return ["minimal", "low", "medium", "high", "xhigh"]
    }

    func setMode(_ value: Int) {
        guard !busy, (0...2).contains(value) else { return }
        mode = value
        resumed = nil
    }

    func modeName() -> String {
        switch mode {
        case 1: return "Escrita no projeto"
        case 2: return "Acesso total"
        default: return "Somente leitura"
        }
    }

    func modelName() -> String {
        if selectedModel == "auto" { return models.first(where: \.isDefault)?.name ?? "Modelo automático" }
        return models.first(where: { $0.id == selectedModel })?.name ?? selectedModel
    }

    func effortName() -> String {
        selectedEffort == "default" ? "Padrão" : effortLabel(selectedEffort)
    }

    func effortLabel(_ value: String) -> String {
        ReasoningEffortLevel.from(value: value).title
    }

    private func handleApproval(_ method: String, _ parameters: JSON, _ requestID: Any) -> Bool {
        guard method == "item/commandExecution/requestApproval" || method == "item/fileChange/requestApproval" else { return false }
        let approval = Approval(requestID: requestID,
                                isFileChange: method == "item/fileChange/requestApproval",
                                command: parameters["command"] as? String,
                                reason: parameters["reason"] as? String)
        pendingApprovals.append(approval)
        if voice.orchestrator.isVoiceSessionActive || voice.isVoiceModeActive {
            voice.orchestrator.speakSystemNoticeNaturally(
                "Preciso da sua aprovação na tela antes de executar esta operação."
            )
        }
        return true
    }

    func respondApproval(_ approval: Approval, decision: String) {
        pendingApprovals.removeAll { $0.id == approval.id }
        write(["id": approval.requestID, "result": ["decision": decision]])
    }

    private func statusLabel(_ raw: String?) -> String? {
        switch raw {
        case "inProgress": return "em andamento"
        case "completed": return "concluído"
        case "failed": return "falhou"
        case "declined": return "recusado"
        default: return raw
        }
    }

    private func patchKindLabel(_ raw: String) -> String {
        switch raw {
        case "add": return "novo"
        case "delete": return "removido"
        case "update": return "alterado"
        default: return raw
        }
    }

    private func fileChangeText(_ changes: [JSON]) -> String {
        changes.compactMap { change -> String? in
            guard let path = change["path"] as? String else { return nil }
            var kindName = "alterado"
            if let kind = change["kind"] as? JSON, let type = kind["type"] as? String { kindName = patchKindLabel(type) }
            else if let kind = change["kind"] as? String { kindName = patchKindLabel(kind) }
            let diff = change["diff"] as? String ?? ""
            return diff.isEmpty ? "\(path) (\(kindName))" : "\(path) (\(kindName))\n\(diff)"
        }.joined(separator: "\n\n")
    }

    private func fileChangeSummary(_ changes: [JSON]) -> (target: String, subKind: String) {
        let names = changes.compactMap { ($0["path"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } }
        let target: String
        if names.isEmpty { target = "arquivos do projeto" }
        else if names.count == 1 { target = names[0] }
        else { target = "\(names[0]) +\(names.count - 1)" }

        let firstKind = (changes.first?["kind"] as? JSON)?["type"] as? String ?? (changes.first?["kind"] as? String ?? "update")
        let subKind = firstKind == "add" ? "write" : "edit"
        return (target, subKind)
    }

    private func parsePlanSteps(from text: String) -> [PlanStep] {
        var steps: [PlanStep] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("- [x]") || line.hasPrefix("- [X]") || line.hasPrefix("* [x]") || line.hasPrefix("* [X]") {
                let title = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty { steps.append(PlanStep(title: title, status: "done")) }
            } else if line.hasPrefix("- [/]") || line.hasPrefix("- [~]") {
                let title = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty { steps.append(PlanStep(title: title, status: "in_progress")) }
            } else if line.hasPrefix("- [ ]") || line.hasPrefix("* [ ]") {
                let title = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty { steps.append(PlanStep(title: title, status: "pending")) }
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                let title = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty { steps.append(PlanStep(title: title, status: "pending")) }
            }
        }
        return steps
    }

    private func upsert(_ item: JSON) {
        let itemID = item["id"] as? String ?? UUID().uuidString
        let activeTurn = turnID
        switch item["type"] as? String {
        case "agentMessage":
            guard let text = item["text"] as? String, !text.isEmpty else { return }
            if let exitIndex = messages.lastIndex(where: { $0.kind == .plan && $0.author == "Revisão" && $0.text == text }) {
                let keepId = messages[exitIndex].id
                messages[exitIndex] = Message(id: keepId, author: "WisdAI", text: text, turnId: activeTurn)
                streamedItems[itemID] = keepId
            } else if let existing = streamedItems[itemID], let index = messages.firstIndex(where: { $0.id == existing }) {
                messages[index].text = text
            } else {
                let reply = Message(author: "WisdAI", text: text, turnId: activeTurn)
                streamedItems[itemID] = reply.id
                messages.append(reply)
            }
        case "userMessage":
            return
        case "commandExecution":
            let rawStatus = item["status"] as? String
            let isDone = rawStatus == "completed" || rawStatus == "failed" || rawStatus == "declined"
            let cmd = item["command"] as? String ?? ""
            let aggregated = item["aggregatedOutput"] as? String
            let label = isDone ? "Executado" : "Executando"
            apply(itemID, Message(
                author: "WisdAI",
                text: label,
                kind: .command,
                detail: cmd.isEmpty ? nil : cmd,
                status: statusLabel(rawStatus) ?? (isDone ? "concluído" : "em andamento"),
                exitCode: item["exitCode"] as? Int,
                turnId: activeTurn,
                target: cmd.components(separatedBy: .newlines).first ?? cmd,
                output: (aggregated?.isEmpty == false) ? aggregated : nil,
                subKind: "command"
            ))
        case "fileChange":
            let rawStatus = item["status"] as? String
            let isDone = rawStatus == "completed" || rawStatus == "failed" || rawStatus == "declined"
            let changes = item["changes"] as? [JSON] ?? []
            let summary = fileChangeSummary(changes)
            let verb: String = {
                if summary.subKind == "write" { return isDone ? "Criado" : "Criando" }
                return isDone ? "Editado" : "Editando"
            }()
            let diffOutput = fileChangeText(changes)
            apply(itemID, Message(
                author: "WisdAI",
                text: verb,
                kind: .fileChange,
                status: statusLabel(rawStatus) ?? (isDone ? "concluído" : "em andamento"),
                turnId: activeTurn,
                target: summary.target,
                output: diffOutput.isEmpty ? nil : diffOutput,
                subKind: summary.subKind
            ))
        case "mcpToolCall":
            let rawStatus = item["status"] as? String
            let isDone = rawStatus == "completed" || rawStatus == "failed" || rawStatus == "declined"
            var output = ""
            if let failure = item["error"] as? JSON { output = failure["message"] as? String ?? "Falha na ferramenta." }
            else if let result = item["result"] as? JSON {
                output = (result["content"] as? [JSON] ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
            }
            let server = item["server"] as? String ?? ""
            let tool = item["tool"] as? String ?? ""
            let target = server.isEmpty ? tool : "\(server) · \(tool)"
            apply(itemID, Message(
                author: "WisdAI",
                text: isDone ? "Executado" : "Executando",
                kind: .tool,
                detail: target,
                status: statusLabel(rawStatus) ?? (isDone ? "concluído" : "em andamento"),
                turnId: activeTurn,
                target: target,
                output: output.isEmpty ? nil : output,
                subKind: "tool"
            ))
        case "webSearch":
            let query = item["query"] as? String ?? ""
            apply(itemID, Message(
                author: "WisdAI",
                text: "Pesquisado na web",
                kind: .web,
                detail: query,
                status: "concluído",
                turnId: activeTurn,
                target: query,
                subKind: "web"
            ))
        case "plan":
            let text = item["text"] as? String ?? ""
            guard !text.isEmpty else { return }
            let parsed = parsePlanSteps(from: text)
            apply(itemID, Message(
                author: "WisdAI",
                text: text,
                kind: .plan,
                turnId: activeTurn,
                steps: parsed.isEmpty ? nil : parsed
            ))
        case "reasoning":
            let summary = (item["summary"] as? [Any] ?? []).compactMap { $0 as? String }.joined(separator: "\n\n")
            guard !summary.isEmpty else { return }
            apply(itemID, Message(
                author: "WisdAI",
                text: summary,
                kind: .reasoning,
                status: "concluído",
                turnId: activeTurn,
                subKind: "thought"
            ))
        case "enteredReviewMode":
            let target = item["review"] as? String ?? "alterações locais"
            apply(itemID, Message(author: "Revisão", text: "Revisando \(target)", kind: .plan, status: "em andamento", turnId: activeTurn))
        case "exitedReviewMode":
            for index in messages.indices where messages[index].author == "Revisão" && messages[index].status == "em andamento" {
                messages[index].status = "concluído"
            }
            guard let review = item["review"] as? String, !review.isEmpty else { return }
            if !messages.contains(where: { ($0.author == "WisdAI" || $0.author == "WisdCode") && $0.text == review }) {
                apply(itemID, Message(author: "Revisão", text: review, kind: .plan, turnId: activeTurn))
            }
        default:
            return
        }
    }

    private func apply(_ itemID: String, _ entry: Message) {
        if let existing = streamedItems[itemID], let index = messages.firstIndex(where: { $0.id == existing }) {
            var updated = entry
            updated.id = existing
            if updated.output == nil { updated.output = messages[index].output }
            if updated.steps == nil { updated.steps = messages[index].steps }
            messages[index] = updated
        } else {
            var started = entry
            if started.kind == .command, started.status == nil { started.status = "em andamento" }
            streamedItems[itemID] = started.id
            messages.append(started)
        }
        schedulePersistMessages()
    }

    private func appendDelta(_ itemID: String, _ delta: String, author: String, kind: Message.Kind, turnId: String? = nil, subKind: String? = nil) {
        guard !delta.isEmpty else { return }
        if let existing = streamedItems[itemID], let index = messages.firstIndex(where: { $0.id == existing }) {
            messages[index].text += delta
        } else {
            let reply = Message(author: author, text: delta, kind: kind, status: kind == .text ? nil : "em andamento", turnId: turnId, subKind: subKind)
            streamedItems[itemID] = reply.id
            messages.append(reply)
        }
        if kind == .text,
           (author == "WisdAI" || author == "WisdCode"),
           voice.orchestrator.isVoiceSessionActive,
           !voice.realtimeSessionActive,
           voice.orchestrator.state == .processing {
            // Stream directly only when voice is actively awaiting this turn synchronously;
            // background parallel tasks announce cleanly on completion via notifySpecialistTaskFinished.
            voice.orchestrator.handleStreamingAssistantDelta(delta)
        }
        schedulePersistMessages()
    }

    private func appendOutputDelta(_ itemID: String, _ delta: String) {
        guard !delta.isEmpty else { return }
        if let existing = streamedItems[itemID], let index = messages.firstIndex(where: { $0.id == existing }) {
            messages[index].output = (messages[index].output ?? "") + delta
            schedulePersistMessages()
        }
    }

    private func historyMessage(_ item: JSON, turnId: String? = nil, skipExitedReview: Bool = false) -> Message? {
        switch item["type"] as? String {
        case "userMessage":
            let raw = (item["content"] as? [JSON] ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
            if raw.isEmpty { return nil }
            let text = raw.hasPrefix("Review the current code changes") ? "Revisar alterações locais" : raw
            return Message(author: "Você", text: text, turnId: turnId)
        case "agentMessage":
            return (item["text"] as? String).flatMap { $0.isEmpty ? nil : Message(author: "WisdAI", text: $0, turnId: turnId) }
        case "commandExecution":
            let cmd = item["command"] as? String ?? ""
            let aggregated = item["aggregatedOutput"] as? String
            return Message(
                author: "WisdAI",
                text: "Executado",
                kind: .command,
                detail: cmd.isEmpty ? nil : cmd,
                status: statusLabel(item["status"] as? String) ?? "concluído",
                exitCode: item["exitCode"] as? Int,
                turnId: turnId,
                target: cmd.components(separatedBy: .newlines).first ?? cmd,
                output: (aggregated?.isEmpty == false) ? aggregated : nil,
                subKind: "command"
            )
        case "fileChange":
            let changes = item["changes"] as? [JSON] ?? []
            let diffOutput = fileChangeText(changes)
            guard !diffOutput.isEmpty else { return nil }
            let summary = fileChangeSummary(changes)
            return Message(
                author: "WisdAI",
                text: summary.subKind == "write" ? "Criado" : "Editado",
                kind: .fileChange,
                status: statusLabel(item["status"] as? String) ?? "concluído",
                turnId: turnId,
                target: summary.target,
                output: diffOutput,
                subKind: summary.subKind
            )
        case "reasoning":
            let summary = (item["summary"] as? [Any] ?? []).compactMap { $0 as? String }.joined(separator: "\n\n")
            return summary.isEmpty ? nil : Message(author: "WisdAI", text: summary, kind: .reasoning, status: "concluído", turnId: turnId, subKind: "thought")
        case "plan":
            return (item["text"] as? String).flatMap {
                guard !$0.isEmpty else { return nil }
                let parsed = parsePlanSteps(from: $0)
                return Message(author: "WisdAI", text: $0, kind: .plan, turnId: turnId, steps: parsed.isEmpty ? nil : parsed)
            }
        case "mcpToolCall":
            let server = item["server"] as? String ?? ""
            let tool = item["tool"] as? String ?? ""
            let target = server.isEmpty ? tool : "\(server) · \(tool)"
            return Message(author: "WisdAI", text: "Executado", kind: .tool,
                           detail: target,
                           status: statusLabel(item["status"] as? String) ?? "concluído",
                           turnId: turnId,
                           target: target,
                           subKind: "tool")
        case "enteredReviewMode":
            let target = item["review"] as? String ?? "alterações locais"
            return Message(author: "Revisão", text: "Revisando \(target)", kind: .plan, turnId: turnId)
        case "exitedReviewMode":
            guard !skipExitedReview, let review = item["review"] as? String, !review.isEmpty else { return nil }
            return Message(author: "WisdAI", text: review, turnId: turnId)
        default:
            return nil
        }
    }

    func attachFiles() {
        let picker = NSOpenPanel()
        picker.allowsMultipleSelection = true
        picker.canChooseDirectories = false
        if picker.runModal() == .OK {
            for url in picker.urls {
                do { try attach(url) }
                catch { self.error = error.localizedDescription }
            }
        }
    }

    private func attach(_ url: URL, recording: URL? = nil) throws {
        let info = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .contentTypeKey])
        guard attachments.count < 5, info.isRegularFile == true,
              let size = info.fileSize, size > 0, size <= 10 * 1024 * 1024 else {
            throw CocoaError(.fileReadTooLarge, userInfo: [NSLocalizedDescriptionKey: "Selecione até cinco arquivos de até 10 MB."])
        }
        let input: JSON
        if info.contentType?.conforms(to: .image) == true {
            input = ["type": "localImage", "path": url.path]
        } else if info.contentType?.conforms(to: .audio) == true {
            input = ["type": "localAudio", "path": url.path]
        } else if size <= 64 * 1024, let text = try? String(contentsOf: url, encoding: .utf8),
                  !text.contains("\0") {
            input = ["type": "text", "text": "Arquivo anexado: \(url.lastPathComponent)\n\n\(text)", "textElements": []]
        } else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: "Formato indisponível. Use imagem, áudio ou texto UTF-8 de até 64 KB."])
        }
        attachments.append(Attachment(name: url.lastPathComponent, input: input, recording: recording))
    }

    func removeAttachment(_ attachment: Attachment) {
        attachments.removeAll { $0.id == attachment.id }
        removeRecording(attachment)
    }

    private func removeRecording(_ attachment: Attachment) {
        if let url = attachment.recording { try? FileManager.default.removeItem(at: url) }
    }

    func toggleRecording() {
        if let recorder {
            recorder.stop()
            self.recorder = nil
            recording = false
            do { try attach(recorder.url, recording: recorder.url) }
            catch {
                try? FileManager.default.removeItem(at: recorder.url)
                self.error = error.localizedDescription
            }
            return
        }
        guard !busy, attachments.count < 5 else { return }
        speaker.stopSpeaking(at: .immediate)
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] allowed in
            DispatchQueue.main.async {
                guard let self, !self.busy, self.recorder == nil else { return }
                guard allowed else {
                    self.error = "Permita o acesso ao microfone nos Ajustes do Sistema."
                    return
                }
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("WisdCode-\(UUID().uuidString).m4a")
                do {
                    let recorder = try AVAudioRecorder(url: url, settings: [
                        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                        AVSampleRateKey: 24000,
                        AVNumberOfChannelsKey: 1,
                        AVEncoderBitRateKey: 64000,
                    ])
                    guard recorder.record() else { throw CocoaError(.fileWriteUnknown) }
                    self.recorder = recorder
                    self.recording = true
                } catch {
                    try? FileManager.default.removeItem(at: url)
                    self.error = "Não foi possível iniciar a gravação."
                }
            }
        }
    }

    func speak(_ text: String, preserveProcessingState: Bool = false, queueIfSpeakingIntermediate: Bool = false) {
        let cleaned = VoiceController.cleanForSpeech(text)
        voice.liveAssistantTranscript = cleaned
        if voice.isVoiceModeActive && voice.voiceContinuityEnabled, let tid = selected, !cleaned.isEmpty {
            CodexRealtimeContinuityStore.shared.recordItem(threadId: tid, role: "assistant", text: cleaned)
        }
        voice.speak(
            text,
            preserveProcessingState: preserveProcessingState,
            queueIfSpeakingIntermediate: queueIfSpeakingIntermediate
        )
    }

    func stopSpeaking() {
        voice.stopSpeaking()
    }

    private var activeRealtimeStreamKeys: [String: String] = [:]
    private var realtimeItemRoles: [String: String] = [:]
    private var completedRealtimeItemIDs: Set<String> = []
    private var realtimeTranscriptEpoch: Int = 0
    private var realtimeStartupToken = UUID()
    private var realtimeSessionStartedAt: Date?
    private var realtimeGreetingSent: Bool = false
    private var codexRealtimeFallbackAccountID: UUID?

    private var voiceWaitWatchdogWorkItem: DispatchWorkItem?
    private var voiceToolWaitWorkItem: DispatchWorkItem?
    private var didSpeakVoiceWaitNoticeForTurn: Bool = false
    private var voiceTurnBaselineMessageID: UUID?
    private var lastSpokenVoiceReplyMessageID: UUID?
    private var activeVoiceDelegatedTaskTitle: String?

    func toggleVoiceConversation() {
        if voice.isVoiceModeActive {
            cancelVoiceWaitWatchdog()
            voice.stopVoiceConversation()
            speakReplies = false
            return
        }

        speakReplies = true
        // Motor Autônomo WisdAI ($0 · Local-First): invariante e imediato
        // independentemente de qual conta/agente (Codex, Antigravity, Claude) está selecionada.
        startChatConversationalVoice()
    }

    private func beginVoiceTurnTracking() {
        cancelVoiceWaitWatchdog()
        guard voice.isVoiceModeActive && !voice.realtimeSessionActive else { return }
        didSpeakVoiceWaitNoticeForTurn = false
        voiceTurnBaselineMessageID = messages.last(where: { ($0.author == "WisdAI" || $0.author == "WisdCode") && $0.kind == .text })?.id
        voice.isProcessing = true
        voice.voiceActivity = .thinking
        scheduleVoiceWaitNotice(delay: 10.0, kind: .thinking)
    }

    private func scheduleVoiceWaitNotice(delay: TimeInterval, kind: TaskActivityStep.StepKind) {
        guard voice.isVoiceModeActive && !voice.realtimeSessionActive && !didSpeakVoiceWaitNoticeForTurn else { return }
        let isToolExecution = (kind == .command || kind == .fileChange || kind == .tool || kind == .search || kind == .generic)
        if isToolExecution {
            guard voiceToolWaitWorkItem == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor [weak self] in
                    self?.fireVoiceWaitNoticeIfStillRunning(isToolExecution: true)
                }
            }
            voiceToolWaitWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        } else {
            guard voiceWaitWatchdogWorkItem == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor [weak self] in
                    self?.fireVoiceWaitNoticeIfStillRunning(isToolExecution: false)
                }
            }
            voiceWaitWatchdogWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func cancelPendingVoiceWaitNoticeOnly() {
        voiceWaitWatchdogWorkItem?.cancel()
        voiceWaitWatchdogWorkItem = nil
        voiceToolWaitWorkItem?.cancel()
        voiceToolWaitWorkItem = nil
    }

    private func cancelVoiceWaitWatchdog() {
        cancelPendingVoiceWaitNoticeOnly()
    }

    private func fireVoiceWaitNoticeIfStillRunning(isToolExecution: Bool) {
        cancelPendingVoiceWaitNoticeOnly()
        guard voice.isVoiceModeActive,
              !voice.realtimeSessionActive,
              busy,
              !didSpeakVoiceWaitNoticeForTurn,
              currentActivityKind != .response else { return }

        didSpeakVoiceWaitNoticeForTurn = true
        let message = Self.longTaskWaitNoticeText(isToolExecution: isToolExecution)
        if voice.orchestrator.isVoiceSessionActive {
            voice.orchestrator.speakSystemNoticeNaturally(message, priorityInterrupt: false)
        } else {
            voice.speak(message, preserveProcessingState: true)
        }
    }

    nonisolated static func longTaskWaitNoticeText(isToolExecution: Bool) -> String {
        if isToolExecution {
            return "Certo, estou executando essa tarefa agora e ela vai levar um tempo. Eu te aviso assim que ela for concluída."
        }
        return "Essa solicitação vai levar um tempo para ser concluída. Assim que terminar, eu informo você aqui."
    }

    nonisolated static func formatCompletedReplyForSpeech(_ replyText: String, hadWaitNotice: Bool) -> String {
        let trimmed = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard hadWaitNotice else { return trimmed }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("pronto") || lower.hasPrefix("conclu") || lower.hasPrefix("terminei") || lower.hasPrefix("feito") {
            return trimmed
        }
        return "Pronto, a tarefa foi concluída. \(trimmed)"
    }

    private func deliverCompletedChatVoiceReply(failureText: String?) {
        cancelVoiceWaitWatchdog()
        let hadWaitNotice = didSpeakVoiceWaitNoticeForTurn
        didSpeakVoiceWaitNoticeForTurn = false

        guard !voice.realtimeSessionActive && (voice.isVoiceModeActive || speakReplies) else {
            voice.isProcessing = false
            return
        }

        if let failureText, !failureText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !messages.contains(where: { $0.id != voiceTurnBaselineMessageID && $0.id != lastSpokenVoiceReplyMessageID && ($0.author == "WisdAI" || $0.author == "WisdCode") && $0.kind == .text }) {
            voice.isProcessing = false
            let msg = "Ocorreu um problema na execução: \(failureText)"
            if voice.orchestrator.isVoiceSessionActive {
                voice.orchestrator.speakSystemNoticeNaturally(msg, priorityInterrupt: false)
            } else {
                speak(msg, preserveProcessingState: false, queueIfSpeakingIntermediate: hadWaitNotice)
            }
            return
        }

        if let reply = messages.last(where: { ($0.author == "WisdAI" || $0.author == "WisdCode") && $0.kind == .text }),
           reply.id != voiceTurnBaselineMessageID,
           reply.id != lastSpokenVoiceReplyMessageID {
            let cleaned = VoiceController.cleanForSpeech(reply.text)
            if !cleaned.isEmpty {
                lastSpokenVoiceReplyMessageID = reply.id
                voice.isProcessing = false
                if voice.orchestrator.isVoiceSessionActive {
                    let adapted = VoiceResponseAdapter.adaptForSpeech(
                        reply.text,
                        profile: voice.orchestrator.behavior,
                        customDictionary: voice.orchestrator.customPronunciation
                    )
                    if voice.orchestrator.state == .processing {
                        let finalText = Self.formatCompletedReplyForSpeech(reply.text, hadWaitNotice: hadWaitNotice)
                        voice.orchestrator.finishAssistantResponse(fullMarkdownText: finalText)
                    } else {
                        let taskTitle = activeVoiceDelegatedTaskTitle ?? currentActivityNote ?? "a consulta solicitada"
                        activeVoiceDelegatedTaskTitle = nil
                        voice.orchestrator.notifySpecialistTaskFinished(
                            agentName: selectedAccount?.name ?? "Agente",
                            title: taskTitle,
                            succeeded: failureText == nil,
                            summary: adapted.spokenText
                        )
                    }
                } else {
                    let finalText = Self.formatCompletedReplyForSpeech(reply.text, hadWaitNotice: hadWaitNotice)
                    speak(finalText, preserveProcessingState: false, queueIfSpeakingIntermediate: hadWaitNotice)
                }
                return
            }
        }

        voice.isProcessing = false
        if !voice.orchestrator.isVoiceSessionActive {
            voice.resumeListeningIfVoiceActive()
        }
    }

    private func startCodexRealtimeOrFallback() {
        let token = UUID()
        realtimeStartupToken = token
        realtimeSessionStartedAt = nil
        realtimeGreetingSent = false
        activeRealtimeStreamKeys = [:]
        realtimeItemRoles = [:]
        completedRealtimeItemIDs = []

        voice.stopSpeaking()
        let activeAcc = selectedAccount ?? localDataRef?.activeAccount
        let voiceSessionId = UUID().uuidString.lowercased()

        var preparedOfferSdp: String?
        var resolvedThreadId: String?
        var didLaunchStartRequest = false

        let tryProceedToStart: () -> Void = { [weak self] in
            guard let self,
                  self.voice.isVoiceModeActive,
                  self.realtimeStartupToken == token,
                  !didLaunchStartRequest,
                  let offerSdp = preparedOfferSdp,
                  let threadId = resolvedThreadId else { return }
            didLaunchStartRequest = true
            self.launchWebRTCRealtimeStart(
                threadId: threadId,
                offerSdp: offerSdp,
                voiceSessionId: voiceSessionId,
                activeAccount: activeAcc,
                token: token
            )
        }

        voice.prepareWebRTCRealtimeSession(
            onOffer: { [weak self] offerResult in
                guard let self, self.voice.isVoiceModeActive, self.realtimeStartupToken == token else { return }
                switch offerResult {
                case .success(let sdp):
                    preparedOfferSdp = sdp
                    tryProceedToStart()
                case .failure(let err):
                    let lower = err.localizedDescription.lowercased()
                    if lower.contains("permission") || lower.contains("notallowed") || lower.contains("denied") {
                        self.voice.isConnecting = false
                        self.voice.voiceErrorMessage = "Permita o acesso ao Microfone para conversar por voz com o WisdAI."
                        self.voice.voiceFeedbackStatus = "Microfone não autorizado"
                    } else {
                        self.startChatConversationalVoice()
                    }
                }
            },
            onDataChannelEvent: { [weak self] event in
                self?.handleWebRTCDataChannelEvent(event)
            },
            onError: { [weak self] errMsg in
                guard let self, self.voice.isVoiceModeActive, self.realtimeStartupToken == token else { return }
                let recentStartup = self.voice.isConnecting || (self.realtimeSessionStartedAt.map { Date().timeIntervalSince($0) < 8.0 } ?? true)
                if recentStartup {
                    self.startChatConversationalVoice()
                } else if !errMsg.isEmpty {
                    self.voice.voiceErrorMessage = errMsg
                }
            }
        )

        if let existingId = selected, !existingId.isEmpty {
            if resumed == existingId {
                resolvedThreadId = existingId
                tryProceedToStart()
            } else {
                let activeCwd = project?.path ?? FileManager.default.homeDirectoryForCurrentUser.path
                let sandbox = ["read-only", "workspace-write", "danger-full-access"][min(max(mode, 0), 2)]
                request("thread/resume", ["threadId": existingId, "cwd": activeCwd, "sandbox": sandbox, "approvalPolicy": mode == 2 ? "never" : "on-request"]) { [weak self] response in
                    guard let self, self.voice.isVoiceModeActive, self.realtimeStartupToken == token else { return }
                    if let thread = (response["result"] as? JSON)?["thread"] as? JSON, let tid = thread["id"] as? String {
                        resolvedThreadId = tid
                        self.selected = tid
                        self.resumed = tid
                        tryProceedToStart()
                    } else {
                        self.startChatConversationalVoice()
                    }
                }
            }
            return
        }

        let activeCwd = project?.path ?? FileManager.default.homeDirectoryForCurrentUser.path
        let sandbox = ["read-only", "workspace-write", "danger-full-access"][min(max(mode, 0), 2)]
        var params: JSON = ["cwd": activeCwd, "sandbox": sandbox, "approvalPolicy": mode == 2 ? "never" : "on-request"]
        if temporaryChat { params["ephemeral"] = true }
        request("thread/start", params) { [weak self] response in
            guard let self, self.voice.isVoiceModeActive, self.realtimeStartupToken == token else { return }
            guard let thread = (response["result"] as? JSON)?["thread"] as? JSON,
                  let tid = thread["id"] as? String else {
                self.startChatConversationalVoice()
                return
            }
            self.ensureConversationRegistered(id: tid, title: "Conversa por voz", cwd: activeCwd)
            self.selected = tid
            self.resumed = tid
            resolvedThreadId = tid
            tryProceedToStart()
        }
    }

    private func launchWebRTCRealtimeStart(
        threadId: String,
        offerSdp: String,
        voiceSessionId: String,
        activeAccount: AIAccount?,
        token: UUID
    ) {
        guard voice.isVoiceModeActive, realtimeStartupToken == token else { return }
        selected = threadId
        resumed = threadId

        let recentChat = messages
            .filter { $0.kind == .text && ($0.author == "Você" || $0.author == "WisdAI" || $0.author == "WisdCode") }
            .map { (role: $0.author == "Você" ? "user" : "assistant", text: $0.text) }
        var initialItems = CodexRealtimePromptCatalog.formatRecentConversationContext(items: recentChat)
        if voice.voiceContinuityEnabled {
            let continuityItems = CodexRealtimeContinuityStore.shared.loadItems(for: threadId)
            if initialItems.isEmpty && !continuityItems.isEmpty {
                initialItems = continuityItems
            }
        }

        var promptText = CodexRealtimePromptCatalog.backendPrompt(
            userFirstName: activeAccount?.name,
            projectName: project?.lastPathComponent
        )
        if !initialItems.isEmpty {
            let formattedHistory = initialItems.map { item in
                let prefix = (item.role == "user") ? "[USER]" : "[BACKEND]"
                return "\(prefix) \(item.text)"
            }.joined(separator: "\n")
            promptText += "\n\n<recent_background_task_conversation>\n\(formattedHistory)\n</recent_background_task_conversation>"
        }

        let baseStartParams: JSON = [
            "threadId": threadId,
            "outputModality": "audio",
            "transport": ["type": "webrtc", "sdp": offerSdp],
            "version": "v3",
            "voice": voice.activeCodexVoice.id,
            "includeStartupContext": true,
            "flushTranscriptTailOnSessionEnd": true,
            "realtimeStartInstructions": CodexRealtimePromptCatalog.startInstructions,
            "realtimeEndInstructions": CodexRealtimePromptCatalog.endInstructions,
            "prompt": promptText
        ]

        request("thread/realtime/start", baseStartParams) { [weak self] response in
            guard let self, self.voice.isVoiceModeActive, self.realtimeStartupToken == token else { return }
            guard let failure = response["error"] as? JSON else { return }
            let msg = (failure["message"] as? String ?? "").lowercased()
            let isQuotaOrAuthIssue = msg.contains("usage limit") || msg.contains("rate limit") || msg.contains("upgrade to pro") || msg.contains("api key") || msg.contains("unauthorized")
            if isQuotaOrAuthIssue {
                self.codexRealtimeFallbackAccountID = activeAccount?.id
                self.startChatConversationalVoice()
                return
            }

            // Conformidade de segurança: sem extração de tokens de ~/.codex/auth.json ou endpoints privados;
            // usa o pipeline conversacional nativo/autorizado no WisdVoiceOrchestrator.
            self.codexRealtimeFallbackAccountID = activeAccount?.id
            self.startChatConversationalVoice()
        }

        // Timeout de segurança: garante conversa imediata pelo chat se o WebRTC demorar
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
            guard let self,
                  self.voice.isVoiceModeActive,
                  self.realtimeStartupToken == token,
                  self.voice.isConnecting,
                  !self.voice.realtimeSessionActive else { return }
            self.startChatConversationalVoice()
        }
    }

    private func handleWebRTCDataChannelEvent(_ event: [String: Any]) {
        guard voice.isVoiceModeActive else { return }
        guard let eventType = event["type"] as? String else { return }
        switch eventType {
        case "input_audio_buffer.speech_started":
            voice.voiceActivity = .listening
            if !voice.isMuted {
                voice.voiceFeedbackStatus = "Ouvindo você…"
            }
        case "response.created":
            if !voice.isOutputMuted {
                voice.voiceActivity = .thinking
                voice.voiceFeedbackStatus = "Pensando…"
            }
        case "conversation.handoff.requested", "delegation.created":
            voice.voiceActivity = .thinking
            voice.voiceFeedbackStatus = "Consultando o agente no chat…"
        default:
            break
        }
    }

    private func sendRealtimeGreetingIfNeeded(threadId: String) {
        guard voice.autoGreetingEnabled, !realtimeGreetingSent, messages.isEmpty else { return }
        realtimeGreetingSent = true
        let activeAcc = selectedAccount ?? localDataRef?.activeAccount
        let greeting = CodexRealtimePromptCatalog.greetingDeveloperMessage(userFirstName: activeAcc?.name)
        request("thread/realtime/appendText", [
            "threadId": threadId,
            "role": "developer",
            "text": greeting
        ]) { _ in }
    }

    nonisolated static func buildVoiceActivationGreeting(
        userFullName: String?,
        hasExistingMessages: Bool,
        projectName: String?
    ) -> String {
        let firstName = userFullName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .first
            .map(String.init)
        let namePrefix = (firstName?.isEmpty == false) ? " \(firstName!)" : ""

        if hasExistingMessages {
            let options = [
                "Oi\(namePrefix)! Estou por aqui na nossa conversa. O que você gostaria de fazer agora?",
                "Olá\(namePrefix)! Pode falar, já estou te ouvindo.",
                "Oi\(namePrefix)! Como posso continuar te ajudando aqui?"
            ]
            let idx = Int(Date().timeIntervalSinceReferenceDate) % options.count
            return options[abs(idx)]
        }

        if let projectName, !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Oi\(namePrefix)! Tudo bem? Estou te ouvindo no projeto \(projectName). Como posso te ajudar hoje?"
        }

        let options = [
            "Oi\(namePrefix)! Tudo bem? Pode falar, como posso te ajudar hoje?",
            "Olá\(namePrefix)! Tudo certo? Sobre o que vamos conversar agora?",
            "Oi\(namePrefix)! Estou por aqui, pode falar o que você precisa."
        ]
        let idx = Int(Date().timeIntervalSinceReferenceDate) % options.count
        return options[abs(idx)]
    }

    nonisolated static func resolveFastVoiceModelIfConversational(
        chosenModel: String,
        task: String,
        account: AIAccount?
    ) -> String {
        guard let account, !account.models.isEmpty else { return chosenModel }
        let lowerTask = task.lowercased()
        let heavyKeywords = [
            "analis", "alter", "edit", "modif", "cri", "arquiv", "projeto", "código", "codigo",
            "bug", "erro", "test", "roda", "execut", "git", "compil", "corrig", "refator",
            "implement", "leia", "ler ", "pesquis", "busca", "pasta", "diret", "deploy", "build"
        ]
        if heavyKeywords.contains(where: { lowerTask.contains($0) }) || task.count > 130 {
            return chosenModel
        }
        let fastCandidates = ["flash-low", "-flash", "haiku", "mini", "nano"]
        for pattern in fastCandidates {
            if let fast = account.models.first(where: { $0.lowercased().contains(pattern) }) {
                return fast
            }
        }
        return chosenModel
    }

    private func startChatConversationalVoice() {
        realtimeStartupToken = UUID()
        realtimeSessionStartedAt = nil
        let userName = selectedAccount?.emailOrIdentity.contains("@") == true ? NSFullUserName() : (selectedAccount?.name ?? NSFullUserName())
        let greeting: String? = voice.autoGreetingEnabled
            ? Self.buildVoiceActivationGreeting(
                userFullName: userName,
                hasExistingMessages: !messages.isEmpty,
                projectName: project?.lastPathComponent
            )
            : nil

        let ctxSnapshot = VoiceWorkspaceContextSnapshot(
            projectName: project?.lastPathComponent,
            workspaceDirectoryDisplay: project?.path,
            securityModeName: modeName(),
            activeExecutionAgent: selectedAccount?.name ?? "WisdAI",
            activeTasksCount: activeTasks.count
        )

        voice.startConversationalChatMode(
            workspaceContext: ctxSnapshot,
            continuityMessages: messages.compactMap { msg in
                guard msg.kind == .text, !msg.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return CodexContinuityItem(role: msg.author == "Você" ? "user" : "assistant", text: msg.text)
            },
            hasCodexAppServer: ready,
            activeTasksProvider: { [weak self] in
                guard let self else { return [] }
                var list = self.activeTasks.values.map { task in
                    VoiceTaskSummarySnapshot(
                        id: task.threadId,
                        title: String(task.prompt.prefix(64)),
                        agentName: task.accountName,
                        modelName: task.modelName,
                        status: task.status,
                        progressNote: task.progressNote
                    )
                }
                if list.isEmpty && self.busy {
                    list.append(VoiceTaskSummarySnapshot(
                        id: self.selected ?? "active-turn",
                        title: self.currentActivityNote ?? "Tarefa em execução",
                        agentName: self.selectedAccount?.name ?? "WisdAI",
                        modelName: self.selectedModel,
                        status: "executando",
                        progressNote: self.currentActivityDetail ?? self.currentActivityNote ?? "Em andamento"
                    ))
                }
                return list
            },
            onDelegateTaskToAgent: { [weak self] agentHint, instruction, riskTier in
                guard let self else { return .unavailable(reason: "Workspace encerrado.") }
                let clean = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else { return .unavailable(reason: "Instrução vazia.") }

                // Roteamento explícito de especialista mantendo a voz/identidade WisdAI inalterada
                var resolvedAgentLabel = self.selectedAccount?.name ?? "o agente ativo"
                if agentHint != .autoActive, let local = self.localDataRef {
                    let targetProvider: AIProvider? = {
                        switch agentHint {
                        case .codex: return .openai
                        case .antigravity: return .gemini
                        case .claude: return .claude
                        case .autoActive: return nil
                        }
                    }()
                    if let targetProvider {
                        if let matched = local.aiAccounts.first(where: { $0.provider == targetProvider && $0.supportsExecution }) {
                            local.setActiveAccount(id: matched.id)
                            self.selectedAccount = matched
                            resolvedAgentLabel = matched.name
                        } else {
                            return .unavailable(reason: "Nenhuma conta \(agentHint.rawValue.capitalized) autenticada e ativa está disponível no momento.")
                        }
                    }
                }

                // Ação de alto risco nunca executa automaticamente pela voz sem aprovação explícita
                if riskTier == .high {
                    self.prompt = clean
                    self.messages.append(Message(
                        author: "Sistema",
                        text: "🛡️ Segurança por Voz: comando de risco alto colocado no campo de envio para sua confirmação manual antes de executar."
                    ))
                    self.persistCurrentMessages()
                    return .awaitingUserApproval(reason: "A instrução foi colocada no campo de envio para revisão manual.")
                }

                if self.voice.voiceContinuityEnabled, let tid = self.selected {
                    CodexRealtimeContinuityStore.shared.recordItem(threadId: tid, role: "user", text: clean)
                }
                self.voiceTurnBaselineMessageID = self.messages.last(where: { ($0.author == "WisdAI" || $0.author == "WisdCode") && $0.kind == .text })?.id
                self.activeVoiceDelegatedTaskTitle = String(clean.prefix(64))
                let prevError = self.error
                self.error = nil
                self.prompt = clean
                self.send(forceReadOnly: riskTier == .low)

                if let sendErr = self.error, !sendErr.isEmpty, sendErr != prevError {
                    self.activeVoiceDelegatedTaskTitle = nil
                    return .unavailable(reason: sendErr)
                }
                let confirmed = self.busy || !self.activeTasks.isEmpty
                guard confirmed else {
                    self.activeVoiceDelegatedTaskTitle = nil
                    return .unavailable(reason: self.error ?? "A execução não foi iniciada pelo orquestrador.")
                }
                return .dispatched(agentDisplayName: resolvedAgentLabel)
            },
            onRecordLocalExchangeToChat: { [weak self] userText, assistantText in
                guard let self else { return }
                let u = userText.trimmingCharacters(in: .whitespacesAndNewlines)
                let a = assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !u.isEmpty || !a.isEmpty else { return }
                if let tid = self.selected ?? self.voice.realtimeThreadId {
                    self.ensureConversationRegistered(id: tid, title: u.isEmpty ? "Conversa por voz" : String(u.prefix(48)), cwd: self.project?.path ?? "")
                    if self.voice.voiceContinuityEnabled {
                        if !u.isEmpty && !VoiceMemoryHygieneAnalyzer.isZeroSemanticFragment(u) {
                            CodexRealtimeContinuityStore.shared.recordItem(threadId: tid, role: "user", text: u)
                        }
                        if !a.isEmpty && !VoiceMemoryHygieneAnalyzer.isZeroSemanticFragment(a) {
                            CodexRealtimeContinuityStore.shared.recordItem(threadId: tid, role: "assistant", text: a)
                        }
                    }
                }
                if !u.isEmpty {
                    self.messages.append(Message(author: "Você", text: u, kind: .text))
                }
                if !a.isEmpty {
                    let msg = Message(author: "WisdAI", text: a, kind: .text)
                    self.lastSpokenVoiceReplyMessageID = msg.id
                    self.messages.append(msg)
                }
                self.persistCurrentMessages()
            },
            greeting: greeting
        ) { [weak self] spokenText in
            guard let self else { return }
            let trimmed = spokenText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if self.busy {
                let words = trimmed.split(whereSeparator: { $0.isWhitespace })
                let lower = trimmed.lowercased()
                let isExplicitStop = lower.contains("pare") || lower.contains("para") || lower.contains("cancela") || lower.contains("interromp")
                if words.count <= 1 && !isExplicitStop {
                    return
                }
            }
            if self.voice.voiceContinuityEnabled, let tid = self.selected {
                CodexRealtimeContinuityStore.shared.recordItem(threadId: tid, role: "user", text: trimmed)
            }
            self.voice.orchestrator.beginAssistantTurnResponseTracking()
            self.voice.isProcessing = true
            self.voice.voiceActivity = .thinking
            self.prompt = trimmed
            self.send()
        }
    }

    static func codexVoiceSystemPrompt(projectName: String?) -> String {
        CodexRealtimePromptCatalog.backendPrompt(userFirstName: nil, projectName: projectName)
    }

    static func wrapConversationalVoiceInstruction(_ task: String, projectName: String?) -> String {
        let projectHint = (projectName?.isEmpty == false) ? " (projeto ativo: \(projectName!))" : ""
        return """
        [Assistente de Voz no Chat\(projectHint)]
        Você está conversando por voz ao vivo com o usuário em português do Brasil, exatamente como o assistente de voz do ChatGPT.
        Regras de resposta para conversa falada natural:
        - Responda com tom humano, caloroso, espontâneo e amigável, em poucas frases diretas (2 a 4 frases naturais para diálogo).
        - Escreva exatamente como alguém falando normalmente: sem formatação Markdown pesada, sem títulos com #, sem listas com marcadores, sem asteriscos nem blocos de código (a menos que o usuário peça código no chat).
        - Se o usuário pedir alterações, leituras ou tarefas no projeto, execute normalmente com suas ferramentas e resuma o resultado de forma clara e conversacional.

        O que o usuário acabou de dizer: \(task)
        """
    }

    private func appendRealtimeTranscriptDelta(role: String, delta: String, explicitStreamKey: String? = nil) {
        guard !delta.isEmpty else { return }
        let normalizedRole = (role == "user") ? "user" : "assistant"
        let author = (normalizedRole == "user") ? "Você" : "WisdAI"

        if let threadId = voice.realtimeThreadId ?? selected {
            ensureConversationRegistered(id: threadId, title: normalizedRole == "user" ? delta : "Conversa por voz", cwd: project?.path ?? "")
        }

        if normalizedRole == "user" {
            voice.liveTranscribedText += delta
            if !voice.isMuted && !voice.isSpeaking {
                voice.voiceActivity = .listening
                voice.voiceFeedbackStatus = "Ouvindo você…"
            }
        } else {
            voice.liveAssistantTranscript += delta
            if !voice.isOutputMuted {
                voice.voiceActivity = .speaking
                voice.voiceFeedbackStatus = "WisdAI respondendo…"
            } else {
                voice.voiceFeedbackStatus = "Áudio silenciado · lendo no chat"
            }
        }

        let keyMapId = explicitStreamKey ?? normalizedRole
        let streamKey: String
        if let existingKey = activeRealtimeStreamKeys[keyMapId] {
            streamKey = existingKey
        } else {
            realtimeTranscriptEpoch += 1
            streamKey = explicitStreamKey ?? "realtime-\(normalizedRole)-\(realtimeTranscriptEpoch)"
            activeRealtimeStreamKeys[keyMapId] = streamKey
        }
        appendDelta(streamKey, delta, author: author, kind: .text)
    }

    private func finishRealtimeTranscript(role: String, text: String, explicitStreamKey: String? = nil) {
        let normalizedRole = (role == "user") ? "user" : "assistant"
        let author = (normalizedRole == "user") ? "Você" : "WisdAI"
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let keyMapId = explicitStreamKey ?? normalizedRole
        if let streamKey = activeRealtimeStreamKeys.removeValue(forKey: keyMapId),
           let msgId = streamedItems[streamKey],
           let idx = messages.firstIndex(where: { $0.id == msgId }) {
            if !trimmed.isEmpty {
                messages[idx].text = trimmed
            }
        } else if !trimmed.isEmpty {
            messages.append(Message(author: author, text: trimmed, kind: .text))
        }

        if normalizedRole == "user" {
            voice.liveTranscribedText = ""
            if let convId = selected, let idx = conversations.firstIndex(where: { $0.id == convId }),
               (conversations[idx].title == "Conversa por voz" || conversations[idx].title == "Nova conversa"),
               !trimmed.isEmpty {
                conversations[idx].title = String(trimmed.prefix(48))
                ChatStorage.shared.upsertConversation(conversations[idx])
            }
        } else {
            voice.liveAssistantTranscript = ""
        }

        if voice.voiceContinuityEnabled,
           let threadId = voice.realtimeThreadId ?? selected,
           !trimmed.isEmpty {
            CodexRealtimeContinuityStore.shared.recordItem(threadId: threadId, role: normalizedRole, text: trimmed)
        }
        persistCurrentMessages()
    }

    @discardableResult
    func ensureProject() -> URL {
        if let existing = project { return existing }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaultURL = home.appendingPathComponent("WisdAI")
        try? FileManager.default.createDirectory(at: defaultURL, withIntermediateDirectories: true)
        project = defaultURL
        return defaultURL
    }

    func chooseProject() {
        let picker = NSOpenPanel()
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.allowsMultipleSelection = false
        if picker.runModal() == .OK {
            project = picker.url
            newConversation()
        }
    }

    func newConversation() {
        guard !busy else { return }
        if selected != nil && !messages.isEmpty {
            persistCurrentMessages()
        }
        selected = nil
        messages = []
        error = nil
        ChatStorage.shared.setLastSelectedThreadId(nil)
        UserDefaults.standard.removeObject(forKey: "wisdcode.desktop.lastSelectedThread")
    }

    func open(_ conversation: Conversation) {
        unseenCompletedThreads.remove(conversation.id)
        openThread(id: conversation.id, cwd: conversation.cwd)
    }

    func openThread(id: String, cwd: String) {
        unseenCompletedThreads.remove(id)
        if let prev = selected, prev != id, !messages.isEmpty {
            persistCurrentMessages()
        }
        temporaryChat = false
        selected = id
        ChatStorage.shared.setLastSelectedThreadId(id)
        UserDefaults.standard.set(id, forKey: "wisdcode.desktop.lastSelectedThread")
        project = cwd.isEmpty ? nil : URL(fileURLWithPath: cwd)
        let cached = ChatStorage.shared.loadMessages(for: id)
        if !cached.isEmpty {
            messages = cached
        } else {
            messages = []
        }
        streamedItems = [:]
        error = nil
        busy = (activeTasks[id] != nil)
        request("thread/read", ["threadId": id, "includeTurns": true]) { [weak self] response in
            guard let self, self.selected == id,
                  let thread = self.accept(response)?["thread"] as? JSON else { return }
            self.loadedHistories.insert(id)
            self.knownLastTurns[id] = (thread["turns"] as? [JSON])?.last?["id"] as? String
            let serverTurns = (thread["turns"] as? [JSON] ?? [])
            if !serverTurns.isEmpty {
                let msgs = serverTurns.flatMap { turn -> [Message] in
                    let turnId = turn["id"] as? String
                    let items = turn["items"] as? [JSON] ?? []
                    let hasAgentMessage = items.contains {
                        ($0["type"] as? String) == "agentMessage" && !(($0["text"] as? String) ?? "").isEmpty
                    }
                    return items.compactMap { self.historyMessage($0, turnId: turnId, skipExitedReview: hasAgentMessage) }
                }
                let localMsgs = ChatStorage.shared.loadMessages(for: id)
                let usesHybridOrCLI = self.conversations.first(where: { $0.id == id })?.agyConversationId != nil
                let localHasReplies = localMsgs.contains { $0.author != "Você" && $0.kind == .text }
                let serverHasReplies = msgs.contains { $0.author != "Você" && $0.kind == .text }
                // Protege o histórico local completo armazenado no SQLite contra sobrescrita por turnos parciais do motor
                let shouldAdoptServer = !msgs.isEmpty && (
                    localMsgs.isEmpty ||
                    (!usesHybridOrCLI && msgs.count > localMsgs.count && (!localHasReplies || serverHasReplies))
                )
                if shouldAdoptServer {
                    self.messages = msgs
                    ChatStorage.shared.saveMessages(msgs, for: id)
                }
            }
        }
    }

    func deleteThread(_ thread: Conversation) {
        guard !accountBusy, activeTasks[thread.id] == nil, !recovery.isRecovering else { return }
        recovery.cancel(thread.id)
        ChatStorage.shared.deleteThread(thread.id)
        self.conversations.removeAll { $0.id == thread.id }
        self.localDataRef?.pinnedThreads.removeAll { $0 == thread.id }
        if self.selected == thread.id {
            self.selected = nil
            self.messages = []
            self.error = nil
            ChatStorage.shared.setLastSelectedThreadId(nil)
            UserDefaults.standard.removeObject(forKey: "wisdcode.desktop.lastSelectedThread")
        }
        if ready {
            request("thread/unsubscribe", ["threadId": thread.id]) { [weak self] response in
                guard let self, self.accept(response) != nil else { return }
                if self.resumed == thread.id { self.resumed = nil }
                self.request("thread/delete", ["threadId": thread.id]) { [weak self] response in
                    guard let self, self.accept(response) != nil else { return }
                    self.recovery.finished(thread.id)
                    self.refresh()
                }
            }
        }
    }

    func renameConversation(_ thread: Conversation, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let idx = conversations.firstIndex(where: { $0.id == thread.id }) {
            conversations[idx].title = trimmed
            ChatStorage.shared.upsertConversation(conversations[idx])
        } else {
            var updated = thread
            updated.title = trimmed
            ChatStorage.shared.upsertConversation(updated)
        }
        if ready {
            request("thread/name/set", ["threadId": thread.id, "name": trimmed]) { [weak self] response in
                _ = self?.accept(response)
            }
        }
    }

    func archiveThreads(_ threads: [Conversation]) {
        guard let first = threads.first else { refresh(); return }
        guard activeTasks[first.id] == nil, !recovery.isRecovering, !accountBusy else {
            error = "Encerre a tarefa de \(first.title) antes de arquivá-la."
            return
        }
        recovery.cancel(first.id)
        request("thread/archive", ["threadId": first.id]) { [weak self] response in
            guard let self, self.accept(response) != nil else { return }
            self.recovery.finished(first.id)
            if self.selected == first.id { self.newConversation() }
            self.archiveThreads(Array(threads.dropFirst()))
        }
    }

    private func isRouteBlockedInRecovery(account: AIAccount, model: String) -> Bool {
        guard account.provider == .openai,
              let sId = account.sessionID,
              let wId = account.workspaceID else { return false }
        let route = "\(sId):\(wId)"
        return recovery.journal.blocked(route) || recovery.journal.blocked("\(route):\(model)")
    }

    func isAccountExecutableNow(_ account: AIAccount) -> Bool {
        switch account.provider {
        case .openai:
            return account.sessionID != nil
        case .gemini, .claude:
            if ProcessInfo.processInfo.processName.contains("Smoke") { return account.supportsExecution }
            let cli = account.cliPath ?? AgentCLIAuthenticator.locateCLI(for: account.provider)
            return cli.map { FileManager.default.isExecutableFile(atPath: $0) } ?? false
        default:
            if ProcessInfo.processInfo.processName.contains("Smoke") { return account.supportsExecution }
            if let cli = account.cliPath ?? AgentCLIAuthenticator.locateCLI(for: account.provider),
               FileManager.default.isExecutableFile(atPath: cli) {
                return true
            }
            let hasKey = (try? AccountKeychain.read(accountID: account.id)) != nil
                || AccountKeychain.readAccountPassword(accountID: account.id) != nil
                || AccountKeychain.readProviderKey(provider: account.provider) != nil
            return hasKey
        }
    }

    struct EditedMessageContext {
        let truncatedMessages: [Message]
        let priorTextMessages: [Message]
        let beforeTurnId: String?
        let editedTitle: String?
    }

    static func prepareContextForEditedMessage(
        in existingMessages: [Message],
        messageID: UUID,
        newText: String
    ) -> EditedMessageContext? {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let editIndex = existingMessages.firstIndex(where: { $0.id == messageID }),
              existingMessages[editIndex].author == "Você" else {
            return nil
        }
        let preserved = Array(existingMessages[..<editIndex])
        let priorTexts = preserved.filter {
            $0.kind == .text && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let targetTurnId = existingMessages[editIndex...].compactMap(\.turnId).first
        let editedTitle = (editIndex == 0) ? String(trimmed.prefix(48)) : nil
        return EditedMessageContext(
            truncatedMessages: preserved,
            priorTextMessages: priorTexts,
            beforeTurnId: targetTurnId,
            editedTitle: editedTitle
        )
    }

    static func buildPriorConversationContextPrompt(priorMessages: [Message], currentTask: String) -> String {
        guard !priorMessages.isEmpty else { return currentTask }
        var lines = ["Contexto da conversa até este ponto:"]
        for msg in priorMessages.suffix(16) {
            let trimmed = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let snippet = trimmed.count > 1200 ? String(trimmed.prefix(1200)) + "…" : trimmed
            lines.append("\(msg.author): \(snippet)")
        }
        lines.append("")
        lines.append("Mensagem editada do usuário (considere apenas o histórico acima, desconsidere qualquer interação posterior): \(currentTask)")
        return lines.joined(separator: "\n")
    }

    private func migrateThreadID(from oldId: String, to newId: String) {
        guard oldId != newId else { return }
        let currentMessages = self.messages
        var updatedConv: Conversation?
        if let idx = conversations.firstIndex(where: { $0.id == oldId }) {
            var conv = conversations[idx]
            conv.id = newId
            conv.agyConversationId = nil
            conv.lastUpdated = Date()
            conversations[idx] = conv
            updatedConv = conv
        }
        if let pinIdx = localDataRef?.pinnedThreads.firstIndex(of: oldId) {
            localDataRef?.pinnedThreads[pinIdx] = newId
        }
        ChatStorage.shared.deleteThread(oldId)
        if let updatedConv {
            ChatStorage.shared.upsertConversation(updatedConv)
        }
        ChatStorage.shared.saveMessages(currentMessages, for: newId)
        if selected == oldId {
            selected = newId
            ChatStorage.shared.setLastSelectedThreadId(newId)
            UserDefaults.standard.set(newId, forKey: "wisdcode.desktop.lastSelectedThread")
        }
        resumed = newId
    }

    func editMessageAndResend(messageID: UUID, newText: String) {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !accountBusy, !recording, !recovery.isRecovering else { return }
        guard activeTasks.count < 5 else {
            error = "Limite de 5 tarefas simultâneas atingido. Aguarde a conclusão de uma tarefa."
            return
        }
        guard let ctx = Self.prepareContextForEditedMessage(in: messages, messageID: messageID, newText: trimmed) else {
            return
        }

        error = nil
        reconcileQuotaAndExpiredLimits()

        var currentAccount = selectedAccount ?? localDataRef?.activeAccount
        var chosenModel = (selectedModel != "auto" ? selectedModel : models.first(where: \.isDefault)?.id ?? models.first?.id) ?? currentAccount?.currentModel ?? "auto"

        if let local = localDataRef, !local.aiAccounts.isEmpty {
            if let best = quotaStore.selectBestRoute(
                preferredAccount: currentAccount,
                preferredModel: chosenModel,
                allAccounts: local.aiAccounts,
                canExecuteAccount: { [weak self] acc in self?.isAccountExecutableNow(acc) ?? acc.supportsExecution },
                isBlocked: { [weak self] acc, mod in self?.isRouteBlockedInRecovery(account: acc, model: mod) ?? false }
            ) {
                currentAccount = best.account
                chosenModel = best.model
                if best.account.id != selectedAccount?.id || best.model != selectedModel {
                    local.setActiveAccount(id: best.account.id)
                    if let idx = local.aiAccounts.firstIndex(where: { $0.id == best.account.id }),
                       let mIdx = local.aiAccounts[idx].models.firstIndex(of: best.model) {
                        local.aiAccounts[idx].activeModelIndex = mIdx
                    }
                    selectedAccount = local.aiAccounts.first(where: { $0.id == best.account.id }) ?? best.account
                    selectedModel = best.model
                }
            } else {
                error = "Nenhuma conta com capacidade disponível neste momento."
                return
            }
        }

        // Recorta o histórico estritamente até a mensagem editada e insere a versão editada do usuário
        var updatedMessages = ctx.truncatedMessages
        updatedMessages.append(Message(author: "Você", text: trimmed))
        self.messages = updatedMessages
        self.streamedItems = [:]

        let threadId = selected ?? UUID().uuidString
        selected = threadId
        recovery.cancel(threadId)

        if let idx = conversations.firstIndex(where: { $0.id == threadId }) {
            conversations[idx].agyConversationId = nil
            conversations[idx].lastUpdated = Date()
            if let newTitle = ctx.editedTitle, !newTitle.isEmpty {
                conversations[idx].title = newTitle
            }
            ChatStorage.shared.upsertConversation(conversations[idx])
        } else {
            ensureConversationRegistered(id: threadId, title: trimmed, cwd: project?.path ?? "")
        }
        persistCurrentMessages()

        let baseInstruction = (voice.isVoiceModeActive && !voice.realtimeSessionActive)
            ? Self.wrapConversationalVoiceInstruction(trimmed, projectName: project?.lastPathComponent)
            : trimmed
        let provider = currentAccount?.provider ?? .openai

        // Para provedores CLI (Gemini/Claude), executeCLITurn injeta automaticamente ctx.priorTextMessages (pois agyConversationId foi limpo).
        if provider == .gemini || provider == .claude {
            dispatchTurnOnRoute(
                existingThreadId: threadId,
                task: trimmed,
                instruction: baseInstruction,
                account: currentAccount,
                model: chosenModel,
                skipAddingUserMessage: true,
                retryDepth: 0
            )
            return
        }

        // Para OpenAI/Codex app-server: tenta reverter no servidor antes do turn editado; caso não aplicável, inicia novo ramo com o contexto até a mensagem editada.
        let dispatchFreshCodexBranch: () -> Void = { [weak self] in
            guard let self else { return }
            let branchInstruction = Self.buildPriorConversationContextPrompt(
                priorMessages: ctx.priorTextMessages,
                currentTask: baseInstruction
            )
            let activeCwd = self.project?.path ?? FileManager.default.homeDirectoryForCurrentUser.path
            let sandbox = ["read-only", "workspace-write", "danger-full-access"][min(max(self.mode, 0), 2)]
            var params: JSON = ["cwd": activeCwd, "sandbox": sandbox, "approvalPolicy": self.mode == 2 ? "never" : "on-request"]
            if self.temporaryChat { params["ephemeral"] = true }
            self.busy = true
            self.request("thread/start", params) { [weak self] response in
                guard let self else { return }
                guard let thread = self.accept(response)?["thread"] as? JSON,
                      let newId = thread["id"] as? String else {
                    self.busy = false
                    return
                }
                self.migrateThreadID(from: threadId, to: newId)
                self.dispatchTurnOnRoute(
                    existingThreadId: newId,
                    task: trimmed,
                    instruction: branchInstruction,
                    account: currentAccount,
                    model: chosenModel,
                    skipAddingUserMessage: true,
                    retryDepth: 0
                )
            }
        }

        if ready, !temporaryChat, let beforeTurnId = ctx.beforeTurnId, !beforeTurnId.isEmpty {
            busy = true
            request("thread/revert", ["threadId": threadId, "beforeTurnId": beforeTurnId]) { [weak self] response in
                guard let self else { return }
                if response["error"] == nil {
                    self.resumed = threadId
                    self.dispatchTurnOnRoute(
                        existingThreadId: threadId,
                        task: trimmed,
                        instruction: baseInstruction,
                        account: currentAccount,
                        model: chosenModel,
                        skipAddingUserMessage: true,
                        retryDepth: 0
                    )
                } else {
                    dispatchFreshCodexBranch()
                }
            }
        } else if ready {
            dispatchFreshCodexBranch()
        } else {
            error = "Conectando ao motor WisdAI, tente novamente em instantes."
        }
    }

    func send(forceReadOnly: Bool = false) {
        let task = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accountBusy, !recording, (!task.isEmpty || !attachments.isEmpty) else { return }

        // Quando há uma sessão Codex Realtime ativa e o usuário digita no chat, encaminha direto para a mesma conversa
        if voice.isVoiceModeActive && voice.realtimeSessionActive,
           let rtThreadId = voice.realtimeThreadId,
           attachments.isEmpty, !busy, !task.isEmpty {
            prompt = ""
            messages.append(Message(author: "Você", text: task, kind: .text))
            persistCurrentMessages()
            request("thread/realtime/appendText", ["threadId": rtThreadId, "text": task, "role": "user"]) { _ in }
            return
        }

        // Se uma tarefa já estiver em execução nesta conversa, trata como intervenção em tempo real!
        if busy || (selected != nil && activeTasks[selected!] != nil) {
            sendIntervention(task)
            return
        }
        if activeTasks.count >= 5 {
            error = "Limite de 5 tarefas simultâneas atingido. Aguarde a conclusão de uma tarefa."
            return
        }

        // Reconcilia imediatamente limites expirados / renovados antes de decidir para onde rotear
        reconcileQuotaAndExpiredLimits()

        var currentAccount = selectedAccount ?? localDataRef?.activeAccount
        var chosenModel = (selectedModel != "auto" ? selectedModel : models.first(where: \.isDefault)?.id ?? models.first?.id) ?? currentAccount?.currentModel ?? "auto"

        if let local = localDataRef, !local.aiAccounts.isEmpty {
            if let best = quotaStore.selectBestRoute(
                preferredAccount: currentAccount,
                preferredModel: chosenModel,
                allAccounts: local.aiAccounts,
                canExecuteAccount: { [weak self] acc in self?.isAccountExecutableNow(acc) ?? acc.supportsExecution },
                isBlocked: { [weak self] acc, mod in self?.isRouteBlockedInRecovery(account: acc, model: mod) ?? false }
            ) {
                let accountChangedRoute = (best.account.id != currentAccount?.id)
                let modelChangedRoute = (best.model != chosenModel)
                currentAccount = best.account
                chosenModel = best.model
                if accountChangedRoute || modelChangedRoute || best.switchedReason != nil {
                    local.setActiveAccount(id: best.account.id)
                    if let idx = local.aiAccounts.firstIndex(where: { $0.id == best.account.id }),
                       let mIdx = local.aiAccounts[idx].models.firstIndex(of: best.model) {
                        local.aiAccounts[idx].activeModelIndex = mIdx
                    }
                    selectedAccount = local.aiAccounts.first(where: { $0.id == best.account.id }) ?? best.account
                    selectedModel = best.model
                    if let reason = best.switchedReason {
                        messages.append(Message(author: "Sistema", text: "⚡ \(reason)"))
                        persistCurrentMessages()
                    }
                }
            } else if local.aiAccounts.contains(where: { isAccountExecutableNow($0) }) {
                let resetInfo = quotaStore.earliestRecoveryDate(across: local.aiAccounts).map {
                    " Próxima liberação prevista: \($0.formatted(date: .omitted, time: .shortened))."
                } ?? ""
                let msg = "⏳ Limite atingido em memória para as contas e modelos conectados.\(resetInfo) Aguarde a renovação ou adicione outra conta em Configurações."
                error = msg
                messages.append(Message(author: "Sistema", text: msg))
                persistCurrentMessages()
                return
            } else {
                let msg = "Nenhuma conta com CLI ou sessão autenticada está disponível neste Mac. Conecte uma sessão OpenAI ou CLI Antigravity/Claude em Configurações."
                error = msg
                messages.append(Message(author: "Sistema", text: msg))
                persistCurrentMessages()
                return
            }
        }

        let baseTurnInstruction = (voice.isVoiceModeActive && !voice.realtimeSessionActive)
            ? Self.wrapConversationalVoiceInstruction(task, projectName: project?.lastPathComponent)
            : task
        let effectiveTurnInstruction = forceReadOnly
            ? "[MODO CONSULTA SOMENTE LEITURA: Apenas leia/analise informações; NÃO edite, crie, remova nem modifique arquivos no workspace.]\n\n\(baseTurnInstruction)"
            : baseTurnInstruction
        let effectiveVoiceModel = (voice.isVoiceModeActive && !voice.realtimeSessionActive)
            ? Self.resolveFastVoiceModelIfConversational(chosenModel: chosenModel, task: task, account: currentAccount)
            : chosenModel

        dispatchTurnOnRoute(
            existingThreadId: selected,
            task: task,
            instruction: effectiveTurnInstruction,
            account: currentAccount,
            model: effectiveVoiceModel,
            skipAddingUserMessage: false,
            retryDepth: 0,
            forceReadOnly: forceReadOnly
        )
    }

    private func dispatchTurnOnRoute(
        existingThreadId: String?,
        task: String,
        instruction: String,
        account: AIAccount?,
        model: String,
        skipAddingUserMessage: Bool,
        retryDepth: Int,
        forceReadOnly: Bool = false
    ) {
        let activeCwd = project?.path ?? FileManager.default.homeDirectoryForCurrentUser.path
        let isGemini = (account?.provider == .gemini) || (account == nil && model.lowercased().contains("gemini"))
        let isClaude = (account?.provider == .claude) || (account == nil && model.lowercased().contains("claude"))

        if isGemini {
            let agyCLI = account?.cliPath ?? AgentCLIAuthenticator.locateCLI(for: .gemini) ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/agy").path
            if FileManager.default.isExecutableFile(atPath: agyCLI) {
                let id = existingThreadId ?? UUID().uuidString
                selected = id
                resumed = id
                executeCLITurn(
                    id: id,
                    task: task,
                    instruction: instruction,
                    model: model,
                    projectURL: project,
                    cliPath: agyCLI,
                    skipAddingUserMessage: skipAddingUserMessage,
                    accountID: account?.id,
                    retryDepth: retryDepth,
                    forceReadOnly: forceReadOnly
                )
                return
            }
            if let accID = account?.id {
                quotaStore.markAccountLimited(accountID: accID, models: account?.models ?? [], until: Date().addingTimeInterval(3600), reason: "CLI agy não encontrada neste Mac")
            }
            let threadForFallback = existingThreadId ?? selected ?? UUID().uuidString
            if autoFallbackToNextAccount(forTask: task, onThread: threadForFallback, failedModel: model, limitKind: .account, until: Date().addingTimeInterval(3600), reason: "CLI Antigravity (agy) indisponível", skipAddingUserMessage: true, retryDepth: retryDepth + 1) {
                return
            }
            error = "CLI Antigravity (agy) não encontrada e nenhuma outra conta está disponível."
            busy = false
            return
        } else if isClaude {
            let claudeCLI = account?.cliPath ?? AgentCLIAuthenticator.locateCLI(for: .claude)
            if let cli = claudeCLI, FileManager.default.isExecutableFile(atPath: cli) {
                let id = existingThreadId ?? UUID().uuidString
                selected = id
                resumed = id
                executeCLITurn(
                    id: id,
                    task: task,
                    instruction: instruction,
                    model: model,
                    projectURL: project,
                    cliPath: cli,
                    skipAddingUserMessage: skipAddingUserMessage,
                    accountID: account?.id,
                    retryDepth: retryDepth,
                    forceReadOnly: forceReadOnly
                )
                return
            }
            if let accID = account?.id {
                quotaStore.markAccountLimited(accountID: accID, models: account?.models ?? AIProvider.claude.defaultModels, until: Date().addingTimeInterval(3600), reason: "CLI claude não instalada neste Mac")
            }
            let threadForFallback = existingThreadId ?? selected ?? UUID().uuidString
            if autoFallbackToNextAccount(forTask: task, onThread: threadForFallback, failedModel: model, limitKind: .account, until: Date().addingTimeInterval(3600), reason: "CLI Claude (claude) indisponível neste Mac", skipAddingUserMessage: true, retryDepth: retryDepth + 1) {
                return
            }
            error = "CLI Claude (claude) não está instalada neste Mac e nenhuma outra conta com tokens disponíveis foi encontrada."
            busy = false
            return
        } else if let provider = account?.provider, provider != .openai {
            if let accID = account?.id {
                quotaStore.markAccountLimited(accountID: accID, models: account?.models ?? [], until: Date().addingTimeInterval(3600), reason: "Provedor \(provider.displayName) requer CLI dedicada")
            }
            let threadForFallback = existingThreadId ?? selected ?? UUID().uuidString
            if autoFallbackToNextAccount(forTask: task, onThread: threadForFallback, failedModel: model, limitKind: .account, until: Date().addingTimeInterval(3600), reason: "Motor \(provider.displayName) indisponível", skipAddingUserMessage: true, retryDepth: retryDepth + 1) {
                return
            }
            error = "O provedor \(provider.displayName) não possui CLI executável neste Mac."
            busy = false
            return
        }

        // Garante que somente modelos compatíveis com OpenAI/Codex cheguem ao codex app-server
        let sanitizedModel: String = {
            if let account, !UsageQuotaStore.isModelCompatible(model, with: account) {
                return models.first(where: \.isDefault)?.id ?? models.first?.id ?? (account.models.first ?? "auto")
            }
            let lower = model.lowercased()
            if lower.contains("claude") || lower.contains("gemini") || lower.contains("deepseek") || lower.contains("grok") || lower.contains("kimi") {
                return models.first(where: \.isDefault)?.id ?? models.first?.id ?? "auto"
            }
            if !models.isEmpty && model != "auto" && !models.contains(where: { $0.id == model }) {
                return models.first(where: \.isDefault)?.id ?? models.first?.id ?? "auto"
            }
            return model
        }()
        if sanitizedModel != selectedModel {
            selectedModel = sanitizedModel
        }

        // Execução padrão via motor codex app-server
        guard ready else {
            error = "Conectando ao motor WisdAI, tente novamente em instantes."
            return
        }
        busy = true
        error = nil
        streamedItems = [:]

        let startOrResume = { [weak self] in
            guard let self else { return }
            let effectiveMode = forceReadOnly ? 0 : self.mode
            let sandbox = ["read-only", "workspace-write", "danger-full-access"][min(max(effectiveMode, 0), 2)]
            let safety: JSON = ["cwd": activeCwd, "sandbox": sandbox,
                                "approvalPolicy": effectiveMode == 2 ? "never" : "on-request"]
            if let existing = existingThreadId, self.resumed == existing {
                self.startTurn(existing, task, instructionOverride: instruction, modelOverride: sanitizedModel, skipAddingUserMessage: skipAddingUserMessage, forceReadOnly: forceReadOnly)
                return
            }
            var parameters = safety
            if existingThreadId == nil { parameters["ephemeral"] = self.temporaryChat }
            if let existingThreadId { parameters["threadId"] = existingThreadId }
            self.request(existingThreadId == nil ? "thread/start" : "thread/resume", parameters) { [weak self] response in
                guard let self else { return }
                guard let thread = self.accept(response)?["thread"] as? JSON, let id = thread["id"] as? String else {
                    self.busy = false
                    return
                }
                self.selected = id
                self.resumed = id
                self.loadedHistories.insert(id)
                self.knownLastTurns[id] = (thread["turns"] as? [JSON])?.last?["id"] as? String
                if !self.conversations.contains(where: { $0.id == id }) {
                    let convTitle = String(task.prefix(32))
                    let newConv = Conversation(id: id, title: convTitle.isEmpty ? "Nova conversa" : convTitle, cwd: activeCwd)
                    self.conversations.insert(newConv, at: 0)
                }
                self.startTurn(id, task, instructionOverride: instruction, modelOverride: sanitizedModel, cwdOverride: activeCwd, skipAddingUserMessage: skipAddingUserMessage, forceReadOnly: forceReadOnly)
            }
        }

        // Garante que o backend codex esteja na sessão ChatGPT alvo antes de enviar startTurn
        if let targetAcc = account,
           targetAcc.provider == .openai,
           let targetSession = targetAcc.sessionID,
           let targetWorkspace = targetAcc.workspaceID,
           let currentActive = accountChoices.first(where: \.active),
           currentActive.id != targetSession || currentActive.workspaceID != targetWorkspace {
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    self.recovery.transitioning = true
                    defer { self.recovery.transitioning = false }
                    _ = try await self.recoveryRPC("accountSession/switch", [
                        "sessionId": targetSession,
                        "accountId": targetWorkspace,
                        "allowBrowserLogin": false
                    ])
                    let verified = try await self.recoveryRPC("accountSession/list", [:])
                    let catalog = try await self.recoveryRPC("model/list", [:])
                    self.applyRecoverySession(verified, models: Self.parseModels(catalog))
                    self.refreshQuota()
                    startOrResume()
                } catch {
                    self.busy = false
                    self.error = error.localizedDescription
                }
            }
            return
        }

        startOrResume()
    }

    @discardableResult
    func autoFallbackToNextAccount(
        forTask task: String,
        onThread threadId: String,
        failedModel: String? = nil,
        limitKind: ProviderLimit = .account,
        until: Date? = nil,
        reason: String? = nil,
        skipAddingUserMessage: Bool = false,
        retryDepth: Int = 0
    ) -> Bool {
        guard retryDepth < 3, let local = localDataRef else { return false }
        let currentAcc = selectedAccount ?? local.activeAccount
        let blockedUntil = until ?? Date().addingTimeInterval(limitKind == .account ? 900 : 300)
        let modelToMark = failedModel ?? currentAcc?.currentModel ?? selectedModel

        if let cid = currentAcc?.id {
            if limitKind == .model, !modelToMark.isEmpty && modelToMark != "auto" {
                quotaStore.markModelLimited(
                    accountID: cid,
                    modelID: modelToMark,
                    until: blockedUntil,
                    reason: reason ?? "Limite do modelo atingido"
                )
                if let idx = local.aiAccounts.firstIndex(where: { $0.id == cid }),
                   let mIdx = local.aiAccounts[idx].models.firstIndex(of: modelToMark) {
                    local.markModelExhausted(accountID: cid, modelIndex: mIdx)
                }
            } else {
                quotaStore.markAccountLimited(
                    accountID: cid,
                    models: currentAcc?.models ?? [],
                    until: blockedUntil,
                    reason: reason ?? "Limite da conta atingido"
                )
                local.markAccountExhausted(accountID: cid)
            }
        }

        let refreshedPref = currentAcc.flatMap { old in local.aiAccounts.first(where: { $0.id == old.id }) }
        guard let next = quotaStore.selectBestRoute(
            preferredAccount: refreshedPref,
            preferredModel: modelToMark,
            allAccounts: local.aiAccounts,
            canExecuteAccount: { [weak self] acc in self?.isAccountExecutableNow(acc) ?? acc.supportsExecution },
            isBlocked: { [weak self] acc, mod in self?.isRouteBlockedInRecovery(account: acc, model: mod) ?? false }
        ) else {
            return false
        }

        let previousLabel = currentAcc?.name ?? "Conta atual"
        local.setActiveAccount(id: next.account.id)
        if let idx = local.aiAccounts.firstIndex(where: { $0.id == next.account.id }),
           let mIdx = local.aiAccounts[idx].models.firstIndex(of: next.model) {
            local.aiAccounts[idx].activeModelIndex = mIdx
        }
        selectedAccount = local.aiAccounts.first(where: { $0.id == next.account.id }) ?? next.account
        selectedModel = next.model

        let modelDisplay = AIProvider.modelDisplayName(for: next.model)
        let remSuffix = quotaStore.remainingPercent(accountID: next.account.id, modelID: next.model).map { " (\($0)% livre)" } ?? ""
        let notice = next.account.id == currentAcc?.id
            ? "⚠️ Limite atingido no modelo \(AIProvider.modelDisplayName(for: modelToMark)). Alternando para \(modelDisplay)\(remSuffix)."
            : "⚠️ Limite atingido em \(previousLabel). Alternando automaticamente para \(next.account.name) · \(modelDisplay)\(remSuffix)."
        messages.append(Message(author: "Sistema", text: notice))
        persistCurrentMessages()

        dispatchTurnOnRoute(
            existingThreadId: threadId,
            task: task,
            instruction: task,
            account: selectedAccount,
            model: next.model,
            skipAddingUserMessage: skipAddingUserMessage,
            retryDepth: retryDepth
        )
        return true
    }

    func sendIntervention(_ newInstruction: String) {
        let task = newInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { return }

        let threadId = selected ?? UUID().uuidString
        selected = threadId
        resumed = threadId
        ensureConversationRegistered(id: threadId, title: task, cwd: project?.path ?? "")

        // 1. Imediatamente adiciona a mensagem do usuário ao chat
        messages.append(Message(author: "Você", text: task))
        prompt = ""
        persistCurrentMessages()

        // 2. Coleta o contexto do que estava sendo executado
        let previousTask = activeTasks[threadId]?.prompt ?? messages.last(where: { $0.author == "Você" && $0.text != task })?.text ?? "Tarefa em andamento"
        let recentActions = currentActivitySteps.suffix(4).map { "- \($0.title)\($0.detail != nil ? ": \($0.detail!)" : "")" }.joined(separator: "\n")

        // 3. Adiciona mensagem de feedback imediato de intervenção
        recordActivity(threadId: threadId, note: "Intervenção recebida: avaliando pertinência e contexto...", detail: task, kind: .thinking, appendToTranscript: true)

        // 4. Interrompe o processo ativo anterior de forma limpa
        voice.stopSpeaking()
        voice.stopListening()
        voice.isProcessing = true
        if let proc = activeCLIProcess {
            proc.terminate()
            activeCLIProcess = nil
        } else if let tId = turnID {
            request("turn/interrupt", ["threadId": threadId, "turnId": tId]) { _ in }
        }
        turnID = nil

        // 5. Monta a instrução adaptativa com contexto prévio e exigência de avaliar pertinência
        let contextualInstruction = """
        [INTERVENÇÃO DO USUÁRIO EM TEMPO REAL]
        O usuário enviou uma nova instrução durante a execução da tarefa anterior.

        • Tarefa anterior que estava em andamento:
        \(previousTask)

        • Ações que você já havia executado ou iniciado:
        \(recentActions.isEmpty ? "(início da tarefa)" : recentActions)

        • Nova mensagem/instrução do usuário:
        "\(task)"

        DIRETRIZ DE EXECUÇÃO:
        1. Avalie cuidadosamente o contexto e a viabilidade da nova solicitação em relação ao que você já estava fazendo.
        2. Analise se a nova instrução é pertinente para o objetivo atual, se deve alterar o rumo, cancelar partes anteriores ou ajustar os próximos passos.
        3. Dê feedback claro ao usuário explicando a sua análise de pertinência e prossiga com a execução adaptada.
        """

        var routedAccount = selectedAccount ?? localDataRef?.activeAccount
        var routedModel = (selectedModel != "auto" ? selectedModel : models.first(where: \.isDefault)?.id ?? models.first?.id) ?? routedAccount?.currentModel ?? "auto"
        if let local = localDataRef, !local.aiAccounts.isEmpty,
           let best = quotaStore.selectBestRoute(
               preferredAccount: routedAccount,
               preferredModel: routedModel,
               allAccounts: local.aiAccounts,
               canExecuteAccount: { [weak self] acc in self?.isAccountExecutableNow(acc) ?? acc.supportsExecution },
               isBlocked: { [weak self] acc, mod in self?.isRouteBlockedInRecovery(account: acc, model: mod) ?? false }
           ) {
            routedAccount = best.account
            routedModel = best.model
            selectedAccount = best.account
            selectedModel = best.model
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            self.dispatchTurnOnRoute(
                existingThreadId: threadId,
                task: task,
                instruction: contextualInstruction,
                account: routedAccount,
                model: routedModel,
                skipAddingUserMessage: true,
                retryDepth: 0
            )
        }
    }

    func interrupt() {
        voice.stopSpeaking()
        voice.stopListening()
        voice.isProcessing = false
        if let proc = activeCLIProcess {
            proc.terminate()
            activeCLIProcess = nil
            busy = false
            resetActivityState()
            return
        }
        resetActivityState()
        guard let selected, let turnID else { return }
        request("turn/interrupt", ["threadId": selected, "turnId": turnID]) { [weak self] response in
            _ = self?.accept(response)
        }
    }

    private func cliToolMessage(
        toolName: String,
        params: JSON,
        toolOutput: String?,
        duration: Double?,
        isDone: Bool,
        turnId: String
    ) -> Message {
        let lower = toolName.lowercased()
        let pathParam = (params["Path"] as? String)
            ?? (params["path"] as? String)
            ?? (params["AbsolutePath"] as? String)
            ?? (params["TargetFile"] as? String)
            ?? (params["DirectoryPath"] as? String)
            ?? ""
        let basename = pathParam.isEmpty ? "" : URL(fileURLWithPath: pathParam).lastPathComponent
        let cleanOutput = toolOutput?.trimmingCharacters(in: .whitespacesAndNewlines)
        let status = isDone ? "concluído" : "em andamento"

        if lower == "run_command" || lower == "command_status" || lower == "send_command_input" {
            let cmd = (params["CommandLine"] as? String)
                ?? (params["command"] as? String)
                ?? (params["Input"] as? String)
                ?? toolName
            let firstLine = cmd.components(separatedBy: .newlines).first ?? cmd
            let shortCmd = firstLine.count > 72 ? String(firstLine.prefix(69)) + "…" : firstLine
            return Message(
                author: "WisdAI",
                text: isDone ? "Executado" : "Executando",
                kind: .command,
                detail: cmd,
                status: status,
                turnId: turnId,
                target: shortCmd,
                output: (cleanOutput?.isEmpty == false) ? cleanOutput : nil,
                durationSeconds: duration,
                subKind: "command"
            )
        }

        if lower == "read_file" || lower == "view_file" || lower == "view_file_outline" || lower == "view_code_item" {
            var lineTag = ""
            if let s = params["StartLine"] as? Int, let e = params["EndLine"] as? Int {
                lineTag = "#L\(s)-\(e)"
            } else if let s = params["StartLine"] as? Int {
                lineTag = "#L\(s)"
            }
            let targetLabel = (basename.isEmpty ? "arquivo" : basename) + lineTag
            let fullDetail = pathParam.isEmpty ? nil : (pathParam + lineTag)
            return Message(
                author: "WisdAI",
                text: isDone ? "Analisado" : "Analisando",
                kind: .fileChange,
                detail: fullDetail,
                status: status,
                turnId: turnId,
                target: targetLabel,
                output: (cleanOutput?.isEmpty == false) ? cleanOutput : nil,
                durationSeconds: duration,
                subKind: "read"
            )
        }

        if lower.contains("write") || lower == "write_to_file" {
            let targetLabel = basename.isEmpty ? "arquivo" : basename
            return Message(
                author: "WisdAI",
                text: isDone ? "Criado" : "Criando",
                kind: .fileChange,
                detail: pathParam.isEmpty ? nil : pathParam,
                status: status,
                turnId: turnId,
                target: targetLabel,
                output: (cleanOutput?.isEmpty == false) ? cleanOutput : nil,
                durationSeconds: duration,
                subKind: "write"
            )
        }

        if lower.contains("edit") || lower.contains("replace") || lower == "sed_file" {
            let targetLabel = basename.isEmpty ? "arquivo" : basename
            return Message(
                author: "WisdAI",
                text: isDone ? "Editado" : "Editando",
                kind: .fileChange,
                detail: pathParam.isEmpty ? nil : pathParam,
                status: status,
                turnId: turnId,
                target: targetLabel,
                output: (cleanOutput?.isEmpty == false) ? cleanOutput : nil,
                durationSeconds: duration,
                subKind: "edit"
            )
        }

        if lower == "list_dir" {
            let targetLabel = basename.isEmpty ? "." : "\(basename)/"
            return Message(
                author: "WisdAI",
                text: isDone ? "Listado" : "Listando",
                kind: .fileChange,
                detail: pathParam.isEmpty ? nil : pathParam,
                status: status,
                turnId: turnId,
                target: targetLabel,
                output: (cleanOutput?.isEmpty == false) ? cleanOutput : nil,
                durationSeconds: duration,
                subKind: "list"
            )
        }

        if lower == "find_by_name" || lower == "grep_search" {
            let query = (params["Query"] as? String)
                ?? (params["query"] as? String)
                ?? (params["Pattern"] as? String)
                ?? (params["pattern"] as? String)
                ?? targetFallback(params)
            let verb = lower == "grep_search"
                ? (isDone ? "Pesquisado no código" : "Buscando no código")
                : (isDone ? "Localizados" : "Localizando")
            return Message(
                author: "WisdAI",
                text: verb,
                kind: .fileChange,
                detail: query.isEmpty ? nil : query,
                status: status,
                turnId: turnId,
                target: query.isEmpty ? "arquivos" : query,
                output: (cleanOutput?.isEmpty == false) ? cleanOutput : nil,
                durationSeconds: duration,
                subKind: "search"
            )
        }

        if lower.contains("search") || lower.contains("browser") || lower.contains("url") {
            let target = (params["query"] as? String)
                ?? (params["Query"] as? String)
                ?? (params["Url"] as? String)
                ?? (params["url"] as? String)
                ?? toolName
            let verb = (lower.contains("read_url") || lower.contains("browser"))
                ? (isDone ? "Página acessada" : "Acessando página")
                : (isDone ? "Pesquisado na web" : "Pesquisando na web")
            return Message(
                author: "WisdAI",
                text: verb,
                kind: .web,
                detail: target,
                status: status,
                turnId: turnId,
                target: target,
                output: (cleanOutput?.isEmpty == false) ? cleanOutput : nil,
                durationSeconds: duration,
                subKind: "web"
            )
        }

        let summaryTarget = basename.isEmpty ? toolName : basename
        return Message(
            author: "WisdAI",
            text: isDone ? "Concluído" : "Executando",
            kind: .tool,
            detail: pathParam.isEmpty ? nil : pathParam,
            status: status,
            turnId: turnId,
            target: summaryTarget,
            output: (cleanOutput?.isEmpty == false) ? cleanOutput : nil,
            durationSeconds: duration,
            subKind: "tool"
        )
    }

    private func targetFallback(_ params: JSON) -> String {
        if let dir = params["SearchDirectory"] as? String ?? params["SearchPath"] as? String {
            return URL(fileURLWithPath: dir).lastPathComponent
        }
        return ""
    }

    func handleCLILine(_ line: String, threadId: String, turnId: String) {
        guard self.turnID == turnId || self.activeTasks[threadId]?.turnId == turnId else { return }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? JSON,
           let event = json["event"] as? String {

            switch event {
            case "init":
                if let convId = json["conversation_id"] as? String, !convId.isEmpty {
                    if let idx = self.conversations.firstIndex(where: { $0.id == threadId }) {
                        self.conversations[idx].agyConversationId = convId
                        ChatStorage.shared.upsertConversation(self.conversations[idx])
                    }
                }
                recordActivity(threadId: threadId, note: "Lendo contexto e planejando ações…", detail: project?.lastPathComponent, kind: .thinking)

            case "step_update":
                guard let update = json["step_update"] as? JSON else { return }
                let stepIndex = update["step_index"] as? Int ?? 0
                let stepType = update["step_type"] as? String ?? ""
                let state = update["state"] as? String ?? ""
                let duration = update["duration_seconds"] as? Double

                if stepType == "thinking" || stepType == "thought" || stepType == "reasoning" {
                    let thoughtText = (update["thinking_delta"] as? String)
                        ?? (update["thought_delta"] as? String)
                        ?? (update["reasoning_delta"] as? String)
                        ?? (update["thought"] as? String)
                        ?? (update["text_delta"] as? String)
                        ?? ""
                    let thoughtKey = "\(turnId)-thought-\(stepIndex)"
                    if !thoughtText.isEmpty {
                        appendDelta(thoughtKey, thoughtText, author: "WisdAI", kind: .reasoning, turnId: turnId, subKind: "thought")
                    }
                    if state == "DONE", let idx = messages.firstIndex(where: { $0.id == streamedItems[thoughtKey] }) {
                        messages[idx].status = "concluído"
                        messages[idx].durationSeconds = duration
                        persistCurrentMessages()
                    } else if currentActivityNote != "Raciocinando sobre a solução…" {
                        recordActivity(threadId: threadId, note: "Raciocinando sobre a solução…", kind: .thinking)
                    }
                    return
                }

                if stepType == "tool" {
                    let toolName = update["tool_name"] as? String ?? "ferramenta"
                    let toolInfo = update["tool_info"] as? JSON
                    let params = toolInfo?["parameters"] as? JSON ?? [:]
                    let toolOutput = toolInfo?["output"] as? String

                    if toolName == "update_focus" {
                        if let focus = params["focus"] as? String, !focus.isEmpty {
                            recordActivity(threadId: threadId, note: focus, kind: .thinking)
                        }
                        return
                    }

                    if toolName == "update_steps" || toolName == "TodoWrite" {
                        let rawSteps = (params["steps"] as? [JSON]) ?? (params["todos"] as? [JSON]) ?? []
                        let parsed = rawSteps.compactMap { item -> PlanStep? in
                            guard let title = (item["title"] as? String) ?? (item["content"] as? String), !title.isEmpty else { return nil }
                            let st = (item["status"] as? String) ?? "pending"
                            return PlanStep(title: title, status: st)
                        }
                        if !parsed.isEmpty {
                            let planKey = "\(turnId)-plan"
                            apply(planKey, Message(
                                author: "WisdAI",
                                text: "Etapas",
                                kind: .plan,
                                status: state == "DONE" ? "concluído" : "em andamento",
                                turnId: turnId,
                                steps: parsed
                            ))
                            persistCurrentMessages()
                        }
                        return
                    }

                    let stepKey = "\(turnId)-tool-\(stepIndex)"
                    let isDone = (state == "DONE")
                    let msg = cliToolMessage(
                        toolName: toolName,
                        params: params,
                        toolOutput: toolOutput,
                        duration: duration,
                        isDone: isDone,
                        turnId: turnId
                    )
                    apply(stepKey, msg)
                    persistCurrentMessages()

                    if !isDone {
                        let liveNote = [msg.text, msg.target].compactMap { $0 }.joined(separator: " ")
                        let activityKind: TaskActivityStep.StepKind = {
                            switch msg.kind {
                            case .command: return .command
                            case .fileChange: return .fileChange
                            case .web: return .search
                            default: return .tool
                            }
                        }()
                        recordActivity(threadId: threadId, note: liveNote + "…", detail: msg.detail, kind: activityKind)
                    } else {
                        completeActivityStep(threadId: threadId)
                        recordActivity(threadId: threadId, note: "Avaliando resultados e próximos passos…", kind: .thinking)
                    }
                } else if stepType == "agent_response" {
                    let delta = update["text_delta"] as? String ?? ""
                    let thoughtDelta = (update["thinking_delta"] as? String)
                        ?? (update["thought_delta"] as? String)
                        ?? (update["reasoning_delta"] as? String)
                        ?? (update["thought"] as? String)
                        ?? ""
                    let usage = update["usage"] as? JSON
                    let thinkingTokens = usage?["thinking_tokens"] as? Int ?? 0
                    if let usage, state == "DONE" {
                        recordCLITokenUsage(stepKey: "\(turnId)-\(stepIndex)", usage: usage)
                    }

                    let thoughtKey = "\(turnId)-thought-\(stepIndex)"
                    let respKey = "\(turnId)-resp-\(stepIndex)"

                    if !thoughtDelta.isEmpty {
                        appendDelta(thoughtKey, thoughtDelta, author: "WisdAI", kind: .reasoning, turnId: turnId, subKind: "thought")
                        if state == "DONE", let idx = messages.firstIndex(where: { $0.id == streamedItems[thoughtKey] }) {
                            messages[idx].status = "concluído"
                            messages[idx].durationSeconds = duration
                        }
                    }

                    if !delta.isEmpty {
                        appendDelta(respKey, delta, author: "WisdAI", kind: .text, turnId: turnId)
                        if currentActivityNote != "Escrevendo resposta…" {
                            recordActivity(threadId: threadId, note: "Escrevendo resposta…", kind: .response)
                        }
                        if state == "DONE" {
                            persistCurrentMessages()
                        }
                    } else if thoughtDelta.isEmpty {
                        if state == "ACTIVE" {
                            recordActivity(threadId: threadId, note: "Pensando…", kind: .thinking)
                        } else if state == "DONE", streamedItems[respKey] == nil {
                            if thinkingTokens > 0 || (duration ?? 0) >= 0.8 {
                                let info = thinkingTokens > 0 ? "\(thinkingTokens) tokens de raciocínio utilizados antes da próxima etapa." : "Análise concluída."
                                apply(thoughtKey, Message(
                                    author: "WisdAI",
                                    text: info,
                                    kind: .reasoning,
                                    status: "concluído",
                                    turnId: turnId,
                                    durationSeconds: duration,
                                    subKind: "thought"
                                ))
                                persistCurrentMessages()
                            }
                        }
                    }
                }

            case "error":
                let errText = ((json["error"] as? JSON)?["message"] as? String)
                    ?? (json["message"] as? String)
                    ?? trimmed
                self.cliExecutionError = errText
                recordCLILimitIfMatched(errText, threadId: threadId)

            case "result":
                let res = json["result"] as? JSON
                let status = (res?["status"] as? String ?? "").uppercased()
                if let usage = res?["usage"] as? JSON {
                    recordCLITokenUsage(stepKey: "\(turnId)-result", usage: usage, incrementRequest: true)
                } else if let accID = activeCLITurnAccountID ?? selectedAccount?.id ?? localDataRef?.activeAccount?.id {
                    quotaStore.recordTokenUsage(accountID: accID, modelID: activeCLITurnModel, tokens: 0, incrementRequest: true)
                }

                if !status.isEmpty && status != "SUCCESS" {
                    let errMsg = ((res?["error"] as? JSON)?["message"] as? String)
                        ?? (res?["error"] as? String)
                        ?? (res?["message"] as? String)
                        ?? (res?["response"] as? String)
                        ?? trimmed
                    self.cliExecutionError = errMsg
                    recordCLILimitIfMatched(errMsg, threadId: threadId)
                }

                if cliDetectedLimit == nil,
                   let finalResp = res?["response"] as? String,
                   !finalResp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let hasTurnText = messages.contains(where: { $0.turnId == turnId && $0.kind == .text && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                    if !hasTurnText {
                        messages.append(Message(author: "WisdAI", text: finalResp, kind: .text, turnId: turnId))
                        persistCurrentMessages()
                    }
                }
                completeActivityStep(threadId: threadId)
                resetActivityState()

            default:
                break
            }
            return
        }

        // Verifica linhas de erro em texto puro emitidas pela CLI (ex: HTTP 429 / ResourceExhausted)
        let lowerLine = trimmed.lowercased()
        let looksLikeStderrError = lowerLine.hasPrefix("error")
            || lowerLine.hasPrefix("rpc error")
            || lowerLine.hasPrefix("api error")
            || lowerLine.hasPrefix("failed")
            || lowerLine.contains("resource_exhausted")
            || lowerLine.contains("status: 429")
            || lowerLine.contains("http 429")
        if looksLikeStderrError {
            self.cliExecutionError = trimmed
            recordCLILimitIfMatched(trimmed, threadId: threadId)
            return
        }

        appendDelta("\(turnId)-plain", line + "\n", author: "WisdAI", kind: .text, turnId: turnId)
        if currentActivityNote != "Escrevendo resposta…" {
            recordActivity(threadId: threadId, note: "Escrevendo resposta…", kind: .response)
        }
    }

    private func recordCLITokenUsage(stepKey: String, usage: JSON, incrementRequest: Bool = false) {
        guard let accID = activeCLITurnAccountID ?? selectedAccount?.id ?? localDataRef?.activeAccount?.id else { return }
        let total = (usage["total_tokens"] as? Int)
            ?? ((usage["input_tokens"] as? Int ?? 0) + (usage["output_tokens"] as? Int ?? 0) + (usage["thinking_tokens"] as? Int ?? 0))
        // Evita dupla contagem quando result soma os tokens dos steps já registrados
        if stepKey.hasSuffix("-result") {
            let alreadyCounted = cliStepTokenCounts.values.reduce(0, +)
            let delta = max(0, total - alreadyCounted)
            quotaStore.recordTokenUsage(accountID: accID, modelID: activeCLITurnModel, tokens: delta, incrementRequest: incrementRequest)
            return
        }
        let prev = cliStepTokenCounts[stepKey] ?? 0
        let delta = max(0, total - prev)
        cliStepTokenCounts[stepKey] = max(prev, total)
        quotaStore.recordTokenUsage(accountID: accID, modelID: activeCLITurnModel, tokens: delta, incrementRequest: incrementRequest)
    }

    private func recordCLILimitIfMatched(_ text: String, threadId: String) {
        let lower = text.lowercased()
        let isLimit = lower.contains("429")
            || lower.contains("resource_exhausted")
            || lower.contains("rate limit")
            || lower.contains("rate_limit")
            || lower.contains("ratelimit")
            || lower.contains("usage limit")
            || lower.contains("insufficient_quota")
            || lower.contains("limit reached")
            || lower.contains("too many requests")
            || (lower.contains("quota") && (lower.contains("exceed") || lower.contains("exhaust") || lower.contains("limit") || lower.contains("zero")))
        guard isLimit else { return }

        let kind: ProviderLimit = (lower.contains("usage limit") || lower.contains("insufficient_quota") || lower.contains("billing") || lower.contains("account"))
            ? .account
            : .model
        let delay = UsageQuotaStore.parseRetryDelaySeconds(from: text) ?? (kind == .account ? 900 : 300)
        let until = Date().addingTimeInterval(delay)
        cliDetectedLimit = (kind, until, text)

        if let accID = activeCLITurnAccountID ?? selectedAccount?.id ?? localDataRef?.activeAccount?.id {
            if kind == .account {
                let mods = localDataRef?.aiAccounts.first(where: { $0.id == accID })?.models ?? []
                quotaStore.markAccountLimited(accountID: accID, models: mods, until: until, reason: "Limite da conta atingido")
            } else {
                quotaStore.markModelLimited(accountID: accID, modelID: activeCLITurnModel, until: until, reason: "Limite do modelo atingido")
            }
        }
    }

    static func resolveAgyModelAndEffort(
        requestedModel: String?,
        accountModels: [String],
        selectedEffort: String,
        level: ReasoningEffortLevel
    ) -> (model: String?, effortArg: String?) {
        guard let raw = requestedModel?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty, raw != "auto" else {
            return (requestedModel, selectedEffort == "default" ? nil : level.cliEffortValue)
        }

        let tierSuffixes = ["-xhigh", "-high", "-medium", "-low"]
        if let matchedSuffix = tierSuffixes.first(where: { raw.hasSuffix($0) }) {
            let base = String(raw.dropLast(matchedSuffix.count))
            if selectedEffort != "default" {
                let desiredSuffixes: [String] = {
                    switch level {
                    case .leve: return ["-low", "-medium", "-high"]
                    case .medio: return ["-medium", "-high", "-low"]
                    case .alto: return ["-high", "-xhigh", "-medium"]
                    case .extraAlto, .ultra: return ["-xhigh", "-high", "-medium"]
                    }
                }()
                for suffix in desiredSuffixes {
                    let candidate = base + suffix
                    if accountModels.contains(candidate) {
                        return (candidate, nil)
                    }
                }
            }
            // Modelos com sufixo de nível (-high, -medium, -low, -xhigh) não aceitam --effort na CLI agy.
            return (raw, nil)
        }

        // Modelos explícitos da CLI agy (ex: claude-opus-4-6-thinking, claude-sonnet-4-6) não suportam --effort junto com --model.
        return (raw, nil)
    }

    func executeCLITurn(
        id: String,
        task: String,
        instruction: String,
        model: String?,
        projectURL: URL?,
        cliPath: String,
        skipAddingUserMessage: Bool = false,
        accountID: UUID? = nil,
        retryDepth: Int = 0,
        forceReadOnly: Bool = false
    ) {
        unseenCompletedThreads.remove(id)
        ensureConversationRegistered(id: id, title: task, cwd: projectURL?.path ?? "")
        let names = attachments.map(\.name).joined(separator: ", ")
        if !skipAddingUserMessage {
            messages.append(Message(author: "Você", text: [task, names].filter { !$0.isEmpty }.joined(separator: "\n")))
            persistCurrentMessages()
        }
        let attachedPaths: [String] = attachments.compactMap { att in
            (att.input["path"] as? String) ?? (att.input["url"] as? String) ?? att.name
        }
        attachments = []
        prompt = ""
        busy = true
        error = nil
        taskStartedAt = Date()
        beginVoiceTurnTracking()
        voice.voiceFeedbackStatus = voice.isVoiceModeActive ? "Pensando…" : "Analisando solicitação…"
        let turnId = UUID().uuidString
        self.turnID = turnId
        let isAgy = cliPath.hasSuffix("agy") || cliPath.contains("/agy")
        let targetAccountID = accountID ?? selectedAccount?.id ?? localDataRef?.activeAccount?.id
        let accountCatalog = localDataRef?.aiAccounts.first(where: { $0.id == targetAccountID })?.models ?? selectedAccount?.models ?? []
        let resolvedAgy = isAgy
            ? Self.resolveAgyModelAndEffort(requestedModel: model, accountModels: accountCatalog, selectedEffort: selectedEffort, level: reasoningLevel)
            : (model: model, effortArg: nil)
        let effectiveModel = resolvedAgy.model ?? model

        self.activeCLITurnModel = effectiveModel ?? selectedAccount?.currentModel ?? "auto"
        self.activeCLITurnAccountID = targetAccountID
        self.cliStepTokenCounts = [:]
        self.cliDetectedLimit = nil
        self.cliExecutionError = nil

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: cliPath)
        var args: [String] = []
        if forceReadOnly {
            if isAgy {
                args.append(contentsOf: ["--mode", "plan", "--sandbox"])
            }
        } else {
            args.append("--dangerously-skip-permissions")
        }
        var effectiveInstruction = instruction
        if !attachedPaths.isEmpty {
            effectiveInstruction += "\n\n[Arquivos anexados: \(attachedPaths.joined(separator: ", "))]"
        }
        let existingAgyId = isAgy ? self.conversations.first(where: { $0.id == id })?.agyConversationId : nil
        let hasActiveAgySession = isAgy && !(existingAgyId ?? "").isEmpty

        if isAgy {
            args.append(contentsOf: ["--output-format", "stream-json"])
            if let effortArg = resolvedAgy.effortArg {
                args.append(contentsOf: ["--effort", effortArg])
            }
            if let existingAgyId, !existingAgyId.isEmpty {
                args.append(contentsOf: ["--conversation", existingAgyId])
            }
        } else if reasoningLevel != .medio {
            effectiveInstruction = "[Esforço de raciocínio: \(reasoningLevel.title) (\(reasoningLevel.effortValue))]\n" + effectiveInstruction
        }

        if !hasActiveAgySession {
            let textMessages = self.messages.filter { $0.kind == .text && !$0.text.isEmpty }
            if textMessages.count > 1 {
                effectiveInstruction = Self.buildPriorConversationContextPrompt(
                    priorMessages: Array(textMessages.dropLast()),
                    currentTask: effectiveInstruction
                )
            }
        }
        args.append(contentsOf: ["-p", effectiveInstruction])
        if let finalModel = effectiveModel, !finalModel.isEmpty && finalModel != "auto" {
            args.append(contentsOf: ["--model", finalModel])
        }
        proc.arguments = args
        proc.currentDirectoryURL = projectURL ?? FileManager.default.homeDirectoryForCurrentUser
        proc.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        activeCLIProcess = proc

        let modelDisplay = AIProvider.modelDisplayName(for: effectiveModel ?? "auto")
        let initialStep = TaskActivityStep(title: "Analisando solicitação", detail: "Modelo: \(modelDisplay)", isCompleted: false, kind: .thinking)
        let runningTask = ActiveThreadTask(
            threadId: id,
            turnId: turnId,
            prompt: task,
            status: "executando",
            accountId: activeCLITurnAccountID,
            accountName: selectedAccount?.name ?? "CLI",
            modelName: effectiveModel ?? "auto",
            startedAt: Date(),
            progressNote: "Pensando…",
            steps: [initialStep]
        )
        activeTasks[id] = runningTask
        if id == selected {
            currentActivityNote = "Pensando…"
            currentActivityDetail = "Modelo: \(modelDisplay)"
            currentActivityKind = .thinking
            currentActivitySteps = [initialStep]
        }

        Task.detached { [weak self] in
            do {
                try proc.run()
                let reader = pipe.fileHandleForReading
                var buffer = Data()
                while true {
                    let data = reader.availableData
                    if data.isEmpty { break }
                    buffer.append(data)
                    while let newline = buffer.range(of: Data([0x0A])) {
                        let lineData = buffer.subdata(in: 0..<newline.lowerBound)
                        buffer.removeSubrange(0..<newline.upperBound)
                        if let line = String(data: lineData, encoding: .utf8) {
                            await MainActor.run { [weak self] in
                                self?.handleCLILine(line, threadId: id, turnId: turnId)
                            }
                        }
                    }
                }
                if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
                    await MainActor.run { [weak self] in
                        self?.handleCLILine(line, threadId: id, turnId: turnId)
                    }
                }
                proc.waitUntilExit()
                let exitStatus = proc.terminationStatus
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard self.turnID == turnId || self.activeTasks[id]?.turnId == turnId else { return }
                    if self.activeCLIProcess === proc { self.activeCLIProcess = nil }
                    self.activeTasks.removeValue(forKey: id)
                    self.resetActivityState()

                    if let detected = self.cliDetectedLimit, (exitStatus != 0 || self.automaticFallback) {
                        self.cliDetectedLimit = nil
                        self.cliExecutionError = nil
                        if self.automaticFallback && self.autoFallbackToNextAccount(
                            forTask: task,
                            onThread: id,
                            failedModel: effectiveModel,
                            limitKind: detected.kind,
                            until: detected.until,
                            reason: detected.message,
                            skipAddingUserMessage: true,
                            retryDepth: retryDepth + 1
                        ) {
                            return
                        }
                        self.error = "Limite atingido (\(modelDisplay)). Próxima liberação prevista: \(detected.until.formatted(date: .omitted, time: .shortened))."
                    } else if exitStatus != 0 || self.cliExecutionError != nil {
                        let rawErr = self.cliExecutionError ?? "O motor CLI encerrou com código \(exitStatus)."
                        self.cliExecutionError = nil
                        let hasAssistantReply = self.messages.contains(where: {
                            $0.turnId == turnId && $0.kind == .text && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        })
                        if !hasAssistantReply {
                            self.error = rawErr
                            self.messages.append(Message(author: "Sistema", text: "⚠️ \(rawErr)"))
                        }
                    }

                    if self.selected != id {
                        self.unseenCompletedThreads.insert(id)
                    }
                    if self.selected == id {
                        self.busy = false
                        self.deliverCompletedChatVoiceReply(failureText: self.error)
                    } else {
                        self.voice.isProcessing = false
                    }
                    if !self.conversations.contains(where: { $0.id == id }) {
                        let title = String(task.prefix(32))
                        let conv = Conversation(id: id, title: title.isEmpty ? "Nova Conversa" : title,
                                                cwd: projectURL?.path ?? "")
                        self.conversations.insert(conv, at: 0)
                    }
                    self.persistCurrentMessages()
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard self.turnID == turnId || self.activeTasks[id]?.turnId == turnId else { return }
                    if self.activeCLIProcess === proc { self.activeCLIProcess = nil }
                    self.activeTasks.removeValue(forKey: id)
                    self.resetActivityState()
                    self.voice.isProcessing = false
                    self.error = "Falha ao executar o agente CLI: \(error.localizedDescription)"
                    if self.selected == id { self.busy = false }
                }
            }
        }
    }

    func startTurn(_ id: String, _ task: String, instructionOverride: String? = nil, modelOverride: String? = nil, cwdOverride: String? = nil, skipAddingUserMessage: Bool = false, forceReadOnly: Bool = false) {
        unseenCompletedThreads.remove(id)
        ensureConversationRegistered(id: id, title: task, cwd: cwdOverride ?? project?.path ?? "")
        let names = attachments.map(\.name).joined(separator: ", ")
        var inputs = attachments.map(\.input)
        let resolvedPrompt = (instructionOverride?.isEmpty == false) ? instructionOverride! : task
        let instruction = resolvedPrompt.isEmpty ? "Responda ao conteúdo anexado." : resolvedPrompt
        inputs.insert(["type": "text", "text": instruction, "textElements": []], at: 0)
        let modelToUse = modelOverride ?? (selectedModel != "auto" ? selectedModel : models.first(where: \.isDefault)?.id ?? models.first?.id)
        let effectiveMode = forceReadOnly ? 0 : mode
        do {
            let chosen = modelToUse ?? "auto"
            try recovery.begin(threadID: id, task: task, inputs: inputs, mode: effectiveMode, effort: selectedEffort,
                               cwd: cwdOverride ?? project?.path ?? "", ephemeral: temporaryChat, model: chosen, baselineTurnID: knownLastTurns[id], baselineKnown: loadedHistories.contains(id))
        } catch { self.error = error.localizedDescription; busy = false; return }
        if !skipAddingUserMessage {
            messages.append(Message(author: "Você", text: [task, names].filter { !$0.isEmpty }.joined(separator: "\n")))
            persistCurrentMessages()
        }
        sentAttachments = attachments
        attachments = []
        prompt = ""
        let sandboxType = ["readOnly", "workspaceWrite", "dangerFullAccess"][min(max(effectiveMode, 0), 2)]
        var turnParameters: JSON = [
            "threadId": id,
            "input": inputs,
            "sandboxPolicy": ["type": sandboxType],
            "approvalPolicy": effectiveMode == 2 ? "never" : "on-request",
        ]
        if let modelToUse { turnParameters["model"] = modelToUse }
        if selectedEffort != "default" {
            turnParameters["effort"] = selectedEffort == "ultra" ? "xhigh" : selectedEffort
        }

        let initialStep = TaskActivityStep(title: "Analisando solicitação", detail: "Modelo: \(modelToUse ?? selectedModel)", isCompleted: false, kind: .thinking)
        let runningTask = ActiveThreadTask(
            threadId: id,
            prompt: task,
            status: "executando",
            accountId: selectedAccount?.id,
            accountName: selectedAccount?.name ?? "Padrão",
            modelName: modelToUse ?? selectedModel,
            startedAt: Date(),
            progressNote: "Pensando…",
            steps: [initialStep]
        )
        activeTasks[id] = runningTask
        if id == selected {
            taskStartedAt = Date()
            currentActivityNote = "Pensando…"
            currentActivityDetail = nil
            currentActivityKind = .thinking
            currentActivitySteps = [initialStep]
            beginVoiceTurnTracking()
            persistCurrentMessages()
        }

        request("turn/start", turnParameters) { [weak self] response in
            guard let self else { return }
            if let turn = self.accept(response)?["turn"] as? JSON {
                let tid = turn["id"] as? String
                if self.selected == id { self.turnID = tid }
                self.activeTasks[id]?.turnId = tid
                if let tid {
                    self.recovery.accepted(id, turnID: tid)
                    if let userIdx = self.messages.lastIndex(where: { $0.author == "Você" && $0.turnId == nil }) {
                        self.messages[userIdx].turnId = tid
                        self.persistCurrentMessages()
                    }
                }
            } else {
                let failure = response["error"] as? JSON
                let failureMsg = failure?["message"] as? String ?? ""
                let lowerFailure = failureMsg.lowercased()
                let classified = ProviderLimit.classify(failure ?? [:])
                let isUnsupportedModel = lowerFailure.contains("is not supported")
                    || lowerFailure.contains("model_not_found")
                    || lowerFailure.contains("unsupported model")
                let isLimit = classified != nil || lowerFailure.contains("usage limit") || lowerFailure.contains("quota") || isUnsupportedModel
                if isLimit {
                    let kind = isUnsupportedModel ? .model : (classified ?? .account)
                    let delay = UsageQuotaStore.parseRetryDelaySeconds(from: failureMsg) ?? (kind == .account ? 900 : 300)
                    if self.autoFallbackToNextAccount(
                        forTask: task,
                        onThread: id,
                        failedModel: modelToUse,
                        limitKind: kind,
                        until: Date().addingTimeInterval(delay),
                        reason: failureMsg,
                        skipAddingUserMessage: true
                    ) {
                        return
                    }
                }
                if let failure, self.recovery.failed(threadID: id, turnID: nil, failure: failure) { self.error = nil; return }
                self.recovery.finished(id)
                self.activeTasks.removeValue(forKey: id)
                self.attachments = self.sentAttachments
                self.sentAttachments = []
                self.prompt = task
                if self.selected == id { self.busy = false }
            }
        }
    }

    func activateAccount(_ account: AIAccount, force: Bool = false) {
        if !force {
            guard activeTasks.isEmpty, !busy, !accountBusy, !recovery.isRecovering else {
                error = "Aguarde as tarefas em execução antes de trocar a sessão do motor."
                return
            }
        }
        localDataRef?.setActiveAccount(id: account.id)
        selectedAccount = account
        let validModel = UsageQuotaStore.isModelCompatible(account.currentModel, with: account) && account.currentModel != "auto"
            ? account.currentModel
            : (account.models.first ?? account.provider.defaultModels.first ?? "auto")
        selectedModel = validModel
        if account.provider == .openai, let sessionID = account.sessionID,
           let choice = accountChoices.first(where: { $0.id == sessionID && $0.workspaceID == account.workspaceID }) {
            if !choice.active { switchAccount(choice) } else { loadModels() }
        } else {
            loadModels()
        }
    }

    func continueWithAccount(_ account: AIAccount, for threadId: String?) {
        limitAlertAccount = nil
        activateAccount(account)
        if let threadId { recovery.retry(threadId) }
    }

    func recoveryRPCEnvelope(_ method: String, _ params: JSON) async throws -> JSON {
        try await withCheckedThrowingContinuation { continuation in
            var completed = false
            request(method, params) { response in
                guard !completed else { return }; completed = true
                continuation.resume(returning: response)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                guard !completed else { return }; completed = true
                continuation.resume(throwing: RecoveryFailure.message("Sem confirmação do motor. A operação não será reenviada automaticamente."))
            }
        }
    }
    func recoveryRPC(_ method: String, _ params: JSON) async throws -> JSON {
        let response = try await recoveryRPCEnvelope(method, params)
        guard let result = response["result"] as? JSON else {
            throw RecoveryFailure.message((response["error"] as? JSON)?["message"] as? String ?? "O motor não confirmou a operação.")
        }
        return result
    }
    func applyRecoverySession(_ reply: JSON, models: [ModelChoice]) {
        modelRequestID = UUID()
        accountChoices = (reply["sessions"] as? [JSON] ?? []).compactMap { raw in
            guard let id = raw["sessionId"] as? String, let route = raw["selectedWorkspaceAccountId"] as? String else { return nil }
            return AccountChoice(id: id, label: raw["email"] as? String ?? "ChatGPT", active: raw["isActive"] as? Bool ?? false, workspaceID: route)
        }
        localDataRef?.syncSessions(accountChoices)
        selectedAccount = localDataRef?.aiAccounts.first { $0.isActive && $0.supportsExecution }
        self.models = models; modelsLoading = false
        selectedModel = models.first(where: \.isDefault)?.id ?? models.first?.id ?? "auto"
        if let account = selectedAccount { localDataRef?.syncModels(accountID: account.id, models: models.map(\.id), source: "Codex model/list") }
        account = accountChoices.first(where: \.active)?.label ?? account
        quota = []; usageWindows = []; creditBalance = nil; resetCredits = nil; plan = nil; accountIdentity = nil
        resumed = nil
    }
    func recoveryTurnStarted(_ record: RecoveryCheckpoint, turnID: String, model: ModelChoice) {
        selectedModel = model.id
        activeTasks[record.threadID] = ActiveThreadTask(threadId: record.threadID, turnId: turnID, prompt: record.task,
                                                      accountId: selectedAccount?.id, accountName: account, modelName: model.id)
        if selected == record.threadID {
            busy = true; self.turnID = turnID; resumed = record.threadID
            messages.append(Message(author: "Sistema", text: "Tarefa retomada no mesmo chat: \(account) · \(model.name). As etapas confirmadas permanecem no histórico."))
            error = nil
        }
    }

    func request(_ method: String, _ parameters: JSON, completion: @escaping (JSON) -> Void) {
        if let transport { transport(method, parameters, completion); return }
        counter += 1
        pending[counter] = completion
        write(["id": counter, "method": method, "params": parameters])
    }

    private func write(_ value: JSON) {
        do {
            guard let input else { throw CocoaError(.fileWriteUnknown) }
            let data = try JSONSerialization.data(withJSONObject: value)
            try input.write(contentsOf: data + Data([10]))
        } catch {
            disconnected()
        }
    }

    func accept(_ response: JSON) -> JSON? {
        if let failure = response["error"] as? JSON {
            error = failure["message"] as? String ?? "O motor WisdCode recusou a solicitação."
            return nil
        }
        return response["result"] as? JSON
    }

    func receive(_ line: Data) {
        guard let message = (try? JSONSerialization.jsonObject(with: line)) as? JSON else { return }
        guard let method = message["method"] as? String else {
            if let id = message["id"] as? Int { pending.removeValue(forKey: id)?(message) }
            return
        }
        let parameters = message["params"] as? JSON ?? [:]
        if let id = message["id"] {
            if !handleApproval(method, parameters, id) {
                write(["id": id, "error": ["code": -32601, "message": "Interação indisponível neste cliente."]])
            }
            return
        }
        switch method {
        case "account/updated":
            accountChanged()
            return
        case "account/login/completed":
            guard let loginID, parameters["loginId"] as? String == loginID else { return }
            self.loginID = nil
            accountBusy = false
            if parameters["success"] as? Bool == true {
                accountChanged()
            } else {
                error = parameters["error"] as? String ?? "O login não foi concluído."
            }
            return
        case "account/rateLimits/updated":
            ingestRateLimitsPayload(parameters)
            return
        case "thread/tokenUsage/updated":
            if let usage = parameters["tokenUsage"] as? JSON,
               let lastTokens = (usage["last"] as? JSON)?["totalTokens"] as? Int,
               let acc = selectedAccount ?? localDataRef?.activeAccount {
                let activeMod = selectedModel != "auto" ? selectedModel : acc.currentModel
                quotaStore.recordTokenUsage(accountID: acc.id, modelID: activeMod, tokens: lastTokens)
            }
            return
        case "thread/realtime/sdp":
            guard voice.isVoiceModeActive,
                  let sdp = parameters["sdp"] as? String,
                  !sdp.isEmpty else { return }
            voice.webrtcBridge.acceptAnswerSdp(sdp) { [weak self] result in
                guard let self, self.voice.isVoiceModeActive else { return }
                if case .failure = result {
                    self.startChatConversationalVoice()
                }
            }
            return
        case "thread/realtime/started":
            let rtThreadId = (parameters["threadId"] as? String) ?? selected ?? ""
            guard voice.isVoiceModeActive, !rtThreadId.isEmpty else { return }
            realtimeStartupToken = UUID()
            realtimeSessionStartedAt = Date()
            activeRealtimeStreamKeys = [:]
            if voice.isUsingWebRTCTransport {
                voice.activateWebRTCRealtimeSession(threadId: rtThreadId) { [weak self] in
                    guard let self, self.ready else { return }
                    self.request("thread/realtime/stop", ["threadId": rtThreadId]) { _ in }
                }
                sendRealtimeGreetingIfNeeded(threadId: rtThreadId)
            } else {
                voice.beginCodexRealtimeSession(
                    threadId: rtThreadId,
                    sendAudioChunk: { [weak self] base64PCM16, sampleRate, channels, samplesPerChannel in
                        guard let self, self.voice.realtimeSessionActive, self.ready else { return }
                        let audioPayload: JSON = [
                            "data": base64PCM16,
                            "sampleRate": sampleRate,
                            "numChannels": channels,
                            "samplesPerChannel": samplesPerChannel
                        ]
                        self.request("thread/realtime/appendAudio", ["threadId": rtThreadId, "audio": audioPayload]) { _ in }
                    },
                    onStop: { [weak self] in
                        guard let self, self.ready else { return }
                        self.request("thread/realtime/stop", ["threadId": rtThreadId]) { _ in }
                    }
                )
            }
            return
        case "thread/realtime/item/started":
            guard voice.isVoiceModeActive,
                  let item = parameters["item"] as? JSON,
                  let itemId = item["id"] as? String,
                  let itemType = item["type"] as? String else { return }
            if itemType == "transcriptSegment" {
                let role = (item["role"] as? String)?.lowercased() == "user" ? "user" : "assistant"
                realtimeItemRoles[itemId] = role
                let seedText = item["text"] as? String ?? ""
                if !seedText.isEmpty {
                    appendRealtimeTranscriptDelta(role: role, delta: seedText, explicitStreamKey: "item-\(itemId)")
                }
            }
            return
        case "thread/realtime/item/transcript/delta":
            guard voice.isVoiceModeActive,
                  let itemId = parameters["itemId"] as? String,
                  let delta = parameters["delta"] as? String else { return }
            let role = realtimeItemRoles[itemId] ?? "assistant"
            appendRealtimeTranscriptDelta(role: role, delta: delta, explicitStreamKey: "item-\(itemId)")
            return
        case "thread/realtime/item/completed":
            guard voice.isVoiceModeActive,
                  let item = parameters["item"] as? JSON,
                  let itemId = item["id"] as? String,
                  let itemType = item["type"] as? String else { return }
            if itemType == "transcriptSegment" {
                guard completedRealtimeItemIDs.insert(itemId).inserted else { return }
                let role = (item["role"] as? String)?.lowercased() == "user"
                    ? "user"
                    : (realtimeItemRoles[itemId] ?? "assistant")
                realtimeItemRoles.removeValue(forKey: itemId)
                let text = item["text"] as? String ?? ""
                finishRealtimeTranscript(role: role, text: text, explicitStreamKey: "item-\(itemId)")
            }
            return
        case "thread/realtime/outputAudio/delta":
            guard voice.isVoiceModeActive, voice.realtimeSessionActive,
                  !voice.isUsingWebRTCTransport,
                  !voice.isOutputMuted,
                  let audio = parameters["audio"] as? JSON,
                  let b64 = audio["data"] as? String else { return }
            let rate = audio["sampleRate"] as? Int ?? 24_000
            let ch = audio["numChannels"] as? Int ?? 1
            voice.enqueueRealtimePCMOutput(base64Data: b64, sampleRate: rate, numChannels: ch)
            return
        case "thread/realtime/transcript/delta":
            guard voice.isVoiceModeActive else { return }
            let role = parameters["role"] as? String ?? "assistant"
            let delta = parameters["delta"] as? String ?? ""
            if realtimeItemRoles.values.contains(role) { return }
            appendRealtimeTranscriptDelta(role: role, delta: delta)
            return
        case "thread/realtime/transcript/done":
            guard voice.isVoiceModeActive else { return }
            let role = parameters["role"] as? String ?? "assistant"
            let text = parameters["text"] as? String ?? ""
            finishRealtimeTranscript(role: role, text: text)
            return
        case "thread/realtime/itemAdded":
            guard voice.isVoiceModeActive,
                  let item = parameters["item"] as? JSON,
                  let itemType = item["type"] as? String else { return }
            if itemType == "input_audio_buffer.speech_started" {
                if !voice.isUsingWebRTCTransport {
                    voice.interruptRealtimeOutputAudio()
                }
                activeRealtimeStreamKeys.removeValue(forKey: "user")
                voice.voiceActivity = .listening
                voice.voiceFeedbackStatus = voice.isMuted ? "Microfone silenciado" : "Ouvindo você…"
            } else if itemType == "handoff_request" {
                voice.voiceActivity = .thinking
                voice.voiceFeedbackStatus = "Consultando o agente no chat…"
            }
            return
        case "thread/realtime/error":
            guard voice.isVoiceModeActive else { return }
            let msg = parameters["message"] as? String ?? ""
            let recentStartup = voice.isConnecting || (realtimeSessionStartedAt.map { Date().timeIntervalSince($0) < 8.0 } ?? true)
            let isLimitError = msg.localizedCaseInsensitiveContains("usage limit") || msg.localizedCaseInsensitiveContains("rate limit") || msg.localizedCaseInsensitiveContains("api key")
            if isLimitError {
                codexRealtimeFallbackAccountID = (selectedAccount ?? localDataRef?.activeAccount)?.id
            }
            if recentStartup || isLimitError {
                startChatConversationalVoice()
            } else if !msg.isEmpty {
                voice.voiceErrorMessage = msg
            }
            return
        case "thread/realtime/closed":
            guard voice.isVoiceModeActive else { return }
            let recentStartup = voice.isConnecting || (realtimeSessionStartedAt.map { Date().timeIntervalSince($0) < 8.0 } ?? true)
            if recentStartup {
                codexRealtimeFallbackAccountID = (selectedAccount ?? localDataRef?.activeAccount)?.id
                startChatConversationalVoice()
            } else if voice.realtimeSessionActive {
                voice.realtimeSessionActive = false
                voice.stopVoiceConversation()
                speakReplies = false
            }
            return
        default:
            break
        }
        if method == "turn/completed", let id = parameters["threadId"] as? String,
           let callback = scheduledThreads.removeValue(forKey: id) {
            let turn = parameters["turn"] as? JSON
            let success = turn?["status"] as? String == "completed"
            let failure = (turn?["error"] as? JSON)?["message"] as? String
            callback(success, id, failure)
            refresh()
            return
        }
        let eventThreadId = parameters["threadId"] as? String
        switch method {
        case "turn/started":
            recordActivity(threadId: eventThreadId, note: "Pensando…", detail: nil, kind: .thinking)
        case "item/started":
            if let item = parameters["item"] as? JSON, (eventThreadId == nil || eventThreadId == selected) {
                upsert(item)
                let itemType = item["type"] as? String ?? ""
                switch itemType {
                case "commandExecution":
                    let cmd = item["command"] as? String
                    recordActivity(threadId: eventThreadId, note: "Executando comando…", detail: cmd, kind: .command)
                case "fileChange":
                    let changes = item["changes"] as? [JSON] ?? []
                    let paths = changes.compactMap { ($0["path"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } }.joined(separator: ", ")
                    recordActivity(threadId: eventThreadId, note: paths.isEmpty ? "Editando arquivos…" : "Editando \(paths)…", detail: paths.isEmpty ? nil : paths, kind: .fileChange)
                case "mcpToolCall":
                    let tool = item["tool"] as? String ?? "ferramenta"
                    let server = item["server"] as? String
                    let desc = server != nil ? "\(server!) · \(tool)" : tool
                    recordActivity(threadId: eventThreadId, note: "Executando \(desc)…", detail: desc, kind: .tool)
                case "webSearch":
                    let query = item["query"] as? String
                    recordActivity(threadId: eventThreadId, note: "Pesquisando na web…", detail: query, kind: .search)
                case "reasoning":
                    recordActivity(threadId: eventThreadId, note: "Pensando…", detail: nil, kind: .thinking)
                case "plan":
                    recordActivity(threadId: eventThreadId, note: "Organizando etapas…", detail: nil, kind: .generic)
                case "agentMessage":
                    recordActivity(threadId: eventThreadId, note: "Escrevendo resposta…", detail: nil, kind: .response)
                default:
                    break
                }
            }
        case "item/completed":
            if let item = parameters["item"] as? JSON, (eventThreadId == nil || eventThreadId == selected) {
                upsert(item)
                completeActivityStep(threadId: eventThreadId)
                persistCurrentMessages()
            }
        case "item/agentMessage/delta":
            guard let item = parameters["itemId"] as? String, let delta = parameters["delta"] as? String else { return }
            if let eventThreadId, activeTasks[eventThreadId] != nil {
                activeTasks[eventThreadId]?.progressNote = "Escrevendo resposta…"
            }
            if selected == eventThreadId || (selected != nil && eventThreadId == nil) {
                if currentActivityNote != "Escrevendo resposta…" {
                    currentActivityNote = "Escrevendo resposta…"
                    currentActivityKind = .response
                }
                appendDelta(item, delta, author: "WisdAI", kind: .text, turnId: turnID)
            }
        case "item/commandExecution/outputDelta":
            guard let item = parameters["itemId"] as? String, let delta = parameters["delta"] as? String else { return }
            if selected == eventThreadId || (selected != nil && eventThreadId == nil) {
                if currentActivityNote != "Executando comando…" {
                    currentActivityNote = "Executando comando…"
                    currentActivityKind = .command
                }
                appendOutputDelta(item, delta)
            }
        case "item/fileChange/outputDelta":
            guard let item = parameters["itemId"] as? String, let delta = parameters["delta"] as? String else { return }
            if selected == eventThreadId || (selected != nil && eventThreadId == nil) {
                appendOutputDelta(item, delta)
            }
        case "item/plan/delta":
            guard let item = parameters["itemId"] as? String, let delta = parameters["delta"] as? String else { return }
            if selected == eventThreadId || (selected != nil && eventThreadId == nil) {
                appendDelta(item, delta, author: "WisdAI", kind: .plan, turnId: turnID)
                if let existing = streamedItems[item], let idx = messages.firstIndex(where: { $0.id == existing }) {
                    let parsed = parsePlanSteps(from: messages[idx].text)
                    if !parsed.isEmpty { messages[idx].steps = parsed }
                }
            }
        case "item/reasoning/summaryTextDelta":
            guard let item = parameters["itemId"] as? String, let delta = parameters["delta"] as? String else { return }
            if selected == eventThreadId || (selected != nil && eventThreadId == nil) {
                appendDelta(item, delta, author: "WisdAI", kind: .reasoning, turnId: turnID, subKind: "thought")
            }
        case "turn/completed":
            if let tid = eventThreadId, let running = activeTasks[tid]?.turnId,
               let observed = (parameters["turn"] as? JSON)?["id"] as? String, observed != running { return }
            if let tid = eventThreadId, let completedID = (parameters["turn"] as? JSON)?["id"] as? String {
                loadedHistories.insert(tid); knownLastTurns[tid] = completedID
            }
            var failureMessage: String? = nil
            if let turn = parameters["turn"] as? JSON, let failure = turn["error"] as? JSON {
                failureMessage = failure["message"] as? String ?? "A tarefa falhou."
            }

            if let tid = eventThreadId,
               let turn = parameters["turn"] as? JSON, turn["status"] as? String == "failed",
               let failure = turn["error"] as? JSON {
                let classified = ProviderLimit.classify(failure)
                let lowerFail = (failureMessage ?? "").lowercased()
                let isUnsupportedModel = lowerFail.contains("is not supported")
                    || lowerFail.contains("model_not_found")
                    || lowerFail.contains("unsupported model")
                let isLimit = classified != nil ||
                              lowerFail.contains("usage limit") ||
                              lowerFail.contains("quota") ||
                              lowerFail.contains("tokens") ||
                              isUnsupportedModel
                if isLimit {
                    let taskToRun = activeTasks[tid]?.prompt ?? messages.last(where: { $0.author == "Você" })?.text ?? ""
                    let failedModelName = activeTasks[tid]?.modelName
                    let kind = isUnsupportedModel ? .model : (classified ?? .account)
                    let delay = UsageQuotaStore.parseRetryDelaySeconds(from: failureMessage ?? "") ?? (kind == .account ? 900 : 300)
                    activeTasks.removeValue(forKey: tid)
                    recovery.finished(tid)
                    if !taskToRun.isEmpty && autoFallbackToNextAccount(
                        forTask: taskToRun,
                        onThread: tid,
                        failedModel: failedModelName,
                        limitKind: kind,
                        until: Date().addingTimeInterval(delay),
                        reason: failureMessage,
                        skipAddingUserMessage: true
                    ) {
                        return
                    }
                }
                if recovery.failed(threadID: tid, turnID: turn["id"] as? String, failure: failure) {
                    if selected == tid, activeTasks[tid] == nil { turnID = nil; error = nil }
                    return
                }
            }
            if let tid = eventThreadId {
                if let taskInfo = activeTasks[tid], let accId = taskInfo.accountId {
                    quotaStore.recordTokenUsage(accountID: accId, modelID: taskInfo.modelName, tokens: 0, incrementRequest: true)
                }
                activeTasks.removeValue(forKey: tid)
                recovery.finished(tid)
                if selected != tid {
                    unseenCompletedThreads.insert(tid)
                }
            }
            if selected == eventThreadId || eventThreadId == nil {
                resetActivityState()
                sentAttachments.forEach(removeRecording)
                sentAttachments = []
                busy = false
                turnID = nil
                if let failureMessage {
                    error = failureMessage
                }
                deliverCompletedChatVoiceReply(failureText: failureMessage ?? error)
                if ready { refreshQuota() }
                refresh()
            }
        default:
            break
        }
    }

    private func disconnected() {
        recovery.disconnected()
        ready = false
        busy = false
        turnID = nil
        error = "A conexão com o motor WisdCode foi encerrada."
        pending.removeAll()
        scheduledBusy = false
        let callbacks = Array(scheduledThreads)
        scheduledThreads.removeAll()
        callbacks.forEach { $0.value(false, $0.key, "A conexão com o motor WisdCode foi encerrada.") }
    }

    func runScheduled(_ task: ScheduledTask, completion: @escaping (Bool, String?, String?) -> Void) {
        guard ready, !accountBusy, !scheduledBusy, !recovery.journal.records.values.contains(where: { ["queued", "waiting", "dispatching"].contains($0.phase) }), accountIdentity == task.accountID else {
            completion(false, nil, "Conta desconectada ou ocupada.")
            return
        }
        scheduledBusy = true
        let finished: (Bool, String?, String?) -> Void = { [weak self] success, threadID, failure in
            self?.scheduledBusy = false
            completion(success, threadID, failure)
        }
        request("thread/start", ["cwd": task.folder, "sandbox": "read-only", "approvalPolicy": "never"]) { [weak self] response in
            guard let self, self.accountIdentity == task.accountID else {
                finished(false, nil, "Conta alterada antes da execução.")
                return
            }
            guard let thread = (response["result"] as? JSON)?["thread"] as? JSON,
                  let id = thread["id"] as? String else {
                let message = (response["error"] as? JSON)?["message"] as? String
                finished(false, nil, message ?? "Não foi possível iniciar a conversa.")
                return
            }
            self.scheduledThreads[id] = finished
            self.request("turn/start", ["threadId": id, "approvalPolicy": "never",
                                       "sandboxPolicy": ["type": "readOnly"],
                                       "input": [["type": "text", "text": task.prompt, "textElements": []]]]) { [weak self] result in
                guard let self else { return }
                if result["result"] == nil {
                    let message = (result["error"] as? JSON)?["message"] as? String
                    self.scheduledThreads.removeValue(forKey: id)?(false, id, message ?? "Falha ao iniciar a tarefa.")
                }
            }
        }
    }

    func reviewChanges() {
        guard ready, !busy, !accountBusy, let project else { return }
        newConversation()
        streamedItems = [:]
        messages.append(Message(author: "Você", text: "Revisar alterações locais"))
        busy = true
        request("thread/start", ["cwd": project.path, "sandbox": "read-only", "approvalPolicy": "never"]) { [weak self] response in
            guard let self else { return }
            guard let id = (self.accept(response)?["thread"] as? JSON)?["id"] as? String else {
                self.busy = false
                return
            }
            self.selected = id
            self.resumed = id
            self.request("review/start", ["threadId": id, "target": ["type": "uncommittedChanges"]]) { [weak self] result in
                guard let self else { return }
                if let turn = self.accept(result)?["turn"] as? JSON {
                    self.turnID = turn["id"] as? String
                    if turn["status"] as? String == "completed" { self.busy = false }
                } else {
                    self.busy = false
                }
            }
        }
    }
}

@main
struct WisdAIApp: App {
    @AppStorage("wisdcode.appearance") private var appearance = "dark"
    @StateObject private var workspace = Workspace()
    @StateObject private var local = DesktopLocalData()

    var body: some Scene {
        WindowGroup {
            DesktopView(workspace: workspace, local: local)
                .frame(minWidth: 820, minHeight: 600)
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
                .task {
                    workspace.localDataRef = local
                    if let active = local.activeAccount {
                        workspace.selectedAccount = active
                        if !UsageQuotaStore.isModelCompatible(workspace.selectedModel, with: active) || workspace.selectedModel == "auto" {
                            let valid = UsageQuotaStore.isModelCompatible(active.currentModel, with: active) && active.currentModel != "auto"
                                ? active.currentModel
                                : (active.models.first ?? active.provider.defaultModels.first ?? "auto")
                            workspace.selectedModel = valid
                        }
                    }
                    workspace.connect()
                    Task { await workspace.refreshAllQuotasNow(force: false) }
                    if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
                       let icon = NSImage(contentsOf: iconURL) {
                        NSApplication.shared.applicationIconImage = icon
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    Task { await workspace.refreshAllQuotasNow(force: false) }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
                    workspace.persistCurrentMessages()
                    ChatStorage.shared.checkpoint()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    workspace.shutdownGracefully()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
    }
}

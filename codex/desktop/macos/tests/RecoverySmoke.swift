import Foundation

@MainActor
final class RecoveryFixture {
    let root: URL
    var active = "a"
    var sessions = ["a", "b"]
    var started: [JSON] = []
    var requests: [String] = []
    var turnStatus = "failed"
    var unknownOperation = false
    var denySwitch = false
    var changeProjectOnResume = false
    var rejectNextStart: String?
    var catalog: [String: [String]] = ["a": ["model-one", "model-two"], "b": ["model-three"]]
    var activeTurn = "original"
    lazy var workspace: Workspace = {
        let workspace = Workspace(recoveryURL: root.appendingPathComponent("journal/checkpoints.json")) { [unowned self] method, params, completion in
            self.respond(method, params, completion)
        }
        workspace.ready = true; workspace.automaticFallback = true; workspace.mode = 1
        workspace.project = root.appendingPathComponent("project"); workspace.selected = "thread"
        workspace.accountChoices = [AccountChoice(id: "a", label: "A", active: true, workspaceID: "workspace-a"), AccountChoice(id: "b", label: "B", active: false, workspaceID: "workspace-b")]
        return workspace
    }()
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("wisdai-recovery-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("project"), withIntermediateDirectories: true)
        let git = Process(); git.executableURL = URL(fileURLWithPath: "/usr/bin/git"); git.arguments = ["init", "-q", root.appendingPathComponent("project").path]
        try git.run(); git.waitUntilExit(); precondition(git.terminationStatus == 0)
        try "completed-once\n".write(to: root.appendingPathComponent("project/done.txt"), atomically: true, encoding: .utf8)
    }
    func prepare(accepted: Bool = true, ephemeral: Bool = false) throws {
        try workspace.recovery.begin(threadID: "thread", task: "ORIGINAL TASK MUST NOT BE REPLAYED", inputs: [["type": "text", "text": "ORIGINAL TASK MUST NOT BE REPLAYED"]],
                                     mode: 1, effort: "high", cwd: root.appendingPathComponent("project").path, ephemeral: ephemeral, model: "model-one", baselineTurnID: "original", baselineKnown: true)
        if accepted { workspace.recovery.accepted("thread", turnID: "original") }
    }
    func respond(_ method: String, _ params: JSON, _ completion: (JSON) -> Void) {
        requests.append(method)
        var result: JSON = [:]
        switch method {
        case "thread/read":
            result = ["thread": ["id": "thread", "cwd": root.appendingPathComponent("project").path,
                                  "turns": [["id": activeTurn, "status": turnStatus, "items": [["id": "completed-write", "type": "fileChange", "status": unknownOperation ? "inProgress" : "completed"]]]]]]
        case "accountSession/list":
            result = ["sessions": sessions.map { ["sessionId": $0, "email": $0, "isActive": $0 == active, "selectedWorkspaceAccountId": "workspace-" + $0] as JSON }]
        case "accountSession/switch":
            if !denySwitch { active = params["sessionId"] as! String }
        case "model/list":
            result = ["data": (catalog[active] ?? []).map { ["id": $0, "model": $0, "displayName": $0, "supportedReasoningEfforts": ["low"], "isDefault": false] as JSON }]
        case "thread/resume":
            if changeProjectOnResume { try! "external change".write(to: root.appendingPathComponent("project/done.txt"), atomically: true, encoding: .utf8) }
        case "turn/start":
            started.append(params)
            if let next = rejectNextStart {
                rejectNextStart = nil
                completion(["error": ["message": "fixture", "data": ["codexErrorInfo": next]]]); return
            }
            activeTurn = "continued-\(started.count)"
            result = ["turn": ["id": activeTurn, "status": "inProgress"]]
        default: break
        }
        completion(["result": result])
    }
    func fail(_ kind: String = "rateLimitExceeded", turn: String? = "original") {
        precondition(workspace.recovery.failed(threadID: "thread", turnID: turn, failure: ["codexErrorInfo": kind, "message": "Fixture limit"]))
    }
    func settle() async throws {
        for _ in 0..<200 {
            if !workspace.recovery.isRecovering { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw RecoveryFailure.message("Recovery fixture timed out")
    }
    func clean() { workspace.recovery.disconnected(); try? FileManager.default.removeItem(at: root) }
}

@main
struct RecoverySmoke {
    @MainActor static func main() async throws {
        let domain = ProcessInfo.processInfo.processName
        precondition(domain == "WisdAIRecoverySmoke")
        UserDefaults.standard.removePersistentDomain(forName: domain)
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        for kind in ["contextWindowExceeded", "sessionBudgetExceeded", "sandboxError", "unauthorized", "badRequest", "misalignmentPolicyViolation"] {
            precondition(ProviderLimit.classify(["codexErrorInfo": kind, "message": "tokens quota 429 insufficient"]) == nil)
        }
        precondition(ProviderLimit.classify(["message": "too many tokens in context"]) == nil)
        precondition(ProviderLimit.classify(["message": "insufficient permissions"]) == nil)
        precondition(ProviderLimit.classify(["codexErrorInfo": "usageLimitExceeded"]) == .account)
        precondition(ProviderLimit.classify(["data": ["codexErrorInfo": "rateLimitExceeded"]]) == .model)
        do {
            let f = try RecoveryFixture(); defer { f.clean() }; try f.prepare(); f.fail(); try await f.settle()
            precondition(f.started.count == 1 && f.started[0]["model"] as? String == "model-two")
            let text = ((f.started[0]["input"] as! [JSON])[0]["text"] as! String)
            precondition(!text.contains("ORIGINAL TASK"))
            precondition(f.started[0]["effort"] == nil)
            precondition(f.workspace.recovery.journal.records["thread"]!.operations.first!.id == "completed-write")
            f.fail(turn: "original"); try await f.settle(); precondition(f.started.count == 1)
            let duplicate: JSON = ["method": "turn/completed", "params": ["threadId": "thread", "turn": ["id": "original", "status": "failed", "error": ["codexErrorInfo": "rateLimitExceeded", "message": "duplicate"]]]]
            f.workspace.receive(try JSONSerialization.data(withJSONObject: duplicate))
            precondition(f.workspace.activeTasks["thread"]?.turnId == "continued-1")
            let content = try String(contentsOf: f.root.appendingPathComponent("project/done.txt"), encoding: .utf8)
            precondition(content == "completed-once\n")
        }
        do {
            let f = try RecoveryFixture(); defer { f.clean() }; try f.prepare(); f.fail("usageLimitExceeded"); try await f.settle()
            precondition(f.active == "b" && f.started.count == 1 && f.started[0]["model"] as? String == "model-three")
            precondition(f.requests.contains("accountSession/switch"))
            precondition((f.started[0]["sandboxPolicy"] as! JSON)["type"] as? String == "workspaceWrite")
            precondition(f.started[0]["approvalPolicy"] as? String == "on-request")
        }
        do {
            let f = try RecoveryFixture(); defer { f.clean() }; try f.prepare(accepted: false); f.fail(turn: nil); try await f.settle()
            precondition((f.started[0]["input"] as! [JSON])[0]["text"] as? String == "ORIGINAL TASK MUST NOT BE REPLAYED")
        }
        do {
            let f = try RecoveryFixture(); defer { f.clean() }; try f.prepare(); f.unknownOperation = true; f.fail(); try await f.settle()
            precondition(f.started.isEmpty && f.workspace.recovery.journal.records["thread"]?.phase == "paused")
        }
        do {
            let f = try RecoveryFixture(); defer { f.clean() }; try f.prepare(); f.changeProjectOnResume = true; f.fail(); try await f.settle()
            precondition(f.started.isEmpty && f.workspace.recovery.journal.records["thread"]?.phase == "paused")
        }
        do {
            let f = try RecoveryFixture(); defer { f.clean() }; try f.prepare(); f.denySwitch = true; f.fail("usageLimitExceeded"); try await f.settle()
            precondition(f.started.isEmpty && f.workspace.recovery.journal.records["thread"]?.phase == "paused")
        }
        do {
            let f = try RecoveryFixture(); defer { f.clean() }; try f.prepare(); f.workspace.mode = 0; f.fail(); try await f.settle()
            precondition((f.started[0]["sandboxPolicy"] as! JSON)["type"] as? String == "readOnly")
        }
        do {
            let f = try RecoveryFixture(); defer { f.clean() }; try f.prepare(); f.sessions = ["a"]; f.fail("usageLimitExceeded"); try await f.settle()
            precondition(f.started.isEmpty && f.workspace.recovery.journal.records["thread"]?.phase == "waiting")
            f.workspace.recovery.tick(); try await f.settle(); precondition(f.started.isEmpty)
            let restored = RecoveryJournal(url: f.root.appendingPathComponent("journal/checkpoints.json"))
            precondition(restored.records["thread"]?.phase == "paused" && !restored.cooldowns.isEmpty)
        }
        do {
            let f = try RecoveryFixture(); defer { f.clean() }; try f.prepare(ephemeral: true)
            let restored = RecoveryJournal(url: f.root.appendingPathComponent("journal/checkpoints.json")); precondition(restored.records.isEmpty)
        }
        do {
            let f = try RecoveryFixture(); defer { f.clean() }; try f.prepare(); f.turnStatus = "completed"; f.fail(); try await f.settle()
            precondition(f.started.isEmpty && f.workspace.recovery.journal.records["thread"] == nil)
        }
        do {
            let f = try RecoveryFixture(); defer { f.clean() }; try f.prepare(); f.rejectNextStart = "usageLimitExceeded"; f.fail(); try await f.settle()
            precondition(f.started.count == 2 && f.active == "b")
        }
        do {
            let f = try RecoveryFixture(); defer { f.clean() }; try f.prepare(); f.sessions = ["a"]; f.fail("usageLimitExceeded"); try await f.settle()
            f.workspace.recovery.journal.cooldowns = []
            f.workspace.recovery.journal.records["thread"]?.retryAfter = Date().addingTimeInterval(-1)
            f.workspace.recovery.tick(); try await f.settle()
            precondition(f.started.count == 1) // Limits renewed; the preserved task can continue.
        }
        do {
            let f = try RecoveryFixture(); defer { f.clean() }; try f.prepare(); f.workspace.automaticFallback = false; f.fail(); try await f.settle()
            precondition(f.started.isEmpty && f.workspace.recovery.journal.records["thread"]?.phase == "paused")
        }
        do {
            let f = try RecoveryFixture(); defer { f.clean() }
            let broken = f.root.appendingPathComponent("broken.json")
            try Data("broken".utf8).write(to: broken)
            let journal = RecoveryJournal(url: broken)
            do { try journal.save(); preconditionFailure("Corrupt checkpoint was overwritten") } catch { }
            let preserved = try Data(contentsOf: broken); precondition(preserved == Data("broken".utf8))
        }
        do {
            let f = try RecoveryFixture(); defer { f.clean() }
            try FileManager.default.removeItem(at: f.root.appendingPathComponent("project/.git"))
            _ = try RecoveryWorkspace.digest(f.root.appendingPathComponent("project").path)
        }
        do {
            let f = try RecoveryFixture(); defer { f.clean() }; try f.prepare(accepted: false)
            f.activeTurn = "unexpected-new-turn"
            f.fail(turn: nil); try await f.settle()
            precondition(f.started.isEmpty && f.workspace.recovery.journal.records["thread"]?.phase == "paused")
        }
        do {
            let f = try RecoveryFixture(); defer { f.clean() }; try f.prepare(); f.fail(); f.workspace.recovery.cancel("thread"); try await f.settle()
            precondition(f.started.isEmpty && f.workspace.recovery.journal.records["thread"]?.phase == "paused")
        }
        do {
            let f = try RecoveryFixture(); defer { f.clean() }; try f.prepare()
            f.workspace.activeTasks["other"] = ActiveThreadTask(threadId: "other", prompt: "parallel task")
            f.fail("usageLimitExceeded"); try await f.settle(); precondition(f.started.isEmpty)
            f.workspace.activeTasks.removeValue(forKey: "other"); f.workspace.recovery.tick(); try await f.settle()
            precondition(f.started.count == 1 && f.active == "b")
        }
        print("PASS: strict limits; model/account fallback; same-thread context; accepted input not replayed; duplicate events; policy preservation; stale files; unknown operations; missing auth; cooldown; restart and ephemeral privacy")
    }
}

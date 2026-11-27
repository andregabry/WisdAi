import Foundation

@MainActor
final class LiveRPC {
    let process = Process()
    let input = Pipe()
    let output = Pipe()
    var id = 0
    var pending: [Int: (JSON) -> Void] = [:]
    var notification: ((Data) -> Void)?
    var injectedLimit: String?
    var injectedModel: String?
    var turnModels: [String] = []
    var turnSessions: [String] = []
    var activeSession = ""
    var allowedSessions: Set<String> = []
    var modelCap: Int? = 2
    var diagnostics: [String] = []
    func start(_ binary: String) throws {
        process.executableURL = URL(fileURLWithPath: binary)
        let host = URL(fileURLWithPath: binary).deletingLastPathComponent().appendingPathComponent("codex-code-mode-host")
        process.arguments = FileManager.default.isExecutableFile(atPath: host.path) ? ["app-server"] : ["-c", "features.code_mode=false", "app-server"]
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        let reader = output.fileHandleForReading
        DispatchQueue.global().async { [weak self] in
            var buffer = Data()
            while true {
                let bytes = reader.availableData
                if bytes.isEmpty { break }; buffer.append(bytes)
                while let end = buffer.firstIndex(of: 10) {
                    let line = Data(buffer[..<end]); buffer.removeSubrange(...end)
                    Task { @MainActor [weak self] in self?.receive(line) }
                }
            }
        }
    }
    func receive(_ data: Data) {
        guard var reply = (try? JSONSerialization.jsonObject(with: data)) as? JSON else { return }
        if let id = reply["id"] as? Int, let completion = pending.removeValue(forKey: id) {
            if var result = reply["result"] as? JSON {
                if let models = result["data"] as? [JSON], models.first?["model"] != nil, let cap = modelCap { result["data"] = Array(models.prefix(cap)) }
                if let sessions = result["sessions"] as? [JSON] {
                    activeSession = sessions.first(where: { $0["isActive"] as? Bool == true })?["sessionId"] as? String ?? ""
                    if !allowedSessions.isEmpty { result["sessions"] = sessions.filter { allowedSessions.contains($0["sessionId"] as? String ?? "") } }
                }
                reply["result"] = result
            }
            completion(reply)
        } else {
            if let params = reply["params"] as? JSON {
                if let failure = params["error"] as? JSON, let message = failure["message"] as? String { diagnostics.append(String(message.prefix(1200))) }
                if let item = params["item"] as? JSON {
                    if let failure = item["error"] as? JSON, let message = failure["message"] as? String { diagnostics.append(String(message.prefix(1200))) }
                    if let output = item["aggregatedOutput"] as? String, output.lowercased().contains("fail") { diagnostics.append(String(output.prefix(1200))) }
                }
            }
            notification?(data)
        }
    }
    func send(_ value: JSON) {
        try! input.fileHandleForWriting.write(contentsOf: JSONSerialization.data(withJSONObject: value) + Data([10]))
    }
    func request(_ method: String, _ params: JSON, _ completion: @escaping (JSON) -> Void) {
        if method == "turn/start" {
            let model = params["model"] as? String ?? "auto"
            if let limit = injectedLimit {
                injectedLimit = nil; injectedModel = model
                completion(["error": ["code": -32000, "message": "Deterministic test limit before acceptance", "data": ["codexErrorInfo": limit]]])
                return
            }
            turnModels.append(model)
            turnSessions.append(activeSession)
        }
        id += 1; pending[id] = completion
        send(["id": id, "method": method, "params": params])
    }
    func stop() { if process.isRunning { process.terminate() }; try? input.fileHandleForWriting.close() }
}

@main
struct RecoveryLive {
    @MainActor static func wait(_ workspace: Workspace) async throws {
        for _ in 0..<1200 {
            if let paused = workspace.recoveryNotices.first(where: { ["paused", "waiting"].contains($0.phase) }) {
                throw RecoveryFailure.message(paused.notice)
            }
            if !workspace.pendingApprovals.isEmpty { throw RecoveryFailure.message("Native approval required; the test did not bypass it.") }
            if !workspace.busy, workspace.activeTasks.isEmpty, workspace.recovery.journal.records.isEmpty {
                if let error = workspace.error { throw RecoveryFailure.message(error) }
                return
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw RecoveryFailure.message("Live validation timed out; no request was replayed.")
    }
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count >= 2 else { fatalError("Pass the packaged codex binary") }
        let domain = ProcessInfo.processInfo.processName
        precondition(domain == "WisdAIRecoveryLive")
        UserDefaults.standard.removePersistentDomain(forName: domain)
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let accountTest = CommandLine.arguments.contains("--accounts")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wisdai-live-recovery-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let git = Process(); git.executableURL = URL(fileURLWithPath: "/usr/bin/git"); git.arguments = ["init", "-q", root.path]; try git.run(); git.waitUntilExit()
        let rpc = LiveRPC(); try rpc.start(CommandLine.arguments[1]); defer { rpc.stop(); try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(recoveryURL: root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".json")) { method, params, completion in rpc.request(method, params, completion) }
        defer { try? FileManager.default.removeItem(at: workspace.recovery.journal.url) }
        rpc.notification = { workspace.receive($0) }
        _ = try await workspace.recoveryRPC("initialize", ["clientInfo": ["name": "wisdai-recovery-live-test", "version": "0.1"], "capabilities": ["experimentalApi": true]])
        rpc.send(["method": "initialized"])
        let account = try await workspace.recoveryRPC("account/read", [:])
        guard (account["account"] as? JSON)?["type"] as? String == "chatgpt" else { print("BLOCKED: official ChatGPT subscription session required; no API inference submitted"); return }
        let sessionReply = try await workspace.recoveryRPC("accountSession/list", [:])
        let sessions = sessionReply["sessions"] as? [JSON] ?? []
        guard let original = sessions.first(where: { $0["isActive"] as? Bool == true }), let originalID = original["sessionId"] as? String,
              let originalWorkspace = original["selectedWorkspaceAccountId"] as? String else { throw RecoveryFailure.message("No verified active session") }
        if accountTest, sessions.count < 2 { print("BLOCKED: second authenticated OpenAI session required; no inference submitted"); return }
        rpc.allowedSessions = accountTest ? Set(sessions.compactMap { $0["sessionId"] as? String }) : [originalID]
        let catalog = try await workspace.recoveryRPC("model/list", [:])
        let models = Workspace.parseModels(catalog)
        guard models.count >= (accountTest ? 1 : 2) else { throw RecoveryFailure.message("Not enough provider-advertised models") }
        workspace.applyRecoverySession(sessionReply, models: models)
        do {
        workspace.ready = true; workspace.mode = 1; workspace.automaticFallback = true
        workspace.project = root; workspace.selectedModel = models[0].id; workspace.selectedEffort = "low"
        workspace.prompt = "In this disposable repository create only minutes.py defining minutes_to_hours(minutes) returning minutes / 60. Do not create tests yet. Use only this folder and no network. Finish after the function is written."
        workspace.send()
        try await wait(workspace)
        guard let threadID = workspace.selected else { throw RecoveryFailure.message("First native task did not create a thread") }
        let sourceURL = root.appendingPathComponent("minutes.py")
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            let history = try await workspace.recoveryRPC("thread/read", ["threadId": threadID, "includeTurns": true])
            for turn in (history["thread"] as? JSON)?["turns"] as? [JSON] ?? [] {
                for item in turn["items"] as? [JSON] ?? [] {
                    let kind = item["type"] as? String ?? "unknown"
                    if ["userMessage", "agentMessage", "reasoning"].contains(kind) { continue }
                    FileHandle.standardError.write(Data(("Tool record: " + kind + " keys=" + item.keys.sorted().joined(separator: ",") + "\n").utf8))
                    for key in ["error", "aggregatedOutput", "result", "contentItems"] where item[key] != nil {
                        let raw = String(describing: item[key]!)
                        let safe = raw.split(separator: "\n").filter { line in !["sk-", "bearer", "access_token", "refresh_token", "api_key", "authorization", "oauth"].contains(where: { line.lowercased().contains($0) }) }.joined(separator: "\n")
                        FileHandle.standardError.write(Data((key + ": " + safe.prefix(1800) + "\n").utf8))
                    }
                }
            }
            let diagnosis = workspace.messages.last(where: { $0.author == "WisdAI" || $0.author == "WisdCode" })?.text ?? workspace.error ?? "No implementation file produced"
            throw RecoveryFailure.message(String(diagnosis.prefix(1600)) + "\n" + rpc.diagnostics.suffix(4).joined(separator: "\n"))
        }
        let originalSource = try Data(contentsOf: sourceURL)
        let originalModified = try FileManager.default.attributesOfItem(atPath: sourceURL.path)[.modificationDate] as? Date
        rpc.injectedLimit = accountTest ? "usageLimitExceeded" : "rateLimitExceeded"
        workspace.prompt = "Continue the same task. minutes.py is complete: preserve it byte for byte. Create test_minutes.py with Python unittest tests for 0, 30 and 90 minutes. Do not repeat the completed implementation step. Use only this folder and no network."
        workspace.send()
        try await wait(workspace)
        guard workspace.selected == threadID else { throw RecoveryFailure.message("Thread identity changed") }
        let after = try Data(contentsOf: sourceURL)
        guard after == originalSource else { throw RecoveryFailure.message("Completed implementation changed during continuation") }
        guard try FileManager.default.attributesOfItem(atPath: sourceURL.path)[.modificationDate] as? Date == originalModified else { throw RecoveryFailure.message("Completed implementation was rewritten during continuation") }
        let test = Process(); test.executableURL = URL(fileURLWithPath: "/usr/bin/env"); test.arguments = ["python3", "-m", "unittest", "discover", "-s", root.path, "-p", "test_minutes.py"]
        test.currentDirectoryURL = root; try test.run(); test.waitUntilExit()
        guard test.terminationStatus == 0, FileManager.default.fileExists(atPath: root.appendingPathComponent("test_minutes.py").path) else { throw RecoveryFailure.message("Continuation tests failed") }
        guard rpc.turnModels.count == 2 else { throw RecoveryFailure.message("Unexpected duplicate inference submission") }
        if !accountTest { guard rpc.turnModels[1] != rpc.injectedModel else { throw RecoveryFailure.message("Model did not switch") } }
        if accountTest {
            guard rpc.turnSessions.count == 2, rpc.turnSessions[0] == originalID, rpc.turnSessions[1] != originalID, !rpc.turnSessions[1].isEmpty else { throw RecoveryFailure.message("Authenticated account did not switch") }
            _ = try await workspace.recoveryRPC("accountSession/switch", ["sessionId": originalID, "accountId": originalWorkspace, "allowBrowserLogin": false])
        }
        _ = try await workspace.recoveryRPC("thread/unsubscribe", ["threadId": threadID])
        _ = try await workspace.recoveryRPC("thread/delete", ["threadId": threadID])
        } catch {
            if accountTest {
                _ = try? await workspace.recoveryRPC("accountSession/switch", ["sessionId": originalID, "accountId": originalWorkspace, "allowBrowserLogin": false])
            }
            if let threadID = workspace.selected {
                _ = try? await workspace.recoveryRPC("thread/unsubscribe", ["threadId": threadID])
                _ = try? await workspace.recoveryRPC("thread/delete", ["threadId": threadID])
            }
            throw error
        }
        print("PASS: two real subscription-backed Codex turns; injected limit; automatic \(accountTest ? "account" : "model") switch; same thread; completed source unchanged; three tests passed; disposable thread deleted")
    }
}

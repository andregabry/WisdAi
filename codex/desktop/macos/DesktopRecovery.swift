import CryptoKit
import Foundation

/// Only explicit provider limits may trigger automatic account/model selection.
enum ProviderLimit: String, Codable {
    case account, model
    static func classify(_ failure: JSON) -> ProviderLimit? {
        let detail = failure["data"] as? JSON ?? failure
        if let info = detail["codexErrorInfo"] as? String {
            switch info {
            case "usageLimitExceeded": return .account
            case "rateLimitExceeded": return .model
            default: return nil // Includes budgets, context limits, policy and sandbox failures.
            }
        }
        if let info = detail["codexErrorInfo"] as? JSON {
            for key in ["httpConnectionFailed", "responseStreamConnectionFailed", "responseTooManyFailedAttempts"] {
                if (info[key] as? JSON)?["httpStatusCode"] as? Int == 429 { return .model }
            }
            return nil
        }
        let text = (failure["message"] as? String ?? "").lowercased()
        if text.contains("usage limit reached") || text.contains("you've hit your usage limit") || text.contains("insufficient_quota") { return .account }
        if text.contains("rate limit exceeded") || text.contains("rate limit reached") || text.contains("too many requests") { return .model }
        return nil
    }
}

struct RecoveryTarget: Codable, Equatable {
    let session: String
    let workspace: String
    let model: String
    var route: String { session + ":" + workspace }
    var key: String { route + ":" + model }
}

struct CompletedOperation: Codable {
    let id: String
    let type: String
    let status: String
}

struct RecoveryCheckpoint: Codable, Identifiable {
    var id: String { threadID }
    let threadID: String
    let task: String
    let cwd: String
    let mode: Int
    let effort: String
    let ephemeral: Bool
    // User-visible input, never credentials or hidden reasoning.
    var originalInput: Data
    var target: RecoveryTarget?
    var acceptedTurnID: String?
    var baselineTurnID: String?
    var baselineKnown: Bool?
    var failedTurnID: String?
    var requestID = UUID().uuidString
    var retryAfter: Date?
    var attempted: [String] = []
    var operations: [CompletedOperation] = []
    var digest: String?
    var attachmentDigests: [String: String]?
    var phase = "running"
    var notice = ""
    var updated = Date()
}

struct RecoveryCooldown: Codable {
    let key: String
    let until: Date
}

@MainActor
final class RecoveryJournal {
    let url: URL
    var records: [String: RecoveryCheckpoint] = [:]
    var cooldowns: [RecoveryCooldown] = []
    private(set) var loadError: String?
    private struct Disk: Codable { let records: [RecoveryCheckpoint]; let cooldowns: [RecoveryCooldown] }
    init(url: URL) {
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let disk = try JSONDecoder().decode(Disk.self, from: Data(contentsOf: url))
                for var record in disk.records {
                    record.phase = "paused"
                    record.notice = "A sessão anterior terminou. Confira o último turno antes de retomar."
                    records[record.threadID] = record
                }
                cooldowns = disk.cooldowns.filter { $0.until > Date() }
            } catch { loadError = "O checkpoint salvo não pôde ser lido. O arquivo original foi preservado para conferência." }
        }
    }
    func save() throws {
        if let loadError { throw RecoveryFailure.message(loadError) }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let disk = Disk(records: records.values.filter { !$0.ephemeral }, cooldowns: cooldowns)
        let data = try JSONEncoder().encode(disk)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    func blocked(_ key: String, now: Date = Date()) -> Bool { cooldowns.contains { $0.key == key && $0.until > now } }
    func block(_ key: String, until: Date) {
        cooldowns.removeAll { $0.key == key || $0.until <= Date() }
        cooldowns.append(RecoveryCooldown(key: key, until: until))
    }
}

enum RecoveryFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}

/// Content fingerprint of Git-tracked and nonignored untracked paths. Git is
/// invoked without a shell, optional locks, fsmonitor hooks or external diffs.
enum RecoveryWorkspace {
    static func digest(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        func git(_ args: [String], optional: Bool = false) throws -> Data {
            let process = Process(); let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["--no-optional-locks", "-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null"] + args
            process.currentDirectoryURL = root
            process.standardInput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice; process.standardOutput = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            guard process.terminationStatus == 0 || optional else { throw RecoveryFailure.message("A retomada automática requer um projeto Git acessível.") }
            return data
        }
        var hash = SHA256()
        hash.update(data: Data(root.path.utf8))
        let isGit = String(decoding: try git(["rev-parse", "--is-inside-work-tree"], optional: true), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        let paths: [String]
        if isGit {
            hash.update(data: try git(["rev-parse", "--verify", "HEAD"], optional: true))
            hash.update(data: try git(["status", "--porcelain=v1", "-z", "--untracked-files=all"]))
            let listing = try git(["ls-files", "-c", "-o", "--exclude-standard", "-z"])
            let parsed = listing.split(separator: 0).compactMap { String(data: Data($0), encoding: .utf8) }
            guard parsed.count == listing.split(separator: 0).count else { throw RecoveryFailure.message("Um nome de arquivo não pôde ser representado no checkpoint.") }
            paths = Set(parsed).sorted()
        } else {
            var readFailed = false
            guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, errorHandler: { _, _ in readFailed = true; return false }) else { throw RecoveryFailure.message("Não foi possível conferir a pasta do projeto.") }
            var names: [String] = []
            for case let url as URL in files {
                if url.lastPathComponent == ".git" { files.skipDescendants(); continue }
                names.append(String(url.path.dropFirst(root.path.count + 1)))
                guard names.count <= 10_000 else { throw RecoveryFailure.message("Projeto grande demais para conferir a retomada automaticamente.") }
            }
            guard !readFailed else { throw RecoveryFailure.message("Há arquivos que não puderam ser conferidos no projeto.") }
            paths = names.sorted()
        }
        guard paths.count <= 10_000 else { throw RecoveryFailure.message("Projeto grande demais para conferir a retomada automaticamente.") }
        var total = 0
        for path in paths {
            let url = root.appendingPathComponent(path)
            guard !path.split(separator: "/").contains(".."), url.standardizedFileURL.path.hasPrefix(root.path + "/") else { throw RecoveryFailure.message("Caminho inválido no checkpoint.") }
            hash.update(data: Data(path.utf8)); hash.update(data: Data([0]))
            // Never follow a parent symlink outside the workspace to inspect its contents.
            let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().path
            guard parent == root.path || parent.hasPrefix(root.path + "/") else { throw RecoveryFailure.message("Um caminho do projeto aponta para fora do workspace.") }
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { hash.update(data: Data("missing".utf8)); continue }
            if attributes[.type] as? FileAttributeType == .typeSymbolicLink {
                hash.update(data: Data(try FileManager.default.destinationOfSymbolicLink(atPath: url.path).utf8))
            } else if attributes[.type] as? FileAttributeType == .typeRegular {
                let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
                total += size
                guard total <= 100 * 1024 * 1024 else { throw RecoveryFailure.message("O checkpoint excede o limite de leitura automática.") }
                hash.update(data: try Data(contentsOf: url))
            } else { hash.update(data: Data("directory-or-special".utf8)) }
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
final class TurnRecoveryCoordinator {
    unowned let workspace: Workspace
    let journal: RecoveryJournal
    private var worker: Task<Void, Never>?
    private var cancelled = Set<String>()
    private var generation = UUID()
    var transitioning = false
    var isRecovering: Bool { worker != nil }
    func restore() { publish() }
    init(workspace: Workspace, url: URL) { self.workspace = workspace; journal = RecoveryJournal(url: url) }

    private func publish() {
        workspace.recoveryNotices = journal.records.values.filter { $0.phase != "running" }.sorted { $0.updated < $1.updated }
        do { try journal.save() }
        catch { workspace.error = "Não foi possível salvar o checkpoint de retomada. A troca automática foi pausada." }
    }
    func begin(threadID: String, task: String, inputs: [JSON], mode: Int, effort: String, cwd: String, ephemeral: Bool, model: String, baselineTurnID: String? = nil, baselineKnown: Bool = false) throws {
        let data = try JSONSerialization.data(withJSONObject: inputs)
        guard data.count <= 25 * 1024 * 1024 else { throw RecoveryFailure.message("Entrada grande demais para preservar na retomada automática.") }
        let choice = workspace.accountChoices.first(where: \.active)
        let target = choice.map { RecoveryTarget(session: $0.id, workspace: $0.workspaceID, model: model) }
        journal.records[threadID] = RecoveryCheckpoint(threadID: threadID, task: task, cwd: cwd, mode: mode, effort: effort,
                                                      ephemeral: ephemeral, originalInput: data, target: target)
        journal.records[threadID]?.baselineTurnID = baselineTurnID
        journal.records[threadID]?.baselineKnown = baselineKnown
        var references: [String: String] = [:]
        for input in inputs where input["type"] as? String == "localImage" {
            guard let path = input["path"] as? String else { continue }
            let size = ((try FileManager.default.attributesOfItem(atPath: path)[.size]) as? NSNumber)?.intValue ?? 0
            guard size <= 25 * 1024 * 1024 else { throw RecoveryFailure.message("Anexo grande demais para conferir a retomada.") }
            references[path] = SHA256.hash(data: try Data(contentsOf: URL(fileURLWithPath: path))).map { String(format: "%02x", $0) }.joined()
        }
        journal.records[threadID]?.attachmentDigests = references
        cancelled.remove(threadID)
        try journal.save()
    }
    func accepted(_ threadID: String, turnID: String) {
        guard journal.records[threadID] != nil else { return }
        journal.records[threadID]?.acceptedTurnID = turnID
        journal.records[threadID]?.phase = "running"
        publish()
    }
    func finished(_ threadID: String) { journal.records.removeValue(forKey: threadID); publish(); tick() }
    func discard(_ threadID: String) {
        cancelled.remove(threadID)
        journal.records.removeValue(forKey: threadID)
        publish()
        try? journal.save()
    }
    func cancel(_ threadID: String) {
        cancelled.insert(threadID)
        if var record = journal.records[threadID] { record.phase = "paused"; record.notice = "Retomada automática cancelada."; journal.records[threadID] = record }
        publish()
    }
    func pauseAll() {
        for id in journal.records.keys { cancel(id) }
    }
    func disconnected() {
        generation = UUID(); worker?.cancel(); worker = nil; transitioning = false
        for id in journal.records.keys {
            journal.records[id]?.phase = "paused"
            journal.records[id]?.notice = "Conexão interrompida: o resultado precisa ser conferido antes de retomar."
        }
        publish()
    }
    func failed(threadID: String, turnID: String?, failure: JSON) -> Bool {
        guard let limit = ProviderLimit.classify(failure), var record = journal.records[threadID] else { return false }
        // A terminal event from an older turn must not restart the new turn.
        if let turnID, let accepted = record.acceptedTurnID, accepted != turnID { return true }
        let eventID = turnID ?? "not-accepted:" + record.requestID
        guard record.failedTurnID != eventID else { return true }
        record.failedTurnID = eventID; record.phase = workspace.automaticFallback ? "queued" : "paused"; record.updated = Date()
        record.notice = workspace.automaticFallback ? "Limite informado pelo provedor. Preparando a continuação do mesmo chat." : "Limite informado pelo provedor. A continuação automática está desativada."
        if let target = record.target {
            if !record.attempted.contains(target.key) { record.attempted.append(target.key) }
            let active = workspace.accountChoices.first(where: \.active)
            let resets = (active?.id == target.session && active?.workspaceID == target.workspace) ? workspace.usageWindows.filter { $0.used >= 100 }.compactMap(\.reset).filter { $0 > Date() } : []
            journal.block(limit == .account ? target.route : target.key, until: resets.max() ?? Date().addingTimeInterval(limit == .account ? 900 : 60))
        }
        journal.records[threadID] = record
        workspace.activeTasks.removeValue(forKey: threadID)
        if workspace.selected == threadID { workspace.busy = false }
        do { try journal.save() } catch { pause(threadID, "Falha ao salvar o checkpoint. A troca foi pausada."); return true }
        publish(); tick(); return true
    }
    func retry(_ id: String) {
        guard journal.records[id] != nil, worker == nil else { return }
        // Explicit retry reconciles the native history and current workspace anew.
        journal.records[id]?.digest = nil
        journal.records[id]?.attempted = []
        journal.records[id]?.phase = "queued"
        cancelled.remove(id); publish(); tick()
    }
    func tick() {
        guard worker == nil, workspace.ready, workspace.automaticFallback, !workspace.accountBusy else { return }
        let records = journal.records.values.sorted(by: { $0.updated < $1.updated })
        guard var record = records.first(where: { $0.phase == "queued" }) ?? records.first(where: { $0.phase == "waiting" && ($0.retryAfter == nil || $0.retryAfter! <= Date()) }) else { return }
        if let retryAfter = record.retryAfter, retryAfter <= Date() {
            record.attempted = []; record.retryAfter = nil
            journal.records[record.threadID] = record
        }
        let token = generation
        worker = Task { [weak self] in
            guard let self else { return }
            defer {
                if token == self.generation {
                    self.worker = nil
                    if self.workspace.ready && !self.workspace.accountBusy { self.workspace.refreshAccount() }
                    if self.journal.records[record.threadID]?.phase == "queued" { self.tick() }
                }
            }
            do { try await self.recover(record.threadID, generation: token) }
            catch { if token == self.generation { self.pause(record.threadID, error.localizedDescription) } }
        }
    }
    private func check(_ id: String, _ token: UUID) throws {
        guard token == generation, !Task.isCancelled, !cancelled.contains(id), workspace.automaticFallback else { throw RecoveryFailure.message("Retomada automática pausada.") }
    }
    private func pause(_ id: String, _ message: String) {
        guard journal.records[id] != nil else { return }
        journal.records[id]?.phase = "paused"; journal.records[id]?.notice = message
        publish()
    }
    private func wait(_ id: String, _ message: String) {
        journal.records[id]?.phase = "waiting"; journal.records[id]?.notice = message; publish()
    }
    private func rpc(_ method: String, _ params: JSON) async throws -> JSON { try await workspace.recoveryRPC(method, params) }
    private func recover(_ id: String, generation token: UUID) async throws {
        guard var record = journal.records[id] else { return }
        try check(id, token)
        guard workspace.pendingApprovals.isEmpty else { wait(id, "Aguardando a decisão de aprovação pendente."); return }
        let canonical = URL(fileURLWithPath: record.cwd).resolvingSymlinksInPath()
        let otherSameProject = workspace.activeTasks.keys.contains { tid in
            guard tid != id else { return false }
            let other = journal.records[tid]?.cwd ?? workspace.conversations.first(where: { $0.id == tid })?.cwd
            guard let other else { return true }
            return URL(fileURLWithPath: other).resolvingSymlinksInPath() == canonical
        }
        guard !otherSameProject && !workspace.scheduledBusy else { wait(id, "Aguardando outra tarefa deste projeto terminar."); return }
        let read = try await rpc("thread/read", ["threadId": id, "includeTurns": true])
        guard let thread = read["thread"] as? JSON, let cwd = thread["cwd"] as? String,
              URL(fileURLWithPath: cwd).resolvingSymlinksInPath() == URL(fileURLWithPath: record.cwd).resolvingSymlinksInPath() else {
            throw RecoveryFailure.message("O projeto do chat não corresponde ao checkpoint.")
        }
        let turns = thread["turns"] as? [JSON] ?? []
        if record.acceptedTurnID == nil {
            guard record.baselineKnown == true, turns.last?["id"] as? String == record.baselineTurnID else {
                throw RecoveryFailure.message("O resultado do envio original não pôde ser confirmado. O chat será preservado sem reenviar a tarefa automaticamente.")
            }
        }
        if let last = turns.last {
            if last["status"] as? String == "inProgress" { wait(id, "O turno original ainda está em execução."); return }
            if let accepted = record.acceptedTurnID {
                guard last["id"] as? String == accepted else { throw RecoveryFailure.message("O chat avançou desde a falha. Confira o estado antes de retomar.") }
                if last["status"] as? String == "completed" { finished(id); return }
            }
        }
        record.operations = []
        var auxiliaryStates: [String: String] = [:]
        for turn in turns {
            for item in turn["items"] as? [JSON] ?? [] {
                let type = item["type"] as? String ?? ""
                if let status = item["status"] as? String, ["inProgress", "in_progress", "running"].contains(status) {
                    throw RecoveryFailure.message("Há uma operação ainda em execução. Confira seu resultado antes da troca.")
                }
                if type == "collabAgentToolCall" {
                    for child in item["receiverThreadIds"] as? [String] ?? [] { if auxiliaryStates[child] == nil { auxiliaryStates[child] = "unknown" } }
                    for (child, raw) in item["agentsStates"] as? JSON ?? [:] { auxiliaryStates[child] = (raw as? JSON)?["status"] as? String ?? "unknown" }
                }
                if ["commandExecution", "fileChange", "mcpToolCall", "dynamicToolCall", "collabAgentToolCall"].contains(type) {
                    let status = item["status"] as? String ?? "unknown"
                    guard !["inProgress", "in_progress", "running", "unknown"].contains(status) else { throw RecoveryFailure.message("Há uma operação sem resultado confirmado. Confira-a antes de repetir ações.") }
                    record.operations.append(CompletedOperation(id: item["id"] as? String ?? "", type: type, status: status))
                }
            }
        }
        guard auxiliaryStates.values.allSatisfy({ ["completed", "errored", "shutdown", "notFound", "interrupted"].contains($0) }) else {
            throw RecoveryFailure.message("Há um agente auxiliar sem conclusão confirmada. Confira-o antes de trocar a sessão.")
        }
        let checkpointCwd = record.cwd
        let currentDigest = try await Task.detached { try RecoveryWorkspace.digest(checkpointCwd) }.value
        if let saved = record.digest, saved != currentDigest { throw RecoveryFailure.message("O projeto mudou enquanto a tarefa aguardava. Confira as mudanças antes de retomar.") }
        record.digest = currentDigest; journal.records[id] = record; try journal.save()
        let sessionsReply = try await rpc("accountSession/list", [:])
        let sessions = (sessionsReply["sessions"] as? [JSON] ?? []).compactMap { raw -> AccountChoice? in
            guard let session = raw["sessionId"] as? String, let route = raw["selectedWorkspaceAccountId"] as? String else { return nil }
            return AccountChoice(id: session, label: raw["email"] as? String ?? "ChatGPT", active: raw["isActive"] as? Bool ?? false, workspaceID: route)
        }
        let ordered = sessions.sorted { $0.active && !$1.active }
        guard !ordered.isEmpty else { wait(id, "Nenhuma sessão oficial conectada está disponível."); return }
        for session in ordered {
            try check(id, token)
            let route = session.id + ":" + session.workspaceID
            if journal.blocked(route) { continue }
            guard record.attempted.count < 12 else { throw RecoveryFailure.message("As alternativas disponíveis já foram tentadas. A tarefa foi preservada para revisão.") }
            if !session.active && (!workspace.activeTasks.isEmpty || workspace.scheduledBusy) {
                wait(id, "Aguardando as outras tarefas terminarem para trocar a sessão global com segurança."); return
            }
            transitioning = true; workspace.accountBusy = true
            defer { transitioning = false; workspace.accountBusy = false }
            if !session.active {
                _ = try await rpc("accountSession/switch", ["sessionId": session.id, "accountId": session.workspaceID, "allowBrowserLogin": false])
            }
            let confirmed = try await rpc("accountSession/list", [:])
            guard let active = (confirmed["sessions"] as? [JSON])?.first(where: { $0["isActive"] as? Bool == true }),
                  active["sessionId"] as? String == session.id,
                  active["selectedWorkspaceAccountId"] as? String == session.workspaceID else {
                throw RecoveryFailure.message("A sessão de destino não foi confirmada. Pode ser necessário fazer login no navegador.")
            }
            let catalog = try await rpc("model/list", [:])
            let models = Workspace.parseModels(catalog)
            workspace.applyRecoverySession(confirmed, models: models)
            let orderedModels = models.sorted { $0.id == record.target?.model && $1.id != record.target?.model }
            guard let model = orderedModels.first(where: {
                let target = RecoveryTarget(session: session.id, workspace: session.workspaceID, model: $0.id)
                return !record.attempted.contains(target.key) && !journal.blocked(target.key)
            }) else { continue }
            let target = RecoveryTarget(session: session.id, workspace: session.workspaceID, model: model.id)
            try check(id, token)
            // The native thread contains the complete accepted input and completed tools.
            // Never replay the original request after an accepted turn.
            let inputs: [JSON]
            if record.acceptedTurnID == nil {
                guard let original = try JSONSerialization.jsonObject(with: record.originalInput) as? [JSON] else { throw RecoveryFailure.message("A entrada original não pôde ser reconstruída.") }
                for (path, expected) in record.attachmentDigests ?? [:] {
                    let current = SHA256.hash(data: try Data(contentsOf: URL(fileURLWithPath: path))).map { String(format: "%02x", $0) }.joined()
                    guard current == expected else { throw RecoveryFailure.message("Um anexo mudou desde o pedido original. Confira-o antes de continuar.") }
                }
                inputs = original
            } else {
                inputs = [["type": "text", "text": "Continue a tarefa original deste chat a partir do último estado confirmado. O turno anterior parou por limite do provedor. Use o histórico existente e confira o estado atual dos arquivos. Preserve as operações concluídas e seus resultados; não refaça etapas concluídas nem reenvie ações externas. Resolva somente as pendências. Se algum efeito estiver incerto, verifique-o antes de agir.", "textElements": []]]
            }
            let effectiveMode = min(max(record.mode, 0), max(workspace.mode, 0), 2)
            let safety: JSON = ["threadId": id, "cwd": record.cwd, "sandbox": ["read-only", "workspace-write", "danger-full-access"][effectiveMode],
                                "approvalPolicy": effectiveMode == 2 ? "never" : "on-request"]
            _ = try await rpc("thread/resume", safety)
            try check(id, token)
            let verifiedDigest = try await Task.detached { try RecoveryWorkspace.digest(checkpointCwd) }.value
            guard verifiedDigest == record.digest else { throw RecoveryFailure.message("O projeto mudou durante a troca. A continuação foi pausada.") }
            let beforeDispatch = try await rpc("accountSession/list", [:])
            guard let actual = (beforeDispatch["sessions"] as? [JSON])?.first(where: { $0["isActive"] as? Bool == true }), actual["sessionId"] as? String == session.id,
                  actual["selectedWorkspaceAccountId"] as? String == session.workspaceID else { throw RecoveryFailure.message("A sessão mudou durante a troca. A continuação foi pausada.") }
            record.target = target; record.requestID = UUID().uuidString; record.retryAfter = nil; record.phase = "dispatching"; record.notice = "Continuando no mesmo chat com \(session.label) · \(model.name)."
            if !record.attempted.contains(target.key) { record.attempted.append(target.key) }
            journal.records[id] = record; try journal.save(); publish()
            guard workspace.pendingApprovals.isEmpty else { wait(id, "Aguardando aprovação pendente antes de continuar."); return }
            let dispatchMode = min(effectiveMode, max(workspace.mode, 0))
            var params: JSON = ["threadId": id, "input": inputs, "model": model.id,
                                "sandboxPolicy": ["type": ["readOnly", "workspaceWrite", "dangerFullAccess"][dispatchMode]],
                                "approvalPolicy": dispatchMode == 2 ? "never" : "on-request"]
            if record.effort != "default", model.efforts.contains(record.effort) { params["effort"] = record.effort }
            let response = try await workspace.recoveryRPCEnvelope("turn/start", params)
            if let failure = response["error"] as? JSON {
                try check(id, token)
                if failed(threadID: id, turnID: nil, failure: failure) { return }
                throw RecoveryFailure.message(failure["message"] as? String ?? "A continuação foi recusada.")
            }
            guard let turn = (response["result"] as? JSON)?["turn"] as? JSON, let turnID = turn["id"] as? String else { throw RecoveryFailure.message("Não foi possível confirmar se a continuação começou. Não será reenviada automaticamente.") }
            accepted(id, turnID: turnID)
            workspace.recoveryTurnStarted(record, turnID: turnID, model: model)
            if token != generation || cancelled.contains(id) || !workspace.automaticFallback {
                _ = try await rpc("turn/interrupt", ["threadId": id, "turnId": turnID])
            }
            return
        }
        let nextReset = journal.cooldowns.filter { $0.until > Date() }.map(\.until).min() ?? Date().addingTimeInterval(60)
        journal.records[id]?.retryAfter = nextReset
        wait(id, "Sem alternativa disponível neste momento. O checkpoint foi preservado. Nova verificação após " + nextReset.formatted(date: .omitted, time: .shortened) + ".")
    }
}

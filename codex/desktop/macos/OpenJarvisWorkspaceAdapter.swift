import Foundation

// MARK: - Workspace Extension Implementing All 12 OpenJarvis Host Tool Contracts

extension Workspace {
    /// Builds a live workspace context dictionary sent alongside OpenJarvis voice turns.
    func buildOpenJarvisWorkspaceContextDictionary() -> [String: Any] {
        let activeAcc = selectedAccount ?? localDataRef?.activeAccount
        let modelDisplay = (selectedModel != "auto" ? selectedModel : models.first(where: \.isDefault)?.id ?? models.first?.id)
            ?? activeAcc?.currentModel
            ?? "auto"
        let rp = resolvedProjectContext
        return [
            "project_id": rp.projectID?.uuidString ?? "",
            "project_name": rp.projectName ?? project?.lastPathComponent ?? "",
            "project_path": rp.absoluteDirectoryPath ?? project?.path ?? "",
            "git_branch": rp.gitBranch ?? "",
            "git_repo": rp.gitRepositoryName ?? "",
            "conversation_id": selected ?? "",
            "active_agent": activeAcc?.name ?? "WisdAI",
            "active_provider": activeAcc?.provider.rawValue ?? "",
            "active_model": modelDisplay,
            "active_effort": reasoningLevel.title,
            "security_mode": modeName(),
            "active_tasks_count": activeTasks.count,
        ]
    }

    /// Dispatches one of the 12 mandatory OpenJarvis BaseTool calls inside @MainActor Workspace.
    @MainActor
    func handleOpenJarvisToolCall(name: String, params: [String: Any]) async -> [String: Any] {
        guard let tool = OpenJarvisToolName(rawValue: name) else {
            return ["ok": false, "error": "Unknown tool contract: \(name)"]
        }

        switch tool {
        case .listProjects:
            return executeListProjectsTool()
        case .getActiveProject:
            return executeGetActiveProjectTool()
        case .getProjectContext:
            return executeGetProjectContextTool(params: params)
        case .listAvailableAgents:
            return executeListAvailableAgentsTool()
        case .executeAgentTask:
            return executeAgentTaskTool(params: params)
        case .getTaskStatus:
            return executeGetTaskStatusTool(params: params)
        case .getTaskEvents:
            return executeGetTaskEventsTool(params: params)
        case .sendTaskInstruction:
            return executeSendTaskInstructionTool(params: params)
        case .cancelTask:
            return executeCancelTaskTool(params: params)
        case .getTaskResult:
            return executeGetTaskResultTool(params: params)
        case .listRunningTasks:
            return executeListRunningTasksTool()
        case .requestTaskApproval:
            return executeRequestTaskApprovalTool(params: params)
        }
    }

    // MARK: - Tool Implementations

    private func executeListProjectsTool() -> [String: Any] {
        let activePath = project?.standardizedFileURL.path
        var items: [[String: Any]] = []
        for p in localDataRef?.projects ?? [] {
            let norm = URL(fileURLWithPath: p.path).standardizedFileURL.path
            let check = ProjectContextResolver.validateDirectorySync(path: p.path)
            items.append([
                "id": p.id.uuidString,
                "name": p.name,
                "path": p.path,
                "additional_paths": p.additionalPaths,
                "is_active": norm == activePath,
                "directory_exists": check.exists,
                "directory_accessible": check.accessible,
            ])
        }
        if let activePath, !activePath.isEmpty,
           !items.contains(where: { URL(fileURLWithPath: ($0["path"] as? String ?? "")).standardizedFileURL.path == activePath }) {
            let check = ProjectContextResolver.validateDirectorySync(path: activePath)
            items.insert([
                "id": "active",
                "name": project?.lastPathComponent ?? "Workspace",
                "path": activePath,
                "additional_paths": [],
                "is_active": true,
                "directory_exists": check.exists,
                "directory_accessible": check.accessible,
            ], at: 0)
        }
        return ["ok": true, "projects": items, "count": items.count]
    }

    private func executeGetActiveProjectTool() -> [String: Any] {
        refreshResolvedProjectContext(inspectGit: true)
        let rp = resolvedProjectContext
        return [
            "ok": true,
            "project_id": rp.projectID?.uuidString ?? "",
            "name": rp.projectName ?? project?.lastPathComponent ?? "",
            "path": rp.absoluteDirectoryPath ?? project?.path ?? "",
            "additional_paths": rp.additionalPaths,
            "directory_exists": rp.directoryExists,
            "directory_accessible": rp.directoryAccessible,
            "validation_error": rp.directoryValidationError ?? "",
            "is_git_repository": rp.isGitRepository,
            "git_repository_name": rp.gitRepositoryName ?? "",
            "git_branch": rp.gitBranch ?? "",
            "conversation_id": selected ?? "",
        ]
    }

    private func executeGetProjectContextTool(params: [String: Any]) -> [String: Any] {
        let requested = (params["project"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if requested.isEmpty {
            refreshResolvedProjectContext(inspectGit: true)
            let rp = resolvedProjectContext
            return [
                "ok": rp.hasValidWorkspaceDirectory,
                "name": rp.projectName ?? project?.lastPathComponent ?? "",
                "project_name": rp.projectName ?? project?.lastPathComponent ?? "",
                "path": rp.absoluteDirectoryPath ?? project?.path ?? "",
                "directory_exists": rp.directoryExists,
                "directory_accessible": rp.directoryAccessible,
                "validation_error": rp.directoryValidationError ?? "",
                "is_git_repository": rp.isGitRepository,
                "git_branch": rp.gitBranch ?? "",
                "git_status": rp.gitWorkingTreeStatus ?? "",
                "config_highlights": rp.projectConfigHighlights,
            ]
        }

        let matched = findProjectItem(matching: requested)
        let targetPath = matched?.path ?? (requested.hasPrefix("/") ? requested : nil)
        guard let targetPath else {
            return [
                "ok": false,
                "error": "Projeto '\(requested)' não encontrado nos projetos configurados do WisdAI.",
            ]
        }
        let rp = ProjectContextResolver.resolve(
            projectID: matched?.id,
            projectName: matched?.name ?? URL(fileURLWithPath: targetPath).lastPathComponent,
            directoryPath: targetPath,
            additionalPaths: matched?.additionalPaths ?? [],
            configuredProjects: localDataRef?.projects ?? [],
            inspectGit: true
        )
        return [
            "ok": rp.hasValidWorkspaceDirectory,
            "name": rp.projectName ?? "",
            "project_name": rp.projectName ?? "",
            "path": rp.absoluteDirectoryPath ?? targetPath,
            "directory_exists": rp.directoryExists,
            "directory_accessible": rp.directoryAccessible,
            "validation_error": rp.directoryValidationError ?? "",
            "is_git_repository": rp.isGitRepository,
            "git_branch": rp.gitBranch ?? "",
            "git_status": rp.gitWorkingTreeStatus ?? "",
            "config_highlights": rp.projectConfigHighlights,
        ]
    }

    private func executeListAvailableAgentsTool() -> [String: Any] {
        let accounts = localDataRef?.aiAccounts ?? []
        let activeID = (selectedAccount ?? localDataRef?.activeAccount)?.id
        var list: [[String: Any]] = []
        for acc in accounts {
            let cliPath = acc.cliPath ?? AgentCLIAuthenticator.locateCLI(for: acc.provider)
            let bundledCodex = acc.provider == .openai
                ? (Bundle.main.url(forAuxiliaryExecutable: "codex")?.path ?? cliPath)
                : cliPath
            list.append([
                "id": acc.id.uuidString,
                "name": acc.name,
                "provider": acc.provider.rawValue,
                "is_active": acc.id == activeID,
                "supports_execution": isAccountExecutableNow(acc),
                "cli_installed": acc.cliInstalled || (bundledCodex.map { FileManager.default.isExecutableFile(atPath: $0) } ?? false),
                "current_model": acc.currentModel,
                "models": Array(acc.models.prefix(8)),
            ])
        }

        // Explicitly include real local binary availability for Codex / Antigravity / Claude Code
        let codexPath = Bundle.main.url(forAuxiliaryExecutable: "codex")?.path ?? AgentCLIAuthenticator.locateCLI(for: .openai)
        let agyPath = AgentCLIAuthenticator.locateCLI(for: .gemini)
        let claudePath = AgentCLIAuthenticator.locateCLI(for: .claude)

        let codexInstalled = codexPath.map { FileManager.default.isExecutableFile(atPath: $0) } ?? false
        let agyInstalled = agyPath.map { FileManager.default.isExecutableFile(atPath: $0) } ?? false
        let claudeInstalled = claudePath.map { FileManager.default.isExecutableFile(atPath: $0) } ?? false

        var installedNames: [String] = []
        var missingNames: [String] = []
        if codexInstalled { installedNames.append("Codex") } else { missingNames.append("Codex (not installed)") }
        if agyInstalled { installedNames.append("Gemini Antigravity") } else { missingNames.append("Gemini Antigravity (not installed)") }
        if claudeInstalled { installedNames.append("Claude Code") } else { missingNames.append("Claude Code (NOT installed)") }

        return [
            "ok": true,
            "selected_agent": (selectedAccount ?? localDataRef?.activeAccount)?.name ?? "none",
            "selected_model": selectedModel,
            "selected_effort": reasoningLevel.title,
            "security_mode": modeName(),
            "installed_agents": installedNames,
            "unavailable_agents": missingNames,
            "accounts": list,
            "installed_backends": [
                "codex": codexInstalled ? "INSTALLED at \(codexPath ?? "")" : "NOT INSTALLED",
                "antigravity": agyInstalled ? "INSTALLED at \(agyPath ?? "")" : "NOT INSTALLED",
                "claude_code": claudeInstalled ? "INSTALLED at \(claudePath ?? "")" : "NOT INSTALLED",
            ],
        ]
    }

    private func executeAgentTaskTool(params: [String: Any]) -> [String: Any] {
        let instruction = (params["instruction"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !instruction.isEmpty else {
            return ["ok": false, "error": "Instrução vazia para execute_agent_task."]
        }

        if let reqProj = (params["project"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reqProj.isEmpty {
            if let matched = findProjectItem(matching: reqProj) {
                let currentNorm = project?.standardizedFileURL.path
                let targetNorm = URL(fileURLWithPath: matched.path).standardizedFileURL.path
                if currentNorm != targetNorm {
                    project = URL(fileURLWithPath: matched.path)
                    refreshResolvedProjectContext(inspectGit: true)
                }
            } else if reqProj.hasPrefix("/") {
                project = URL(fileURLWithPath: reqProj)
                refreshResolvedProjectContext(inspectGit: true)
            } else {
                return [
                    "ok": false,
                    "error": "Projeto '\(reqProj)' não encontrado. Projetos válidos: \((localDataRef?.projects ?? []).map(\.name).joined(separator: ", ")).",
                ]
            }
        }

        if let modelOverride = (params["model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !modelOverride.isEmpty {
            selectedModel = modelOverride
        }
        if let effortOverride = (params["effort"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !effortOverride.isEmpty {
            selectedEffort = effortOverride.lowercased()
        }

        let agentStr = (params["agent"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "auto"
        let hint: VoiceSpecialistAgentHint = {
            if agentStr.contains("antigrav") || agentStr.contains("gemini") || agentStr == "agy" { return .antigravity }
            if agentStr.contains("codex") || agentStr.contains("openai") { return .codex }
            if agentStr.contains("claude") { return .claude }
            return .autoActive
        }()
        let readOnly = (params["read_only"] as? Bool) ?? false
        let risk: VoiceActionRiskTier = readOnly ? .low : .medium

        let outcome = submitUnifiedMessage(
            instruction,
            source: .voice,
            agentHint: hint,
            riskTier: risk,
            forceReadOnly: readOnly,
            enqueueIfBusy: false
        )

        switch outcome {
        case .started(let meta):
            return [
                "ok": true,
                "status": "started",
                "task_id": meta.conversationID,
                "project": meta.projectName ?? project?.lastPathComponent ?? "",
                "working_directory": meta.workingDirectory,
                "agent": meta.agentDisplayName,
                "model": meta.modelID,
                "effort": meta.reasoningEffortTitle,
            ]
        case .queued(let meta, let position):
            return [
                "ok": true,
                "status": "queued",
                "position": position,
                "task_id": meta.conversationID,
                "project": meta.projectName ?? project?.lastPathComponent ?? "",
                "agent": meta.agentDisplayName,
            ]
        case .awaitingUserApproval(let reason, let meta):
            return [
                "ok": false,
                "status": "awaiting_user_approval",
                "task_id": meta.conversationID,
                "reason": reason,
            ]
        case .blockedDirectory(let err, let dir):
            return [
                "ok": false,
                "status": "blocked_directory",
                "directory": dir,
                "error": err,
            ]
        case .unavailable(let reason):
            return [
                "ok": false,
                "status": "unavailable",
                "error": reason,
            ]
        }
    }

    private func executeGetTaskStatusTool(params: [String: Any]) -> [String: Any] {
        let reqID = (params["task_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetID = (reqID?.isEmpty == false ? reqID : nil) ?? selected ?? activeTasks.keys.first
        guard let targetID else {
            return ["ok": true, "has_active_task": false, "status": "idle", "pending_approvals": pendingApprovals.count]
        }

        let snap = executionEventBus.snapshot(for: targetID)
        let active = activeTasks[targetID]
        return [
            "ok": true,
            "has_active_task": active != nil || snap?.status == "running" || snap?.status == "waiting_approval",
            "task_id": targetID,
            "status": snap?.status ?? (active != nil ? "running" : "idle"),
            "project": snap?.projectName ?? project?.lastPathComponent ?? "",
            "agent": snap?.agentName ?? active?.accountName ?? "",
            "model": snap?.modelID ?? active?.modelName ?? "",
            "effort": snap?.reasoningEffort ?? reasoningLevel.title,
            "current_phase": snap?.currentPhase ?? active?.progressNote ?? "",
            "current_detail": snap?.currentDetail ?? "",
            "elapsed_seconds": snap?.elapsedSeconds ?? Int(Date().timeIntervalSince(active?.startedAt ?? Date())),
            "files_read": snap?.filesRead ?? [],
            "files_modified": snap?.filesModified ?? [],
            "commands_count": snap?.commandsRun.count ?? 0,
            "tests_count": snap?.testsRun.count ?? 0,
            "pending_approval": snap?.pendingApprovalDescription ?? pendingApprovals.first?.command ?? pendingApprovals.first?.reason ?? "",
            "error": snap?.errorDetail ?? "",
        ]
    }

    private func executeGetTaskEventsTool(params: [String: Any]) -> [String: Any] {
        let reqID = (params["task_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetID = (reqID?.isEmpty == false ? reqID : nil) ?? selected ?? activeTasks.keys.first ?? ""
        let limit = max(1, min(40, (params["limit"] as? Int) ?? 15))
        let evs = executionEventBus.events(for: targetID).suffix(limit)
        let serialized: [[String: Any]] = evs.map { ev in
            [
                "kind": ev.kind.rawValue,
                "title": ev.title,
                "detail": ev.detail ?? "",
                "file_path": ev.filePath ?? "",
                "command_line": ev.commandLine ?? "",
                "succeeded": ev.succeeded as Any,
            ]
        }
        return ["ok": true, "task_id": targetID, "events": serialized, "count": serialized.count]
    }

    private func executeSendTaskInstructionTool(params: [String: Any]) -> [String: Any] {
        let instruction = (params["instruction"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !instruction.isEmpty else {
            return ["ok": false, "error": "Instrução vazia."]
        }
        if let reqID = (params["task_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reqID.isEmpty,
           reqID != selected,
           let conv = conversations.first(where: { $0.id == reqID }) {
            open(conv)
        }
        let outcome = submitUnifiedMessage(
            instruction,
            source: .voiceIntervention,
            agentHint: .autoActive,
            riskTier: .medium,
            forceReadOnly: false,
            enqueueIfBusy: true
        )
        switch outcome {
        case .started(let meta):
            return ["ok": true, "status": "started", "task_id": meta.conversationID]
        case .queued(let meta, let pos):
            return ["ok": true, "status": "queued", "task_id": meta.conversationID, "position": pos]
        case .awaitingUserApproval(let reason, _):
            return ["ok": false, "status": "awaiting_user_approval", "reason": reason]
        case .blockedDirectory(let err, _):
            return ["ok": false, "status": "blocked_directory", "error": err]
        case .unavailable(let reason):
            return ["ok": false, "status": "unavailable", "error": reason]
        }
    }

    private func executeCancelTaskTool(params: [String: Any]) -> [String: Any] {
        if let reqID = (params["task_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reqID.isEmpty,
           reqID != selected,
           let conv = conversations.first(where: { $0.id == reqID }) {
            open(conv)
        }
        let cancelled = cancelActiveTaskFromVoice()
        return [
            "ok": cancelled,
            "cancelled": cancelled,
            "message": cancelled ? "Tarefa em execução cancelada." : "Nenhuma tarefa em execução para cancelar.",
        ]
    }

    private func executeGetTaskResultTool(params: [String: Any]) -> [String: Any] {
        let reqID = (params["task_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetID = (reqID?.isEmpty == false ? reqID : nil) ?? selected ?? executionEventBus.snapshotsByConversation.keys.first
        guard let targetID else {
            return ["ok": false, "error": "Nenhuma tarefa encontrada."]
        }
        let snap = executionEventBus.snapshot(for: targetID)
        let replyText: String = {
            if let md = snap?.finalReportMarkdown, !md.isEmpty { return md }
            if targetID == selected {
                return messages.last(where: { $0.author != "Você" && $0.kind == .text })?.text ?? ""
            }
            return ChatStorage.shared.loadMessages(for: targetID)
                .last(where: { $0.author != "Você" && $0.kind == .text })?.text ?? ""
        }()
        return [
            "ok": !replyText.isEmpty || snap != nil,
            "task_id": targetID,
            "status": snap?.status ?? "unknown",
            "project": snap?.projectName ?? "",
            "agent": snap?.agentName ?? "",
            "files_read": snap?.filesRead ?? [],
            "files_modified": snap?.filesModified ?? [],
            "commands_run": (snap?.commandsRun ?? []).map { ["command": $0.commandLine, "exit_code": $0.exitCode as Any, "finished": $0.finished] },
            "tests_run": (snap?.testsRun ?? []).map { ["suite": $0.commandOrSuite, "passed": $0.passed as Any, "finished": $0.finished] },
            "error": snap?.errorDetail ?? "",
            "result_markdown": String(replyText.prefix(4000)),
        ]
    }

    private func executeListRunningTasksTool() -> [String: Any] {
        var rows: [[String: Any]] = []
        for (tid, task) in activeTasks {
            let snap = executionEventBus.snapshot(for: tid)
            rows.append([
                "task_id": tid,
                "prompt": task.prompt,
                "status": snap?.status ?? task.status,
                "agent": task.accountName,
                "model": task.modelName,
                "project": snap?.projectName ?? "",
                "phase": snap?.currentPhase ?? task.progressNote,
            ])
        }
        return ["ok": true, "running_tasks": rows, "count": rows.count]
    }

    private func executeRequestTaskApprovalTool(params: [String: Any]) -> [String: Any] {
        let decisionRaw = (params["decision"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "status"
        if pendingApprovals.isEmpty {
            return ["ok": true, "has_pending_approval": false, "count": 0]
        }
        let first = pendingApprovals[0]
        if decisionRaw == "approve" || decisionRaw == "accept" || decisionRaw == "allow" {
            respondApproval(first, decision: "accept")
            return ["ok": true, "has_pending_approval": !pendingApprovals.isEmpty, "action": "accepted", "command": first.command ?? "", "reason": first.reason ?? ""]
        }
        if decisionRaw == "deny" || decisionRaw == "decline" || decisionRaw == "reject" {
            respondApproval(first, decision: "decline")
            return ["ok": true, "has_pending_approval": !pendingApprovals.isEmpty, "action": "declined", "command": first.command ?? "", "reason": first.reason ?? ""]
        }
        if decisionRaw == "cancel" {
            respondApproval(first, decision: "cancel")
            return ["ok": true, "has_pending_approval": !pendingApprovals.isEmpty, "action": "cancelled", "command": first.command ?? "", "reason": first.reason ?? ""]
        }
        return [
            "ok": true,
            "has_pending_approval": true,
            "count": pendingApprovals.count,
            "is_file_change": first.isFileChange,
            "command": first.command ?? "",
            "reason": first.reason ?? "",
        ]
    }

    private func findProjectItem(matching query: String) -> ProjectItem? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let compactQ = q.replacingOccurrences(of: " ", with: "")
        let projects = localDataRef?.projects ?? []
        if let exact = projects.first(where: { $0.id.uuidString.lowercased() == q || $0.name.lowercased() == q || $0.path.lowercased() == q }) {
            return exact
        }
        if let compact = projects.first(where: { $0.name.lowercased().replacingOccurrences(of: " ", with: "") == compactQ }) {
            return compact
        }
        return projects.first(where: { $0.name.lowercased().contains(q) || $0.path.lowercased().contains(q) })
    }
}

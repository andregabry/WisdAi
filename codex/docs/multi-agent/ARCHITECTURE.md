# Codex multi-agent architecture audit

Audited upstream revision `8703d32bd0ea5cf26768859a3dd476df906ba053`.

| Area | Upstream implementation | Integration boundary |
| --- | --- | --- |
| Authentication | `codex-rs/login` owns OAuth, device login and credential storage. CLI and app-server expose account operations. | Keep provider sign-in and credentials inside each official agent. Codex account operations keep their existing scope. |
| Execution | `core` runs Codex turns. `tools`, `exec-server`, `execpolicy` and `sandboxing` enforce tool policy. | External harnesses need their own adapter and a demonstrably equivalent execution boundary. Changing model provider still runs the Codex harness. |
| Model selection | `models-manager`, `model-provider` and app-server thread settings select models and inference endpoints. | Provider model configuration cannot represent an external harness or its session. |
| Session persistence | `thread-store`, `rollout` and `state` hold conversation, rollout and thread metadata. | Read completed turns through the app server. Keep native histories in their own stores and associate IDs through existing thread metadata if the schema permits. |
| Client API | `app-server-protocol` defines thread read/resume, turn status and approval requests. | Reuse read and resume semantics. Existing approval requests cover operations routed through Codex. |
| Migration | `external-agent-migration` and `externalAgentConfig/*` detect and import supported external artifacts, including Claude artifacts. | Useful for understanding native history mapping. Import is a one-time conversion and provides neither live execution nor bidirectional continuity. |
| Interfaces | `tui` has slash commands and an agent command center. The desktop launcher opens a separate app. | The existing CLI is the smallest public surface. A later TUI selector can reuse its service. OpenAI confirms the desktop client source is closed. |
| Tests | Cargo unit and integration tests, app-server protocol scenarios, TUI snapshots and Bazel CI targets. | Run focused suites for CLI, app-server and session storage before a real two-way handoff. |

[OpenAI maintainer confirmation about desktop source](https://github.com/openai/codex/discussions/16538)

## Claude execution boundary

The candidate design separates Claude's native interactive process from the Codex tool broker. The native process needs access to its own sign-in and session facilities. It must lack direct write access to the project and must be prevented from running arbitrary commands or reaching an alternate tool channel. Claude permission modes and MCP tool configuration are inputs to this design. An operating-system boundary and broker-side authorization are the enforcement points.

For an initial handoff, expose a narrow broker for workspace reads and patch proposals. Use the existing Codex patch safety and approval flow to execute accepted patches under the source thread's effective policy. Keep shell execution unavailable until it can use the existing command policy and approval flow. The app-server's one-off `command/exec` takes client-provided environment and permission inputs, so it is unsuitable as a direct Claude tool. Keep the broker's thread identity, path, policy and approval state under Codex control.

Before dispatch, check the source thread is idle and capture the checkpoint and Git state. Revalidate them after any user interaction and immediately before applying a patch. Record the target session ID, operation ID, decision and execution result with the source thread. Retrying a request with an already committed operation ID must return its result without executing again. Unknown outcomes must be reconciled against the workspace before a retry.

A disposable-workspace proof must cover traversal, symlinks, edits to Git internals, direct writes, shell or hook execution, cancellation, approval denial, and changed files between approval and application. Claude must remain able to sign in and use its native subscription under the same boundary. Keep handoff disabled on any platform where either enforcement or supported authentication fails.

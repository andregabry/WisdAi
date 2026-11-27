# Native project and account management

The native app is still a validation preview. Do not generate a final installer until the user's full frontend-parity gate has passed.

## Projects and conversations

The project menu exposes editing, pinning, Finder access, archiving its loaded conversations and removing its local record. Creating a project without choosing a folder creates a private workspace under `~/Library/Application Support/WisdAI/Projects/<UUID>`. Removing a project keeps its source files and conversations. Multiple source folders are represented in navigation; the active execution boundary remains the selected primary workspace and existing Codex policy.

Project and chat actions open with a secondary click (right mouse button or the trackpad equivalent) anywhere on the corresponding sidebar row. The inline ellipsis buttons were removed. Settings close from the fixed upper-right corner of the modal or with Escape.

Conversation menus expose rename, archive and permanent deletion. Deletion has a separate confirmation and uses `thread/unsubscribe` followed by `thread/delete`; a failed response leaves the conversation visible. Running tasks cannot be deleted. The local model and UI do not delete rollout files directly.

## Accounts and catalogs

Each configured profile has its own UUID. Adding the same provider twice creates two profiles; editing a profile updates the existing UUID. A profile is distinct from an authenticated execution session.

OpenAI profiles are bound to sessions returned by the official backend's `accountSession/list`. Selecting a usable profile calls `accountSession/switch`. Switching clears stale model/usage data and refreshes the catalog. `model/list` responses are accepted only for the corresponding request, active session and workspace route. Catalog caches are scoped to one profile. Existing conversation context stays in the Codex thread; no hidden model state is transferred.

DeepSeek and NVIDIA discovery send only an authenticated GET request to the provider's fixed HTTPS model endpoint. These calls do not send prompts or invoke tools. Returned models describe a catalog and do not guarantee quota or inference entitlement. API keys supplied directly to WisdAI are stored in Keychain; metadata encoding rejects plaintext credentials. Redirects are rejected. Official CLI credentials are not read, exported or copied.

Antigravity discovery invokes only `agy models` from outside the project. The observed installed CLI returned six model IDs. The desktop marks this as the global CLI session catalog with unverified profile identity, so it cannot be mistaken for two isolated authenticated Google accounts. Claude configuration references and other provider profiles remain pending authentication and execution adapters. External profiles are disabled in the execution selector. No metadata-only provider fallback is enabled.

Settings open in a native modal, with searchable categories and account setup in a nested sheet. Some settings categories remain integration placeholders and do not establish parity with all ChatGPT functionality.

## Automatic quota continuation

The native preview exposes **Continuar automaticamente ao atingir limite** in account settings. Interactive Codex turns now have a local recovery coordinator. Explicit model rate limits select another model advertised by the active session; account usage limits select another connected official session. Each switch verifies the active session/workspace and reloads its real model catalog before dispatch. This currently supports the Codex harness with official OpenAI sessions only. External CLI profiles and API catalogs are not execution adapters.

Continuation uses the same native thread, project, accepted messages and recorded tool results. After an accepted turn, the coordinator sends a continuation instruction rather than replaying the original task. Before acceptance, replay is permitted only when the native history still matches the known baseline. Unknown send outcomes, unfinished tools or auxiliary agents, changed files, pending approvals, disconnected sessions and unconfirmed authentication pause or defer recovery. Completed operation IDs and statuses are recorded; the active model is instructed to inspect uncertain effects. This prevents blind input replay but cannot promise that a model never independently repeats a semantic action.

The checkpoint stores explicit task input, attachment hashes, thread/turn IDs, project path, policy, completed operation records, content fingerprint and attempted routes in private local storage (directory 0700, file 0600). Native conversation and test outputs remain in the original thread history. Hidden reasoning and official credentials are not transferred. Ephemeral chat input is excluded from disk. Restarted checkpoints require **Conferir e retomar**, and corrupt journals are preserved. In Git projects the fingerprint covers tracked and nonignored untracked content, HEAD and status; ignored files and nested repository contents are outside that fingerprint. Projects exceeding 10,000 paths or 100 MB pause automatic recovery.

Recovery preserves or reduces the configured sandbox/approval mode and continues through native Codex tools. It never auto-accepts a pending approval. Global account switches wait for other tasks to finish. Scheduled jobs are deferred during pending interactive recovery and do not yet have their own automatic recovery checkpoint. Context-window limits, configured budgets, authentication and policy failures do not trigger quota rotation.

Cooldowns use reported exhausted-window reset times when available, otherwise 60 seconds for a model and 15 minutes for an account. Attempts are bounded to 12 alternatives per round; unavailable routes wait until a cooldown expires. Account usage is refreshed from the native backend after switching. No quota estimate is fabricated for an external provider.

Full native builds now require the compatible `codex-code-mode-host` alongside `codex`. The earlier helper-less fallback allowed conversation responses but failed local file execution for the exercised models. Startup and packaging now report the missing dependency instead of silently disabling Code Mode.

## Validation

Run from the repository root:

```sh
desktop/macos/tests/run-state-smoke.sh
desktop/macos/tests/run-recovery-smoke.sh
python3 desktop/macos/tests/thread-lifecycle.py /absolute/path/to/compiled/codex
```

The recovery smoke test uses deterministic protocol fixtures to cover model/account selection, same-thread context, accepted-input replay prevention, duplicate failures, cooldown renewal, policy preservation, stale files, unresolved operations, missing authentication, cancellation, restart and ephemeral privacy. It does not invoke inference.

An opt-in live subscription test exercises actual native inference in a disposable Git repository:

```sh
desktop/macos/tests/run-recovery-live.sh /absolute/path/to/compiled/codex
desktop/macos/tests/run-recovery-live.sh /absolute/path/to/compiled/codex --accounts
```

The first creates a conversion function, injects a quota rejection before the next request is accepted, and automatically selects another real model in the same thread to create and run three tests. It independently checks the function content and modification time, accepted request count and tests, then deletes only its disposable thread. The account variant requires two authenticated official sessions and restores the original account afterward. These tests use subscription quota; the test checks for ChatGPT authentication and does not use paid API authentication. No actual provider quota is deliberately exhausted. Mid-turn quota failure after partial operations is fixture-tested, not live-provider-tested.

The state test uses a separate defaults domain and generated fake Keychain fixture. It checks profile persistence, duplicate prevention on update, catalog separation, revoked sessions, project removal preserving files, credential encoding rejection, endpoint selection, parsers and redirect rejection. The lifecycle test uses a disposable Git repository and isolated CODEX_HOME and never submits inference.

The optimized native preview was built and signed without creating a DMG. UI checks exercised project creation, emoji selection, editing, cancellation/removal, modal settings, the real OpenAI session's catalog and nested account setup. Live two-account switching requires the user to finish the second official login. API catalog authentication requires a user-supplied key. External execution, multiple simultaneous Google sessions and complete ChatGPT parity remain unverified.

## Official references

- [Claude Code multiple-account configuration](https://code.claude.com/docs/en/authentication#log-in-with-multiple-accounts)
- [Antigravity CLI reference](https://antigravity.google/docs/cli/reference)
- [Antigravity authentication](https://antigravity.google/docs/install)
- [DeepSeek model discovery](https://api-docs.deepseek.com/api/list-models/)
- [NVIDIA hosted model endpoint](https://docs.nvidia.com/nim-operator/latest/guardrail.html)

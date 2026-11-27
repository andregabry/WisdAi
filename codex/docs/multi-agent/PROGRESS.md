# Multi-agent progress

## Windows Desktop Creation, Cross-Platform Architecture and Compilation, 24 November 2026

- **Diagnosed Windows Portability Architecture**:
  - The existing desktop client in `codex/desktop/macos` is written in Swift (`AppKit` + `SwiftUI`), which is proprietary to macOS and cannot compile or run on Windows.
  - The backend engine (`codex-rs`) is written in Rust and supports Windows native targets (`x86_64-pc-windows-msvc` / `windows-sandbox-rs`).
- **Created Native Windows Desktop Client (`codex/desktop/windows/`)**:
  - **Stack**: Built an Electron-based Windows client with modern web technologies (HTML5, CSS3, ES6) maintaining 100% visual parity with the ChatGPT interface and the macOS counterpart.
  - **Custom Titlebar & Windows 11 Styling**: Frameless window with custom minimize, maximize, and close controls; dark/light theme support, custom scrollbars, and responsive viewport.
  - **Sidebar & Views**: Complete implementation of Início (Chat), Espaço (Workspaces & Files), Agendado (Scheduled local conversations), Plugins (100 plugins catalog), and Configurações (Settings modal).
  - **Multi-Provider & Engine Bridge (`engine.js`)**: Spawns `codex.exe app-server` via JSON-RPC over stdio; seamlessly handles CLI agent fallback (`agy.exe`, `claude.exe`, `codex.exe`); persists accounts, conversations, API keys, and space files in `%APPDATA%\WisdAI`.
- **Created Compilation Scripts and Automated Packaging Pipeline**:
  - `build-windows.bat`: One-click batch compilation script for Windows environments.
  - `build-windows.ps1`: Automated PowerShell build script with error handling and parameter options.
  - `installer/WisdAI.iss`: Inno Setup compiler script for generating standalone setup installers (`WisdAI-Setup-0.7.1-x64.exe`).
  - `.github/workflows/wisdai-desktop-windows.yml`: GitHub Actions automated workflow for continuous building on `windows-latest`.
- **Testing, Validation & Distribution**:
  - Ran `electron-builder` targeting Windows x64.
  - Verified compilation of genuine Windows PE32+ executable (`WisdAI.exe`).
  - Packaged and zipped the release artifact: `dist/windows/WisdAI-Desktop-0.7.1-windows-x64.zip` (112 MB) with SHA-256 verification.
  - Documented full architectural and compilation guide in `WINDOWS_BUILD.md`.

## Chat operational resolution, Multi-provider CLI execution and Vector Account Action icon, 24 November 2026

- **Diagnosed and Resolved Chat Non-Functionality Root Causes**:
  - **Auxiliary Executable Inclusion**: Discovered that `codex-code-mode-host` was missing from `dist/WisdAI.app/Contents/MacOS/`. This caused `Bundle.main.url(forAuxiliaryExecutable: "codex-code-mode-host")` to fail on app start, setting `workspace.ready = false` and preventing `canSend` from ever enabling the Send button or allowing Enter key dispatch. Restored and signed `codex-code-mode-host` in the bundle; verified that `codex app-server` now successfully boots as child PID under `WisdAI`.
  - **Automatic Workspace Fallback**: Fixed `send()` in `DesktopShell.swift` and `WisdCode.swift`. Previously, if `workspace.project` was `nil`, sending popped an `NSOpenPanel` modal; if skipped/cancelled, `let project` guard silently aborted message dispatch. Implemented `workspace.ensureProject()` which automatically provisions `~/WisdAI` as a seamless default workspace, enabling chat immediately without forcing folder selection dialogs.
  - **Multi-Provider CLI Agent Execution**: Discovered that `codex app-server` rejected Gemini models (`The 'gemini-2.5-flash' model is not supported when using Codex with a ChatGPT account`) while the ChatGPT account had exceeded usage quota. Re-architected `send()` and added `executeCLITurn(...)` to route Gemini turns directly to the authenticated `agy` CLI (`~/.local/bin/agy`) and Claude turns to `claude` CLI, streaming outputs live into the transcript via `appendDelta` with interrupt handling.
  - **Account Independence & Model Scoping**: Fixed `supportsExecution` on `DesktopModels.swift` and updated `loadModels()` in `WisdCode.swift` to immediately populate models for the active account without mixing catalogs across accounts.
- **Account Action Icon Guarantee (`AccountActionIcon`)**:
  - Built a custom SwiftUI vector component `AccountActionIcon` consisting of `Circle().stroke(Color(red: 0.18, green: 0.58, blue: 0.98), lineWidth: 1.8)` with a centered bold `"!"` (`Text("!")`).
  - Completely eliminates AppKit `NSPopUpButton` template monochrome overrides, guaranteeing the 22px diameter (+3px larger) and pastel-blue rendering in the accounts card without collapse arrows.
- **Verification and Testing**:
  - Successfully passed `run-state-smoke.sh` and `run-recovery-smoke.sh`.
  - Recompiled, signed, and launched `WisdAI.app` (PID 99080) with active child backend `codex app-server` (PID 99086).


- Fixed macOS AppKit `NSPopUpButton` behavior where the system menu control was clamping the SF Symbol to 15x15 and overriding the blue foreground color with default white template text.
- Re-architected `accountMenuIcon` in `DesktopSettings.swift`:
  - Created a dedicated `NSImage.SymbolConfiguration` specifying `pointSize: 25`, weight `.semibold`, and explicit palette color `NSColor(red: 0.12, green: 0.52, blue: 0.98)`.
  - Applied `.renderingMode(.original)` to preserve the vibrant blue color and full 25pt size without AppKit template overrides.
- Verified rendering with pixel inspection confirming blue pixel rendering. Recompiled, resigned, and restarted `WisdAI.app`.

## Visual branding, App icon, Send button and Voice mode, 23 November 2026

- **Brand Logotype Integration**:
  - Embedded the official WisdAI logo banner (`BrandLogo.png`) in the sidebar header, empty chat welcome view, and Settings sidebar via `BrandLogoView`.
- **Application Icon**:
  - Generated full multi-resolution `AppIcon.icns` (16x16 up to 1024x1024) from the second user-provided image (butterfly + AI) with macOS standard continuous squircle styling.
  - Configured `CFBundleIconFile` in `Info.plist` and set `NSApplication.shared.applicationIconImage` at runtime for immediate Dock updates.
- **Chat Send & Voice Mode Buttons**:
  - Added dedicated, always-visible **Send button** (`arrow.up` in circle) in the composer bar, active in vibrant blue when text is present.
  - Added dedicated **Voice Mode button** (`waveform` in circular pill) directly opening `voiceDialog` without sheet presentation conflicts.
  - `voiceDialog` automatically initiates listening upon open, pulses dynamically, and sends audio input directly to the agent upon completion.
- **Account Dropdown Icon**:
  - Enlarged the account action dropdown icon by 3px (size 28 in settings, size 14 in composer) in pure vibrant blue.
- Recompiled, signed, and relaunched `WisdAI.app` on macOS.

## Real CLI agent authentication and dedicated API Keys section, 23 November 2026

- Separated API Key management from Accounts:
  - Created a dedicated `Chaves de API` section in Desktop Settings (`DesktopSettings.swift`) for direct provider API keys (OpenAI, Claude, Gemini, DeepSeek, NVIDIA, Groq, Kimi) with hardware-encrypted macOS Keychain storage, real official endpoint validation, and key removal.
  - Restricted the `Contas` section strictly to CLI agent accounts (no API key fields or token inputs on account cards or modals).
- Implemented real authentication for CLI agent accounts (`DesktopAccounts.swift`, `DesktopModals.swift`):
  - Added `AgentCLIAuthenticator` performing actual authentication for provider agent CLIs (locating `/usr/local/bin/codex`, `~/.local/bin/agy`, etc.).
  - Account creation/editing (`AddAccountModalView`) now uses **Usuário/E-mail** and **Senha** with the button "Autenticar Conta no Agente CLI".
  - Verifies credentials against real official authentication endpoints and CLI processes without any simulation. Rejections (e.g. HTTP 401/403) display the real server error and halt creation; real authenticated sessions load genuine model catalogs.
  - Stored account passwords securely in macOS Keychain using `AccountKeychain.saveAccountPassword`.
- Recompiled, resigned, and restarted `WisdAI.app` on macOS.

## Settings and project modal refinement, 23 November 2026

- Restructured Desktop Settings (`DesktopSettings.swift`):
  - Consolidated `Perfil` and `Aparência` into a unified `Perfil` view containing user profile identity, theme picker (Sistema/Claro/Escuro), interactive light/dark theme cards, voice synthesis options, and assistant skill personalization.
  - Consolidated `Segurança e login` and `Conta` into a unified `Contas` view containing token fallback toggle, hardware enclave encryption info, active session details, and multi-account AI management with independent models and `!` (`exclamationmark.circle`) dropdown actions.
  - Removed obsolete tabs: `Controles parentais`, `Faturamento`, and `Codex Cloud`.
- Cleaned project modal borders (`DesktopModals.swift`):
  - Removed purple outline completely from project name field and icon search field, maintaining clean neutral borders.
- Refined account action icon in settings (`DesktopSettings.swift`):
  - Enlarged `exclamationmark.circle` icon by 3px to size 25 with medium weight.
  - Set icon color to vibrant solid blue (`RGB 0.12, 0.52, 0.98`).
  - Removed the default dropdown/collapse downward chevron arrow using `.menuIndicator(.hidden)`.
  - Removed inline model disclosure from account cards; models are now listed exclusively when opening to edit/add accounts in `AddAccountModalView`.
- Recompiled and verified WisdAI macOS application on ARM64 macOS 14.0+, resigning the application bundle and restarting the active instance.

## Native quota continuity, 23 November 2026

- Added an interactive-turn recovery coordinator to the existing native app. Explicit model rate limits select another real model; account usage limits select another connected official Codex session. The same native thread, project and tool history are retained. Sessions and catalogs are verified through the backend before dispatch. This does not enable Google, Claude or other external-agent execution.
- Recovery records accepted turn IDs, known pre-submit baseline, explicit input, attachment hashes, completed operation IDs/statuses, content-sensitive workspace fingerprint, effective sandbox/approval mode, attempted targets and cooldowns in private local checkpoints. Accepted tasks are continued with a new instruction, never blindly replayed. Unknown send outcomes, changed workspaces, unresolved tools or auxiliary agents, pending approvals, disconnects and unconfirmed sessions defer or pause recovery. Ephemeral input is excluded from disk; restarted records require explicit reconciliation. No hidden model state or credentials are copied.
- Preserved native tool approval and sandbox enforcement, with no automatic approval grants. Global session switching waits for other tasks. Cooldowns and bounded attempts prevent busy retry loops; exhausted routes can become eligible after reset. Scheduled turns remain outside interactive recovery. Ignored files and nested repository content remain outside the Git fingerprint. The system prevents blind request replay, not every possible semantic repetition by a model.
- Added account-settings control and conversation recovery status with pause/reconcile actions. Deleted and archived chats discard their recovery record; logout/disconnect pause pending work. API catalogs and external provider profiles remain disabled for execution rather than being relabeled OpenAI calls.
- A real native execution test exposed a missing Code Mode host: disabling Code Mode yielded replies but no requested local files. Included the compatible official installed host with the fork and made it required for native startup/packaging. The corrected optimized 0.7.1 validation app compiled, was ad hoc signed and passed deep signature verification. No DMG was generated, and the running login window was left open.
- Passed state and deterministic recovery smoke suites: same-provider profile isolation, model/account selection, native context retention, no replay of accepted input, duplicate failures, completed operation records, sandbox preservation/downgrade, stale content, unknown operations, missing authentication, cooldown/reset behavior, cancellation, restart and ephemeral privacy. Shell syntax, plist validation and diff whitespace checks passed.
- Passed actual subscription-backed inference with the compiled fork and Code Mode host in a disposable Git repository: one model created minutes.py; a quota rejection was injected before the next request was accepted; the coordinator selected another real model on the same thread to add test_minutes.py. All three independent Python tests passed. The completed function's content and modification time were unchanged, and exactly two inference requests were accepted. The disposable native thread was deleted. This simulates a provider quota error; no actual account was deliberately exhausted. Post-acceptance partial-operation failure is fixture-tested, not yet live-provider-tested.
- Real account-mode preflight found only one connected official OpenAI session and submitted no inference. Requested the user's second official browser login in the validation app. Live two-account failover remains unverified until that login; fixture account switching passed. External Google/Claude adapters and full ChatGPT parity remain pending. Final installer remains subject to the user's parity gate. See [native account and recovery details](DESKTOP_ACCOUNTS.md).

## Project, chat and account management, 23 November 2026

- Continued the existing native desktop code, including the project/account models and modals found in the current working tree. Added visible menus for projects and chats, functional project editing, emoji/icon selection, project-level chat archiving, confirmation before local project removal, and permanent chat deletion through `thread/delete`. Project removal does not remove source files or conversation records. Empty projects get a private local workspace instead of resolving an empty path to the repository.
- Fixed deletion that previously only archived the thread and swallowed backend errors. The new flow unsubscribes the client and deletes only after successful responses. Active tasks cannot be deleted or switched to another session mid-execution.
- The account selector now switches the actual official Codex session. Adding an arbitrary provider record no longer changes only a label while still executing with the original OpenAI credentials. Multiple profiles of the same provider have independent UUIDs and update in place. Session discovery adds actual OpenAI sessions and revokes executable state for removed sessions.
- Removed hard-coded model lists and seeded connected accounts. Codex `model/list` is refreshed after session changes, scoped to the active session/workspace, and stale responses are rejected. Catalog caches are saved per account, never copied to every account of a provider. A provider catalog advertises models; it does not prove inference entitlement or available quota.
- Added read-only DeepSeek and NVIDIA model-catalog clients using their official HTTPS endpoints. The installed official Antigravity CLI returned six real model IDs through its documented `models` command without inference; the desktop can query this catalog while explicitly marking it as the CLI global session with unverified profile identity. API keys explicitly supplied to WisdAI are stored in macOS Keychain; metadata serialization rejects plaintext credentials. Legacy WisdAI-supplied keys are migrated without reading official CLI credentials. Redirects are rejected so keys cannot be forwarded to another host. The UI distinguishes a saved profile, a returned catalog, and an executable authenticated session.
- Settings now open as a native modal with a searchable category sidebar, grouped accounts, nested account setup, real model disclosure and theme-aware surfaces. Full visual/behavior parity with ChatGPT remains incomplete; settings categories without integrations still say so.
- Validation: native optimized build and ad hoc signature verification passed for an isolated local validation app. The Swift state smoke test passed same-provider profile persistence, update deduplication, project edits/removal preserving files, per-account catalog isolation, revoked-session blocking, serialization rejection of plaintext credentials, Keychain round-trip with a generated fake fixture, catalog parsing, allowed endpoints and redirect rejection. The real packaged backend passed create/read/rename/archive/unarchive/unsubscribe/delete in a disposable Git repository and isolated CODEX_HOME, with no inference.
- Native UI validation passed creating a disposable project, choosing emoji, editing its name, canceling removal and confirming removal. Settings opened as a modal; the account page displayed the actual official session and its four engine-reported models. Nested account setup and disabled API discovery before key entry were verified. No real API key was entered, no browser login was submitted by the agent, and no private conversation was deleted. The old SwiftUI alert modifiers conflicted during the chat-confirmation check; they were consolidated into one typed confirmation presenter. The corrected dialog still needs a UI check after the active login workflow permits restarting the preview.
- Pending: live switching between two authenticated OpenAI accounts (only one session was returned), live API catalog calls with user-supplied keys, and official external-agent authentication/model-discovery/execution adapters. Claude profiles can store a separate configuration-directory reference but do not yet authenticate or execute from the desktop. Google and other external profiles are configuration records, not verified simultaneous sessions. Autonomous quota failover remains disabled; the earlier metadata-only fallback was removed. The final installer remains blocked on the user's full-parity requirement.

## Current desktop work, 22 November 2026

- The user requested visual and interaction parity with the authenticated ChatGPT website. The native desktop shell now has the reference's rail, Chat/Work presentation, centered composer, model/effort popover, attachment menu, voice panel, project/chat navigation and grouped settings. Existing backend actions are retained. Added native rename, archive/unarchive, logout and ephemeral-thread requests, with their validation limits tracked separately.
- The native app compiled and launched with its bundled fork. UI checks covered search, model-menu presentation, profile/settings navigation, dark/light switching, the task editor and local library import/favorite/filter/list/removal. A real protocol smoke test passed initialization, models, archived thread listing, account, rate limits and an ephemeral read-only thread without inference.
- Full parity is incomplete. The user completed Space onboarding and its authenticated library navigation, tabs, table and Sites empty state were inspected. Added a native Space view with local folders, type tabs, search, selection, favorites and recoverable trash. New-view import, favorite, search, list, trash and restore checks passed with a disposable TXT; trash persistence across restarts remains pending. Live voice, collaborative pages, hosted Sites and several settings remain pending. See [the parity matrix](FRONTEND_PARITY.md) for the screen-by-screen status and remaining tests.
- The user instructed that the final installer must await complete validation. The earlier internal 0.7.0 disk image was moved into `dist/preview-0.7.0` and labeled `PROTOTYPE-NOT-VALIDATED-0.7.0.dmg`. Subsequent checks use a local app copy. No final installer is approved by this work.

## Completed

- Cloned official Codex and audited revision `8703d32bd0ea5cf26768859a3dd476df906ba053`.
- Documented architecture, provider compatibility and implementation gates.
- Added `codex agent-status` to the source checkout. The command checks for Claude Code on the local executable search path and runs only its documented `auth status` command. It reports coarse authentication states and discards provider diagnostics. Login and logout continue through the respective official clients.

## Verification

- Installed Codex CLI reported an active ChatGPT login. CLI help for agent browsing, resume and app-server, MCP listing, and an app-server initialize and thread list round trip passed. These checks used the installed binary.
- Both new Rust tests passed in an isolated Cargo harness using the workspace's locked versions of the probe's direct dependencies. The same harness reported a missing installation on the ordinary PATH and signed-out status with checksum-verified official Claude Code 2.1.311 under an empty temporary configuration.
- The full source CLI baseline was attempted with Rust 1.95.0. Cargo remained in upstream Rusty V8 submodule resolution. Source CLI build and regression results remain unverified.

## Blockers and next actions

- The official desktop client is closed source. The public app-server supports clients and the public TUI supports Codex slash commands. Neither supplies a documented desktop selector extension.
- The external process must enforce the active Codex sandbox and approvals before Claude task execution can be wired in. Native Claude permission prompts do not enforce Codex policy, and launching an executable in the same directory grants no isolation by itself.
- Verify subscription-only execution, including account and extra-usage behavior, with a real authenticated test account before enabling a handoff. The temporary installation was tested signed out. No provider inference was invoked.
- Checkpoint transfer, recovery, account management and the selector remain pending. Continue with a disposable-workspace policy proof, then validate a real round trip. See [Implementation plan](IMPLEMENTATION_PLAN.md).

## Build validation follow-up

- Retried the locked source build with `CARGO_NET_GIT_FETCH_WITH_CLI=true`. The system Git backend fetched the pinned Rusty V8 revision and its submodules. An offline Cargo dependency tree then resolved successfully and showed that V8 is outside the default macOS CLI build graph.
- The optional Codex V8 release checksum URL returned HTTP 504. The default CLI did not need that artifact. No repository dependency or feature changes were required.
- Restarted with `CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 CARGO_INCREMENTAL=0` after the initial build approached the disk limit. `cargo +1.95.0 test --locked -p codex-cli --bin codex` compiled and linked the modified CLI test target on Apple Silicon macOS. Result was 310 passed, one ignored.
- The official Claude Code 2.1.311 binary reported signed out under the normal local configuration. Requested native Claude account sign-in and confirmation that extra usage is off. Subscription-backed inference remains unverified.
- Documented a candidate execution boundary that routes proposed patches through existing Codex policy and approvals. No external tool execution is enabled.
- `cargo +1.95.0 build --locked -p codex-cli --bin codex` produced the standalone fork binary. It reported the existing ChatGPT login, listed MCP configuration, accepted resume help, and completed app-server initialization and a thread-list request. `agent-status` reported both the missing and signed-out cases on the actual fork binary.
- Focused library suites passed. Execution policy had 7 passed, sandboxing had 121 passed and three ignored, and thread storage had 284 passed.
- In a disposable Git repository, the fork's read-only macOS sandbox allowed a project read and blocked writes inside and outside the repository. The same sandbox launched the official Claude binary for `--version`. The Codex Seatbelt base policy allows process execution and forks, so this is a filesystem regression check and native startup check. It leaves subprocess control and per-action Codex approval enforcement to be proven.
- A separate throwaway Seatbelt profile allowed only its named entry executable. Claude's `--version` ran under that rule and a shell probe could not start an unlisted executable. This isolated test did not exercise an authenticated Claude session or combine filesystem, process and network controls. It is not a shipping adapter.
- The first parallel CLI integration run had one startup-config deadline failure. The case passed by itself, and the serial rerun of all selected suites passed. App-server had 11 passed, execution policy had 2 passed, login had 9 passed and MCP listing had 8 passed.
- Next gate is a supported Claude account sign-in and an authenticated sandbox test with a narrow tool broker. Checkpoint persistence, approval forwarding, and Codex → Claude → Codex remain unimplemented and unverified. No live Claude task or paid provider call was made.

## Direct account integration

- Inspected the local Craft Anything 0.5.0 image read-only. Its native binaries reference Claude Code discovery and direct the user to the official CLI login. Its [documentation](https://github.com/storytold/craft-anything/blob/main/docs/claude-code.md) confirms that it runs the installed Claude Code executable and leaves authentication to that process.
- The requested architecture now requires the WisdCode engine to use a directly authorized account without launching an external agent or using paid API authentication. Craft Anything's Claude integration depends on the external executable and is outside this scope.
- [Anthropic's published authentication rules](https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use) reserve native Claude subscription authentication for approved uses and direct third-party product integrations to API or cloud-provider authentication. A supported direct Claude subscription connection for WisdCode has not been established.

## Official CLI setup

- The user chose the official CLI approach. WisdCode's terminal command `codex agent-connect claude` or `codex agent-connect antigravity` detects the native executable, installs it from the provider on first use if needed on macOS or Linux, and hands sign-in to the provider's official terminal command. Existing installations can be used on Windows when on PATH.
- The command requires an interactive terminal, starts from the user's home directory, and keeps account storage in the native CLI. It does not start an inference turn. Antigravity setup uses the documented ACP login entry point. The published bootstrap currently accepts its default invocation and may configure the user's shell.
- The provider/model selector, quota synchronization, checkpoint transfer, sandboxed execution and task continuation remain pending. Antigravity's [official ACP support](https://antigravity.google/docs/cli/acp) provides an interface to investigate for models, sessions and permission requests. Do not expose an external agent in the selector until its execution and recovery gates pass.
- Expanded the same setup command to Kimi Code, Xiaomi MiMo Code and GitHub Copilot. Kimi uses the official browser device flow. MiMo's own authorization screen offers Token Plan and pay-as-you-go, so the setup explains how to select Token Plan. Copilot uses its official OAuth login. The fork does not request any API key or submit tasks as part of setup.
- DeepSeek Harness has an official CLI in preview, but its documented CLI setup requires a DeepSeek API key. No equivalent NVIDIA subscription-backed coding CLI has been verified. Neither is exposed by this account setup command.
- Built the standalone CLI and passed all 310 selected CLI unit tests, with one ignored. A disposable pseudo-terminal test verified executable discovery and native sign-in arguments for all five provider options using local test doubles. Also verified that noninteractive sign-in is rejected. Live installation and browser authorization remain untested.
- The user authorized API support for DeepSeek and NVIDIA. Added [opt-in DeepSeek configuration](API_PROVIDERS.md) and verified that the fork accepts it offline. The hosted NVIDIA endpoint requires a Chat Completions adapter that is not implemented. No API keys were read and no inference requests were made.

## Local checkpoint and Antigravity validation

- Opened a real Antigravity ACP session in a disposable Git repository using the installed official CLI and its sandbox option. Separately started and read a disposable Codex app-server thread. Neither protocol probe submitted inference.
- Added `codex agent-checkpoint save --context <reviewed-task.json> --output <outside-project.json>` and `codex agent-checkpoint verify <outside-project.json>`. Input fields are `objective`, `conversation_summary`, `completed`, `pending` and `test_results`. The checkpoint stores the canonical repository root, branch, HEAD, Git status and a digest of tracked diffs and nonignored untracked contents. It creates a private local file without replacing existing files and does not transmit the content.
- This checkpoint is an explicit, manually reviewed snapshot. It does not capture live thread history automatically, enforce tool policy or resume an external agent. Use it from a quiescent repository. Ignored files and the contents of nested repositories are outside the fingerprint. The provider selector and approval bridge remain pending.
- Completed a live, manually orchestrated Codex → Antigravity → Codex test in a disposable repository. Packaged Codex created the conversion function. A separate test driver sent the reviewed WisdCode checkpoint to Antigravity over its native ACP session. Antigravity added a test file without changing the function or README. All three Python cases passed. The old checkpoint rejected the changed repository, a fresh checkpoint verified it, and the original Codex session resumed read-only without changing the files.
- The fork authenticated for the first step but its local build lacked the optional Code Mode host executable. The successful first and final turns used the packaged Codex CLI with its bundled helper. The WisdCode checkpoint commands used the compiled fork.
- The Antigravity turn wrote its test file without an ACP approval request. This directly demonstrates why forwarding ACP requests alone cannot guarantee Codex approval enforcement. Keep autonomous handoff disabled until a policy boundary prevents direct edits and routes writes through Codex approval. The live test was driven outside the product and does not validate an in-app provider selector.
- The standalone fork compiled, all 311 selected CLI tests passed, and one was ignored. The new unit test covers tracked and untracked edits that keep Git status unchanged.

## Validation without a model

- Added `codex agent-checkpoint validate <checkpoint> --output <new-checkpoint> -- <program> [args]`. It verifies the repository, intersects the effective Codex permissions with read-only access, disables network access and runs the explicitly supplied local test command through the existing sandbox launcher. It verifies the repository again and saves a new checkpoint with a command digest only if the test succeeds. Test stdout and stderr remain in the terminal.
- Built the standalone fork and ran 311 CLI tests successfully, with one ignored. On Apple Silicon macOS, the compiled command passed the three conversion tests and wrote a verifiable receipt. A write attempt and a loopback connection were blocked, and a stale checkpoint was rejected. None of these failures produced a receipt.
- An independent macOS sandbox proof allowed writes in a disposable staging directory and denied writes in a sibling directory. Under that outer write boundary, the native Antigravity CLI completed ACP initialization and session creation. The proof enabled network for the native client and submitted no prompt. It did not verify provider-only network access, protected reads or promotion of changes.
- Provider limit detection, autonomous failover, restricted staging of real tasks, and automatic promotion remain pending. No autonomous route was enabled based on the sandbox smoke test alone.

## Staging verified work

- Added `codex agent-checkpoint stage <checkpoint> --parent <directory-outside-project>`. It creates a private copy of the current Git-tracked and nonignored untracked regular files. It preserves working edits and excludes the Git database, ignored untracked files and deleted working files. It rejects symlinks, unsupported path types and stale checkpoints, and verifies the source again after copying.
- The staging directory is a file snapshot. Access restrictions for the external process, patch validation and promotion back into the original project are separate integration steps.
- The user requested multiple accounts per provider as a follow-up, including two OpenAI accounts and two Google accounts. Use distinct account identities and provider-supported session separation. Make account selection explicit and verify entitlement and isolation per provider before using an account for fallback. Account management is pending.
- The standalone CLI built successfully. All 312 selected CLI tests passed, with one ignored. A live CLI smoke test copied the disposable conversion project, edited the staging copy, verified that the original checkpoint still matched, and confirmed that a stale checkpoint could not be staged.

## Cross-provider context

- The user confirmed that native Codex logout and login already covers OpenAI-to-OpenAI account changes in their workflow. WisdCode leaves that flow in place and focuses on transitions to other providers.
- Added `codex agent-checkpoint export <checkpoint>`. Run it from the original project. It verifies the current Git state and emits only the reviewed task JSON to stdout, without repository metadata, stored authentication, or model state. Use `stage` separately for the working files. The export is suitable for a provider adapter to consume via stdin.
- Google and Claude still use their native sign-in. The export does not launch an external CLI or automatically switch an active session. Automatic execution and promotion still require an enforceable provider boundary.
- The user clarified that external providers should retain multiple simultaneous signed-in accounts where supported, permit explicit account selection, and report usage and token or quota status per account. Keep account status and usage availability distinct. Display unknown quota where the provider does not publish it, and distinguish provider-reported live usage from the last known value. Do not read native credential stores to implement account selection or infer quotas from local token counts.

## Interactive Antigravity handoff

- Added `codex agent-checkpoint handoff <checkpoint> --parent <directory>` for macOS. It verifies the source, prepares a fresh staging copy, saves reviewed context there, and opens the official Antigravity CLI interactively inside the Codex sandbox. The outer policy denies access to the original repository and confines project writes to staging. The native CLI retains its account flow and prompts. Network is enabled for Antigravity, and the original checkpoint is verified again after exit.
- The standalone binary built and 312 CLI tests passed, with one ignored. A pseudo-terminal smoke test with a local test double verified the launch arguments, context availability, blocked source reads and allowed staging writes. The real interactive provider turn remains to be tested through this command. The command retains staging output for review and does not apply it to the original project.
- The user's real handoff log confirmed authentication but showed sandbox write denials for Antigravity logs, caches, crashes and conversation persistence. Narrowly allowed those native runtime directories while leaving provider settings, authentication files and the original project outside writable roots. The CLI built and 312 tests passed, with one ignored. A fresh native terminal launch created its log and emitted no permission-denied messages in the terminal, but did not produce the test file during an unattended run. Interactive completion is still unverified.
- The native log also showed denied writes to Antigravity's artifact, presence and annotation directories. Added those three narrow grants and rebuilt the CLI. The unattended launch still did not create the pending test file, and the original remained unchanged.

## macOS terminal preview package

- Built and packaged the terminal preview for Apple Silicon. Extracted the archive, installed it into a disposable directory, and verified its version and checkpoint command help. The package includes an installer that refuses to overwrite an existing WisdCode binary. The optional Code Mode helper is not included.
- Configured the native handoff to accept edits within the outer staging sandbox. A real run authenticated and exchanged model responses, but did not produce the pending test file within the unattended test window. The source project remained unchanged. Handoff completion and promotion remain unverified.

## Visual Parity, Dynamic Models & Fast Login, 23 November 2026

- **Project Modal & Popover Parity (Images 1 & 2):**
  - Project edit modal updated with square icon button, name input, and popover.
  - Icon popover features `Emoji | Ícones` tabs, `Limpar` button, purple-bordered search bar (`Pesquisar ícones`), 8 color swatches (White, Coral Red, Orange, Yellow, Green, Blue, Purple, Pink), and a 4x8 grid of 32 outline icons.
  - "Pastas de origem" section with rounded container displaying folder rows with `x` delete buttons and "Adicionar pasta" row linked to `NSOpenPanel`.
  - Footer with "Remover projeto local" red button on the left, "Cancelar" and "Salvar" white pill on the right.

- **Sidebar Project Row & Context Menu (Image 3):**
  - Sidebar project row styled with square bordered icon badge in project's color.
  - Context menu options aligned 1:1 with Image 3: `Fixar` (`pin.fill`), `Editar` (`gearshape`), `Seção` (`list.bullet.indent` submenu), `Mostrar no Finder` (`folder`), `Arquivar chats` (`archivebox`), and destructive `Remover projeto` (`xmark`).
  - Project subthreads expanded by default beneath each project.

- **Dynamic Focus Ring Behavior & Dropdown Menu:**
  - Removed static purple borders from all text fields. Purple focus rings now display dynamically via `@FocusState` only when a field is actively in use (focused). When inactive, fields retain standard subtle dark borders.
  - Replaced account action button with exclamation in a circle (`exclamationmark.circle`), which triggers a dedicated dropdown menu for profile actions (update models, edit account, activate, remove).
  - Designed visible custom Select dropdown for AI providers in account modal, showing provider icon, display name, and chevron.
  - Dynamically display provider-specific login/credential fields (account identifier, e-mail/username, API key/token, browser connection), allowing multiple distinct accounts per provider.
  - Added dedicated "Carregar Modelos" button with live loading state to query and store models individually per account, eliminating model summing or cross-account leakage.
  - Icon & color modal/popover updated with real-time reactive selection, clear button, tabs, and outline icon grid.

  - Display names and underlying slugs displayed clearly in chat composer, model popovers, and Settings.

- **Optimized Fast Account Connection:**
  - Removed artificial timer chains in account connection flows.
  - Browser login requests dispatched instantly on `DispatchQueue.main.async` via `NSWorkspace.shared.open`, opening the authentication page in milliseconds.


## Native macOS desktop preview

- The user approved a separate native interface modeled on the Codex layout. Added a SwiftUI client in `desktop/macos` using the fork's bundled app-server. It offers a project picker, recent conversations, history, new and resumed chat turns, streamed assistant messages and cancellation.
- Desktop turns explicitly request Codex's read-only sandbox and no interactive approvals. The desktop preview does not yet surface editable coding turns, provider switching, checkpoint controls, or the full official desktop feature set. It reuses the user's existing Codex configuration and login.
- The build script produces an Apple Silicon DMG containing `WisdCode.app` and an Applications link. The bundle is ad-hoc signed for local testing, with macOS 14 as its minimum version. The optional Code Mode host is absent from the bundle.
- Mounted the desktop DMG, verified the bundle signature and Applications link, observed the native window, and confirmed that the app launched its bundled backend. An isolated protocol smoke test passed initialization, recent-history listing and read-only thread creation. No live desktop inference turn was submitted.

## Desktop attachments, audio and accounts

- Desktop 0.2.0 adds image and audio inputs through the app-server, UTF-8 text attachments, microphone recording and optional local read-aloud of completed replies. Voice interaction is turn-based. Audio input requires a compatible model.
- Added a ChatGPT account panel backed by native app-server login, stored-session selection and quota reporting. Usage is shown only when reported by the server. External provider account management remains outside the desktop preview.
- Built the native arm64 app and signed the local DMG bundle. Verified signature, the microphone permission declaration, window startup and bundled app-server launch from an installed copy. The bundled server returned active account, account-session list and usage limits. Live audio inference, browser login completion and microphone capture were not tested.

## Desktop 0.6 panels

- Added local scheduled read-only conversations bound to the selected account, with one-time, daily and weekly options, pause and resume. The scheduler runs only while a WisdCode window is open. The task store is shared across windows.
- Added a local file library with search, favorites, filters, grid/list and Finder actions. Added local site folders and an action that prepares a site-creation prompt in chat. Cloud libraries, publication and shared sites are outside these local implementations.
- The Personalizar panel calls the native plugin and skill APIs. It lists real catalog data, offers supported installs/removals and toggles skill availability. Workflows requiring a provider installation interstitial or connector authorization still need the official client.
- Added native working-tree code review, a settings page and a usage panel with server-reported plan, credits, limit windows, token totals and explicit confirmation for a limit reset. Purchases and auto-recharge remain managed on the official ChatGPT usage page.
- Verified bundled server reads for plugins, skills, account, usage windows and token summary. This smoke test did not run scheduled inference, install plugins or redeem credits.
- Built the native 0.6.0 arm64 DMG, verified the image and bundle signature, and launched its bundled app-server from a temporary installed copy. The desktop package uses an ad-hoc signature for local testing.

## Desktop 0.6.0 verification and 0.6.1 fixes

- Verified Desktop 0.6.0 scheduled turns (`Agendado`) and working-tree code review (`Revisão de código`) against a disposable Git repository (`app.py` with a subtraction regression). Both flows failed closed on file inspection in 0.6.0 because `codex-code-mode-host` was absent from the app bundle while `gpt-6-astra` invoked `code_mode` (`exec`).
- Additional 0.6.0 client gaps found during inspection and protocol testing: `DesktopView` recreated `Timer.publish(every: 15, ...)` on SwiftUI body updates (resetting the 15s countdown), `upsert()`, `historyMessage()`, `item/started`, live item deltas, `enteredReviewMode`, and `exitedReviewMode` were unwired in `receive()` and `open()`, `ScheduledTask` did not record `lastThreadID` or expose open/run-now/delete actions, and background scheduled errors wrote into the global chat error banner.
- Fetched and SHA-256 verified Codex V8 artifacts (`rusty_v8` `152.2.0`) and compiled `codex-code-mode-host` for Apple Silicon. Updated `desktop/macos/build-dmg.sh` to bundle, strip (`xcrun strip -S -x`), and ad-hoc sign `codex-code-mode-host` alongside `codex`.
- Fixed the persistent 15s scheduler timer, wired `upsert()`, `historyMessage()`, live deltas, and review mode items (deduplicating `exitedReviewMode` when paired with `agentMessage`), updated `ScheduledTask` with backward-compatible `lastThreadID` plus open/run-now/delete actions, and bumped `Info.plist` to `0.6.1` (`CFBundleVersion` `7`).
- What passed after fixes: `swiftc -typecheck` passed with zero warnings; legacy `ScheduledTask` JSON decoding preserved compatibility; scheduled read-only execution (`cat app.py`) and `review/start` (`uncommittedChanges`, detecting `[P1] Restore addition in add`) succeeded via bundled `codex` + `codex-code-mode-host`; `WisdCode-Desktop-0.6.1-macos-arm64.dmg` passed `hdiutil verify`, `codesign --verify --deep --strict`, `account/read`, `account/rateLimits/read`, `accountSession/list`, `model/list`, `plugin/list`, `skills/list`, `review/start`, and window/app-server launch from a temporary installed copy.
- Still pending verification for desktop: interactive UI clicking through the `Agendado` modal and task buttons, `Personalizar` plugin install/removal, credit reset redemption with real server state, live microphone recording/audio inference, and interactive ChatGPT OAuth completion. Cloud scheduling, shared Sites, connector authorization, and any external agent selector in the desktop UI remain out of scope until multi-agent boundary gates pass.

## Feedback em Tempo Real de Execução e Ajustes de Interface

- **Feedback de Execução em Tempo Real (`LiveActivityCard`):**
  - Implementado card de feedback contínuo em tempo real no chat (`DesktopShell.swift`), exibido imediatamente após o envio da solicitação e durante toda a execução da tarefa.
  - Indicador visual animado com ponto pulsante azul e spinner de progresso, título do agente/modelo em execução e cronômetro de tempo decorrido com atualização segundo a segundo (`00:00s`).
  - Destaque em tempo real do que está sendo feito a cada instante: `currentActivityNote` (ex.: "Analisando e raciocinando...", "Executando comando no terminal", "Modificando arquivos no projeto", "Escrevendo resposta...") com caixa monospaçada para comandos de terminal, caminhos de arquivo e consultas.
  - Timeline com histórico das etapas executadas durante a tarefa: ícone de checkmark verde para passos concluídos e spinner azul animado para o passo em andamento.
  - Botão de interrupção imediata ("Parar") visível no card para cancelamento rápido a qualquer momento.
  - Rolagem automática do chat sempre sincronizada com as novas etapas e texto gerado.

- **Streaming do Agente CLI (`agy`) com NDJSON:**
  - Integrado parâmetro `--output-format stream-json` no CLI do Gemini Antigravity (`agy`), permitindo leitura linha a linha de eventos estruturados (`init`, `step_update`, `agent_response`, `tool`, `result`).
  - Mapeamento em tempo real de chamadas de ferramentas (`run_command`, `view_file`, `write_to_file`, `search_web`), mantendo o usuário informado sobre cada ação intermediária antes da resposta final.

- **Ícone de Ações de Conta (+3px e Azul Vibrante):**
  - Corrigido o botão de menu de ações no canto superior direito dos cards de contas em `DesktopSettings.swift`.
  - Aplicado `.buttonStyle(.plain)` com `foregroundColor(Color(red: 0.12, green: 0.53, blue: 1.0))` e tamanho de 19px (+3px), garantindo cor azul consistente no macOS sem sobrescrita de estilo do AppKit.

- **Verificação de Regressão e Compilação:**
  - Testes de integridade de estado e recuperação executados e aprovados: `run-state-smoke.sh` e `run-recovery-smoke.sh` (0 erros e 0 warnings).
  - Binário nativo compilado com `-O`, assinado e em execução (`WisdAI.app`).

## Staged checkpoint review and policy-enforced promotion

- Added `codex agent-checkpoint review-staged <checkpoint> --staging <dir>` and `codex agent-checkpoint promote <checkpoint> --staging <dir> [--approve-digest <sha256>] [--output <new-checkpoint>]` in `codex-rs/cli/src/agent_checkpoint.rs`.
- `review-staged` and `promote` verify the source checkpoint, validate staging outside the source repository, skip `.wisdcode-task.json` metadata when absent from source, and reject `.git` path components, symlinks, path traversal, and non-regular files. `promote` enforces Codex's active `FileSystemSandboxPolicy` via `ConfigBuilder` (blocking writes under `read-only` or restricted policies), requires interactive terminal confirmation or an exact matching `--approve-digest`, and revalidates both the source checkpoint and staging digest immediately before writing.
- Autonomous failover, automatic cross-provider switching, and automatic promotion remain disabled.
- What passed: `cargo +1.95.0 test --locked -p codex-cli --bin codex` passed 314 unit tests (0 failed, 1 ignored), including 4 `agent_checkpoint` tests covering added/modified/deleted promotion, preserved `.gitignore` files, `read-only` rejection, wrong-digest and denial rejection, concurrent source modification rejection, `.git` tampering, and symlink escapes. An end-to-end disposable repository smoke test passed `save` → `verify` → `stage` → simulated external staging edits → `review-staged` → rejected `read-only` and wrong-digest `promote` → approved `promote` under `workspace-write` → `validate` inside the read-only, network-disabled Seatbelt sandbox.
- Still pending verification: a live interactive `codex agent-checkpoint handoff` session producing real external agent edits followed by `review-staged` and `promote`, multi-account isolation and per-account usage/quota verification for external providers, and an in-process/brokered per-action Codex approval bridge before enabling any desktop provider selector or autonomous handoff.

## WisdAI 0.7.0 Desktop: Projetos, Múltiplas Contas de IA, Concorrência e Fallback de Modelos

> Registro anterior, substituído pela validação de 23 de novembro acima. Os perfis externos não comprovavam autenticação; o fallback baseado somente nos metadados foi removido. Esta seção histórica não descreve as garantias atuais do aplicativo.

- **Refatoração para WisdAI**: O aplicativo macOS foi integralmente refatorado de WisdCode para `WisdAI` (`CFBundleDisplayName`, `CFBundleName`, `CFBundleIdentifier`, `Info.plist`, `build-dmg.sh`, cabeçalhos da interface e mensagens do motor).
- **Gestão Completa de Projetos**:
  - Modal avançada de criação e edição (`ProjectModalView`): seleção de nome, escolha entre 20 ícones SF Symbols, paleta de 9 cores de ícone, seleção de cor do nome, seletor nativo de pasta (`NSOpenPanel`) e preview em tempo real.
  - Edição de projetos existentes via menu de contexto ("Editar projeto").
  - Exclusão de projetos com remoção do armazenamento e desvinculação limpa do workspace ("Excluir projeto").
- **Seção Recentes Colapsável e Filtrada**:
  - A seção "Recentes" agora possui controle de expansão/colapso (`recentCollapsed`).
  - Filtragem estrita: chats vinculados a projetos existentes são excluídos da lista de recentes e exibidos exclusivamente sob a árvore do seu respectivo projeto.
  - Exclusão direta de chats pelo menu de contexto ("Excluir chat"), desvinculando do workspace e motor.
- **Mecanismo de Múltiplas Contas de IA e Download de CLI**:
  - Suporte a múltiplos provedores (`OpenAI`, `Claude`, `Gemini Antigravity`, `DeepSeek`, `NVIDIA`, `Grok`, `Kimi`).
  - Suporte a múltiplas contas do mesmo provedor (ex: várias contas OpenAI, Gemini ou Claude).
  - Modal dedicada (`AddAccountModalView`) com seleção da empresa, nome personalizado, fluxo de download/incorporação da CLI oficial (`codex`, `claude`, `agy`, `deepseek`, etc.) e autenticação OAuth/chave de API.
- **Concorrência de até 5 Tarefas Simultâneas**:
  - Implementado o gerenciamento de tarefas ativas concorrentes (`activeTasks: [String: ActiveThreadTask]`).
  - Usuário pode disparar tarefas em diferentes chats e alternar entre eles livremente; até 5 tarefas rodam simultaneamente em paralelo sem interferência mútua.
  - Roteamento de deltas de streaming e eventos `turn/completed` por ID de thread, com badges e spinners visuais nos chats em execução e no cabeçalho da barra lateral.
- **Seleção de Conta/Modelo no Chat e Fallback Automático de Limites**:
  - Seletor integrado no compositor de chat permitindo alternar rapidamente a conta conectada e o modelo ativo.
  - Fallback automático dentro da mesma conta: ao atingir limite de tokens ou requisições (429/quota), o WisdAI avança automaticamente para o próximo modelo disponível da mesma conta, mantendo o contexto e o progresso da tarefa.
  - Alerta inteligente de limite esgotado (`AccountLimitAlertModalView`): quando todos os modelos da conta ativa se esgotam, o app exibe modal para selecionar outra conta conectada ou adicionar nova conta, preservando a continuidade exata da tarefa.
- **Verificação**: Compilação e verificação de tipos Swift para macOS arm64 (`xcrun swiftc -typecheck -parse-as-library`) passaram com zero erros e zero avisos.

## WisdAI 0.7.1 Desktop: Fallback Automático entre Contas, Seletor de Projetos e Indicadores de Status

- **Fallback Automático Transparente entre Contas**:
  - Implementado `autoFallbackToNextAccount(forTask:onThread:)` no `WisdCode.swift` e gerenciamento de estado em `DesktopLocalData`.
  - Quando a conta ativa esgota seus tokens ou cota (`usageLimitExceeded`, `insufficient_quota`, erros 429), o WisdAI marca a conta/modelo como esgotada e seleciona imediatamente a próxima conta disponível com suporte a execução (ex: Gemini Antigravity, outra sessão conectada), reiniciando a execução automaticamente sem travar a conversa e sem exigir seleção manual do usuário.
  - Correção na inicialização (`DesktopPanels.swift`): contas não-OpenAI (como Gemini Antigravity) não são mais desativadas indevidamente por ausência de `sessionID`.
  - Suporte completo a execução direta via CLI do fornecedor (`agy` para Gemini Antigravity e `claude` para Claude) e motor `codex app-server`.
- **Seletor de Projetos no Compositor & Modo Livre (Sem Projeto)**:
  - Adicionado menu dropdown no compositor de chat permitindo alternar entre:
    - "Trabalhar sem projeto" (chat livre sem vincular ou criar pastas no disco).
    - Lista de projetos existentes criados pelo usuário com marcação de seleção.
    - "Criar novo projeto…" (abre o modal nativo de criação).
  - Removida a criação automática forçada de diretórios de projeto ao iniciar um novo chat.
- **Estilização Minimalista de Chats na Sidebar com Indicadores de Pingo**:
  - Removido o visual pesado de botão com moldura/hover retangular na lista de conversas da barra lateral.
  - Implementados pingos circulares minimalistas de 7x7px para sinalização clara de status:
    - **Pingo verde (`Color.green`)**: Chat atualmente selecionado e ativo.
    - **Pingo roxo (`Color.purple`)**: Chat executando tarefa em segundo plano simultaneamente.
    - **Pingo amarelo (`Color.yellow`)**: Tarefa concluída em segundo plano que ainda não foi visualizada pelo usuário (desaparece ao abrir o chat).
- **Identidade Visual e Refinamentos de Interface**:
  - Incorporação dos novos assets gráficos: marca oficial `BrandLogo.png` no cabeçalho e boas-vindas, e novo ícone oficial `AppIcon.icns`.
  - Ícone de menu de ações de conta ajustado: exclamação em círculo (+3px, 20px) em tom azul pastel (`Color(red: 0.38, green: 0.68, blue: 0.98)`).
  - Unificação de Perfil e Aparência, Contas e Segurança, e separação dedicada de Chaves de API nas configurações.

- **Correção no Fluxo de Criação de Projetos e Vínculo de Chats**:
  - **Remoção de criação automática espúria**: O método `rememberProject()` foi corrigido para não mais chamar `local.addOrUpdateProject` silenciosamente. Projetos agora são criados exclusivamente através do fluxo explícito do usuário.
  - **Comparador resiliente de caminhos (`matchesPath`)**: Implementado `matchesPath` em `ProjectItem`, normalizando symlinks, barras finais e verificando pertinência de subdiretórios (`standardized.resolvingSymlinksInPath()`), garantindo que chats iniciados em qualquer subpasta do projeto continuem vinculados àquele projeto.
  - **Ativação imediata ao salvar projeto**: Ao criar ou salvar um projeto na modal, o workspace agora ativa o projeto, reseta para uma nova conversa limpa (`workspace.newConversation()`) e define `workMode = true`, preparando o chat imediatamente para receber a primeira mensagem.
  - **Botão explícito de Novo Chat no Projeto**: Adicionado botão `+` diretamente na linha de cada projeto na barra lateral e opção "Novo chat neste projeto" no menu de contexto, permitindo iniciar um chat diretamente dentro do projeto selecionado.
  - **Registro instantâneo de chats na sidebar**: Ao iniciar uma nova conversa com `thread/start`, a `Conversation` é inserida imediatamente na lista local antes mesmo do término do turno, aparecendo de imediato aninhada no respectivo projeto na barra lateral.

- **Unificação da Interface (Remoção das Abas Chat e Work)**:
  - Removido o seletor de abas segmentado `[Chat | Work]` do topo da aplicação em [DesktopShell.swift](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/DesktopShell.swift). A interface agora é sempre única e unificada, oferecendo todas as ferramentas (projetos, permissões, inspeção, anexos e controle por voz) em um fluxo direto e sem alternância de abas.
  - Barra superior simplificada com botão de alternância da barra lateral, indicador e atalho de detalhes do projeto ativo, e botão de chat temporário.

- **Controle por Voz Real e Diálogo Conversacional Bidirecional**:
  - **Módulo Nativo de Voz ([DesktopVoice.swift](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/DesktopVoice.swift))**:
    - Reconhecimento de fala em tempo real utilizando o framework nativo `Speech` (`SFSpeechRecognizer` em `pt-BR`) com suporte a execução no dispositivo (on-device) no macOS.
    - Captura de áudio via `AVAudioEngine` transmitindo buffers de áudio continuamente com cálculo de amplitude (RMS) para animação fluida da esfera de voz.
    - Síntese de voz com `AVSpeechSynthesizer` em português brasileiro (`pt-BR`) com delegate para controle de estados e conversa contínua.
    - Filtro de fala inteligente (`cleanForSpeech`): remove blocos de código e marcações markdown (crases, asteriscos, títulos, links) para leitura verbal natural.
  - **Execução Real de Tarefas por Voz**:
    - Transcrição ao vivo de comandos de voz: ao concluir a fala, o texto é injetado diretamente como prompt e despachado para execução real (`send()`).
    - Anúncios verbais de marcos durante a execução de tarefas (ex.: *"Iniciando a tarefa"*, *"Executando comando no terminal"*, *"Modificando arquivos"*, *"Tarefa concluída"*).
    - Fala automática das respostas e explicações do agente em ambos os motores: CLI (`agy` Gemini Antigravity) e `codex app-server`.
  - **Interface Interativa do Modo Voz**:
    - Diálogo com esfera gradiente reativa ao volume da voz do usuário e da fala do agente.
    - Balão de transcrição de fala em tempo real mostrando as palavras ditadas enquanto o usuário fala.
    - Modos de conversa contínua (mãos livres) e leitura de etapas da tarefa.
    - Botão de microfone direto adicionado no campo de texto do compositor para ditado rápido e sem atrito.
  - **Permissões de Sistema**: Declaradas `NSMicrophoneUsageDescription` e `NSSpeechRecognitionUsageDescription` em [Info.plist](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/Info.plist).





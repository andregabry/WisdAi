# Official agent compatibility

| Agent | Native sign-in and entitlement | Interface and session feasibility |
| --- | --- | --- |
| Codex | Existing ChatGPT sign-in and account management. | Reuse the existing CLI, TUI, app-server and native thread IDs. |
| Claude Code | Official binary supports Claude account login. Hosting the unmodified binary is subject to Anthropic's conditions. SDK-based product authentication generally uses API or cloud credentials. | The binary exposes authentication status, interactive launch and native session resume. The SDK/print mode exposes structured output, with separate authentication constraints. Hosting the native interactive binary is the candidate for subscription use. Verify billing selection and policy enforcement before orchestration. |
| Google Antigravity | Official `agy` supports Google account login, with separate documented cloud authentication options. | Interactive and headless interfaces exist. Verify which headless modes accept the user's entitlement and whether native sessions can be resumed by ID under equivalent permissions. |
| Kimi Code | Official `kimi login` handles Kimi account login. Verify Kimi Code entitlement for the account. | Official `kimi acp` exposes a multi-session ACP server and reports authentication-required errors. Check resume and permission capabilities during negotiation. |
| Xiaomi MiMo | Official MiMo Code supports Xiaomi platform authorization. Token Plan is a distinct subscription with plan limits. | Native terminal agent is available. Confirm a supported external execution and resume contract before implementing an adapter. |
| DeepSeek | Official Harness is in developer preview. The documented Codex model integration uses a DeepSeek API key. | Harness is a research candidate. No compatible subscription-backed handoff has been verified. |
| NVIDIA | OpenShell supplies execution controls for existing agents. NemoClaw runs OpenClaw with configurable inference. | Treat these as runtime infrastructure until a specific NVIDIA coding agent with native account entitlement and session interfaces is verified. |

Sources

- [Anthropic authentication and binary hosting](https://code.claude.com/docs/en/legal-and-compliance)
- [Claude Code CLI and native session commands](https://code.claude.com/docs/en/cli-reference)
- [Antigravity installation and authentication](https://antigravity.google/docs/cli/install) and [headless mode](https://antigravity.google/docs/cli/headless/)
- [Kimi command reference](https://moonshotai.github.io/kimi-cli/en/reference/kimi-command.html) and [ACP](https://moonshotai.github.io/kimi-cli/en/reference/kimi-acp.html)
- [Xiaomi MiMo Code](https://mimo.mi.com/docs/en-US/tokenplan/integration/mimo-code)
- [DeepSeek API and Harness overview](https://api-docs.deepseek.com/guides/codex) and [Codex model integration](https://api-docs.deepseek.com/quick_start/agent_integrations/codex/)
- [NVIDIA OpenShell](https://developer.nvidia.com/blog/p122891) and [NemoClaw](https://developer.nvidia.com/blog/p115891)

A launchable binary does not imply Codex-equivalent isolation, API-free billing or portable sessions. Expose only verified capabilities. Keep account identifiers, models and quotas unavailable where the native interface does not supply them reliably.

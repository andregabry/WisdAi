# Optional API providers

## DeepSeek

DeepSeek exposes a native Responses endpoint, which the existing Codex engine can use. To enable it, merge this provider entry into the existing Codex configuration file. Keep the top-level default provider and existing login settings as they are.

```toml
[model_providers.deepseek]
name = "DeepSeek"
base_url = "https://api.deepseek.com"
env_key = "DEEPSEEK_API_KEY"
wire_api = "responses"
requires_openai_auth = false
supports_websockets = false
```

Supply the key as the `DEEPSEEK_API_KEY` environment variable in the shell that launches WisdCode. Select the provider and model for that launch.

```sh
codex -c 'model_provider="deepseek"' -c 'web_search="disabled"' -m deepseek-flash
```

DeepSeek publishes a custom model catalog with the exact model capabilities, reasoning settings and supported tool shape. For a deployment, save that catalog locally and use a launch-specific `model_catalog_json` override. Avoid applying the vendor setup script over an existing ChatGPT configuration if the goal is to preserve the default login and model provider. A DeepSeek invocation sends its conversation and tool context to DeepSeek and uses the API key owner's usage allowance.

[DeepSeek Responses API](https://api-docs.deepseek.com/guides/responses_api/) · [DeepSeek Codex integration and model catalog](https://api-docs.deepseek.com/quick_start/agent_integrations/codex/)

## NVIDIA

NVIDIA's hosted NIM API documents Chat Completions at `https://integrate.api.nvidia.com/v1/chat/completions`. The current Codex transport supports the Responses protocol. Configuring that endpoint as a Responses provider would fail. Support requires a dedicated adapter with streaming, tool-call argument assembly, tool-result replay, cancellation and error mapping. Only enable it after local tests of those behaviors and a separately authorized inference smoke test.

[NVIDIA hosted LLM APIs](https://docs.api.nvidia.com/nim/reference/llm-apis)

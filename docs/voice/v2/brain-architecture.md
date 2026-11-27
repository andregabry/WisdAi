# Arquitetura do Cérebro Conversacional Local (**WisdAI Brain**)

## 1. Princípio de Independência e Seleção Intercambiável

O WisdAI Brain desacopla completamente a inteligência conversacional por voz dos provedores proprietários dos agentes de código (`Codex`, `Claude`, `Gemini`). A interface suporta troca explícita via `VoiceBrainEngineKind` (`LocalIntelligenceEngine.swift`):

- **`.adaptiveAuto` (`Automático`):** usa `llama.cpp Metal` ou `MLX` caso já estejam ativos/carregados; caso contrário usa `Apple FoundationModels` (ANE) com latência de inicialização zero e falha explicitamente se nenhum backend estiver disponível.
- **`.appleFoundationModels`:** força o `SystemLanguageModel.default` embarcado no macOS (`ANE Nativo`, zero download em disco).
- **`.localLlamaCppMetal`:** executa `llama-server` (`b12809`, licença MIT) exclusivamente em loopback `127.0.0.1:<porta_efêmera>` com descarga GPU Metal (`-ngl 99`) e streaming SSE (`/v1/chat/completions`).
- **`.localMLXServer`:** conecta-se a um servidor local compatível (`127.0.0.1:<porta>/v1`) com verificação prévia em `/v1/models`.

Quando o usuário seleciona explicitamente `.localLlamaCppMetal` ou `.localMLXServer` sem modelo/servidor pronto, `LocalConversationalBrain.refreshBackendAvailability()` **não simula sucesso nem cai silenciosamente em outro motor**: reporta `.compactHeuristicFallback` (`"Modelo conversacional indisponível"`) com `lastErrorDetail` técnico claro.

---

## 2. Catálogo GGUF Verificado (SHA-256 + Perfil de Hardware)

| ID do Catálogo | Arquivo / Fonte | Tamanho | Licença | RAM Mínima | SHA-256 |
| :--- | :--- | :---: | :--- | :---: | :--- |
| `qwen3-1.7b-q4_k_m` | `unsloth/Qwen3-1.7B-GGUF` | 1.03 GB (`1,107,409,472` B) | Apache-2.0 | 8 GB (`Essential`) | `b139949c5bd74937ad8ed8c8cf3d9ffb1e99c866c823204dc42c0d91fa181897` |
| `qwen2.5-1.5b-instruct-q4_k_m` | `Qwen/Qwen2.5-1.5B-Instruct-GGUF` | 1.04 GB (`1,117,320,736` B) | Apache-2.0 | 8 GB (`Essential`) | `6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e` |
| `gemma-3-1b-it-q4_k_m` | `unsloth/gemma-3-1b-it-GGUF` | 769 MB (`806,058,272` B) | Gemma License | 8 GB (`Essential`) | `8270790f3ab69fdfe860b7b64008d9a19986d8df7e407bb018184caa08798ebd` |
| `qwen3-4b-q4_k_m` | `unsloth/Qwen3-4B-GGUF` | 2.33 GB (`2,497,281,312` B) | Apache-2.0 | 16 GB (`Advanced`) | `f6f851777709861056efcdad3af01da38b31223a3ba26e61a4f8bf3a2195813a` |
| `google-gemma-3-4b-it-q4_k_m` | `bartowski/google_gemma-3-4b-it-GGUF` | 2.32 GB (`2,489,758,112` B) | Gemma License | 16 GB (`Advanced`) | `4996030242583a40aa151ff93f49ed787ac8c25e4120c3ae4588b2e2a7d1ae94` |
| `llama-3.2-3b-instruct-q4_k_m` | `bartowski/Llama-3.2-3B-Instruct-GGUF` | 1.88 GB (`2,019,377,696` B) | Llama 3.2 | 12–16 GB (`Advanced`) | `6c1a2b41161032677be168d354123594c0e6e67d2b9227c84f296ad037c728ff` |
| `microsoft-phi-4-mini-instruct-q4_k_m` | `bartowski/microsoft_Phi-4-mini-instruct-GGUF` | 2.32 GB (`2,491,874,688` B) | MIT | 16 GB (`Advanced`) | `01999f17c39cc3074afae5e9c539bc82d45f2dd7faa3917c66cbef76fce8c0c2` |

---

## 3. Tratamento Específico de Streaming e Memória

- **Supressão de `<think>` no Qwen3:** `LocalLlamaServerBrainRuntime` envia `/no_think` quando executando variantes `qwen3` para manter latência conversacional baixa e executa remoção incremental + final de blocos `<think>...</think>` no cliente SSE para que blocos internos de raciocínio jamais sejam falados em voz alta.
- **Gestão Térmica/RAM em Macs de 8 GB:** `llama-server` é encerrado automaticamente após 240 s de ociosidade ou imediatamente diante de alertas `.warning` / `.critical` do `VoiceMemoryPressureWatcher`.
- **Resultados Reais no Apple M2 (8 GB):**
  - `Apple FoundationModels (ANE)`: Turno 1 TTFT `3,964.4 ms` (total `4,628.2 ms`), Turno 2 quente TTFT `924.5 ms` (total `1,975.1 ms`).
  - `Qwen3-1.7B-Q4_K_M` (`llama.cpp Metal`): carga fria/média do processo `11,422.1 ms` (após warm cache OS: `7,140 ms`), TTFT em diálogo contínuo **`154.2–226.7 ms`**, resposta completa `1,006–1,440 ms` — **redução de ~4× a 6× no TTFT** em regime aquecido.

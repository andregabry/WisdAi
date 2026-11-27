# WisdAI V5 — Perfis de Hardware & Reestruturação do Laboratório de Voz

---

## 1. Matriz por Perfil de Hardware (`VoiceHardwareTier`)

| Perfil | RAM Unificada | Cérebro LLM Recomendado | Motor TTS Neural Padrão | Memória Total Estimada | Capacidade S2S |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Essential (`8 GB`)** — *Host atual testado* | 8 GB | Apple FoundationModels (ANE 0 heap) ou `Qwen3-1.7B Q4_K_M` (~1.03 GB Metal) | **Supertonic-3 INT8 (122.8 MB)** ou **Kokoro-82M INT8 (126.2 MB)** | **~447 MB** (teste Swift Audio+TTS) até **~1.6 GB** (com llama.cpp ativo) | Bloqueado nativamente (`NativeS2SRuntimeProbe`) para evitar OOM |
| **Advanced (`16–24 GB`)** | 16–24 GB | `Qwen3-4B Q4_K_M` (~2.33 GB) / `Gemma-3-4B` | Supertonic-3 INT8, Kokoro FP32 (`334 MB`) ou Loopback `mlx-audio` (`Qwen3-TTS-0.6B` / `Chatterbox`) | ~2.5–6.0 GB | Experimental Inglês via `moshi_mlx` loopback se servidor iniciado pelo usuário |
| **Ultra (`32–64+ GB`)** | 32+ GB | `Qwen3-4B+` + múltiplos agentes paralelos | Todos os locais + Loopback `Qwen3-TTS-1.7B VoiceDesign` / `Fish S1` | ~6–18 GB | `PersonaPlex 7B` / `MiniCPM-o` externos via loopback |

---

## 2. Reestruturação da Interface (Paridade Completa)

### Voice Laboratory ([`VoiceLaboratoryView.swift`](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/VoiceLaboratoryView.swift))
Organizado em 3 blocos sem ambiguidade:
1. **`3A. Identidade Vocal`**: seleciona `JARVIS`, `Aurora`, `Atlas` ou `Aria` e timbre (`Masculina` / `Feminina`), ligado ao `VoiceIdentityManager`.
2. **`3B. Motor Neural & Voice Design`**: seleciona `Supertonic-3`, `Kokoro-82M`, `Auto`, `Piper`, `Apple` ou `Loopback`, idioma (`pt-BR`, `pt-PT`, `en-GB`, `en-US`, `es-ES`), speaker específico (`M1..M5` ou `pm_alex`, `bm_george`, `pf_dora`), velocidade real e slider honesto de **passos Flow Matching** (somente quando Supertonic-3 está ativo).
3. **`3C. Voz Efetiva em Execução` + Botão `"Aplicar e testar voz"`**: exibe lado a lado **Solicitada**, **Configurada**, **Carregada em RAM**, **Última Inferência Real** (incluindo `sid` C, Hz de amostragem e F0 Hz medido) e qualquer `divergenceAlert`. O botão `"Aplicar e testar voz"` roda exatamente `orchestrator.previewCurrentConfiguredVoice()` — mesma configuração e mesmo pipeline da conversa.

### Ajustes, Popover do Chat & Menu de Contexto ([`DesktopSettings.swift`](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/DesktopSettings.swift), [`DesktopShell.swift`](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/DesktopShell.swift))
- Botões `Mulher` / `Homem`, chips de identidade (`JARVIS`, `Aurora`, `Atlas`, `Aria`), popover de speakers neurais (`Supertonic-3` e `Kokoro-82M`) e botões `"Testar voz"` agora compartilham o mesmo `VoiceIdentityManager` via ponte bidirecional no [`DesktopVoice.swift`](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/DesktopVoice.swift).

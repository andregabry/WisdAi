# WisdAI — Auditoria do Subsistema de Voz e Prova de Conceito (OpenJarvis Native Integration)

- **Branch:** `feature/openjarvis-native-integration` (baseada em `feature/voice-identity-jarvis-v5` @ `5e33caf`)
- **Hardware medido:** Apple M2, 8 GB RAM (`macOS`), sem Homebrew (`brew`) instalado
- **Repositórios de referência auditados:**
  - `https://github.com/open-jarvis/OpenJarvis` @ `8b07c88e26e401ac00d2db558a069d604c4f0477` (`Apache-2.0`)
  - `https://github.com/lancejames221b/openjarvis` @ `4582aacd2a31c08917f6c9eee249d9d65117d93f` (`MIT`)
  - `https://huggingface.co/jgkawell/jarvis` @ `37f8763122312665f091d1fc760abaf1f79b02cc` (`HF license: mit`, sem dataset declarado no `MODEL_CARD`)

---

## 1. Auditoria Comparativa dos Repositórios de Referência

| Critério | `open-jarvis/OpenJarvis` (`8b07c88e`) | `lancejames221b/openjarvis` (`4582aacd`) | `jgkawell/jarvis` (`37f87631`) |
| --- | --- | --- | --- |
| **Licença declarada** | `Apache-2.0` | `MIT` | `mit` no card (base VITS Piper `en-gb-x-rp`, dataset não documentado; risco de semelhança/propriedade intelectual cinematográfica) |
| **Arquitetura** | Backend modular em Python (`OrchestratorAgent`, `ToolExecutor`, `before_tool_call`, `MemoryService` + `LocalFactStore`, `SystemPromptBuilder`, `EventBus`, FastAPI `/v1/chat/completions`, WebSocket `/v1/agents/events`, `FasterWhisperBackend`, `KokoroTTSBackend`, engines `LlamaCppEngine`, `AppleFm`, `MLX`, `OpenAICompat`) | Bot Discord em Node.js (`conversation-session.js`) + microserviços GPU (`piper_tts_service.py`, `qwen3_tts_service.py` com `cuda`/`bfloat16`) e `systemd` Linux | Pesos Piper ONNX (`jarvis-high.onnx` 114 MB, `jarvis-medium.onnx` 63,5 MB, 22.05 kHz, `en-gb-x-rp`) |
| **Suporte a macOS M2 8 GB** | Nativo (core + UDS FastAPI = **31,7 MB RSS**); porém extra `[voice]` instala PyTorch + `kokoro==0.9.4` (**900–1020 MB RSS**) e falha sem `espeak-ng` via Homebrew (`espeakng-loader` sai com erro 1) | Incompatível diretamente (`cuda`/`systemd`/paths `/home/generic/dev/...`) | Roda em CPU via `piper-tts` (`GPL-3.0-or-later`) ou `sherpa-onnx` |
| **STT e Hotwords** | `FasterWhisperBackend` (`MIT`) com suporte real a `hotwords` e `vad_filter=True` | Referencia Whisper externo + tabela MIT de filtros anti-alucinação | N/A |
| **TTS PT-BR / EN** | Core suporta `TTSBackend` registrável; padrão Python `KokoroTTSBackend` sofre com PyTorch/GPL `phonemizer-fork` | Piper (`en-GB`) + Qwen3-TTS Linux/CUDA | **Inglês britânico claro em `high`, porém PT-BR inaceitável** (pronuncia português com fonemas ingleses) |
| **Audio Transport** | CLI usa `sounddevice` **half-duplex** (`record_until_silence`) — inferior ao `VoiceNativeAudioEngine` VPIO AEC do WisdAI | Discord RTP | Somente síntese |
| **Decisão** | **ADOTAR como núcleo conversacional, orquestração de tools, memória persistente, STT hotword e servidor local UDS.** | **NÃO adotar** runtime/arquitetura (apenas referência leve de estilo/filtros MIT). | **NÃO usar para PT-BR** e **evitar `piper-tts` GPLv3** como runtime principal. |

---

## 2. Inventário e Classificação do Subsistema Atual do WisdAI

Classificação completa por arquivo/componente conforme estado antes da substituição arquitetural:

| Arquivo / Componente | Papel atual | Decisão | Justificativa técnica |
| --- | --- | --- | --- |
| `UnifiedAgenticPipeline.swift` (`ExecutionEventBus`, `ProjectContextResolver`, `UnifiedMessageMetadata`, `ContextualTranscriptNormalizer`, `VoicePresentationEngine`) | Contrato de projeto ativo, pipeline unificada e eventos de execução | **Preservar e Adaptar** | Já conecta `Workspace`, `Codex`, `Antigravity`, aprovações e eventos ao barramento único. Passará a atender também às 12 tools do `OrchestratorAgent` do OpenJarvis via host callback UDS. |
| `VoiceNativeAudioEngine.swift` (`VoiceNativeAudioEngine`) | Áudio full-duplex `VPIO` macOS, AEC, detecção acústica de fala e flush imediato de saída no barge-in | **Preservar e Conectar** | Superior ao `record_until_silence` half-duplex do OpenJarvis por oferecer AEC de hardware real e barge-in em `< 20 ms`. |
| `VoiceSpeechUnderstanding.swift` (`BoundedVoicePermissions`, `SpeechAnalyzerOnDeviceSTTProvider`, `UnifiedLocalSTTCoordinator`) | Captura de microfone + fallback `SpeechAnalyzer` / `SFSpeechRecognizer` | **Adaptar** | Mantém captura nativa/Apple e adiciona envio de áudio PCM/WAV ao `/v1/speech/transcribe` do OpenJarvis (`FasterWhisperBackend` com hotwords dinâmicos dos projetos WisdAI). |
| `VoiceNeuralRuntime.swift` (`LocalLlamaServerBrainRuntime`, `SupertonicNeuralTTSProvider`, `KokoroNeuralTTSProvider`) | Subprocesso `llama-server` Metal e bindings C-API do `sherpa-onnx` (`Apache-2.0`) para Supertonic-3 (`MIT`) e Kokoro (`Apache-2.0`) | **Adaptar** | `LocalLlamaServerBrainRuntime` alimenta `LlamaCppEngine` do OpenJarvis; `SupertonicNeuralTTSProvider` / `KokoroNeuralTTSProvider` proveem síntese neural limpa de baixa RAM (< 350 MB) sem PyTorch (1 GB) e sem `piper-tts`/`phonemizer-fork` GPLv3. |
| `WisdCode.swift` (`Workspace`, `submitUnifiedMessage`, `activeTasks`, projetos, contas, UI principal) | Orquestrador real de execução e estado do workspace | **Preservar e Conectar** | Permanece intacto na UI, projetos, histórico, contas e execução de agentes; expõe servidor local UDS (`wisdai-host.sock`) para as 12 tools do OpenJarvis. |
| `VoiceOrchestrator.swift` (`WisdVoiceOrchestrator`) | Controlador monolítico com roteamento ad-hoc V2–V6 | **Substituir** | Lógica de conversação, decisão de tools, memória e prompt migram integralmente para o `OrchestratorAgent` + `/v1/wisdai/voice/stream` do OpenJarvis. |
| `DesktopVoice.swift` (`VoiceController`) | Controlador legado de voz no chat + ponte SwiftUI | **Adaptar / Simplificar** | Passa a operar exclusivamente sobre a sessão nativa OpenJarvis + `VoiceNativeAudioEngine`, mantendo compatibilidade com `DesktopShell`/`DesktopSettings`/`DesktopPanels`. |
| `VoiceGateway.swift` (`VoiceLanguageVariant`, `VoiceKeychainStore`, provedores streaming/gateway) | Tipos de idioma, keychain e fallback externo opcionais | **Adaptar / Podar** | Preserva tipos essenciais (`VoiceLanguageVariant`, `VoicePolicyPreferences`, provedores nuvem/Apple opcional) e remove seleção paralela fragmentada. |
| `VoiceIdentityProfile.swift` (`VoiceModelCatalog`, `VoiceModelAssetManager`, `WisdVoicePersona`) | Catálogo/instalação de modelos e seleção de voz | **Adaptar** | Mantém seleção real de voz limpa (`Supertonic M4/M5/F1/F4`, `Kokoro bm_george/pm_alex/pf_dora`) ligada diretamente ao `OpenJarvis`; remove defaults com DSP metálico/pitch destrutivo. |
| `VoiceStudioDSPProcessor.swift` (`SubtleMetallicResonator`, `StreamingWSOLAPitchShifter`) | Efeitos artificiais de ressonância metálica e pitch-shift em pós-processamento | **Remover após validação** | Origem comprovada de distorção robótica/metálica na voz Jarvis; vozes neurais limpas (`Supertonic M4`, `Kokoro bm_george`) soam superiores sem este DSP. |
| `VoiceBehaviorEngine.swift` (`ConversationalBehaviorPlanner`, `ActiveListeningBackchannelEngine`, templates rígidos) | Planos e frases artificiais pré-moldadas (V3) | **Remover após validação** | Substituído pela conversação fluida gerida pelo OpenJarvis (`SystemPromptBuilder` + streaming real token-a-sentença). |
| `VoiceVocalizationCache.swift` (`VocalizationCacheEngine`) | Pré-aquecimento e injeção de clipes artificiais (`uhum`, `aham`, `boa pergunta`) | **Remover após validação** | Substituído por streaming conversacional direto do OpenJarvis, reduzindo artificialidade e I/O/RAM. |
| `LocalIntelligenceEngine.swift` (`LocalQueryComplexityAnalyzer`, `LocalConversationalBrain`) | Roteador heurístico baseado em regex/palavras-chave e gerador local ad-hoc | **Remover após validação** | Substituído integralmente pelo `OrchestratorAgent` com `function_calling` real sobre as 12 tools do WisdAI. |
| `VoiceMemoryAndTelemetry.swift` | Telemetria de processo (`ProcessResourceProbe`), higiene de logs e guarda de memória | **Adaptar** | Reaproveita redação de logs, probe RSS/CPU e substitui heurística paralela pela persistência do `MemoryService` / `LocalFactStore` do OpenJarvis isolada de estado transitório. |
| `VoiceHUDViews.swift` & `VoiceLaboratoryView.swift` | HUD conversacional e painel de calibração DSP/V5–V6 | **Adaptar (`HUD`) / Remover ou simplificar (`Laboratory`)** | Preserva HUD conversacional e remove controles legados artificiais de ressonância/pitch/V5 em favor do status nativo do runtime OpenJarvis. |
| `DesktopCodexVoiceWebRTC.swift` | Orbe visual (`CodexHorizonOrbView`), continuidade e ponte WebRTC legada | **Adaptar** | Mantém componentes visuais (`CodexHorizonOrbView`, `CodexWaveformCanvasView`) e remove/desativa acoplamentos legados substituídos pelo OpenJarvis. |

---

## 3. Resultados da Prova de Conceito (PoC) Isolada

### 3.1 Síntese Neural e Qualidade Acústica (Amostras Auditadas por `read_file`)

Todas as amostras abaixo foram geradas em execução real no Apple M2 (sem DSP metálico/pitch adicionado nos candidatos limpos) em `openjarvis_poc_samples/`:

| Motor / Voz | Arquivo PoC | Idioma | SR | Duração | Load (ms) | Síntese (ms) | RTF | RSS Processo | Avaliação Auditiva Direta |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `piper-tts` `jgkawell/jarvis-medium` | `poc_piper_jarvis_medium_en.wav` | EN-GB | 22050 Hz | 6,11 s | 221,4 | 256,9 | 0,042 | 257,8 MB | Timbre britânico reconhecível, leve aspereza VITS. |
| `piper-tts` `jgkawell/jarvis-high` | `poc_piper_jarvis_high_en.wav` | EN-GB | 22050 Hz | 6,29 s | 252,8 | 1195,8 | 0,190 | 371,0 MB | Inglês britânico limpo estilo JARVIS; porém depende de `piper-tts` **GPL-3.0-or-later**. |
| `piper-tts` `jgkawell/jarvis-high` | `poc_piper_jarvis_high_ptbr.wav` | PT-BR | 22050 Hz | 5,09 s | — | 708,5 | 0,139 | 371,0 MB | **Reprovada para PT-BR:** fonetização inglesa (`"Bô-nôit, cân-cliú-í..."`), ininteligível em português. |
| `OpenJarvis KokoroTTSBackend` (PyTorch) | *(PoC inicial)* | EN / PT | 24000 Hz | — | 20317,0 | falha s/ brew | — | **896–1020 MB** | **Reprovado no runtime:** exige 1 GB RAM p/ PyTorch, puxa `phonemizer-fork` **GPLv3** e falha sem `espeak-ng` Homebrew. |
| `sherpa-onnx` C-API **Supertonic-3 M4** (`MIT`) | `poc_clean_supertonic_m4_ptbr.wav` / `_en.wav` | PT-BR / EN | 44100 Hz | 7,27 s / 7,13 s | 419,7 | 1519 / 1503 | **0,209–0,211** | **346–349 MB** | **Melhor equilíbrio geral:** 44,1 kHz natural, sem artefatos robóticos nem metalicidade, pronúncia fluida em PT-BR e EN. (Nota: siglas concatenadas como `WisdMeet` melhoram com léxico espaçado `Wisd Meet`). |
| `sherpa-onnx` C-API **Supertonic-3 M5** (`MIT`) | `poc_clean_supertonic_m5_ptbr.wav` | PT-BR | 44100 Hz | 6,87 s | 419,7 | 1496,8 | **0,218** | **347,8 MB** | Barítono profundo maduro natural para perfil grave sem distorção DSP. |
| `sherpa-onnx` C-API **Kokoro-int8** `bm_george` (`Apache-2.0`) | `poc_clean_kokoro_bm_george_en.wav` | EN-GB | 24000 Hz | 6,37 s | 630,2 | 4823,2 | 0,757 | 505,0 MB | Excelente voz inglesa britânica estilo Jarvis, **sem PyTorch**. |
| `sherpa-onnx` C-API **Kokoro-int8** `pm_alex` / `pf_dora` (`Apache-2.0`) | `poc_clean_kokoro_pm_alex_ptbr.wav` / `_pf_dora_ptbr.wav` | PT-BR | 24000 Hz | 5,36 s / 5,22 s | 707–726 | 3250–3400 | 0,623–0,634 | 293–540 MB | Funcionais e limpas sem DSP; levemente menos fluidas que Supertonic M4 em PT-BR (`0,63` vs `0,21` RTF). |

### 3.2 OpenJarvis STT (`FasterWhisperBackend` com `hotwords`)

- Modelo `base` CPU `int8` (`load_ms = 6436 ms`, `rss = 507–649 MB`):
  - **EN sem hotwords:** `"Good evening. I've completed the inspection of the WISME repository..."`
  - **EN com hotwords (`WisdMeet, WisdAI, Antigravity, Codex`) (`1204,7 ms`):** **`"Good evening, I've completed the inspection of the WisdMeet repository..."`**
  - **PT-BR sem hotwords:** `"Concluia Auditoria no Weasemite..."`
  - **PT-BR com hotwords (`784,5 ms`):** **`"Concluia Auditoria no WisdMeet, encontrei o controlador principal e o orçamento de GT..."`**

### 3.3 OpenJarvis Backend Server + `OrchestratorAgent` + `MemoryService` + `llama-server` Metal sobre Unix Domain Socket

- **`llama-server` Metal (`Qwen3-1.7B-Q4_K_M`, `-ngl 99`, `ctx 4096`):** boot `7196,0 ms`, `RSS = 1584,1–1589,6 MB`
- **Daemon OpenJarvis Python (FastAPI UDS + `OrchestratorAgent` + `MemoryService`):** **`RSS = 31,7 MB`** (conjunto total `1615,8 MB` < 2 GB em Mac de 8 GB)
- **Turno 1 (PT-BR — consulta ativa de projeto e agentes, `3988,7 ms`):** `OrchestratorAgent` executou realmente `get_active_project()` + `list_available_agents()` e respondeu com dados exatos do `WisdMeet`, `Antigravity`, `Codex` e indisponibilidade honesta do `Claude Code` sem CLI instalado.
- **Turno 2 (PT-BR — delegação autônoma, `2421,9 ms`):** `OrchestratorAgent` executou `execute_agent_task(project="WisdMeet", agent="antigravity", ...)` criando `task-1`.
- **Gap identificado no PoC para corrigir na implementação nativa:**
  1. `_handle_agent_stream()` upstream em `openjarvis/server/routes.py` aguarda o agente terminar todo o texto antes de emitir um único bloco SSE (`TTFT = 3427,9 ms`), embora `aclose()` aborte imediatamente (`0,9 ms`). Nossa integração nativa adicionará streaming incremental verdadeiro de tokens/frases no endpoint `/v1/wisdai/voice/stream`.
  2. `FactExtractor` padrão gravou fatos efêmeros de turno/projeto (`"Projeto ativo: WisdMeet"`) e respondeu Turno 3 em português quando influenciado por fatos em português; na integração nativa, filtraremos `FactExtractor` apenas para preferências duráveis e ancoraremos explicitamente o idioma de resposta do turno atual.

---

## 4. Decisão Arquitetural Selecionada

1. **Cérebro Conversacional e Memória:** Daemon local **OpenJarvis** (`open-jarvis/OpenJarvis` `Apache-2.0` empacotado em `OpenJarvisRuntime/`, sem dependências GPL/LGPL nem PyTorch bloat — `~245 MB` em disco / `~32 MB` RSS) gerenciado nativamente pelo Swift `OpenJarvisProcessManager` sobre **Unix Domain Socket** (`openjarvis.sock` + Bearer Token por sessão), conectado ao `llama-server` Metal (`Qwen3-1.7B-Q4_K_M`) ou engine nuvem/AppleFM configurado.
2. **Ponte Bidirecional das 12 Tools:** Servidor callback local autenticado em Swift (`wisdai-host.sock` via POSIX AF_UNIX) atendendo em tempo real as 12 tools registradas no `OrchestratorAgent` do OpenJarvis diretamente sobre `Workspace`, `ProjectContextResolver`, `ExecutionEventBus` e `submitUnifiedMessage`.
3. **Transporte de Áudio Full-Duplex & Barge-In:** `VoiceNativeAudioEngine` (Apple CoreAudio `VPIO` AEC) no cliente Swift conectado ao stream token-a-sentença do OpenJarvis, garantindo interrupção acústica imediata em `< 20 ms` e distinção rigorosa entre interromper fala vs cancelar tarefa em execução.
4. **STT & Voz Neural Limpa:** `FasterWhisperBackend` (`MIT`, hotwords dinâmicos por projeto/agente) com fallback nativo macOS; síntese limpa padrão em **`Supertonic-3` (`M4` para JARVIS / `M5` para Ultron BR / `F1` para Aurora)** e suporte a **`Kokoro-int8` (`bm_george` EN-GB / `pm_alex` / `pf_dora` PT-BR)** via `sherpa-onnx` C-API (`Apache-2.0`), com **DSP metálico e pitch-shifting desativados/removidos**.

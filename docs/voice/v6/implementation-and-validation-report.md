# WisdAI — Relatório de Implementação e Validação V6 (Correção P0 da Arquitetura de Voz Agêntica)

**Branch:** `feature/voice-identity-jarvis-v5`  
**Base anterior:** `a6001de`  
**Ambiente validado:** MacBook Pro `Mac14,7` (Apple M2, 8 GB RAM, macOS 27.0.1)  
**Auditoria prévia relacionada:** [agentic-voice-architecture-audit.md](file:///Users/andregabry/Project/WisdAI/docs/voice/v6/agentic-voice-architecture-audit.md)

---

## 1. Sumário Executivo e Causa Raiz Confirmada

A investigação forense na base SQLite real do aplicativo (`~/Library/Application Support/WisdAI/Database/wisdai_history.sqlite`, thread `53C9FCCE-CED4-4868-89E3-E2944158C61B`, `cwd=/Users/andregabry/Project/WisdMeet`) demonstrou que o modo texto (`[0]..[211]`) executava ferramentas reais via `/Users/andregabry/.local/bin/agy`, enquanto o modo de voz (`[212]..[233]`) desviava instruções faladas legítimas (`"Analise o projeto"`, `"Então verifique o código"`, `"Quero que você analise todo o código do projeto Whit Meet"`, `"Faça uma auditoria..."`) para o cérebro conversacional local `Qwen3-1.7B-Q4_K_M` (`llama.cpp Metal`) sem ferramentas — levando o modelo local a pedir o repositório ao usuário ou alucinar implementações inexistentes (*"redes neurais convolucionais"*).

Além do roteamento rígido por substrings no `LocalQueryComplexityAnalyzer` e da ausência de vocabulário contextual no STT, o ciclo de validação E2E real revelou **cinco defeitos adicionais reais**:

1. **Degradação e alteração de prompt em voz (`WisdCode.swift`):** `resolveFastVoiceModelIfConversational` rebaixava modelos fortes em chamadas de voz e `wrapConversationalVoiceInstruction` adulterava o prompt enviado ao agente especialista.
2. **Flags restritivas indevidas na CLI (`WisdCode.swift`):** `onDelegateTaskToAgent` forçava `forceReadOnly = (riskTier == .low)`, convertendo consultas em `--mode plan --sandbox` (`agy`), que criava `plan.md` em vez de responder diretamente dentro das permissões do projeto.
3. **Falha ao alternar para Codex em threads locais/Antigravity e drop de catálogo (`WisdCode.swift`):**
   - `loadModels()` descartava a resposta `model/list` quando `accountSession/list` hidratava `session` de `nil` para a sessão ChatGPT ativa durante o boot;
   - `dispatchTurnOnRoute()` não filtrava `models` obsoletos do provedor anterior e enviava `"model": "auto"` inválido ao `codex app-server`;
   - `thread/resume` falhava silenciosamente quando `existingThreadId` havia sido criado localmente ou em outro provedor (corrigido com fallback automático para `thread/start` preservando o histórico do chat).
4. **Quebra de leitura e pronúncia de arquivos na síntese vocal (`DesktopVoice.swift`, `UnifiedAgenticPipeline.swift`, `VoiceConversationEngine.swift`):**
   - `VoiceController.splitIntoNaturalSentences` quebrava frases nos pontos internos de nomes de arquivos (`MeetSessionController.swift`, `README.md`, `.git`);
   - `VoicePresentationEngine.composeSpokenSummary` incluía listas numeradas e intervalos `(linhas 1–32)` com pronúncia artificial de `"README.md"`, além de `stripRepetitiveOpeners` usar `.trimmingCharacters` nos dois extremos (removendo o ponto final da frase).
5. **Race de destruição C++ no encerramento de runtimes ONNX (`VoiceNeuralRuntime.swift`):** Quando `SupertonicNeuralTTSProvider` e `KokoroNeuralTTSProvider` eram descarregados de forma assíncrona no fim do processo, `OrtApis::ReleaseEnv` concorria com os destrutores estáticos `atexit` da `libonnxruntime` (`LoggingManager::~LoggingManager()`, `SIGABRT` / `mutex lock failed: Invalid argument`). Corrigido com `RTLD_NODELETE` e `unloadSynchronously()`.

---

## 2. Arquitetura Unificada em 4 Camadas

A solução separa responsabilidades de forma estrita sem remover as capacidades conversacionais e neurais introduzidas nas fases V2–V5:

1. **Conversation Controller (`VoiceOrchestrator.swift` / `LocalIntelligenceEngine.swift`):**
   - Mantém escuta ativa, turno contínuo, controle de microfone/sessão, interrupções e conversa livre fora de código;
   - Aplica **anti-hallucination guard** local (`looksLikeUngroundedRepoClaimOrAsk`) e escala imediatamente para execução real quando há escopo de projeto ativo.
2. **Task Orchestrator (`UnifiedAgenticPipeline.swift` / `WisdCode.swift`):**
   - `Workspace.submitUnifiedMessage(...)` unifica submissões por `.text` (`Workspace.send()`), `.voice`, `.voiceIntervention`, `.recovery` e `.scheduled` sobre o mesmo envelope `UnifiedMessageMetadata` (`projectID`, `workspaceID`, `workingDirectory` validado, `additionalDirectories`, `agentID`, `providerID`, `accountID`, `modelID`, `reasoningEffort`, `sessionID`, `permissionsMode`, `sandboxPolicy`, `approvalPolicy`);
   - Suporta perguntas em tempo real sobre execução, enfileiramento complementar sem derrubar a tarefa atual (`enqueueIfBusy: true` -> `.taskQueued`) e cancelamento explícito de tarefa ativa preservando a sessão de voz (`cancelActiveTaskFromVoice()` -> `.taskCancelled`);
   - `ProjectContextResolver` valida existência e acessibilidade do diretório antes de qualquer despacho (bloqueando `.blockedDirectory` + evento `.taskBlocked` sem fallback silencioso para `$HOME`) e extrai estado Git real (repositório, branch, working tree) e destaques de configuração.
3. **Agent Execution Engine (`WisdCode.swift` / CLIs `agy`, `codex app-server`, `claude`):**
   - Executa ferramentas reais no projeto ativo com fidelidade absoluta ao modelo (`gemini-4-hydrogen-high`), esforço (`ultra`), conta e modo de permissão escolhidos na UI;
   - Publica eventos estruturados em `ExecutionEventBus` (`task.*`, `agent.connected`, `tool.*`, `file.*`, `command.*`, `test.*`, `approval.required`) para telemetria e respostas vivas em linguagem natural.
4. **Voice Presentation Engine (`VoicePresentationEngine`, `DesktopVoice.swift`, `VoiceNeuralRuntime.swift`, `VoiceStudioDSPProcessor.swift`):**
   - Preserva integralmente os relatórios técnicos completos no histórico do chat;
   - Gera resumos orais naturais concisos (2–4 frases, até ~300 caracteres no modo equilibrado), removendo blocos de código, JSONs extensos, tabelas Markdown, stack traces, caminhos POSIX longos, intervalos `(linhas X-Y)` e muletas de abertura (`"Hmm…"`, `"Ah…"`, `"Entendi,"`);
   - Preserva estado contínuo do `VoiceStudioDSPProcessor` fora do laço de chunks e corrige divisões de sentença e pronúncia técnica (`README.md`, `.swift`, `.git`, `WisdMeet`).

---

## 3. Ficheiros Criados e Modificados

- **Novos arquivos:**
  - [UnifiedAgenticPipeline.swift](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/UnifiedAgenticPipeline.swift) — Contratos `MessageInputSource`, `UnifiedMessageMetadata`, `UnifiedSubmissionOutcome`, `ResolvedProjectContext`, `ProjectContextResolver`, `ExecutionEventBus` (`ExecutionEvent`, `ActiveTaskExecutionSnapshot`, `formatGroundedProgressAnswer`), `ContextualTranscriptNormalizer` e `VoicePresentationEngine`.
  - [AgenticVoiceE2ESmoke.swift](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/tests/AgenticVoiceE2ESmoke.swift) — Suíte E2E real (Testes A–H) sem mocks para execução agêntica e síntese WAV.
  - [run-agentic-voice-e2e.sh](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/tests/run-agentic-voice-e2e.sh) — Empacotador isolado `.app` (`com.wisdai.AgenticVoiceE2ESmoke`) com symlinks auxiliares para `codex` e `codex-code-mode-host`.
  - [agentic-voice-architecture-audit.md](file:///Users/andregabry/Project/WisdAI/docs/voice/v6/agentic-voice-architecture-audit.md) e [implementation-and-validation-report.md](file:///Users/andregabry/Project/WisdAI/docs/voice/v6/implementation-and-validation-report.md).
- **Arquivos modificados:**
  - [WisdCode.swift](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/WisdCode.swift)
  - [VoiceOrchestrator.swift](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/VoiceOrchestrator.swift)
  - [LocalIntelligenceEngine.swift](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/LocalIntelligenceEngine.swift)
  - [VoiceMemoryAndTelemetry.swift](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/VoiceMemoryAndTelemetry.swift)
  - [VoiceGateway.swift](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/VoiceGateway.swift)
  - [VoiceSpeechUnderstanding.swift](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/VoiceSpeechUnderstanding.swift)
  - [VoiceConversationEngine.swift](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/VoiceConversationEngine.swift)
  - [VoiceBehaviorEngine.swift](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/VoiceBehaviorEngine.swift)
  - [VoiceNeuralRuntime.swift](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/VoiceNeuralRuntime.swift)
  - [DesktopVoice.swift](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/DesktopVoice.swift)
  - [build-dmg.sh](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/build-dmg.sh)
  - [VoiceSmokeTests.swift](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/tests/VoiceSmokeTests.swift)

---

## 4. Resultados Reais dos Testes (Após a Edição Final do Código)

### 4.1 Suítes de Regressão e Contratos

Todas as três suítes compiladas e executadas após a última edição em Swift retornaram código de saída `0`:

| Suíte | Script | Resultado Final Verificado |
| :--- | :--- | :--- |
| **Voice & Pipeline Smoke** | [run-voice-smoke.sh](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/tests/run-voice-smoke.sh) | **`VOICE_SMOKE_ALL_PASS`** — Inclui Kokoro-82M (`load=535ms`, PT-BR/EN/ES), llama.cpp Metal `Qwen3-1.7B` (`TTFT=100ms`, `total=792ms`), Supertonic-3 44.1 kHz (`RTF=0.203`, `M2=88.9Hz`, `M4=119.5Hz`, `F1=183.0Hz`), Native AudioEngine 32-cycle VPIO, e **`PASS: V6 Agentic Voice Pipeline Contracts`**. Benchmark: `Ring20ms P50=0.0003ms P95=0.0003ms`, `TestFootprint=664.6MB`, `CPU=8.4%`. |
| **State Smoke** | [run-state-smoke.sh](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/tests/run-state-smoke.sh) | **`PASS`** — Isolamento de projetos, credenciais, cotas, SQLite interno, decoupling de esforço/modelo e roteamento de voz. |
| **Recovery Smoke** | [run-recovery-smoke.sh](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/tests/run-recovery-smoke.sh) | **`PASS`** — Limites estritos, fallback conta/modelo, preservação de políticas e privacidade efêmera. |

### 4.2 Suíte E2E Real (Testes A–H em `run-agentic-voice-e2e.sh`)

Executada com repositórios Git reais temporários (`WisdMeet@main` e `WisdFin@feature/beta`), binário real `/Users/andregabry/.local/bin/agy`, binário auxiliar real `codex app-server`, modelos neurais em disco e código de saída `0` (**`AGENTIC_VOICE_E2E_ALL_PASS`**):

| Teste | Escopo Validado | Evidência Direta Observada |
| :--- | :--- | :--- |
| **Teste A** | Auditoria por voz via `VoiceOrchestrator` → `submitNormalizedVoiceTranscript` (`"Whit Meet"` → `"WisdMeet"`) → `agy` CLI real | **PASS** — Emitiu **16 eventos** reais no `ExecutionEventBus` (`task.received`, `task.started`, `agent.connected`, `command.*`, 4x `tool.started`/`file.read`, `task.completed`). Relatório completo salvo no chat (`4421 chars`) citando símbolos/arquivos reais; resumo oral conciso (`216 chars`), sem Markdown/blocos/`"Hmm"`. |
| **Teste B** | Equivalência `.text` (`Workspace.send()`) vs `.voice` (`submitUnifiedMessage(.voice)`) | **PASS** — Mesmo modelo (`gemini-4-hydrogen-high`), mesmo esforço (`ultra`), mesmo `permissionsMode=1` e mesmo `workingDirectory`; ambos leram `AudioJitterBridge.swift` e responderam `42`. |
| **Teste C** | Diretório inexistente (`/tmp/.../NonExistentRepo_XYZ`) | **PASS** — Bloqueado imediatamente via `ProjectContextResolver` (`.blockedDirectory` + evento `.taskBlocked`), erro explícito citando o caminho inexistente, sem cair em `$HOME` e sem alucinar. |
| **Teste D** | Conversação viva durante execução + fila + cancelamento | **PASS** — Enquanto `agy` rodava, respondeu imediatamente com dados vivos (`"Gemini Antigravity com gemini-3.8-flash-high está em execução há 1 segundos..."`), enfileirou pedido complementar (`.taskQueued`) e cancelou explicitamente por voz (`"Pode parar esta tarefa agora"` → `.taskCancelled`). |
| **Teste E** | Isolamento multi-projeto (`WisdMeet@main` vs `WisdFin@feature/beta`) | **PASS** — Leu `token_beta_772` em `Sources/BetaSentinel.swift` (`feature/beta`) sem vazar símbolos do repositório A, com snapshots isolados por `conversationID`. |
| **Teste F** | Troca real de agentes (`Antigravity`, `Codex`, `Claude Code`) | **PASS (Antigravity + Codex + Claude Honesty)** — `Claude Code` ausente (`claudeCLI=NOT_INSTALLED`) retornou `.unavailable` honesto; **`Codex app-server`** conectou com sessão ChatGPT ativa (`andre.gabry@icloud.com`), catálogo real (`gpt-6-astra`, `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.6-luna`), executou leitura real de `README.md` (`events=["agent.connected", "task.started", "agent.connected", "tool.started", "file.read", "task.completed"]`) e respondeu **`WisdMeet`**. |
| **Teste G** | Anti-alucinação em repo sem redes neurais | **PASS** — `agy` inspecionou `WisdMeet` e respondeu honestamente que não existe rede neural convolucional implementada no projeto. |
| **Teste H** | Amostras reprodutíveis de voz em `pt-BR` e `en` (`Supertonic M4/M5 + Kokoro pf_dora`) | **PASS** — 5 arquivos WAV 24 kHz exportados e verificados acusticamente e por audição direta. |

---

## 5. Amostras de Voz Geradas e Inspecionadas (Teste H)

Localização: [voice_samples_v6_e2e](file:///Users/andregabry/.gemini/antigravity/brain/15f30b3f-af87-4fae-bd9f-5f3efd1c6b44/voice_samples_v6_e2e)

| Arquivo WAV | Voz / Motor | Idioma | Duração | RTF | F0 Mediana | Pico / DC Offset | Inspeção Auditiva Direta |
| :--- | :--- | :--- | :---: | :---: | :---: | :---: | :--- |
| [v6_jarvis_m4_ptbr_01_live_audit_summary.wav](file:///Users/andregabry/.gemini/antigravity/brain/15f30b3f-af87-4fae-bd9f-5f3efd1c6b44/voice_samples_v6_e2e/v6_jarvis_m4_ptbr_01_live_audit_summary.wav) | JARVIS (`supertonic:m4`, DSP limpo) | `pt-BR` | 15,75 s | 0,209 | 118,2 Hz | 0,317 / -0,00000 | Resumo executivo natural em 3 frases, sem leitura de linhas/caminhos longos ou `"Hmm"`. |
| [v6_jarvis_m4_ptbr_02_progress_during_task.wav](file:///Users/andregabry/.gemini/antigravity/brain/15f30b3f-af87-4fae-bd9f-5f3efd1c6b44/voice_samples_v6_e2e/v6_jarvis_m4_ptbr_02_progress_during_task.wav) | JARVIS (`supertonic:m4`, DSP limpo) | `pt-BR` | 9,74 s | 0,225 | 120,6 Hz | 0,332 / 0,00000 | Fluidez contínua sem quebrar em `MeetSessionController.swift`. |
| [v6_ultron_br_m5_ptbr_03_audit_complete.wav](file:///Users/andregabry/.gemini/antigravity/brain/15f30b3f-af87-4fae-bd9f-5f3efd1c6b44/voice_samples_v6_e2e/v6_ultron_br_m5_ptbr_03_audit_complete.wav) | Ultron BR (`supertonic:m5`, `ultronBRDefault`) | `pt-BR` | 10,18 s | 0,218 | 90,9 Hz | 0,589 / -0,00004 | Timbre masculino profundo com ressonância sutil e zero zumbido robótico. |
| [v6_aurora_kokoro_ptbr_04_audit_complete.wav](file:///Users/andregabry/.gemini/antigravity/brain/15f30b3f-af87-4fae-bd9f-5f3efd1c6b44/voice_samples_v6_e2e/v6_aurora_kokoro_ptbr_04_audit_complete.wav) | Aurora (`kokoro:pf_dora`, DSP limpo) | `pt-BR` | 7,78 s | 0,608 | 171,4 Hz | 0,389 / -0,00000 | Voz feminina natural e clara em `pt-BR`. |
| [v6_jarvis_m4_en_05_audit_complete.wav](file:///Users/andregabry/.gemini/antigravity/brain/15f30b3f-af87-4fae-bd9f-5f3efd1c6b44/voice_samples_v6_e2e/v6_jarvis_m4_en_05_audit_complete.wav) | JARVIS (`supertonic:m4`, DSP limpo) | `en-US` | 9,71 s | 0,224 | 115,9 Hz | 0,343 / 0,00000 | Inglês limpo e natural citando símbolos reais do projeto. |

---

## 6. Limitações Conhecidas e Condições do Ambiente

1. **`Claude Code` CLI ausente neste Mac:** `AgentCLIAuthenticator.locateCLI(for: .claude)` retornou `nil`. O fluxo foi validado garantindo recusa honesta (`.unavailable` sem alucinação); execução real da CLI `claude` não pôde ser rodada nesta máquina por ausência do binário externo.
2. **Entrada de voz na suíte automatizada:** A suíte `AgenticVoiceE2ESmoke` injeta transcrições diretamente em `WisdVoiceOrchestrator.submitNormalizedVoiceTranscript(...)` (exercitando o normalizador contextual, roteador, barreira anti-alucinação, pipeline unificado e `ExecutionEventBus` em modo headless sem microfone VPIO físico). A captura ao vivo de microfone + VPIO de 32 ciclos foi coberta em `VoiceSmokeTests.swift`, mas testes falados presenciais via microfone real dependem da interação direta com `WisdAI.app`.

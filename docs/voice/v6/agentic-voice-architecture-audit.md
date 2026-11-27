# WisdAI — Auditoria Arquitetural P0 do Modo de Voz Agêntico

**Prioridade:** P0 — Bloqueador funcional  
**Ambiente auditado:** MacBook Pro `Mac14,7` (Apple M2, 8 GB RAM, macOS 27.0.1)  
**Caso real investigado:** Projeto `WisdMeet` (`/Users/andregabry/Project/WisdMeet`), conta ativa `Gemini Antigravity` (`/Users/andregabry/.local/bin/agy`), modelo `gemini-4-hydrogen-high`, esforço `ultra`, modo `2` (`danger-full-access`).

---

## 1. Causa Raiz Confirmada (Evidência Forense Real)

A inspeção direta do banco SQLite interno (`~/Library/Application Support/WisdAI/Database/wisdai_history.sqlite`, thread `53C9FCCE-CED4-4868-89E3-E2944158C61B`, `cwd = /Users/andregabry/Project/WisdMeet`, `agy_conversation_id = 189f554e-6907-48bb-ab9b-04ca2f7fe6f2`) comprovou exatamente onde o fluxo se rompeu entre o modo texto e o modo voz:

1. **No modo texto (mensagens `[0]..[211]`):**  
   `DesktopShell.send()` → `Workspace.send()` → `Workspace.dispatchTurnOnRoute()` → `Workspace.executeCLITurn()` acionou o processo real `/Users/andregabry/.local/bin/agy`, lendo ficheiros e executando comandos reais em `/Users/andregabry/Project/WisdMeet`.
2. **Ao ativar o modo de voz (mensagens `[212]..[233]`):**  
   `Workspace.toggleVoiceConversation()` (`WisdCode.swift:1798`) iniciou `startChatConversationalVoice()` → `VoiceController.startConversationalChatMode()` → `VoiceOrchestrator.startSessionWithContinuity()`.
   - As falas finalizadas entraram em `VoiceOrchestrator.handleFinalizedAutonomousTurn(_ utterance:)` (`VoiceOrchestrator.swift:1699`), que consultou o classificador determinístico por substrings **`LocalQueryComplexityAnalyzer.route()`** (`LocalIntelligenceEngine.swift:153`).
   - Os pedidos reais falados pelo utilizador não casaram com as substrings rígidas de `workspaceActionPatterns` (`LocalIntelligenceEngine.swift:84-99`):
     - `[220]`: *"Eu quero fazer uma implementação de neural nesse app pode verificar se já está implementado"* → caiu em **`.handleLocally`** (não casou com `"verifique o arquivo"`).
     - `[222]`: *"Eu quero que você analise todo o código e verifique se já foi implementado um sistema de neu"* → cortado prematuramente no turno e caiu em **`.handleLocally`**.
     - `[224]`: *"Então verifique o código"* → caiu em **`.handleLocally`** (`workspaceActionPatterns` exigia `"verifique o arquivo"`, não `"verifique o código"`).
     - `[226]`: *"Analise o projeto"* → caiu em **`.handleLocally`** (`workspaceActionPatterns` exigia `"analisar o projeto"`, não `"analise o projeto"`).
     - `[228]`: *"Então detalhe"* → caiu em **`.handleLocally`**, levando o LLM local **`Qwen3-1.7B-Q4_K_M` (`llama.cpp Metal`)** sem ferramentas a **alucinar** *"redes neurais convolucionais, redes neurais de camada única..."*.
     - `[230]`: *"Quero que você analise todo o código do projeto Whit Meet"* → STT transcreveu `"Whit Meet"` em vez de `"WisdMeet"` (ausência de vocabulário contextual em `SFSpeechAudioBufferRecognitionRequest`), e `"analise todo o código"` não casou com `"analise o código"`, caindo novamente em **`.handleLocally`**.
     - `[232]`: *"Faça uma auditoria no projeto E M"* → `"auditoria"` / `"auditar"` sequer existia em `workspaceActionPatterns`, caindo outra vez em **`.handleLocally`** e pedindo ao utilizador para compartilhar o repositório.

### Causas Raiz Secundárias Confirmadas no Código

1. **Silenciamento e degradação de modelo no `Workspace.send()` (`WisdCode.swift:2946-2954`):** mesmo quando uma fala alcançava `onDelegateTaskToAgent` → `self.send()`, `resolveFastVoiceModelIfConversational` rebaixava `gemini-4-hydrogen-high` para modelos `-flash`/`haiku`/`mini` se o texto não casasse com `heavyKeywords`, e `wrapConversationalVoiceInstruction` instruía o agente CLI a omitir blocos de código e listas markdown (corrompendo o relatório técnico no chat).
2. **Incompatibilidade de permissões e flags CLI em `executeCLITurn` (`WisdCode.swift:3868-3890`):**
   - `onDelegateTaskToAgent` forçava `forceReadOnly = (riskTier == .low)`, transformando consultas válidas em `--mode plan --sandbox` para a CLI `agy`.
   - Teste direto com `agy --mode plan --sandbox --output-format stream-json` (`task-8920`) mostrou que `--mode plan` força o agente a gerar `plan.md` via `write_file`, além de restringir comandos sob `--sandbox` mesmo quando o utilizador estava em modo `2` (`danger-full-access`).
   - `isClaude` (`executeCLITurn`) não utilizava `--output-format stream-json --verbose` nem respeitava modos intermediários de permissão.
3. **Contexto de projeto incompleto e ausência de validação de diretório (`VoiceMemoryAndTelemetry.swift:72-86, 156-164` & `WisdCode.swift:3909`):**
   - `VoiceWorkspaceContextSnapshot` carregava apenas `projectName`, `workspaceDirectoryDisplay` mascarado pelo `VoiceLogRedactor.redact`, `securityModeName`, `activeExecutionAgent` e `activeTasksCount` — sem `projectID`, `workspaceID`, caminho absoluto validado, repositório Git, branch, estado do working tree, modelo selecionado nem esforço de raciocínio.
   - `executeCLITurn` e `dispatchTurnOnRoute` não validavam se `projectURL.path` existia ou era legível antes de executar, podendo falhar tardiamente ou cair no diretório `HOME`.
4. **Ausência de `ExecutionEventBus` estruturado:** `handleCLILine` (`WisdCode.swift:3506`) e `handleEvent` (`WisdCode.swift:4429`) atualizavam apenas notas textuais de UI (`recordActivity`), sem publicar eventos estruturados (`task.*`, `file.*`, `command.*`, `test.*`, `approval.required`) para o controlador conversacional responder com fatos reais durante a execução.
5. **Alucinação local & vícios de abertura (`LocalIntelligenceEngine.swift` / `VoiceOrchestrator.swift:1994` / `VoiceConversationEngine.swift:424`):**
   - Sem barreira rígida contra perguntas de código no `LocalConversationalBrain` e com menção explícita a `"Hmm…"` no prompt de sistema (`VoiceConversationEngine.swift:424`), o modelo local de 1.7B abria respostas repetidamente com `"Hmm..."` e inventava arquiteturas ou pedia código.
6. **STT sem vocabulário contextual (`VoiceGateway.swift:1034`, `VoiceSpeechUnderstanding.swift:248`):** `SFSpeechAudioBufferRecognitionRequest` não recebia `contextualStrings` (`WisdAI`, `WisdMeet`, `WisdFin`, `WisdKids`, `WisdPlay`, `Codex`, `Claude Code`, `Antigravity`, projetos/tecnologias ativas), nem havia normalizador pós-ASR conservador preservando a transcrição bruta original.
7. **Qualidade e segmentação vocal durante streaming (`VoiceOrchestrator.swift:2307`, `VoiceConversationEngine.swift:650-680`):** `VoiceStudioDSPProcessor` era reinstanciado por cláusula dentro do loop de TTS (reiniciando filtros IIR e envelopes a cada vírgula/frase), e pausas entre cláusulas precisavam de suavização de borda para evitar transientes sutis.

---

## 2. Inventário Completo da Arquitetura Atual

| Componente | Implementação Atual Verificada | Limitação Identificada |
| :--- | :--- | :--- |
| **Pipeline escrito** | `DesktopShell.swift:1357` → `Workspace.send()` (`WisdCode.swift:2872`) → `dispatchTurnOnRoute()` (`2968`) → `executeCLITurn()` (`3821`) / `startTurn()` (`4031`) | Preserva agente, modelo, esforço, anexos e diretório; porém sem validação prévia de diretório inexistente nem evento bus estruturado. |
| **Pipeline falado** | `VoiceNativeAudioEngine` (`onInputAudioChunk`) → `VoiceOrchestrator` → `UnifiedLocalSTTCoordinator` → `HybridTurnTakingAnalyzer` → `handleFinalizedAutonomousTurn()` (`VoiceOrchestrator.swift:1699`) | Barrado por `LocalQueryComplexityAnalyzer.route()`, enviando instruções agênticas para `LocalConversationalBrain` (`Qwen3-1.7B` / Apple FM) sem ferramentas. |
| **Reconhecimento de voz (STT)** | `UnifiedLocalSTTCoordinator` (`VoiceSpeechUnderstanding.swift:438`): prioriza `SpeechAnalyzerOnDeviceSTTProvider` (macOS 26+) com fallback `AppleSpeechStreamingSTTProvider` (`SFSpeechRecognizer`, rotação 48s) + Deepgram opt-in. | Não popula `contextualStrings` com projetos/agentes ativos nem corrige erros fonéticos evidentes como `"Whit Meet"`. |
| **Síntese de voz (TTS)** | `SupertonicNeuralTTSProvider` (44.1 kHz, padrão `M4` JARVIS / `M5` Ultron BR), `KokoroNeuralTTSProvider` (24 kHz, `pf_dora`/`pm_alex`/`pm_santa`/`bm_george`), `SherpaVitsPiper`, `AppleNaturalPCM`, loopback MLX + `VoiceStudioDSPProcessor` + `StreamingSincResampler`. | Estado do `VoiceStudioDSPProcessor` era reiniciado a cada cláusula no loop TTS (`VoiceOrchestrator.swift:2307`); segmentação quebrava cláusulas curtas com vírgula. |
| **Modelo conversacional** | `LocalConversationalBrain` (`LocalIntelligenceEngine.swift:267`): `qwen3-1.7b-q4_k_m` via `llama.cpp Metal` (ativo em `local.wisdai.desktop`) ou Apple `FoundationModels` / MLX Server. | Executava papel de pseudo-auditor de código quando o roteador falhava; sem filtro anti-alucinação pós-geração. |
| **Serviço de execução de agentes** | `Workspace` (`WisdCode.swift`), com limite de até 5 `activeTasks` em paralelo indexadas por `threadId`, fila `UsageQuotaStore` e recuperação por checkpoints (`DesktopRecovery.swift`). | Não expõe `UnifiedMessageEnvelope` comum nem fila explícita para instruções adicionais durante execução sem abortar a tarefa atual. |
| **Integração com CLIs** | • **Codex (OpenAI):** subproceso `codex app-server` JSON-RPC + `codex-code-mode-host` (`thread/start`, `thread/resume`, `turn/start`, `turn/interrupt`, `handleApproval`).<br>• **Antigravity (Gemini):** `/Users/andregabry/.local/bin/agy --output-format stream-json --model ... [--effort ...] [--conversation ...]` (`resolveAgyModelAndEffort`).<br>• **Claude Code:** `locateCLI(for: .claude)` + `-p` + `--model` (CLI não instalada neste Mac no momento). | `forceReadOnly` forçava `--mode plan --sandbox` na voz mesmo em pedidos normais do modo 2; `claude` sem `--output-format stream-json`; `additionalPaths` não repassados com `--add-dir`. |
| **Gestão de sessões, contexto e projetos** | `ChatStorage` (`wisdai_history.sqlite`: tabelas `conversations` com `cwd` + `agy_conversation_id` e `messages`); `DesktopLocalData.projectsList` (`ProjectItem` com `id`, `name`, `path`, `additionalPaths`); `CodexRealtimeContinuityStore`; `VoiceMemoryStore` + `VoiceSQLiteKnowledgeStore`. | Faltava `ProjectContextResolver` com status Git/branch/working tree, validação de existência no disco e contexto unificado compartilhado com a voz. |
| **Eventos de ferramentas e fallback** | `handleCLILine` (`WisdCode.swift:3506`) e `handleEvent` (`4429`) atualizam `messages` e `activeTasks`; `autoFallbackToNextAccount` trata HTTP 429/quota. | Sem `ExecutionEventBus` tipado; falava avisos genéricos por timer fixo (`2s`/`10s`) sem detalhar ficheiros/comandos/testes reais. |
| **System prompts** | `VoiceBehaviorProfile.systemPromptInstructions` (`VoiceConversationEngine.swift:391`), `VoiceOrchestrator.buildLocalBrainInstructions` (`1991`), `Workspace.wrapConversationalVoiceInstruction` (`WisdCode.swift:2393`), `CodexRealtimePromptCatalog`. | `wrapConversationalVoiceInstruction` prejudicava respostas técnicas no chat; `systemPromptInstructions` sugeria `"Hmm…"`; `buildLocalBrainInstructions` não conhecia diretório/Git/esforço ativos. |

---

## 3. Fluxo Alvo (Arquitetura Unificada V6)

1. **`UnifiedMessageEnvelope` & `ProjectContextResolver`:** texto e voz passam pelo mesmo pipeline (`submitUnifiedMessage`), preservando todos os metadados (IDs, diretório validado, Git/branch, agente, provedor, conta, modelo exato, esforço de raciocínio, permissões e histórico) sem rebaixamento silencioso de modelo.
2. **Separação em 4 camadas:**
   - **Conversation Controller:** interpreta intenção, distingue controle de voz × consulta de status × nova instrução paralela/enfileirada × cancelamento de tarefa × diálogo conceitual, aplicando guarda anti-alucinação com escalonamento automático.
   - **Task Orchestrator:** valida contexto do projeto, roteia e enfileira mensagens unificadas, mantendo isolamento multi-projeto e multi-conta.
   - **Agent Execution Engine:** executa `Codex`, `Antigravity` (`agy`) e `Claude Code` mantendo fidelidade de flags, permissões e diretórios, publicando eventos no **`ExecutionEventBus`**.
   - **Voice Presentation Engine:** traduz o relatório técnico completo (preservado integralmente no chat) em resumo falado natural sem ler blocos de código, JSON, logs, stack traces, tabelas nem caminhos extensos, evitando aberturas robóticas repetitivas.

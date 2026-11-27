# Full-Duplex Acústico, Interrupção Natural e Orquestração Paralela de Agentes

## 1. Pipeline Full-Duplex e Barge-In Instantâneo

- **Captura e Reprodução Simultâneas (`VoiceNativeAudioEngine.swift`):**
  - Captura com fallback automático caso VoiceProcessingIO (VPIO) falhe ou gere deadlock em dispositivos macOS, alimentando `AdaptiveJitterBuffer` em 24 kHz mono float (`Ring20ms P50 = 0.0003 ms`, `P95 = 0.0003–0.0004 ms`).
  - Ordem corrigida no tap de entrada: `onInputAudioChunk` executa **antes** de `onRawAudioBufferForSpeech`, garantindo que VAD e medidores RMS reflitam o bloco atual antes da avaliação do ASR.
- **Cancelamento Coordenado em Barge-In (`VoiceOrchestrator.performManualOrVADBarageIn`):**
  1. `BargeInCoordinator` registra o prefixo realmente ouvido pelo usuário e trunca o contexto do turno anterior (`barge-in measured = 0.050–0.121 ms` nos testes unitários de fila/jitter).
  2. `cancelAllOutgoingSpeechAndGeneration()` avança `PlaybackCancellationGate`, incrementa `activeTurnGenerationID`, cancela a `Task` SSE do `llama-server` / `Apple FM`, chama `kokoroTTS.cancelAll()` (callback C++ retorna `0`), `appleTTS.cancelAll()` e limpa `queuedSpeechChunks` + `outputJitterBuffer`.

---

## 2. Supressão de Eco com Cauda Acústica Real (`Hangover`)

- `AdaptiveJitterBuffer` agora exporta `playbackReferenceState` contendo `lastRenderedRMS`, `lastRenderUptimeNs` e `bufferedMs`.
- `AcousticEchoSuppressor` mantém janela de **cauda acústica (`hangoverNs = 420 ms`)** após o último frame drenado ao alto-falante, suprimindo eco residual sem exigir piso fixo rígido (`0.018`) sobre microfones silenciosos quando o alto-falante está realmente em repouso.

---

## 3. Orquestração Paralela de Agentes sem Bloquear a Conversa

- **Roteamento Explícito (`LocalQueryComplexityAnalyzer`):**
  - Perguntas conceituais (*"O Codex é bom para refatorar?"*, *"Como funciona um teste unitário no Xcode?"*) e perguntas curtas complexas (*"Por que deadlock acontece?"*, score semântico >= 0.65) permanecem locais em `.handleLocally`.
  - Solicitações diretas com verbo delegador (`"peça ao "`, `"peça pro "`, `"diga ao "`, `"rode "`) são encaminhadas como `.delegateToSpecialist` com flag `allowsConcurrentConversation = true`.
- **Confirmação Real via `VoiceDelegationDispatchResult`:**
  - `DesktopVoice.swift` e `WisdCode.swift` retornam `.dispatched(agentName)` apenas após confirmar `busy || !activeTasks.isEmpty`, ou `.awaitingUserApproval(reason)` / `.unavailable(reason)`.
  - O assistente **nunca confirma execução sem despacho real** e continua conversando normalmente enquanto o agente executa; ao concluir, `notifySpecialistTaskFinished` aguarda caso o usuário esteja falando (`.userSpeaking` / `.processing`) e anuncia naturalmente no estado `.listening`.

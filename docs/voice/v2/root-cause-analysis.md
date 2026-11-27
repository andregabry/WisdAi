# Diagnóstico Empírico de Causa Raiz — Loop "Molina" / "Comendo" e Incoerência Conversacional

## 1. Evidência Coletada no Armazenamento Local

Antes de aplicar correções, inspecionou-se diretamente o estado persistido no host:
- `~/Library/Application Support/WisdAI/Database/wisdai_history.sqlite` (thread `53C9FCCE-CED4-4868-89E3-E2944158C61B`, `seq=182..189`):
  - `seq=182` (`[Você]`): `"Molina"`
  - `seq=183` (`[WisdAI]`): *"Olá! Parece que você está mencionando o nome \"Molina\"..."*
  - `seq=184` (`[Você]`): `"Molina. Comendo"`
  - `seq=186` (`[Você]`): `"Molina. Comendo."`
  - `seq=188` (`[Você]`): `"Molina. Comendo. ."`
- `~/.codex/realtime-voice-continuity.json`: 14 itens na thread `53C9FCCE-CED4-4868-89E3-E2944158C61B`, reproduzindo exatamente a progressão cumulativa de string.
- `voice_knowledge_fts.sqlite`: `0` linhas (`voice_facts` vazio no instante da auditoria).

---

## 2. Causas Raiz Provadas Empiricamente

1. **Buffer de `SpeechTranscriber(.progressiveTranscription)` sem rotação de segmento (`VoiceSpeechUnderstanding.swift` & `VoiceGateway.swift`):**
   - Experimentos controlados (`SpeechTranscriber` no macOS `27.0.1`) comprovaram que `.progressiveTranscription` **não zera o `range` temporal** (`[0.00..2.44]` → `[0.00..5.77]`) quando apenas variáveis Swift (`committedPrefix` / `activeVolatileText`) são limpas em `commitCurrentUtterance()`.
   - Como o mesmo fluxo contínuo permanecia aberto, qualquer eco residual ou ruído ambiente fazia o `SpeechAnalyzer` reemitir `"Molina"`, depois `"Molina. Comendo"`, `"Molina. Comendo."` e `"Molina. Comendo. ."`.
   - Verificou-se também que `await analyzer.finalize(through:)` bloqueia indefinidamente se não houver buffers subsequentes após o último áudio, enquanto **rotacionar uma nova instância de `SpeechAnalyzer` com `.timeIndexedProgressiveTranscription` e `modelRetention: .processLifetime`** prepara em **`2.7 ms`** em regime quente (`13.3 ms` a frio) com zero vazamento de prefixo entre turnos.

2. **Referência de Eco Incorreta e Ordem Invertida do Tap Acústico (`VoiceNativeAudioEngine.swift` & `VoiceOrchestrator.swift`):**
   - `onRawAudioBufferForSpeech` era disparado antes de `onInputAudioChunk` atualizar o estado acústico/VAD.
   - `AcousticEchoSuppressor` recebia `micRMS` no lugar do RMS real drenado pelo `AdaptiveJitterBuffer`, sem janela de decaimento pós-reprodução.
   - Correção: `AdaptiveJitterBuffer` passou a publicar `playbackReferenceState` real (`lastRenderedRMS`, `lastRenderUptimeNs`, `bufferedMs`, zerados ao dar flush/reset), e `AcousticEchoSuppressor` passou a aplicar janela de **cauda acústica (`hangoverNs = 420 ms`)** permitindo apenas barge-in humano forte quando acima do piso de eco.

3. **Ausência de Isolamento por Sessão/Época (`VoiceOrchestrator.swift`):**
   - Respostas parciais tardias de STT ou chunks de TTS anteriores podiam sobrepor turnos novos após reinicialização ou barge-in.
   - Correção: inclusão de `sessionGenerationID`, `activeTurnGenerationID`, `PlaybackCancellationGate` e `utteranceEpoch` / `segmentEpoch` verificados em todos os pontos assíncronos.

4. **Re-injeção de Memória Contaminada (`CodexRealtimeContinuityStore` & `VoiceMemoryAndTelemetry.swift`):**
   - Turnos espúrios salvos em `realtime-voice-continuity.json` voltavam para o `seedFromHistoryItems` da próxima sessão.
   - Correção: filtragem estrutural via `VoiceMemoryHygieneAnalyzer.filterCleanContextItems` (sem listas de palavras fixas), além de inspetor visual e seletivo no **Laboratório de Voz** que identificou **11 registros contaminados** no arquivo real do usuário sem auto-excluir histórico legítimo.

---

## 3. Telemetria Diagnóstica de 11 Estágios (Opt-In)

Em `VoiceMemoryAndTelemetry.swift`, `VoicePipelineTraceStage` instrumenta sob demanda os 11 estágios do turno:
1. Microfone → 2. Processamento Acústico → 3. Transcrição Parcial → 4. Transcrição Final → 5. Contexto Recuperado → 6. System Prompt → 7. Modelo Conversacional → 8. Resposta Textual → 9. Adaptação Oral → 10. Síntese Vocal → 11. Reprodução.

`telemetry.enablePipelineDiagnosticsTrace` permanece **`false` por padrão**, mantido apenas em memória RAM durante uso explícito e limpo ao desativar.

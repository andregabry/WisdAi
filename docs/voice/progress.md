# Registro Contínuo de Progresso — WisdAI Autonomous Voice Intelligence Engine

> Última atualização: 2026-11-27 06:39 UTC (Correção P0 de Runtime Concluída)

---

## Correção P0 de Runtime & Diagnóstico (2026-11-27)

- **Causa raiz comprovada (`sample` + sonda CoreAudio + logs `05:44`):**
  1. **Deadlock ABBA na Main Thread (`VoiceNativeAudioEngine.swift:1250` e `1282`):** Ao iniciar captura + reprodução full-duplex com `setVoiceProcessingEnabled(true)`, o CoreAudio/AVFAudio (`macOS 27.0.1`) falhava `newEngine.start()` com `Error -10875` (`PerformCommand(*outputNode, kAUInitialize, NULL, 0)`). Como `.AVAudioEngineConfigurationChange` estava registado com `queue: .main`, ao liberar `newEngine` (`-[AVAudioEngine dealloc] -> _dispatch_sync_f_slow` na Main Thread) enquanto a queue `engine` bloqueava em `-[NSOperation waitUntilFinished]` aguardando `OperationQueue.main`, ocorria deadlock ABBA antes mesmo do fallback.
  2. **Janela `0 ch, 0 Hz` pós-teardown CoreAudio VPIO:** Após falha/encerramento de `VoiceProcessingIO`, `outputNode.outputFormat(forBus: 0)` ficava `0 Hz / 0 ch` por `~430 ms`; tentativas imediatas caíam em `-10875` (`IsFormatSampleRateAndChannelCountValid(outputHWFormat)`).
  3. **Injeção de dispositivo `inputNode` (`-10851`):** `applyAudioUnitDevice` alterava `inputNode.audioUnit` mesmo no dispositivo padrão do sistema.
  4. **Reconhecimento Progressivo & Propagação de Erros:** `SpeechTranscriber` atualizado para `preset: .progressiveTranscription` (`VoiceSpeechUnderstanding.swift:167`) e erros de subsistema agora propagam via `lastErrorSummary` / `activeBannerNotice` / `voiceErrorMessage` + card permanente de diagnóstico em Configurações → Voz (`VoiceHUDViews.swift:961`).
- **Validação final pós-última edição (`2026-11-27`):**
  - `run-voice-smoke.sh`: `VOICE_SMOKE_ALL_PASS` (`13` conjuntos de testes, `Barge-in = 0.051 ms`, `82.304` amostras PCM, testes P0 de deadlock/playback e diagnóstico sanitizado).
  - `run-state-smoke.sh`: `PASS`.
  - `run-recovery-smoke.sh`: `PASS`.
  - Bateria Incremental **Testes A–I**: `TESTS_A_TO_I_PASS` (`TEST_A` Interface, `TEST_B` Captura `33.600` amostras, `TEST_C` Reprodução `Alto-falantes (MacBook Pro) · 260 ms`, `TEST_D` ASR PT-BR `"Olá assistente, como está o projeto"`, `TEST_E` TTS `Luciana · 72.386 amostras`, `TEST_F` `Apple FoundationModels (On-Device ANE)`, `TEST_G` `StartupMs: 2416.0 | BargeMs: 0.266`, `TEST_H` delegação assíncrona ativa, `TEST_I` operação independente sem agentes externos).
  - `WisdAI.app`: compilado Release (`-O`), assinado `--deep --strict`, reiniciado (`PID 84467`).

---

## Status Final das Fases (Seção 20)

| Fase | Escopo | Status | Evidência Verificada |
|---|---|---|---|
| **Fase 1** | Auditoria WisdAI + diagnóstico `"Conectando voz"` + OpenJarvis (`556ddf32`) | **Concluída** | Causas raiz em [current-implementation-audit.md](current-implementation-audit.md) e análise completa em [openjarvis-analysis.md](openjarvis-analysis.md). |
| **Fase 2** | Pesquisa aberta (Moshi, PersonaPlex, MiniCPM-o, Kokoro, CosyVoice, Apple FM/Speech, VAD) | **Concluída** | [model-comparison.md](model-comparison.md), [hardware-requirements.md](hardware-requirements.md), [licensing.md](licensing.md). |
| **Fase 3** | Prova de Conceito isolada (`VoicePoC.swift`) em Apple M2 8 GB | **Concluída** | `WISDAI_VOICE_POC_PASS` pós-edição final: Áudio `167.15 ms`, SpeechTranscriber `130.09 ms`, FM warm `511.8 ms`, Barge-in `0.121 ms`. |
| **Fase 4** | Decisão Arquitetural + Conjunto completo em `docs/voice/` | **Concluída** | Arquitetura C (Adaptativa Local-First) documentada em [architecture.md](architecture.md) e guias irmãos. |
| **Fase 5** | Módulos independentes `WisdomUpVoiceIntelligence` (`VoiceSpeechUnderstanding`, `LocalIntelligenceEngine`, `VoiceIdentityProfile`, eco & FTS5) | **Concluída** | Módulos desacoplados sem dependência de UI/chat, com supressão de eco próprio, SQLite FTS5 trust-tier e monitor de pressão de memória. |
| **Fase 6** | Integração Orquestrador + Remoção do bloqueio WebRTC + HUD/Settings | **Concluída** | `toggleVoiceConversation()` usa sempre o Motor Autônomo WisdAI; `UnifiedLocalSTTCoordinator` + `BoundedVoicePermissions` (2,0s) + watchdog `2,5s` eliminam `"Conectando voz"` infinito. |
| **Fase 7** | Otimização (warm-up paralelo `prewarm` + `VoiceTTSWarmupCoordinator`, anti-eco, pressão RAM) | **Concluída** | Warm-up silencioso de TTS e pré-aquecimento ANE executam em paralelo ao arranque sem bloquear a interface. |
| **Fase 8** | Validação Final, Regressão e Build Release `-O` | **Concluída** | `run-voice-smoke.sh`, `run-state-smoke.sh`, `run-recovery-smoke.sh` e `VoicePoC.swift` aprovados; `dist/WisdAI.app` compilado em Release `-O`, assinado `--deep --strict` e em execução. |

---

## Resultados Pós-Edição Final (Apple M2 · 8 GB RAM · macOS 27.0.1)

- **Suíte `run-voice-smoke.sh`:** `VOICE_SMOKE_ALL_PASS`
  - Barge-in & truncamento ao prefixo ouvido: `0.470 ms`
  - Síntese real local Apple Natural PCM: `82.304` amostras float @ `24 kHz`
  - Benchmark DSP: `Ring20ms P50=0.0003ms P95=0.0003ms`, `Resample48k->16k+PCM16 P50=0.0009ms P95=0.0010ms` (`Footprint=13.1 MB`, `CPU=8.3%`)
  - Validação do roteador autônomo local (conversa local, troca de idioma, status real de tarefas sem inventar estado, delegação paralela Codex/Antigravity/Claude e bloqueio de risco alto)
  - Validação do supressor de eco próprio e quarentena anti-injeção `.untrusted` no SQLite FTS5
  - Invariância da `VoiceIdentityDescriptor` entre provedores/agentes e resolução Local-First
- **Suíte `run-state-smoke.sh`:** `PASS` (sem regressões de chat, projetos, contas, cotas, fallback e voz)
- **Suíte `run-recovery-smoke.sh`:** `PASS` (sem regressões de recuperação, limites e privacidade efêmera)
- **PoC Nativa `VoicePoC.swift`:** `WISDAI_VOICE_POC_PASS`
  - `POC_1_AUDIO_INIT_MS=167.15 | profile=low8GB`
  - `POC_2_SPEECH_ANALYZER_INIT_MS=130.09 | installed=pt_PT,pt_BR`
  - `POC_3_PAUSE_HOLD=true intent=pauseToThinkHold`
  - `POC_4_LOCAL_LLM coldMs=5733.3 warmFirstMs=511.8 warmTotalMs=865.6 toolTurnMs=507.1 enSwitchMs=471.0`
  - `POC_5_TTS_TTFA_MS=1019.9 totalSynthMs=1090.9 samples24k=175244`
  - `POC_6_BARGE_IN_MS=0.121 flushedSamples=143232`
  - `POC_7_RESOURCES ramBefore=2.1MB ramAfter=14.7MB cpu=12.4% totalPoCMs=10515.7`
- **Build & Assinatura `dist/WisdAI.app`:**
  - Compilação Release (`-target arm64-apple-macosx14.0 -O`) e assinatura `codesign --force --sign -` + `codesign --verify --deep --strict` concluídas com saída `0`.
  - Processo verificado em execução (`WisdAI` PID `59807` e `codex app-server` PID `59829`).

---

## Observações Honestas de Escopo e Ambiente

1. **Pesos opcionais `Kokoro-82M` (`Apache-2.0`, ~320 MB):** catalogados em Configurações → Voz com verificação prévia de RAM e espaço livre em disco; não foram baixados automaticamente sem confirmação explícita do utilizador.
2. **Interação ao vivo com microfone na GUI:** os testes automatizados validam captura, pipeline DSP, STT on-device, Apple FoundationModels, síntese PCM real em memória, roteamento de agentes e build assinado; a primeira conversa presencial via microfone no app gráfico depende da concessão interativa de permissão de Microfone pelo utilizador no macOS caso ainda não esteja autorizada no bundle atual.

# P0 Audio Engine Regression Fix — `com.apple.coreaudio.avfaudio error -10875`

**Data:** 2026-11-27  
**Branch:** `feature/voice-intelligence-v3` (sem merge automático em `main`)  
**Incidente P0:** `[Reprodução (Áudio)] Não foi possível iniciar o motor de áudio nativo: The operation couldn’t be completed. (com.apple.coreaudio.avfaudio error -10875).`  
**Hardware / Ambiente avaliado:** Mac14,7 Apple Silicon M2 (8.0 GB RAM), macOS 27.0.1 (`26A434`), dispositivos ativos no momento da reprodução: `Microfone (MacBook Pro)` (`id=78`, `builtIn`), `Alto-falantes (MacBook Pro)` (`id=71`, `builtIn`) e `Microfone do iPhone’s Andre|Gabry` (`id=83`, `continuityOrVirtual`).

---

## 1. Causa Raiz Comprovada Empiricamente

A auditoria direta com binários reprodutores contra CoreAudio / `AVFAudio` demonstrou quatro fatores combinados que levavam à falha `-10875` (`kAudioUnitErr_FailedInitialization`):

1. **Ordem inválida de habilitação do `VoiceProcessingIO` (`VoiceNativeAudioEngine.swift`, originado em `d2129bb` e preservado em `8506883`):**
   - `configureAndStartEngine` chamava `try newEngine.inputNode.setVoiceProcessingEnabled(true)` **antes** de anexar e conectar o grafo de saída (`AVAudioSourceNode -> mainMixerNode -> outputNode`).
   - Em macOS 27.0.1 (`26A434`), essa ordem falhou **`15/15` ciclos diretos com `-10875`**, pois o agregado interno de VPIO inicializava sem roteamento conectado do mixer de saída.
   - Invertendo a ordem — anexar/conectar `AVAudioSourceNode -> mainMixerNode` (e consultar o formato de `outputNode`) **antes** de `setVoiceProcessingEnabled(true)` — a inicialização VPIO passou **`30/30` ciclos consecutivos em sonda isolada (`ok=30, fail=0`)** e **`32/32` ciclos completos no `VoiceNativeAudioEngine` (`vpio=true`, 48 kHz / 7 ch in, 48 kHz / 2 ch out)**.

2. **Reprodução exata do erro fatal `-10875` em rota Continuity / Multi-Clock (`Microfone do iPhone’s Andre|Gabry` + `Alto-falantes (MacBook Pro)`):**
   - Quando a rota de entrada é `.continuityOrVirtual` (ou dispositivo com domínio de clock distinto da saída em AUHAL sem VPIO), `allowVP` já era `false` e o motor tentava abrir captura + reprodução simultaneamente em um único `AVAudioEngine`.
   - Sonda isolada comprovou que captura isolada no Continuity (`id=83`) e reprodução isolada em `Alto-falantes` (`id=71`) inicializam com `START OK`, mas **ambos em um único `AVAudioEngine` falham com `-10875`** — propagado em `VoiceOrchestrator.swift` literalmente como `[Reprodução (Áudio)] Não foi possível iniciar o motor de áudio nativo: The operation couldn’t be completed. (com.apple.coreaudio.avfaudio error -10875).`.

3. **Vazamento de `CADefaultDeviceAggregate-*`, janela HAL pós-teardown de VPIO e falha ao limpar estado:**
   - Após falha ou encerramento de VPIO, `CoreAudio` mantém o formato de hardware de saída em `0.0 Hz / 0 ch` transitoriamente (`delay=0ms -> ERR -10875`, recuperando após espera de estabilização HAL) e registra transitoriamente dispositivos agregados efêmeros `CADefaultDeviceAggregate-<pid>-*`.
   - `CoreAudioDeviceCatalog.enumerateDevices()` não filtrava `CADefaultDeviceAggregate-*`, e `stopEngineOnly()` checava `if wantCapture` **depois** que `startFullDuplexAsync` já havia sobrescrito `wantCapture`, deixando taps/VPIO sem limpeza determinística em trocas de modo e ignorando `OSStatus` de `AudioUnitSetProperty`.

4. **Ausência de autoridade única serializada de ciclo de vida e concorrência no encerramento Kokoro/Piper:**
   - `startFullDuplexAsync` suspendia em `await waitForValidOutputHWFormat(...)` na `MainActor` sem serialização nem geração cancelável, permitindo sobreposição entre `start`, `stop`, seletores de dispositivo e `scheduleEngineRecovery` (`.AVAudioEngineConfigurationChange` sem limite de orçamento de recuperação).
   - Em `VoiceNeuralRuntime.swift`, `KokoroNeuralTTSProvider.deinit` e `SherpaVitsPiperTTSProvider.deinit` chamavam `unloadSync()` síncrono na thread de desalocação enquanto `synthQueue`/`queue` ainda executava inferência C++ (`Ort::Exception: GetElementType is not implemented`).

---

## 2. Correções Arquiteturais Implementadas

- **Autoridade única serializada em `codex/desktop/macos/VoiceNativeAudioEngine.swift`:**
  - Introduzidos `AudioEngineLifecycleState`, `AudioEngineOperationKind`, `AudioEngineFailureRecord` e expansão de `AudioEngineRuntimeTelemetry`.
  - Todas as transições assíncronas (`startFullDuplexAsync`, `selectInputDevice`, `selectOutputDevice`, recuperação de `.AVAudioEngineConfigurationChange`) passam por fila serializada (`runSerializedLifecycleOperation`) com token `lifecycleGeneration`, debounce de `280 ms` e limite deslizante de **3 recuperações automáticas em 12 s** (eliminando loops infinitos).
  - Filtro de `CADefaultDeviceAggregate-*`, validação prévia `isDeviceAlive` + `nominalSampleRate > 0` + canais `> 0` + permissão de microfone, espera HAL (`waitForHALFormatsReady`) e remoção garantida de tap + `setVoiceProcessingEnabled(false)` em `teardownEnginesCleanly()`.
  - Ordem corrigida do grafo VPIO (`AVAudioSourceNode -> mainMixerNode` antes de `setVoiceProcessingEnabled(true)`).
  - **Modo de Compatibilidade Separado (`configureAndStartSplitEngines`):** quando rota Continuity/Virtual ou cross-clock recusa AUHAL duplex único, inicializa `playbackEngine` e `captureEngine` independentes com supressão de eco por software explícita (`.degradedCompatibility`), sem mascarar perda de AEC hardware; se o dispositivo selecionado recusar mesmo separado e existir hardware Built-In integrado distinto, realiza fallback único para Built-In antes de falhar explicitamente.
  - Módulos conversacionais (`VoiceBehaviorEngine`, `VoiceVocalizationCache`, `VoiceOrchestrator`) permanecem desacoplados: não criam nem manipulam `AVAudioEngine`.
- **Segurança de ciclo de vida ONNX/Sherpa (`codex/desktop/macos/VoiceNeuralRuntime.swift`):**
  - `KokoroNeuralTTSProvider.deinit` e `SherpaVitsPiperTTSProvider.deinit` agora agendam `destroyTts` na própria serial queue (`synthQueue` / `queue`), impedindo destruição concorrente durante inferência.
- **Atribuição honesta de falhas & Diagnóstico completo (`codex/desktop/macos/VoiceOrchestrator.swift` e `codex/desktop/macos/VoiceHUDViews.swift`):**
  - Classificação fiel entre captura/VPIO e reprodução segundo `AudioEngineFailureRecord.operation`, `startupWatchdogTask` ajustado para `5,0 s`, sincronização de topologia em `onDeviceTopologyChanged`.
  - HUD, janela de Diagnóstico Permanente e `exportSanitizedDiagnosticsReport()` (redigido por `VoiceLogRedactor`) agora expõem versão/commit, estado `AudioEngineLifecycleState`, estado `AudioUnit`, dispositivos + sample rate + canais de entrada/saída, estado `VoiceProcessingIO`, estado do tap, grafo conectado, última operação, último erro + código `OSStatus`, contadores `restartCount` / `recoveryCount`, estado da sessão e motores ativos (STT/LLM/TTS).

---

## 3. Regressão, Testes Executados e Evidências

- `codex/desktop/macos/tests/VoiceSmokeTests.swift` ampliada com `testNativeAudioEngineThirtyCycleAndRecoveryRegression()` e verificação dos novos campos em `testPermanentDiagnosticsReportAndComponentStates()`.
- Resultados observados após as últimas edições nos arquivos Swift:
  - `bash codex/desktop/macos/tests/run-voice-smoke.sh`: **`VOICE_SMOKE_ALL_PASS`** (exit `0`), incluindo:
    - `PASS: Native AudioEngine 32-cycle VPIO, concurrency serialization, split-engine Continuity & route switch regression` (`32/32` ciclos VPIO sem `-10875`, concorrência serializada, split-engine Continuity `Microfone do iPhone’s Andre|Gabry` operacional e recuperação pós-troca de rota);
    - `PASS: Real Kokoro-82M neural synthesis (load=604ms, ptBR=3299ms/117129@24kHz, en=3224ms, es=2852ms)`;
    - `PASS: Real llama.cpp Metal + Qwen3-1.7B inference (load=6826ms, TTFT=126ms, total=579ms, replyChars=95)`;
    - `PASS: V3 Behavior Engine, Acoustic F0, Cache (Kokoro hit=0.002ms) & Priority Audio`;
    - `PASS: Permanent diagnostics probes & sanitized GPU/CPU/RAM report`.
  - `bash codex/desktop/macos/tests/run-state-smoke.sh`: **`PASS`** (exit `0`).
  - `bash codex/desktop/macos/tests/run-recovery-smoke.sh`: **`PASS`** (exit `0`).

---

## 4. Limitações Residuais Honestas

- Em dispositivos Bluetooth HFP/A2DP ou entradas Continuity/Virtual (`Microfone do iPhone`), o `VoiceProcessingIO` (AEC de hardware da Apple) não é suportado em grafo único com alto-falantes do Mac; o motor ativa explicitamente **Modo de Compatibilidade Separado** (`.degradedCompatibility`) com supressão acústica por software (`AcousticEchoSuppressor`), avisando o usuário sem simular AEC de hardware.
- Os caminhos legados secundários em `DesktopVoice.swift` (ditado legado e stream WebRTC legado, que não são acionados pelo botão principal de voz conversacional via `WisdVoiceOrchestrator`) permanecem inalterados neste fix P0 para manter escopo cirúrgico e seguro.

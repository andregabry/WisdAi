# Auditoria Integral do Código-Fonte e Histórico da Branch (`feature/voice-intelligence-v2`)

**Data da auditoria:** 2026-11-27  
**Repositório:** `https://github.com/andregabry/WisdAi`  
**Branch base:** `main` (`d2129bb`)  
**Branch de desenvolvimento:** `feature/voice-intelligence-v2`  
**Ambiente verificado:** macOS `27.0.1` (`26A434`), Apple M2 (`8.0 GB RAM`), Apple Swift `6.4.2`

---

## 1. Sincronização e Avaliação Técnica dos Commits Anteriores

Antes de qualquer modificação na branch `feature/voice-intelligence-v2`, os dois commits remotos preexistentes sobre `main` (`d2129bb`) foram inspecionados criticamente:

### Commit `d40f3dd` — `fix(voice): expose unavailable local brain and avoid implicit agent delegation`
- **O que resolveu corretamente:**
  - Eliminou respostas genéricas simulando compreensão quando `LocalConversationalBrain` falhava ou estava indisponível.
  - Removeu o roteamento acidental por simples menção ao nome de um agente (`Codex`, `Claude`, `Gemini`) em frases conceituais.
- **Lacunas técnicas identificadas e corrigidas na V2:**
  - `hasDirectDelegateVerb` não cobria locuções usuais em português como `"peça ao "`, `"peça pro "`, `"peça para o "`, `"fala pro "` e `"diga ao "`, bloqueando comandos canônicos como *"Peça ao Codex para analisar a autenticação do projeto e continue conversando comigo sobre a arquitetura"*.
  - Termos conceituais como `"compile"` ou `"execute"` podiam disparar delegação mesmo em perguntas puramente explicativas (ex.: *"Como funciona..."*).
  - Injeção do prefixo literal `"[Responda naturalmente em português brasileiro] "` dentro de `userText` poluia o turno do usuário em modelos locais e histórico.
  - Em falhas transitórias, `LocalConversationalBrain` travava permanentemente em `.compactHeuristicFallback` sem expor `lastErrorDetail`.

### Commit `69ce6cf` — `fix(voice): gate transcripts on acoustic activity and stop persisting raw ASR as facts`
- **O que resolveu corretamente:**
  - Removeu a gravação indiscriminada de transcrições brutas via `storeFact` no SQLite FTS5.
  - Introduziu verificação de atividade acústica antes de processar transcrições parciais.
- **Lacunas técnicas identificadas e corrigidas na V2:**
  - Bloqueio rígido por `userSpeechStartedAtNs != 0` com piso fixo (`0.018`) arriscava descartar fala legítima em microfones de ganho baixo.
  - Faltava isolamento por época/geração (`sessionGenerationID`, `activeTurnGenerationID`, `utteranceEpoch`) para impedir bleed entre sessões ou após barge-in.
  - O `SpeechTranscriber` continuava sem finalização/rotação de segmento entre turnos consecutivos.
  - Histórico contaminado pré-existente em `~/.codex/realtime-voice-continuity.json` permanecia sendo re-injetado no prompt a cada nova sessão.

---

## 2. Inventário Arquitetural dos Módulos de Voz e Integração (`codex/desktop/macos/`)

| Arquivo | Responsabilidade Principal na V2 | Modificado/Criado |
| :--- | :--- | :--- |
| `VoiceNativeAudioEngine.swift` | Full-duplex CoreAudio (`AdaptiveJitterBuffer` com envelope RMS + timestamp real de renderização para AEC, ring buffer 20 ms, reamostrador `AudioPCMConverter`) | Atualizado |
| `VoiceSpeechUnderstanding.swift` | `SpeechAnalyzerOnDeviceSTTProvider` com `.timeIndexedProgressiveTranscription`, `.processLifetime`, `utteranceEpoch` e `AcousticEchoSuppressor` com janela de cauda de 420 ms | Atualizado |
| `VoiceGateway.swift` | Protocolos streaming STT/TTS/S2S, `connectionEpoch` / `segmentEpoch` / `sessionEpoch` em transportes Apple/OpenAI/Gemini/Deepgram | Atualizado |
| `LocalIntelligenceEngine.swift` | `VoiceBrainEngineKind` (`adaptiveAuto`, `appleFoundationModels`, `localLlamaCppMetal`, `localMLXServer`), complexidade semântica, remoção de meta-tags, `VoiceDelegationDispatchResult` | Atualizado |
| `VoiceIdentityProfile.swift` | Identidade vocal WisdAI (`Aurora`, `Atlas`, `Aria`), perfis `VoiceHardwareTier`, presets `KokoroVoicePreset`, catálogo SHA-256 e `VoiceModelAssetManager` com consentimento explícito | Atualizado |
| `VoiceNeuralRuntime.swift` | Runtime C ABI `dlopen` (`sherpa-onnx` v1.13.8) para `KokoroNeuralTTSProvider`, processo loopback `LocalLlamaServerBrainRuntime` (`llama.cpp` Metal), cliente `LocalMLXClientRuntime`, `NativeS2SRuntimeProbe`, `VoiceAudioPreviewPlayer` | Criado |
| `VoiceConversationEngine.swift` | FSM determinística, `HybridTurnTakingAnalyzer`, `VoiceResponseAdapter`, `TechnicalPronunciationDictionary` (ajuste PT/EN/ES) e `BargeInCoordinator` | Atualizado |
| `VoiceMemoryAndTelemetry.swift` | Memória em camadas portátil, SQLite FTS5 com quarentena, trace opt-in de 11 estágios (desativado por padrão) e `VoiceMemoryHygieneAnalyzer` estrutural | Atualizado |
| `VoiceOrchestrator.swift` | Orquestração por épocas (`PlaybackCancellationGate`, `sessionGenerationID`), seleção neural de TTS, fiação do cérebro local, descarte automático sob pressão de memória | Atualizado |
| `VoiceLaboratoryView.swift` | Interface **Laboratório de Voz**: troca de cérebro/TTS, teste A/B + WAV, perfis de hardware, métricas ao vivo, trace opt-in e inspetor/limpador de memória | Criado |
| `VoiceHUDViews.swift` | HUD/Orb de voz e cartão compacto de status real de modelos | Atualizado |
| `DesktopSettings.swift` | Integração de `VoiceLaboratoryView` em **Configurações → Voz** | Atualizado |
| `DesktopVoice.swift` & `WisdCode.swift` | Verificação real `VoiceDelegationDispatchResult` em tarefas em segundo plano e filtro contra gravação de fragmentos vazios na continuidade | Atualizados |
| `DesktopCodexVoiceWebRTC.swift` | Métodos `allThreads()` e `removeMatchingItems(...)` em `CodexRealtimeContinuityStore` para auditoria/remoção controlada | Atualizado |
| `build-dmg.sh` | Inclusão explícita de `VoiceNeuralRuntime.swift` e `VoiceLaboratoryView.swift` na compilação Release do app | Atualizado |
| `tests/VoiceSmokeTests.swift` | Suíte expandida cobrindo regressões de Fase 1–2, catálogo V2, consentimento, síntese neural Kokoro real e inferência `llama.cpp` + `Qwen3-1.7B` | Atualizado |

---

## 3. Dependências de Terceiros Auditadas

- **Sem acoplamento estrutural a provedor único:** todo o fluxo local-first opera sem OpenAI Realtime, Gemini Live, Deepgram ou ElevenLabs. APIs pagas seguem desativadas por padrão em `VoicePolicyPreferences.strictDefault`.
- **Runtimes opcionais fora do repositório Git e do `.app` DMG:** baixados apenas mediante consentimento explícito em `~/Library/Application Support/WisdAI/Voice/{Runtimes,Models}/` com verificação obrigatória de SHA-256.

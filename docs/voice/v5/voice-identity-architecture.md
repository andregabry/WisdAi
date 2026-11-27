# WisdAI V5 — Arquitetura da Identidade Vocal (`VoiceIdentityManager`)

**Módulo principal:** [`VoiceIdentityProfile.swift`](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/VoiceIdentityProfile.swift)  
**Orquestração:** [`VoiceOrchestrator.swift`](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/VoiceOrchestrator.swift)

---

## 1. Fonte Única de Verdade (`VoiceIdentityManager`)

Todo o ecossistema de voz desktop lê e escreve através de uma única configuração unificada codificada em JSON sob a chave `wisdai.voice.unifiedConfig.v5` (`UnifiedVoiceConfig`):

- `identityId`: `WisdVoicePersona` (`.jarvis`, `.aurora`, `.atlas`, `.aria`)
- `engineId`: `VoiceTTSEngineKind` (`.supertonic3`, `.kokoro82M`, `.autoLocal`, `.appleNaturalPCM`, `.sherpaPiperVits`, `.chatterbox`, `.cosyVoice2`, etc.)
- `modelId`: identificador exato do pacote em disco (`supertonic-3-multilang-int8`, `kokoro-82m-ptbr-onnx`, `apple-natural-pcm`, etc.)
- `speakerId`: identificador efetivo do locutor (`supertonic:m2`, `supertonic:m4`, `pm_alex`, `bm_george`, `pf_dora`, etc.)
- `language`: `VoiceLanguageVariant` (`.portugueseBR`, `.portuguesePT`, `.englishGB`, `.englishUS`, `.spanishES`)
- `vocalGender`: `WisdVoiceTimbre` (`.male`, `.female`)
- `speechRate`: cadência efetiva (`0.75...1.30`)
- `personalityId`: `VoicePersonalityStyle` (incluindo `.jarvisExecutive`)
- `design`: `VoiceDesignConfig` (`flowMatchingSteps`, `cadence`, `pauseScale`, `warmth`, `directness`, `expressivity`, `formality`, `detailLevel`)

Sempre que o estado muda, `VoiceIdentityManager` sincroniza todas as chaves legadas (`wisdcode.voice.*` e `wisdai.voice.*`) e propaga a atualização para `VoiceController` (sem loop de reentrância via `isApplyingIdentityManagerUpdate` / `isSyncingFromIdentityManager`).

---

## 2. Rastreabilidade em 4 Camadas (`Requested → Configured → Loaded → Inferred`)

Para impedir divergências silenciosas entre UI e áudio real:

1. **`requestedSnapshot` (`VoiceSelectionSnapshot`)**: o que o usuário pediu explicitamente (identidade, gênero, motor, speaker, idioma e `numericSpeakerSID` esperado).
2. **`configuredSnapshot` (`VoiceSelectionSnapshot`)**: o que o pipeline resolveu após validar disponibilidade em disco e suporte linguístico real (ex.: Kokoro rejeita `pt-PT` e resolve honestamente para alternativa compatível).
3. **`loadedSnapshot` (`VoiceLoadedRuntimeSnapshot`)**: modelo realmente carregado em memória RAM (`modelId`, `sampleRateHz`, `loadedSpeakerCount`).
4. **`inferredSnapshot` (`VoiceInferredRuntimeSnapshot`)**: gravado após cada síntese real (conversa ou prévia), registrando:
   - motor que executou (`actualEngineId`),
   - modelo e speaker exatos (`actualModelId`, `actualSpeakerId`, `actualNumericSID`),
   - idioma fonetizado (`actualLanguage`), taxa de amostragem (`actualSampleRateHz`), latência (`synthLatencyMs`),
   - **frequência fundamental mediana medida no PCM (`estimatedF0Hz` via `AcousticFeatureExtractor.measureMedianFundamentalFrequencyHz`)**,
   - indicador booleano `fallbackOccurred` e alerta explícito `divergenceAlert` caso ocorra fallback ou desacordo de timbre (como fallback macOS para voz feminina quando usuário pediu voz masculina).

---

## 3. Troca de Voz em Tempo Real (Live Switching Zero-10875)

Durante uma sessão ativa, alternar identidade, gênero, speaker ou motor executa `cancelPendingSpeechForLiveVoiceSwitch()`:

1. Avança `playbackGate` (`PlaybackCancellationGate`), descartando imediatamente pacotes pendentes em geração.
2. Cancela apenas tarefas TTS ativas (`kokoroTTS.cancelAll()`, `supertonicTTS.cancelAll()`, etc.).
3. Drena apenas o buffer circular de saída via `audioEngine.bargeInFlushPlayback()` e `audioEngine.flushAuxiliaryVocalizationOnly()`.
4. **Não** chama `audioEngine.stop()` nem recria `AVAudioEngine` / VoiceProcessingIO — preservando integralmente a correção da regressão CoreAudio `-10875`.
5. Invalida e pré-aquece `VocalizationCacheEngine` com o novo contexto.

---

## 4. Isolamento Estrito da Cache Vocal (`VoiceVocalizationCache.swift`)

A assinatura [`VocalizationIdentityContext`](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/VoiceVocalizationCache.swift) v5 isola amostras pré-renderizadas em memória e em disco (`v5_<sha256>`) por **8 dimensões**:

`v5 | engineID | modelID | modelVersion | identityID | speakerID | voicePreference | language | r<rateBucket> | prosodySignature`

Diretórios legados sem prefixo `v5_` criados em versões anteriores são purgados automaticamente uma única vez na inicialização (`purgeNonV5Directories`), evitando reaproveitamento de backchannels femininos em sessões masculinas.

# WisdAI V5 — Neural Voice Design Engine (Honesto por Capacidade Real)

**Estruturas principais:**  
- `VoiceDesignConfig` em [`VoiceIdentityProfile.swift`](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/VoiceIdentityProfile.swift)  
- `EngineProsodyCapabilities` em [`VoiceBehaviorEngine.swift`](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/VoiceBehaviorEngine.swift)

---

## 1. Princípio de Honestidade Técnica

Em implementações anteriores, controles visuais de personalidade, emoção ou tom podiam existir desconectados do que o motor TTS realmente aceita. Na V5, nenhum parâmetro fictício é exibido como ajuste acústico ativo:

| Controle | Supertonic-3 ONNX | Kokoro-82M ONNX | Piper VITS | Apple Natural PCM | Loopback MLX (`Chatterbox`/`CosyVoice`) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Identidade / Speaker Real** | ✅ `sid=0..9` (`M1..M5`, `F1..F5`) | ✅ `sid=0..53` (`pm_alex`, `bm_george`, `pf_dora`, etc.) | ⚠️ 1 voz por arquivo `.onnx` | ✅ `AVSpeechSynthesisVoice` | ✅ Param `"voice"` REST |
| **Velocidade Real (`speed`)** | ✅ `0.75...1.30×` | ✅ `0.75...1.30×` | ✅ `0.75...1.30×` | ✅ Mapeada ao `AVSpeechUtterance.rate` | ✅ Campo JSON `"speed"` |
| **Passos Flow Matching (`num_steps`)** | ✅ **Real (`4...12` passos no C ABI)** | ❌ Oculto | ❌ Oculto | ❌ Oculto | ❌ Oculto |
| **Escala de Pausas (`silence_scale`)** | ✅ Real (`0.12...0.45`) | ✅ Real (`0.12...0.45`) | ✅ Real (`0.12...0.45`) | ⚠️ Apenas pausas entre cláusulas | ⚠️ Via texto/pontuação |
| **Pitch / Entonação sintética** | ❌ Oculto (timbre vem do vetor do speaker) | ❌ Oculto (Kokoro não possui pitch knob) | ❌ Oculto | ✅ Sutil (`0.95...1.06`) | ❌ Oculto |
| **Tags emocionais nativas** | ❌ Oculto | ❌ Oculto | ❌ Oculto | ❌ Oculto | ✅ `supportsNativeAudioTags` |

---

## 2. Fluxo de Controle (`VoiceDesignConfig`)

- **`flowMatchingSteps` (`4...12`, padrão `10` para JARVIS)**: altera diretamente `SherpaGenerationConfigC.num_steps` no `SupertonicNeuralTTSProvider`. Menos passos (`4–6`) priorizam resposta ultrarrápida (~0.15 RTF); `8–10` passos refinam naturalidade harmônica e transientes mantendo RTF < 0.27.
- **`cadence` & `pauseScale`**: modulam `rateMultiplier` e `silenceScale` por cláusula em `VoiceProsodyPlanner` + `silence_scale` nativo do ONNX.
- **`warmth`, `directness`, `expressivity`, `formality`, `detailLevel`**: alimentam o `LocalConversationalBrain`, o `ConversationalBehaviorPlanner` e o `NaturalSpeechComposer` (transformação textual e escolha contextual de pausas/backchannels, explicitamente identificada como comportamento conversacional e não como síntese emocional falsa).

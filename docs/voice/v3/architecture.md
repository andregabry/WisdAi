# WisdAI Voice Intelligence V3 — Architecture & Conversational Behavior Engine

**Branch:** `feature/voice-intelligence-v3` (derivada de `feature/voice-intelligence-v2` em `e879bdc`, preservando o PR #15 intacto)  
**Hardware alvo de referência:** Apple Silicon (M2, 8 GB RAM unificada, macOS 27.0.1)

---

## 1. Princípios de Evolução (V2 → V3)

A V3 **não substitui** nem remove a base validada da V2 (isolamento por `sessionGenerationID`, rotação `CMTime=0` no `SpeechTranscriber`, filtro acústico de eco com janela de 420 ms, `AdaptiveJitterBuffer` com rastreamento hardware CoreAudio, integridade SHA-256 + `tar` endurecida e loopbacks estritos `127.0.0.1`).  
Sobre essa base, foi adicionada a camada **WisdAI Conversational Behavior Engine** em dois novos módulos focados e leves:

- [`VoiceBehaviorEngine.swift`](../../../codex/desktop/macos/VoiceBehaviorEngine.swift)
- [`VoiceVocalizationCache.swift`](../../../codex/desktop/macos/VoiceVocalizationCache.swift)

```
Mic Capture (CoreAudio) ─▶ AcousticFeatureExtractor (vDSP F0 / Inclinação / WPM)
                                     │
                                     ▼
UnifiedLocalSTTCoordinator ─▶ HybridTurnTakingAnalyzer (F0 ascendente + hold adaptativo)
                                     │
         ┌───────────────────────────┴───────────────────────────┐
         ▼ (durante pausa natural >=290ms na fala)               ▼ (turno concluído)
ActiveListeningBackchannelEngine                        ConversationalBehaviorPlanner
         │                                                       │
         ▼ (<1ms cache lookup)                                   ▼ (stream hint sem vazar JSON)
VocalizationCacheEngine ──(Prioridade 4)──┐             LocalConversationalBrain (Qwen3 / ANE)
                                          │                      │
                                          │                      ▼
VoiceNativeAudioEngine (AVAudioSourceNode)│             NaturalSpeechComposer + VoiceProsodyPlanner
  • Prioridade 1/2: Fala humana / Barge-in│                      │
  • Prioridade 3: outputJitterBuffer ─────┴───(suprime Aux)──◀───┘ (Kokoro / Piper / Apple / mlx-audio)
  • Prioridade 4: auxiliaryVocalizationBuffer (integrado ao AcousticEchoSuppressor)
```

---

## 2. Subsistemas Implementados na V3

### 2.1 Active Listening & Backchanneling (`ActiveListeningBackchannelEngine`)
- Emite feedback vocal breve (`Uhum…`, `Aham!`, `Entendi…`, `Certo…`, `Sei…`, `Ah, sim!`, `Interessante…`) durante micro-pausas naturais (`290 ms – 860 ms`) enquanto o usuário mantém a palavra em narrativas longas (`>= 3.0 s` ou `>= 9` palavras).
- **Decisão sem temporizadores aleatórios:** combina pontuação de continuidade sintática (conjunções finais, reticências, vírgulas), contorno F0 ascendente/estável e duração ativa do turno.
- **Limites e diversidade:** cooldown dinâmico (~5.3s a 8.0s), máximo de 2–3 feedbacks por turno, rodízio anti-repetição e silenciamento automático no perfil **Profissional** ou quando `backchannelFrequency == 0`.
- **Invariantes preservadas:** nunca encerra o turno STT, nunca altera a FSM de `.userSpeaking` para `.assistantSpeaking`, nunca contamina o `VoiceMemoryStore`, e nunca dispara ferramentas/agentes.

### 2.2 Vocalization Cache Engine (`VocalizationCacheEngine`)
- Pré-aquece pequenas amostras PCM 24 kHz usando exclusivamente o **motor neural, idioma e identidade vocal ativos**, com variações de entonação (`engaged`, `reflective`, `warm`, `brief`), ritmo e intensidade.
- **Isolamento estrito de identidade:** indexado por assinatura `engineID|voicePreference|language`; qualquer troca de voz (`pf_dora` ↔ `pm_alex`), idioma ou motor invalida imediatamente a cache em memória (com incremento de geração para descartar pré-aquecimentos em voo).
- **Orçamento para 8 GB RAM:** limite rígido de 10 MB em memória com eviction LRU e resposta a `VoiceMemoryPressureLevel` (`.warning` mantém apenas 5 clipes essenciais; `.critical` esvazia memória preservando cache em disco isolada por hash).

### 2.3 Full-Duplex por Prioridade (`VoiceNativeAudioEngine`)
- Introduz `auxiliaryVocalizationBuffer` dedicado à reprodução de feedback vocal auxiliar (Prioridade 4).
- O callback em tempo real `AVAudioSourceNode` verifica primeiro `outputJitterBuffer` (Prioridade 3 — resposta principal). Caso haja amostras principais prontas, o canal auxiliar é esvaziado imediatamente para **zero sobreposição**.
- `combinedPlaybackReferenceState` soma as referências de reprodução principal e auxiliar no `AcousticEchoSuppressor`, mantendo o microfone continuamente aberto sem eco espúrio nem corte de captura.

### 2.4 Conversational Behavior Planner, Prosody Planner & Natural Speech Composer
- **`ConversationalBehaviorPlanner`:** planeia em O(1) (`intent`, `behavior`, `expression`, `vocalization`, `intensity`, `rateMultiplier`, `pauseScale`, `allowUserSpeech`) sem inferência extra a cada pequena pausa. `stripBehaviorMetadataFromSpeech` impede leitura de JSON/tags em voz alta.
- **`VoiceProsodyPlanner`:** ajusta `rateMultiplier`, `silenceScale` (Kokoro/Piper), `pitchMultiplier` sutil (Apple Natural, limitado a `0.95...1.06`) e micropausas digitais (`prePauseMs`/`postPauseMs`) conforme capacidades reais de cada motor (`EngineProsodyCapabilities`).
- **`NaturalSpeechComposer`:** evolui o `VoiceResponseAdapter` removendo aberturas e fechamentos robóticos repetitivos (*"Certamente!"*, *"Se precisar de mais alguma coisa..."*), suavizando enumerações em prosa oral e preservando identificadores técnicos e precisão factual.

### 2.5 Inteligência Acústica Leve (`AcousticFeatureExtractor` + `UserConversationalStyleAdapter`)
- Calcula F0 (autocorrelação normalizada `vDSP` 75–350 Hz), inclinação tonal (`rising`/`falling`/`level`), decaimento de energia e ritmo de palavras por minuto (~0.1 ms por bloco, sem modelos extras).
- `UserConversationalStyleAdapter` adapta suavemente ritmo (`±4%`) e tolerância de pausa sem tratar inferências acústicas como afirmações psicológicas.
- Degrada graciosamente (`AcousticTurnFeatures.unavailable`) quando não há captura de microfone.

### 2.6 Perfis, Personalidade e Laboratório de Voz V3 (`VoiceLaboratoryView.swift`)
- Perfis: **Natural**, **Expressivo**, **Profissional**, **Casual** e **Personalizado**.
- Personalidades evoluídas: **Aurora**, **Atlas** e **Aria** em `VoicePersonalityProfile`, mantidas bloqueadas por sessão (sem mudança automática no meio da conversa).
- Nova aba **Comportamento V3** no Laboratório de Voz exibindo apenas controles efetivamente suportados pelo motor selecionado, além de auditoria ao vivo da cache (`<100 ms`), comparação **V2 vs V3** e sonda loopback `mlx-audio`.

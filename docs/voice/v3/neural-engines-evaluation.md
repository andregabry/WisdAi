# Avaliação Comparativa de Motores Neurais Expressivos & Speech-to-Speech (V3)

**Data:** 2026-11-27  
**Critério estrito:** Nenhuma disponibilidade simulada; modelos pesados não são descarregados sem consentimento explícito; apenas capacidades reais são expostas na UI.

---

## 1. Matriz de Candidatos TTS Expressivos (Local / Loopback)

| Candidato | PT-BR Real | PT-PT Real | Expressividade & Não-Verbais | Streaming & Cancelamento | Licença Comercial | Apple Silicon (M2 8 GB) | Latência / Memória / Decisão |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Kokoro-82M INT8 (`sherpa-onnx` v1.13.8)** | **Sim** (`pf_dora`, `pm_alex`, `pm_santa`) | **Não** (`p` cobre PT-BR) | Boa cadência StyleTTS2; responde a pontuação (`...`, `!`, `?`), `speed` e `silence_scale` | Cláusulas via C ABI + progresso por epoch (`cancelledEpoch`) | Pesos **Apache-2.0** *(nota: `libsherpa-onnx-c-api` usa `espeak-ng` GPL-3.0 in-process via `dlopen`)* | Excelente | **~140 MB RAM**, cláusula ~2.4s, cache vocal **0.002 ms lookup / ~17–21 ms DAC**. **Mantido como motor primário V3.** |
| **Apple Voz Natural PCM (`AVSpeechSynthesizer`)** | Sim (Luciana / Siri) | **Sim** (`Joana` nativa) | Moderada; aceita `rate` e leve `pitchMultiplier` (`0.95..1.06`) | Streaming via `synth.write` + `stopSpeaking(.immediate)` | SDK macOS | Nativo macOS | Baixa RAM; útil para **PT-PT fallback** e baseline comparativo. |
| **Piper VITS ONNX (`vits-piper-pt_BR-*` / `pt_PT-tugao-medium`)** | **Sim** (`faber`, `cadu`) | **Sim** (`tugao-medium`) | Estável/inteligível, menos expressivo que Kokoro | Síntese rápida C ABI reutilizando `libsherpa-onnx-c-api.dylib` | **MIT** (pesos; mesmo `espeak-ng` via `sherpa-onnx`) | Excelente (~63 MB em disco, <90 MB RAM) | **PoC real implementada** em `SherpaVitsPiperTTSProvider` (`VoiceNeuralRuntime.swift`); aguarda pesos sob consentimento. |
| **Chatterbox Multilingual (Resemble AI)** | **Sim** (`pt` + finetunes `pt-BR`/`pt-PT`) | **Sim** (com packs dedicados) | Alta expressividade, controle de exagero; variantes Turbo com tags paralinguísticas | Streaming via servidor HTTP `mlx-audio` loopback (`127.0.0.1`) | **MIT** | Pesado em PyTorch (~13 GB); viável em **MLX Q4** (~1.5–2.5 GB RAM) isolado, apertado junto ao Qwen3-1.7B em 8 GB | **Adaptador HTTP loopback real** implementado (`LocalExpressiveTTSLoopbackClient`); testável com `mlx_audio.server`. |
| **CosyVoice 2 / Fun-CosyVoice 3.0** | **Não oficial** (upstream foca ZH/EN/JA/KO + 9 idiomas sem PT nativo) | **Não oficial** | Alta: tags `[laughter]`, `[breath]`, `<strong>` e bi-streaming (~150 ms) | Streaming HTTP via `mlx-audio-plus` / FunAudioLLM | **Apache-2.0** | Roda via Python/MLX (~1.5–2.5 GB em Q4) | Integrado ao adaptador loopback, mas **inadequado como padrão PT-BR** sem fine-tune português. |
| **Sesame CSM-1B** | **Não** (focado em inglês) | **Não** | Muito natural em diálogo contextual inglês | Fluxo por turnos com codec Mimi | **Apache-2.0** | ~4–6 GB VRAM/UMA (inviável com LLM local simultâneo em 8 GB) | Catalogado honestamente como inglês / 16–24+ GB RAM. |
| **Nari Labs Dia-1.6B / Dia2** | **Não** (focado em inglês) | **Não** | Altíssima: risos, suspiros e múltiplos falantes (`[laughs]`, `[sighs]`) | Dia v1 não-streaming; Dia2 suporta streaming | **Apache-2.0** | Exige **8–10 GB RAM** (inviável em Mac 8 GB com LLM ativo) | Catalogado em `VoiceModelCatalog` (`nari-dia-1.6b`) bloqueado para perfil 8 GB. |
| **F5-TTS** | Não nativo | Não nativo | Clonagem por referência | PyTorch lento em 8 GB | **CC-BY-NC-4.0 (Não Comercial)** | Pesado | **Bloqueado de uso comercial**; aviso explícito exibido. |

---

## 2. Matriz de Candidatos Speech-to-Speech (S2S) Multimodais

| Modelo | Português Real | Latência / Full-Duplex | Licença | Memória & Compatibilidade Mac 8 GB | Status Implementado na V3 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Kyutai Moshi (7B · MLX Q4)** | Limitado (primariamente Inglês) | Excelente (~200 ms codec Mimi) | **CC-BY 4.0** (pesos) / Apache-2.0 (MLX) | Q4 ocupa **~5–8 GB** isolado — impossível rodar estável em 8 GB junto com app + IDE + agentes | Abstração real `LocalMultimodalS2SLoopbackTransport` (`ws://127.0.0.1:8998/api/chat`) + sonda estrita RAM >= 14 GB e handshake WebSocket real. |
| **NVIDIA PersonaPlex 7B** | Foco em Inglês | Full-duplex com personas por prompt | **NVIDIA Open Model License** | ~16 GB em disco/RAM — perfil **Ultra (24–32+ GB)** | Catalogado em `VoiceModelCatalog`; bloqueado em 8 GB. |
| **MiniCPM-o 2.6 / 4.5** | **Sim** (30+ idiomas incl. PT) | Full-duplex multimodal áudio+texto+visão | **Apache-2.0** | Quantizado Int4 exige **~7–12 GB+** — inviável com folga em 8 GB, excelente candidato em Macs 16–32 GB via `mlx-vlm` | Suportado via `LocalMultimodalS2SLoopbackTransport` quando RAM efetiva >= 14 GB e servidor ativo responder ao ping. |

---

## 3. Decisões Técnicas Desta Fase

1. **Preservar Kokoro-82M + Vocalization Cache V3 em 8 GB RAM:** Nenhum candidato testado ou catalogado superou o equilíbrio **PT-BR nativo + Apache-2.0 + ~140 MB + C ABI estável** em 8 GB unificados. A adição da cache de vocalizações (`0.71 MB` para 11 amostras `Kokoro`) reduziu o tempo de reação de feedback vocal para **17–21 ms em hardware CoreAudio**.
2. **Duas evoluções reais de motores alternativos sem baixar gigabytes não autorizados:**
   - **Piper VITS C-ABI nativo (`SherpaVitsPiperTTSProvider`)** pronto para rodar `pt-BR` e **`pt-PT` genuíno** reutilizando a `libsherpa-onnx-c-api.dylib` já instalada.
   - **Cliente HTTP loopback `mlx-audio` (`LocalExpressiveTTSLoopbackClient`)** e **Transporte S2S loopback (`LocalMultimodalS2SLoopbackTransport`)** prontos para **Chatterbox Multilingual MLX / CosyVoice2 / MiniCPM-o** assim que o usuário subir o servidor local em `127.0.0.1` em Macs compatíveis.

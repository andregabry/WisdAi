# WisdAI V5 — Avaliação de Arquiteturas Speech-to-Speech (S2S) vs Pipeline Híbrido Neural

**Hardware de referência do host:** MacBook Pro M2 (`Mac14,7`), 8 GB RAM unificada, macOS 27.0.1 (`26A434`).

---

## 1. Modelos S2S End-to-End Investigados

| Modelo | Parâmetros | Peso em Disco | Memória Unificada Mínima Real | Idiomas Reais | Viabilidade Local em 8 GB RAM | Status no WisdAI |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Kyutai Moshi (MLX Q4)** | ~7B (Helium + Mimi) | ~5.19 GB | **16+ GB RAM** (pesos + KV + codec estouram 8 GB) | Predominantemente Inglês | **Inviável com fluidez** em 8 GB simultâneo com LLM/UI | Catalogado com gate de hardware (`NativeS2SRuntimeProbe`) + suporte experimental via loopback |
| **NVIDIA PersonaPlex 7B v1** | ~7B (base Moshi + role conditioning) | ~16.3 GB | **24–32+ GB RAM** | Predominantemente Inglês | **Inviável** em 8 GB | Catalogado para perfil Studio/Ultra (`>= 24 GB RAM`) |
| **MiniCPM-o 2.6 / 4.5** | ~8B–9B multimodal | ~16.6–19.1 GB | **24–32+ GB RAM** | EN / ZH / multilíngue parcial | **Inviável** em 8 GB | Catalogado para perfil Studio (`>= 32 GB RAM`) |
| **OpenAI Realtime / Gemini Live** | Cloud WebRTC / WS | N/A | N/A | PT-BR, EN, ES, etc. | Requer API Key & opt-in pago (`allowPaidVoiceAPIs`) | Integrado somente sob consentimento explícito; motor autônomo independe dele |

---

## 2. Por que o Pipeline Híbrido Neural V5 Vence em Apple Silicon 8 GB (e com Agentes)

1. **Orçamento real de memória:** Em um Mac com 8 GB de RAM unificada, macOS + Xcode/IDE consomem ~3 GB. Um pipeline S2S de 7B deixa margem zero para contexto conversacional longo, delegação a agentes e estabilidade de áudio (`-10875` / swap thrashing).
2. **Qualidade em Português Brasileiro:** Os modelos S2S nativos abertos atuais (Moshi, PersonaPlex) são treinados primariamente em Inglês. Em Português, o pipeline desacoplado **SpeechTranscriber + Qwen3-1.7B Metal / Apple FM + Supertonic-3 Flow Matching (`44.1 kHz`) / Kokoro-82M (`en-GB` / `pt-BR`)** entrega pronúncia superior em PT-BR e EN-GB usando apenas **~450 MB–1.6 GB** no processo total.
3. **Orquestração de Agentes Paralelos:** Um pipeline híbrido permite narrar ações assíncronas (`Action Narrator`), injetar `Working Memory` auditável no SQLite FTS5 e impor guardrails estritos de risco (`VoiceActionRiskTier`) — capacidades que modelos S2S audio-to-audio puros ainda perdem ou tornam opacas.
4. **Visão de evolução (16–32+ GB):** A interface `LocalExpressiveTTSLoopbackClient` + `NativeS2SRuntimeProbe` já deixa o caminho limpo para usuários em Macs Advanced/Ultra iniciarem servidores MLX/S2S dedicados em `127.0.0.1` sem afetar quem opera em 8 GB.

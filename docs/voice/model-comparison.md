# Matriz Comparativa Tecnológica — Motores de Áudio, Fala e Inteligência Local

> Legenda de origem dos dados: **[Medido]** = executado neste MacBook (Apple M2, 8 cores, 8 GB RAM, macOS 27.0.1); **[Publicado]** = especificação/benchmark oficial do projeto; **[Estimado]** = projeção técnica para hardware Apple Silicon.

---

## 1. Speech-to-Speech (S2S) Multimodal & Síntese Neural (TTS)

| Critério | **Moshi (Kyutai)** | **PersonaPlex (NVIDIA)** | **MiniCPM-o 2.6/4.5** | **Sesame CSM-1B** | **CosyVoice (Alibaba)** | **Kokoro-82M** | **F5-TTS** | **Piper (VITS)** | **Apple Natural PCM (`AVSpeech` Warm)** |
|---|---|---|---|---|---|---|---|---|---|
| **Naturalidade da voz** | Alta [Publicado] | Alta [Publicado] | Alta [Publicado] | Muito alta em EN [Publicado] | Excelente multilíngue [Publicado] | Muito boa p/ 82M [Publicado] | Boa (zero-shot) [Publicado] | Média-boa (VITS) [Publicado] | Boa em `Siri Natural` (`Sandra`); sem voz M local aqui [Medido] |
| **Expressividade** | Alta (full-duplex) | Alta (persona) | Alta (multimodal) | Alta em diálogo EN | Alta (controle emocional) | Boa por estilo/velocidade | Boa por áudio de ref. | Baixa-média (estática) | Moderada |
| **Latência / TTFA** | ~200–350 ms [Publicado] | ~250–400 ms [Publicado] | ~350–600 ms [Estimado] | ~300–500 ms (GPU) [Publicado] | ~150–300 ms streaming [Publicado] | ~70–220 ms ANE/CoreML/MLX [Publicado] | ~400–900 ms (difusão) [Estimado] | < 80 ms CPU [Publicado] | **157.8 ms warm** (2811 ms cold) **[Medido]** |
| **Capacidade Full-Duplex** | Sim (nativa S2S) | Sim (nativa S2S) | Parcial / turno | Turno contextual | Streaming unilateral (S2S via wrapper) | Streaming unilateral | Não nativa | Não nativa | Sim quando acoplado ao `AudioEngine` + `AdaptiveJitterBuffer` **[Medido]** |
| **Interrupção (Barge-in)** | Nativa | Nativa | Externa | Externa | Externa | Externa (`<150ms` via JitterBuffer) | Externa | Externa | **0.118–0.469 ms** flush **[Medido]** |
| **Hesitações & Pausas Naturais** | Boa em EN | Boa em EN | Boa com LLM | Boa em EN | Controlada pelo motor conversacional | Controlada pelo motor conversacional | Controlada pelo motor | Controlada pelo motor | Controlada pelo `HybridTurnTakingAnalyzer` **[Medido]** |
| **Inteligência Acústica Nativa** | Sim (Mimi codec) | Sim | Sim | Codec Mimi + texto | Não (só saída) | Não | Não | Não | Depende de camada acústica externa |
| **Português Brasil (`pt-BR`)** | Fraco / experimental | Fraco | Moderado-bom | **Pobre (foco EN)** | **Forte nativo** | **Bom (`pf_dora`, `pm_santa`)** | Moderado-bom (cloning) | **Bom (`faber-medium`)** | **Disponível nativo (`Sandra`)** **[Medido]** |
| **Português Europeu (`pt-PT`)** | Fraco | Fraco | Limitado | Pobre | Moderado | Limitado (tende a PT-BR) | Limitado | Raro | **Compact (`Joana`)** **[Medido]** |
| **Inglês (`en`) / Espanhol (`es`)** | EN Excelente / ES Limit. | EN Excelente | EN/ZH fortes, ES mod. | EN Excelente / ES Fraco | EN/ES Excelentes | EN/ES Excelentes | EN Excelente / ES Mod. | EN/ES Bons | **EN/ES Nativos macOS** |
| **Personalização Vocal** | Fino ajuste / ref. | Conditioning / persona | Voice cloning / ref. | Prompt contextual | Zero-shot cloning | Style vectors / mistura | Zero-shot 10s ref. | Treino / voz fixa | Escolha entre vozes do sistema |
| **Execução 100% Local** | Sim (16GB+ rec.) | Sim (quantizada) | Sim (16GB+ rec.) | Sim (GPU/ANE 8-12GB+) | Sim (6-8GB+) | **Sim (~320MB modelo)** | Sim (4-6GB) | **Sim (~60–150MB)** | **Sim (0 MB download)** **[Medido]** |
| **RAM / CPU / GPU** | 4–8 GB (Q4) / 14–16 GB (FP16) | 4–8 GB (MLX Q4) | 6–12 GB+ | 8–12 GB VRAM/UM | 6–8 GB VRAM/UM | **0.3–0.7 GB** (ANE/MPS/CPU) | 4–6 GB | **0.06–0.15 GB CPU** | **~15 MB delta processo** (`speechsynthesisd` sistema) **[Medido]** |
| **Apple Silicon / Intel** | Silicon MLX/MPS (Intel inviável) | Silicon MLX (Intel inviável) | Silicon/CUDA | Silicon (lento Intel) | CUDA / MPS | **Apple Silicon ANE/MPS** + Intel CPU | MPS / CUDA | Silicon + Intel | **Silicon + Intel Nativos** |
| **Quantização** | 4-bit / 8-bit MLX | 4-bit / 8-bit MLX | GGUF / AWQ / Q4 | Q4/Q8 experimental | FP16 / ONNX | FP16 / INT8 ONNX / CoreML | FP16 | ONNX INT8/FP32 | Gerenciada pelo SO |
| **Licença Comercial** | Código MIT/Apache; **Pesos CC-BY-4.0** | Código MIT; **NVIDIA Open Model License** | Apache-2.0 + *MiniCPM CLA* | Apache-2.0 (HF gated) | **Apache-2.0** | **Apache-2.0** | Pesos mista / cuidado comercial | **GPL-3.0** *(copyleft!)* | SDK Apple macOS nativo |
| **Dependências Externas** | Rust/Candle ou Python MLX (~4–8GB pesos) | Python MLX (~4–8GB pesos) | Python / llama.cpp-o (~6–9GB) | PyTorch / Transformers | PyTorch / FunASR | `onnxruntime` / CoreML / `espeak-ng` (~320MB) | PyTorch / Vocos | `sherpa-onnx` + `espeak-ng` | Nenhuma (macOS built-in) |
| **Custos Operacionais** | $0 local | $0 local | $0 local | $0 local | $0 local | **$0 local** | $0 local | $0 local | **$0 local** |
| **Integração Ferramentas/Agentes** | Fraca (sem tool-calling complexo nativo) | Fraca | Boa em texto+áudio | Baixa | Nenhuma (apenas TTS) | Nenhuma (apenas TTS) | Nenhuma (apenas TTS) | Nenhuma (apenas TTS) | Via Orquestrador WisdAI |
| **Maturidade Tecnológica** | Média | Alpha-Beta | Média | Pesquisa/Beta | Média-Alta | **Alta para edge** | Média | Alta | **Produção madura Apple** |

---

## 2. Reconhecimento de Fala (STT), Inteligência Acústica (VAD/AEC) & Inferência Local

| Tecnologia | Latência | PT-BR / PT-PT / EN / ES | RAM | Apple Silicon / Intel | Quantização | Licença | Veredito WisdAI |
|---|---|---|---|---|---|---|---|
| **Apple `SpeechAnalyzer` + `SpeechTranscriber` (`macOS 26+`)** | Volatile ~100ms [Publicado]; Init **103.0 ms** **[Medido]** | **`pt_BR`, `pt_PT` já instalados on-device** **[Medido]**; EN/ES suportados | Gerida pelo daemon Apple (~baixíssimo impacto no app) | Apple Silicon macOS 26+ | Apple ANE nativo | Apple SDK Comercial | **Motor Primário STT (`macOS 26+`)** |
| **Apple `SFSpeechRecognizer`** | ~180–350 ms [Publicado] | PT-BR/EN on-device; limite 60s contínuo | Baixa | Silicon + Intel macOS 14+ | Apple nativo | Apple SDK Comercial | **Fallback Compatibilidade (`macOS 14–25`)** |
| **`whisper.cpp` (Q5_0 Metal)** | ~300–1500 ms janela [Publicado] | PT-BR/PT-PT/EN/ES Excelentes | ~150 MB (`tiny`) – ~850 MB (`small Q5`) | Silicon Metal + Intel AVX | GGML Q4/Q5/Q8 | **MIT** | **Plugin Opcional Offline (Intel / `>=16 GB`)** |
| **`mlx-whisper`** | ~200–700 ms [Publicado] | Excelente multilíngue | ~400 MB – 1.5 GB | Só Apple Silicon (Python MLX) | 4-bit / 8-bit MLX | **MIT** | Opcional Python/>=16 GB |
| **`faster-whisper`** | Rápido em CUDA; CPU no macOS | Excelente multilíngue | ~500 MB – 2 GB | CPU no Mac (sem Metal nativo!) | INT8 CTranslate2 | **MIT** | Preterido no Mac frente a Metal/MLX/`SpeechAnalyzer` |
| **Apple `SpeechDetector` + `AcousticVADTracker` + `HybridTurnTakingAnalyzer`** | **`< 1 ms` bloco áudio** **[Medido]** | Regras semânticas PT-BR/PT-PT/EN/ES **[Medido]** | **< 1 MB** | Silicon + Intel | N/A | Apple SDK + WisdAI | **Primário Imediato** |
| **Silero VAD** | < 1–3 ms / frame 30ms [Publicado] | Agnóstico idioma | ~2–15 MB ONNX | Silicon + Intel | FP16/INT8 | **MIT** | Evolução opcional via CoreML/ONNX |
| **Smart Turn (Pipecat)** | ~30–120 ms [Publicado] | Foco primário EN; v2/v3 expansível | ~150–400 MB | Silicon MPS/CPU | FP16/INT8 | **BSD-2-Clause** | Referência excelente de Turn-Taking acústico futuro |
| **WebRTC VAD / AEC + VPIO** | Microssegundos VAD; VPIO depende buffer HAL | Agnóstico | < 2 MB | Silicon + Intel | N/A | **BSD-3-Clause** / Apple HAL | VPIO + Correlator de Eco por software (`AdaptiveJitterBuffer`) |
| **Apple `FoundationModels` (`SystemLanguageModel.default`)** | Cold **3.88s**; Warm **470–538 ms TTFT** **[Medido]** | PT-BR / EN fluentes **[Medido]** (prompt multilíngue) | Zero heap pesado no app (ANE do SO; janela 4096 tok) | Apple Silicon `macOS 26+` (Apple Intelligence) | Apple ANE | Apple SDK Comercial | **Cérebro Conversacional Local Primário (`macOS 26+`)** |
| **`llama.cpp` (Metal `Q4_K_M`, 3B)** | ~35–55 tok/s decode M2 8GB [Publicado] | Depende do modelo (ex. Qwen2.5-3B / Gemma-3) | ~1.8–2.2 GB RAM | Silicon Metal + Intel | GGUF Q2..Q8 | Engine **MIT** (pesos variam) | **Alternativa Local para Hosts sem Apple FM ou `>=16 GB`** |
| **Apple MLX / Core ML / ONNX Runtime** | Sub-real-time ANE/GPU | Infraestrutura de execução | Conforme modelo | MLX/CoreML Silicon; ORT multi | 4/8/16-bit | **MIT** (MLX/ORT) / Apple | Runtime padrão para evolução `Kokoro-82M` / `Silero` |

# Avaliação de Arquiteturas Speech-to-Speech Nativas (S2S) vs Pipeline Híbrido

## 1. Modelos Avaliados no Repositório HuggingFace (Metadados Reais)

| Modelo | Tamanho dos Pesos | Licença | Requisitos Mínimos de Runtime / Hardware | Situação no Host M2 (8 GB RAM) |
| :--- | :---: | :--- | :--- | :--- |
| **Kyutai Moshi MLX Q4** (`kyutai/moshiko-mlx-q4`) | `4,950.3 MB` (~5.19 GB) | `CC-BY-4.0` | Python 3.10+ + `mlx` + `moshi_mlx`; >= 16 GB RAM recomendados; idioma principal inglês | **Incompatível** em execução simultânea no M2 8 GB e sem stack Python/MLX instalada |
| **NVIDIA PersonaPlex 7B v1** (`nvidia/personaplex-7b-v1`) | `16,341.8 MB` (~16.3 GB) | NVIDIA Open Model | GPU/RAM >= 24–32 GB (`Ultra`), stack PyTorch | **Incompatível** (< 24 GB RAM / sem runtime PyTorch) |
| **MiniCPM-o 2.6 / 4.5** (`openbmb/MiniCPM-o-*`) | `16,625.1 MB` – `19,119.9 MB` | Apache-2.0 | GPU/RAM >= 24–32 GB (`Ultra`), runtime Python multimodal | **Incompatível** (< 32 GB RAM / sem runtime externo) |

---

## 2. Política de Gating e Alternância em `WisdAI Voice`

- **`VoiceExecutionArchitectureMode` (`VoiceIdentityProfile.swift`):**
  - `.neuralHybrid` (**Padrão recomendado**): `Apple SpeechTranscriber` → `WisdAI Brain` (`Apple FM` ou `llama.cpp` Metal / `MLX`) → `Kokoro-82M Neural` ou `Apple Natural PCM`.
  - `.nativeSpeechToSpeech` (**Experimental**): disponível apenas quando `NativeS2SRuntimeProbe.evaluate(hardwareTier:)` confirma memória efetiva >= 14–16 GB e detecta ambiente runtime/binário MLX/Moshi executável.
- **Comportamento no Apple M2 8 GB:** quando o usuário alterna para `.nativeSpeechToSpeech` no **Laboratório de Voz**, `NativeS2SRuntimeProbe` exibe motivo técnico explícito (*"Memória RAM efetiva (~8 GB) insuficiente para S2S nativo em execução simultânea... Modo Híbrido Neural ativo"*) e bloqueia promessas falsas.

---

## 3. Conclusão Arquitetural

No estado atual de hardware e distribuição sem dependências Python embarcadas no `.app`, o **pipeline Híbrido Neural Local** (`SpeechTranscriber` + `Qwen3-1.7B Metal` / `Apple FM` + `Kokoro-82M INT8`) oferece suporte superior em **Português do Brasil**, pegada total em disco de ~1.25 GB (versus 5–19 GB), isolamento seguro por época e controle determinístico de barge-in e ferramentas/agentes.

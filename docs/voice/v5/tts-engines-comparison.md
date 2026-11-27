# WisdAI V5 — Reavaliação Técnica & Comparativa de Motores Neurais TTS

Esta auditoria avaliou objetivamente os motores neurais disponíveis, suas licenças, requisitos reais de memória no macOS arm64 e testes reais de síntese executados nesta máquina (Apple M2, 8 GB RAM, Python 3.9.6 sem `mlx`/`conda`/`brew` instalados).

---

## 1. Análise das Limitações do Motor Anterior (Kokoro-82M)

- **Qualidade idiomática vs. expressividade:** Em PT-BR, o Kokoro-82M (`kokoro-int8-multi-lang-v1_0`, 24 kHz) utiliza `espeak-ng pt-br` e StyleTTS2/ISTFTNet. A dicção é boa, mas:
  - Possui apenas 2 vozes masculinas em português (`pm_alex` ~122–130 Hz e `pm_santa` ~131–137 Hz, mais rouca/escura).
  - Roda com **RTF ~0.60–0.79** em CPU no M2 (~3.0–3.9s para gerar 5–6s de áudio), gerando sensação de "leitura" em turnos mais longos.
  - Não possui `pt-PT` genuíno (o código `pt-br` foi isolado na V5 para não falsificar português europeu).
  - Para inglês britânico (`bm_george`, `bm_daniel`, `bm_lewis`), o arquivo `espeak-ng-data` empacotado exigia o código **`en-GB-x-rp`** (case-sensitive) + `lexicon-gb-en.txt`; usar `"en-gb"` em minúsculo falhava silenciosamente na fonetização.

---

## 2. Descoberta & Integração Nativa V5: **Supertonic-3 ONNX INT8 (`44.1 kHz`)**

Auditando as capacidades da biblioteca nativa `libsherpa-onnx-c-api.dylib v1.13.8` já instalada no WisdAI, confirmou-se suporte completo em C ABI a **Supertone Supertonic-3** (`sherpa-onnx-supertonic-3-tts-int8-2026-05-11.tar.bz2`, 122.8 MB compactado, `vector_estimator` + Flow Matching + Length-Aware RoPE):

- **Taxa nativa:** **44.100 Hz** (reamostrada com filtro polifásico CoreAudio `AVAudioConverter` para 24 kHz no streaming de sessão, preservando 44.1 kHz nas amostras do laboratório).
- **Latência e carga medidas no M2 8 GB:**
  - Load frio: **~433 ms**.
  - Síntese Flow Matching (`num_steps = 6`): **RTF ~0.155–0.161** (~6,4× mais rápido que tempo real; ~1.1s para 7.3s de áudio).
  - Síntese Flow Matching (`num_steps = 10`, alta qualidade): **RTF ~0.245–0.265** (~3,8× mais rápido que tempo real — ainda ~2,5× mais rápido que o Kokoro-82M!).
- **Vozes reais em 31 idiomas (incluindo `pt`, `en`, `es`):** 5 vozes femininas (`F1`–`F5`, `sid=0...4`) e **5 vozes masculinas reais** (`M1`–`M5`, `sid=5...9`), destacando-se `M2` (`sid=6`, F0 mediano ~89–90 Hz em PT) e `M4` (`sid=8`, F0 mediano ~111–132 Hz em PT).
- **Licença:** Código Supertone/sherpa-onnx sob **MIT / Apache-2.0**; pesos sob **BigScience Open RAIL-M** (permite execução local responsável, sem dependência de Python/cloud).

---

## 3. Matriz Comparativa Completa dos Motores Avaliados

| Motor | Parâmetros / Peso | Taxa / Arquitetura | Licença | Suporte PT Real | Status neste Host M2 8 GB | Veredito V5 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Supertonic-3 INT8** | ~122.8 MB (`tar.bz2`) | 44.1 kHz Flow Matching ONNX | MIT (código) + Open RAIL-M (pesos) | **Sim (`pt`, `en`, `es` + 28)** | **Operacional & testado localmente** (C ABI nativa) | **Novo motor neural padrão recomendado para JARVIS** |
| **Kokoro-82M INT8** | 82M (~126.2 MB) | 24 kHz StyleTTS2 ONNX | Apache-2.0 (+ eSpeak GPL) | **PT-BR (`pf_dora`, `pm_alex`, `pm_santa`), EN-GB, EN-US, ES** | **Operacional & testado localmente** (`en-GB-x-rp` corrigido) | **Mantido como motor primário alternativo (excelente EN-GB/PT-BR)** |
| **Piper VITS** (`pt_BR-cadu`) | ~64.0 MB | 22.05 kHz VITS ONNX | MIT (+ eSpeak) | Sim (modelos dedicados por idioma, incl. `pt-PT`) | **Testado localmente** (`load=373ms, RTF=0.070`, timbre mais seco) | Fallback ultraleve / opção PoC `pt-PT` |
| **Apple Natural PCM** | Integrado macOS | `AVSpeechSynthesizer` | Apple macOS SDK | PT-BR (neste Mac apenas `Luciana` fem. não-Eloquence), PT-PT (`Joana`), EN-GB (`Daniel` masc.) | **Testado localmente** (usado apenas como baseline/fallback) | Baseline zero-download; alerta explícito se não houver voz masculina instalada |
| **Kyutai Pocket TTS** | ~100M (~93.8 MB int8) | 24 kHz Zero-Shot ONNX | MIT | `sherpa-onnx` release focado em Inglês | Compatível via C ABI v1.13.8 (não instalado em disco por foco PT-BR) | Candidato inglês zero-shot futuro |
| **Qwen3-TTS (0.6B / 1.7B)** | 0.6B (~1.8 GB) / 1.7B (~4.3 GB) | 12Hz Dual-Track (`VoiceDesign` / `CustomVoice`) | Apache-2.0 | **Sim (10 idiomas incl. PT)** | **Não executável nativamente sem Python 3.10+ / MLX** (host possui Python 3.9.6) | Suportado via cliente loopback (`mlx-audio`) para Macs 16+ GB |
| **Chatterbox Multilingual** | ~500M Llama | Zero-shot + tags emocionais | MIT | **Sim (incl. pack `pt-PT`)** | Pesos ~13 GB / PyTorch/MLX; inviável nativo em 8 GB simultâneo | Catalogado + loopback `127.0.0.1` em perfil Advanced/Ultra |
| **CosyVoice 2 / 3** | 0.5B | Flow Matching LLM (`mlx`/`onnx`) | Apache-2.0 | Cross-lingual parcial (foco ZH/EN/JA/KO/EU) | Requer runtime Python/FunASR ou conversão ONNX customizada | Catalogado + loopback `127.0.0.1` em 16+ GB |
| **Fish Speech / OpenAudio S1** | ~0.5B+ | Autoregressive VQ | Fish Audio / Apache-2.0 | **Sim (PT multilíngue)** | Requer servidor Python/MLX externo | Catalogado V5 para perfil 16+ GB via loopback |
| **IndexTTS-2** | Modelo duração/emoção | PyTorch MPS | Apache-2.0 (código) | Foco ZH/EN/ES/JA; sem port Swift/ONNX oficial | Inadequado para runtime embarcado 8 GB | Documentado no catálogo técnico com requisitos reais |
| **Sesame CSM-1B & Dia-1.6B** | 1B–1.6B | Conversacional / diálogo | Apache-2.0 | Foco em **Inglês** | >6–18 GB de stack / Python externo | Catalogado honestamente com aviso de idioma/RAM |
| **F5-TTS** | Diffusion Flow | PyTorch | **CC-BY-NC-4.0 (Não Comercial)** | Principalmente EN/ZH | Bloqueado para uso comercial por licença + Python externo | Sinalizado com bloqueio de licença |

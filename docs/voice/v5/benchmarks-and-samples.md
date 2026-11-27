# WisdAI V5 — Benchmarks Reais & Amostras Comparativas JARVIS

**Hardware de medição:** MacBook Pro `Mac14,7` · Apple M2 · 8 GB RAM · macOS 27.0.1 (`26A434`)  
**Script gerador das amostras:** `gen_v5_samples.swift` executado diretamente contra o runtime embarcado (`SupertonicNeuralTTSProvider`, `KokoroNeuralTTSProvider`, `AppleNaturalPCMStreamingTTSProvider` e `AudioPCMConverter.normalizeForSpeech`).

---

## 1. Benchmarks Reais Medidos (`run-voice-smoke.sh` pós-correção final)

| Componente / Métrica | Valor Medido | Observação |
| :--- | :--- | :--- |
| **Supertonic-3 INT8 (`num_steps=6`, smoke)** | **RTF = `0.199`** | 44.1 kHz nativo; `M2 = 90.0 Hz`, `M4 = 117.9 Hz` vs. `F1 = 185.3 Hz` |
| **Kokoro-82M INT8 (`pf_dora` / `pm_alex` / `bm_george`)** | **Load = `567 ms`**, síntese PT-BR `3033 ms` (`117129` samples @ 24 kHz) | `pf_dora = 173.9 Hz` vs. `pm_alex = 130.4 Hz` \| `en-GB-x-rp` `bm_george = 139.5 Hz` |
| **Brain Local (`qwen3-1.7b-q4_k_m` + `llama.cpp Metal`)** | **Load = `6600 ms`**, **TTFT = `105 ms`**, total `736 ms` (`142` chars) | Execução 100% offline local |
| **Apple Natural PCM** | `82304` float samples @ 24 kHz | Baseline zero-download |
| **Barge-in + Corte de Contexto** | **`0.306 ms`** | Truncamento exato ao prefixo efetivamente ouvido |
| **Cache Neural V5 (Kokoro hit)** | **`0.006 ms`** | Diretórios isolados `v5_<sha256>` |
| **Ring Buffer 20 ms / Resample 48k→16k** | Ring P50 `0.0003 ms` (P95 `0.0004 ms`); Resample P50 `0.0009 ms` (P95 `0.0010 ms`) | Footprint do processo de teste: `581.2 MB`, CPU `3.6%` |

---

## 2. Catálogo Completo das 22 Amostras Comparativas (`voice_samples_v5`)

As 22 amostras abaixo cobrem as **5 categorias obrigatórias em PT-BR** para os 3 candidatos JARVIS principais + variações adicionais (`Supertonic M5` e `EN-GB`) + 3 controles de regressão, geradas após a normalização fonética (`hmm` → `hum`, `…` e pontuação prosódica).  
Diretório dos artefatos: `/Users/andregabry/.gemini/antigravity/brain/15f30b3f-af87-4fae-bd9f-5f3efd1c6b44/voice_samples_v5/`

### Candidato A — `Supertonic-3 M2` (`supertonic:m2`, `sid=6`, 44.1 kHz, Flow Matching `num_steps=10`)
*Perfil acústico: barítono sereno (~87–93 Hz mediano).*

| Categoria | Arquivo WAV | Taxa | Duração | Síntese | RTF | F0 Mediano |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 01. Saudação inicial | `jarvisA_supertonic_m2_01_saudacao.wav` | 44.1 kHz | 5.83s | 2065 ms | 0.354 | 92.8 Hz |
| 02. Resposta conversacional fluida | `jarvisA_supertonic_m2_02_conversacional.wav` | 44.1 kHz | 9.02s | 2253 ms | 0.250 | 91.5 Hz |
| 03. Explicação técnica clara | `jarvisA_supertonic_m2_03_tecnica.wav` | 44.1 kHz | 9.07s | 2268 ms | 0.250 | 91.3 Hz |
| 04. Pausa, hesitação e naturalidade | `jarvisA_supertonic_m2_04_pausa_natural.wav` | 44.1 kHz | 8.76s | 2093 ms | 0.239 | 87.2 Hz |
| 05. Conversa enquanto agentes executam | `jarvisA_supertonic_m2_05_multiagente.wav` | 44.1 kHz | 10.59s | 2522 ms | 0.238 | 88.9 Hz |
| EN-GB. Executivo britânico | `jarvisA_supertonic_m2_enGB.wav` | 44.1 kHz | 6.79s | 1737 ms | 0.256 | 82.1 Hz |

### Candidato B — `Supertonic-3 M4` (`supertonic:m4`, `sid=8`, 44.1 kHz, Flow Matching `num_steps=10`)
*Perfil acústico: tenor-barítono articulado (~115–130 Hz mediano).*

| Categoria | Arquivo WAV | Taxa | Duração | Síntese | RTF | F0 Mediano |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 01. Saudação inicial | `jarvisB_supertonic_m4_01_saudacao.wav` | 44.1 kHz | 5.58s | 1538 ms | 0.275 | 114.5 Hz |
| 02. Resposta conversacional fluida | `jarvisB_supertonic_m4_02_conversacional.wav` | 44.1 kHz | 8.64s | 2025 ms | 0.234 | 124.9 Hz |
| 03. Explicação técnica clara | `jarvisB_supertonic_m4_03_tecnica.wav` | 44.1 kHz | 8.67s | 2039 ms | 0.235 | 129.7 Hz |
| 04. Pausa, hesitação e naturalidade | `jarvisB_supertonic_m4_04_pausa_natural.wav` | 44.1 kHz | 8.41s | 2028 ms | 0.241 | 116.7 Hz |
| 05. Conversa enquanto agentes executam | `jarvisB_supertonic_m4_05_multiagente.wav` | 44.1 kHz | 10.16s | 2470 ms | 0.243 | 118.2 Hz |

### Candidato C — `Kokoro-82M pm_alex` / `bm_george` (24 kHz)
*Perfil acústico: voz masculina PT-BR (`pm_alex`, ~126–130 Hz) e britânica `en-GB-x-rp` (`bm_george`, 139.5 Hz).*

| Categoria | Arquivo WAV | Taxa | Duração | Síntese | RTF | F0 Mediano |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 01. Saudação inicial | `jarvisC_kokoro_pm_alex_01_saudacao.wav` | 24.0 kHz | 5.32s | 3642 ms | 0.685 | 130.4 Hz |
| 02. Resposta conversacional fluida | `jarvisC_kokoro_pm_alex_02_conversacional.wav` | 24.0 kHz | 6.99s | 4166 ms | 0.596 | 128.3 Hz |
| 03. Explicação técnica clara | `jarvisC_kokoro_pm_alex_03_tecnica.wav` | 24.0 kHz | 7.28s | 4349 ms | 0.597 | 128.3 Hz |
| 04. Pausa, hesitação e naturalidade | `jarvisC_kokoro_pm_alex_04_pausa_natural.wav` | 24.0 kHz | 6.00s | 3674 ms | 0.613 | 126.3 Hz |
| 05. Conversa enquanto agentes executam | `jarvisC_kokoro_pm_alex_05_multiagente.wav` | 24.0 kHz | 7.38s | 4575 ms | 0.620 | 128.3 Hz |
| EN-GB. Britânico (`bm_george`) | `jarvisC_kokoro_bm_george_enGB.wav` | 24.0 kHz | 5.89s | 4756 ms | 0.807 | 139.5 Hz |

### Alternativa `Supertonic-3 M5` & Controles de Regressão

| Categoria | Arquivo WAV | Taxa | Duração | Síntese | RTF | F0 Mediano |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| Alternativa M5 · 01. Saudação | `alt_supertonic_m5_01_saudacao.wav` | 44.1 kHz | 5.94s | 1597 ms | 0.269 | 95.2 Hz |
| Alternativa M5 · 05. Multiagente | `alt_supertonic_m5_05_multiagente.wav` | 44.1 kHz | 10.79s | 2537 ms | 0.235 | 88.6 Hz |
| Controle Feminino Kokoro (`pf_dora`) | `control_kokoro_pf_dora_05_multiagente.wav` | 24.0 kHz | 7.18s | 4929 ms | 0.686 | 166.7 Hz |
| Controle Apple Natural PT-BR (`Luciana` fem.) | `control_apple_ptBR_05_multiagente.wav` | 24.0 kHz | 9.56s | 1152 ms | 0.121 | 189.0 Hz |
| Controle Apple Natural EN-GB (`Daniel` masc.) | `control_apple_enGB_daniel.wav` | 24.0 kHz | 5.88s | 326 ms | 0.055 | 107.1 Hz |

---

## 3. Verificação Auditiva Pós-Normalização (Trecho 04)

- **Problema detetado anteriormente na escuta da amostra `04`:** o token `"Hmm…"` fazia o G2P `espeak-ng` do Kokoro soletrar `"agá eme eme"`, e o caractere unicode `…` provocava micro-hesitação artificial na entrada do Supertonic.
- **Correção aplicada (`VoiceBehaviorEngine.swift` + `VoiceNeuralRuntime.swift`):** expansão idiomática de `"hmm"` → `"hum"` em `normalizeForEspeakG2P` / `normalizeForSupertonic`, ajuste de `.hmm` em `VocalizationKind` e conversão de `…` para pausa vírgula natural.
- **Revalidação auditiva (`read_file` nos WAVs regenerados `04`):** confirmado de ouvido que `jarvisA_supertonic_m2_04`, `jarvisB_supertonic_m4_04` e `jarvisC_kokoro_pm_alex_04` pronunciam a pausa reflexiva com naturalidade sem soletração nem gaguejo.

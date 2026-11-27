# Benchmarks Reais e Inventário das Amostras de Áudio

**Hardware de medição:** Apple MacBook M2 (`8.0 GB RAM` unificados, `Apple M2` GPU máx `5,461 MB`, `macOS 27.0.1` `26A434`)  
**Compilação:** Swift `6.4.2`, `-swift-version 5 -target arm64-apple-macosx14.0 -parse-as-library -O`

---

## 1. Benchmarks Medidos dos Motores Conversacionais (Brain)

| Motor / Modelo | Estado Medido | Carga do Processo / Sessão | TTFT Medido | Latência Total Resposta | Caracteres | Observações Reais |
| :--- | :--- | :---: | :---: | :---: | :---: | :--- |
| **Apple FoundationModels (`ANE`)** | Turno 1 (frio) | ~0 ms no processo | `3,964.4 ms` | `4,628.2 ms` | 157 | Executado nativamente via `SystemLanguageModel.default` |
| **Apple FoundationModels (`ANE`)** | Turno 2 (quente) | 0 ms | `924.5 ms` | `1,975.1 ms` | 240 | Boa qualidade PT-BR sem download em disco |
| **`Qwen3-1.7B-Q4_K_M` (`llama-server b12809` Metal `-ngl 99`)** | Teste fumaça (`run-voice-smoke.sh`) | `7,140 ms` (warm OS page cache; `16,701 ms` 1ª carga fria / `11,422.1 ms` benchmark dedicado) | **`215–397 ms`** | **`1,006–1,121 ms`** | 146–168 | Sem `<think>` vazado; SSE streaming direto |
| **`Qwen3-1.7B-Q4_K_M` (`llama.cpp Metal`)** | Multi-turno (Turnos 1 e 2 quentes) | — | **`226.7 ms`** / **`154.2 ms`** | **`1,255.5 ms`** / **`1,440.0 ms`** | 192 / 245 | **TTFT ~4× a 6× menor** que Apple FM em diálogo ativo |

---

## 2. Benchmarks Medidos de Síntese Vocal (`TTS`) e DSP

| Operação Medida | Config / Voz | Latência / Tempo Medido | Duração do Áudio / Amostras | Observação Real |
| :--- | :--- | :---: | :---: | :--- |
| **Kokoro-82M INT8** — Carga C API (`dlopen`) | `sherpa-onnx v1.13.8`, 54 vozes | `611.8–667 ms` | `24,000 Hz` mono float | Carregamento sob demanda |
| **Kokoro-82M INT8** — Cláusula curta P50 (`pt-BR`) | `pf_dora` (`4` threads vs `2` threads) | `1,549.9 ms` (`4T`) / `1,550.1 ms` (`2T`) | ~2 s (limitado por banda de memória INT8) | Mesmo áudio fluido |
| **Kokoro-82M INT8** — Frase média (`pt-BR` fumaça) | `pf_dora` (`4T` vs `2T`) | `3,082 ms` (`4T`) vs `3,307 ms` (`2T`) | `117,131` amostras (`4.88 s`, RTF ~`0.63`) | Ganho ~7% com 4 threads |
| **Apple Voz Natural (`AVSpeechSynthesizer.write`)** | Cláusula curta P50 (`pt-BR`) | **`99.1 ms`** | Streaming `24 kHz` | Ultrabaixa latência, timbre metálico nas vozes compactas |
| **Ring Buffer 20 ms + Reamostrador 48k → 16k PCM16** | `VoiceSmokeTests` | **`P50=0.0003 ms` / `0.0010 ms`** | `P95=0.0003–0.0004 ms` / `0.0013–0.0014 ms` | Pegada do binário de teste: `32.8–200.2 MB` |
| **Barge-In (Truncamento + Flush Jitter)** | `BargeInCoordinator` | **`0.050–0.121 ms`** | Preserva prefixo ouvido | Validado em 3 execuções |

---

## 3. Resultados Reais das Suítes Executadas (Após Última Edição)

1. **`./codex/desktop/macos/tests/run-voice-smoke.sh`:** `Command exited with code 0` — **`VOICE_SMOKE_ALL_PASS`** (incluiu síntese real Kokoro `ptBR=3082ms`, `en=3138ms`, `es=2801ms` e inferência real `Qwen3-1.7B` `TTFT=215ms / total=1006ms`).
2. **`./codex/desktop/macos/tests/run-state-smoke.sh`:** `Command exited with code 0` — **`PASS`** em todos os invariantes de estado, continuidade WebRTC e contas.
3. **`./codex/desktop/macos/tests/run-recovery-smoke.sh`:** `Command exited with code 0` — **`PASS`** em limites estritos, fallback e privacidade efêmera.
4. **Compilação Full Release (`swiftc -swift-version 5 -target arm64-apple-macosx14.0 -parse-as-library -O ... codex/desktop/macos/*.swift`):** `Command exited with code 0` — **`FINAL_BINARY_COMPILE_OK`**.

---

## 4. Inventário das 7 Amostras WAV Reais Geradas e Auditadas

Armazenadas em `~/Library/Application Support/WisdAI/Voice/Samples/` e no diretório de artefatos da sessão (`voice_samples/`, **24 kHz PCM16 mono**):

| Arquivo | Motor / Voz / Idioma | Síntese | Tamanho | SHA-256 | Avaliação Auditiva Real |
| :--- | :--- | :---: | :---: | :--- | :--- |
| `01_ptbr_kokoro_aurora_pf_dora.wav` | Kokoro-82M `pf_dora` (`pt-BR`) | `5,230.5 ms` (`7.77 s` áudio) | `372,886` B | `41231b75...b0f30` | Prosódia fluida, entonação natural brasileira |
| `02_ptbr_kokoro_alex_pm_alex_multitask.wav` | Kokoro-82M `pm_alex` (`pt-BR`) | `6,557.7 ms` (`10.04 s` áudio) | `481,834` B | `bea6f838...94fa` | Dicção masculina clara, natural e profissional (`Atlas`) |
| `03_ptbr_kokoro_atlas_pm_santa.wav` | Kokoro-82M `pm_santa` (`pt-BR`) | `4,835.9 ms` (`7.75 s` áudio) | `371,822` B | `3995faf5...fbd9` | Timbre mais grave/teatral; motivou escolha de `pm_alex` como padrão `Atlas` |
| `04_enus_kokoro_heart_af_heart.wav` | Kokoro-82M `af_heart` (`en-US`, regenerado) | `5,880.0 ms` (`7.15 s` áudio) | `343,060` B | `082e6a99...8f8c0` | `"Wiz D A I"` corrigido após 1ª auditoria |
| `05_eses_kokoro_dora_ef_dora.wav` | Kokoro-82M `ef_dora` (`es-ES`) | `4,519.9 ms` (`6.50 s` áudio) | `312,040` B | `6542b049...43158` | Fluido em espanhol |
| `06_ptbr_apple_natural_comparative.wav` | Apple Natural Luciana (`pt-BR`) | `1,061.6 ms` (`9.30 s` áudio) | `446,450` B | `0fba2298...609ec4` | Muito rápido (`~1s`), porém timbre metálico |
| `07_ptpt_apple_natural_joana.wav` | Apple Natural Joana (`pt-PT`) | `254.9 ms` (`8.22 s` áudio) | `394,456` B | `d012edc1...37e099` | Rota honesta para `pt-PT` não suportado pelo Kokoro |

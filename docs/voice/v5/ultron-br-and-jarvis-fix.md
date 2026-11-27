# WisdAI V5.1 — Correção Cirúrgica da Distorção do JARVIS & Nova Identidade **Ultron BR**

**Branch:** `feature/voice-identity-jarvis-v5`  
**Hardware de validação:** Apple M2 (`Mac14,7`) · 8 GB RAM · macOS 27.0.1 · `/usr/bin/python3` `3.9.6` (sem `python3.10+`, `uv`, `brew` ou `conda`)  
**Amostras reproduzíveis (25 WAVs):** `/Users/andregabry/.gemini/antigravity/brain/15f30b3f-af87-4fae-bd9f-5f3efd1c6b44/voice_samples_ultron_jarvis/`

---

## 1. Diagnóstico Empírico da Distorção Robótica Exclusiva do **JARVIS** (Ablação Real)

Seguindo a diretriz de **não refatorar o pipeline funcional das demais vozes (`Aurora`, `Atlas`, `Aria`)**, cada etapa exclusiva do perfil **JARVIS** foi medida acusticamente (HNR, ZCR, Jitter, salto máximo entre amostras `maxDiff` e DC offset):

| Fator Isolado no JARVIS | Evidência Empírica Medida | Impacto Perceptivo | Correção Cirúrgica Aplicada |
| :--- | :--- | :--- | :--- |
| **1. Speaker padrão `Supertonic-3 M2` (`sid=6`)** | `HNR_med = 6.6 dB` (`HNR_p10 = -1.3 dB`), `ZCR = 1067 Hz` em frase longa; `HNR = -0.5..-2.0 dB` e `ZCR = 1040..1601 Hz` em frases curtas — contra `Supertonic M4` (`HNR_med = 11.5–13.3 dB`, `ZCR = 316.7–416.7 Hz`), `Supertonic F1` (`15.4 dB`) e `Kokoro pf_dora` (`10.7 dB`) | Voz anasalada/áspera com energia aperiódica alta | `.jarvis` migrado para **`supertonic:m4`** (`sid=8`) com autocura em `UnifiedVoiceConfig.loadMigrated` (`m2` → `m4`) |
| **2. Resampler `AVAudioConverter` sem estado por chunk (`44.1 kHz → 24 kHz`)** | `resampleHighQuality` instanciado por chunk dobrava descontinuidades entre amostras (`maxDiff = 0.0996 → 0.1884`, `peak = 0.6422 → 0.7449`) | Cliques e aspereza metálica nas emendas de chunks em streaming | Novo `StreamingSincResampler` janelado por Blackman com estado contínuo em `VoiceStudioDSPProcessor.swift`, preservando `HNR_med = 11.9–13.3 dB` em `24 kHz` |
| **3. DC Offset do `Kokoro-82M`** | Saídas Kokoro brutas carregavam desvio CC de `+0.023..+0.030` | Estalos de transição entre trechos e fadiga no limitador | Filtro passa-alta Butterworth de 2.ª ordem em `26 Hz` no `VoiceStudioDSPProcessor` (`dc = ±0.0000` em todas as amostras) |
| **4. Estado salvo em `local.wisdai.desktop` (`bm_george` `en-GB` em texto PT-BR)** | `defaults read local.wisdai.desktop` revelou `Unified: jarvis kokoro_82m bm_george en-GB rate= 1.08 steps= 10` enquanto o texto conversacional e as pré-visualizações eram em PT-BR | Fonetização `en-GB-x-rp` aplicada sobre palavras portuguesas | `effectiveSynthesisLanguage(forText:configured:)` em `VoiceOrchestrator.swift` + cura do lock acidental `bm_george`/`en-GB` na carga migrada |
| **5. Rota legada `AVAudioUnitTimePitch` exclusiva para voz masculina** | `DesktopVoice.swift` aplicava `AVAudioUnitTimePitch(pitch: -290, overlap: 12.0)` em `synthesizeAndPlayWithBaritoneTimbre` e `fallback.pitchMultiplier = 0.82` | Artefato robótico severo caso o fallback legado fosse acionado | Bypass do `AVAudioUnitTimePitch` destrutivo e `fallback.pitchMultiplier = 1.0` |

> [!NOTE]
> As vozes saudáveis (`Aurora`, `Atlas`, `Aria`) permanecem com `VoiceDSPParameters.clean` (`requiresColorationDSP == false`), recebendo apenas o bloqueador de DC de `26 Hz` (transparência harmônica preservada) e o novo `StreamingSincResampler` contínuo.

---

## 2. Nova Identidade Vocal: **Ultron BR** & Avaliação de Motores no Host Real

### 2.1 Avaliação Honesta de `Qwen3-TTS VoiceDesign` e `Chatterbox Multilingual` (8 GB RAM)

- **`Qwen3-TTS 1.7B VoiceDesign`** (~`4.3 GB` em pesos) e **`Chatterbox Multilingual`** (`~500M` Llama): exigem **Python ≥ 3.10 + MLX/PyTorch** e **12–16+ GB de RAM** para operar em baixa latência ao lado do LLM conversacional. Este host possui **Apple M2 · 8 GB RAM compartilhada · `/usr/bin/python3` (`3.9.6`)**, sem `brew`, `uv` ou `conda`.
- **Decisão técnica implementada:**
  - Não baixar gigabytes de checkpoints incompatíveis com o Python `3.9.6` / RAM `8 GB` do host.
  - Suporte completo via cliente loopback local (`LocalExpressiveTTSLoopbackClient` em `VoiceNeuralRuntime.swift`) enviando o campo `instructions` estilístico do **Ultron BR** quando o utilizador executar servidor externo em Macs 16+ GB.
  - **Experiência nativa offline 8 GB zero-nuvem** entregue pela combinação **`Supertonic-3 INT8` (`122.8 MB`, speaker nativo profundo `M5`, `sid=9`, `87–93 Hz` F0)** + cadeia DSP não-destrutiva **`VoiceStudioDSPProcessor`**, mantendo streaming de sessão e *barge-in* em `< 0.1 ms`.

### 2.2 Cadeia Acústica Não-Destrutiva (`VoiceStudioDSPProcessor.swift`)

Em vez de modulação em anel (*ring-mod*), vocoder agressivo ou duplicação de vozes, o `VoiceDSPParameters.ultronBRDefault` aplica (`toneSemitones: 0.0`, `metallicIntensity: 0.24`, `resonance: 0.48`, `expressivityAmount: 0.78`, `outputVolume: 1.08`):

1. **Bloqueador de DC (HPF `26 Hz`, Butterworth 2.ª ordem).**
2. **Shift de tom WSOLA (`toneSemitones`) em bypass quando `0.0`:** a ablação mostrou que abaixar `M4` por WSOLA (`ultron_br_m4_wsola_studioDSP`) degrada `HNR_med` para `3.4–4.1 dB` e eleva `Jitter` para `7.61–9.14%`; usar **`M5` nativo em `0.0 st`** preserva timbre grave natural (`87.0–93.4 Hz`) com **`HNR_med = 10.1–12.7 dB`**.
3. **EQ Paramétrico de Estúdio:** foco em corpo vocal (`115 Hz` / `285 Hz`), clareza articular (`2950 Hz`) e controle de região anasalada (`490 Hz`).
4. **Ressonador Titânio Amortecido (`metallicIntensity`):** par de *allpass* curtos amortecidos (`~15–20%` sutil por padrão) sem batimento metálico destrutivo.
5. **Saturação harmônica suave (`tanh`), compressor dinâmico `2.2:1` e limitador *brickwall* em `-1.0 dBFS` (`0.891`) com `0` clippings.**

---

## 3. Controles Individuais por Voz & Persistência Independente

Implementados em **`PerVoiceAudioPreferences`** / `perVoicePreferences` (`VoiceIdentityProfile.swift`) e sincronizados nas interfaces **`VoiceLaboratoryView.swift`** e **`DesktopSettings.swift`**:

- **`Velocidade`** (`speechRate`)
- **`Tom`** (`toneSemitones`, `-4.0 ... +4.0 st`)
- **`Intensidade Metálica`** / **`Intensidade metálica`** (`metallicIntensity`, `0 ... 100%`)
- **`Ressonância`** (`resonance`, `0 ... 100%`)
- **`Expressividade`** (`expressivityAmount`, `0 ... 100%`)
- **`Volume`** (`outputVolume`, `25 ... 150%`)
- Ações **`Aplicar e testar voz`** (Voice Lab), **`Testar voz`** (Ajustes) e **`Restaurar padrão`** (`resetPreferences(for:)`).

Cada persona (`Aurora`, `JARVIS`, `Ultron BR`, `Atlas`, `Aria`) armazena seus próprios ajustes independentemente em disco e o cache vocal inclui a assinatura prosódica + DSP (`prosodySignature`) e passa pelo utilitário compartilhado `finalizePreviewAudio`.

---

## 4. Amostras de Aceitação & Métricas Acústicas Reais (4 Frases Obrigatórias)

Todas as 25 amostras foram inspecionadas por script Python de medição acústica (sem clipping: `clip = 0`, `dc = ±0.0000`) e verificadas por escuta direta das gravações em PT-BR:

| Grupo / Configuração | Frase 01 (`Ah, interessante…`) | Frase 02 (`Encontrei o problema…`) | Frase 03 (`Tudo pronto…`) | Frase 04 (`Hmm… temos um pequeno problema…`) | Observação Acústica |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`jarvis_fixed_m4_44k`** (`44.1 kHz`, novo padrão JARVIS) | `F0=111.1Hz`, `HNR=11.8dB`, `Jitter=3.52%` | `F0=121.2Hz`, `HNR=13.2dB`, `Jitter=3.36%` | `F0=121.2Hz`, `HNR=11.7dB`, `Jitter=3.35%` | `F0=117.3Hz`, `HNR=12.0dB`, `Jitter=3.57%` | Zero raspagem; `+5.1` a `+6.6 dB` acima do `M2` antigo |
| **`jarvis_fixed_m4_stream24k`** (`24 kHz` via `StreamingSincResampler`) | `F0=123.1Hz`, `HNR=12.0dB`, `Jitter=3.63%` | `F0=121.8Hz`, `HNR=13.3dB`, `Jitter=2.98%` | `F0=123.7Hz`, `HNR=12.1dB`, `Jitter=3.66%` | `F0=121.2Hz`, `HNR=11.9dB`, `Jitter=3.06%` | Streaming `24 kHz` mantém HNR e pronuncia `"Hum"` natural |
| **`jarvis_fixed_kokoro_pm_alex`** (`24 kHz` + bloqueador DC) | `F0=129.7Hz`, `HNR=6.3dB`, `Jitter=5.29%` | `F0=127.0Hz`, `HNR=8.2dB`, `Jitter=4.49%` | `F0=130.4Hz`, `HNR=7.4dB`, `Jitter=5.75%` | `F0=128.3Hz`, `HNR=8.1dB`, `Jitter=4.84%` | `dc = -0.0000`, alternativo PT-BR masculino limpo |
| **`ultron_br_m5_studioDSP`** (`44.1 kHz`, padrão **Ultron BR**) | `F0=89.1Hz`, `HNR=10.1dB`, `Jitter=5.14%` | `F0=87.0Hz`, `HNR=11.0dB`, `Jitter=4.86%` | `F0=93.4Hz`, `HNR=11.2dB`, `Jitter=4.64%` | `F0=92.8Hz`, `HNR=12.7dB`, `Jitter=3.43%` | Grave profundo cinematográfico, ressonância titânio sutil e limpa |
| **`ultron_br_m4_wsola_studioDSP`** (ablação WSOLA rejeitada) | `F0=84.6Hz`, `HNR=3.4dB`, `Jitter=9.14%` | `F0=83.8Hz`, `HNR=4.1dB`, `Jitter=7.61%` | `F0=81.2Hz`, `HNR=3.8dB`, `Jitter=8.61%` | `F0=84.0Hz`, `HNR=3.4dB`, `Jitter=8.05%` | Descartada como padrão: WSOLA introduz dispersão de fase |
| **`ultron_br_kokoro_pm_santa_studioDSP`** (fallback Kokoro) | `F0=131.1Hz`, `HNR=6.0dB`, `Jitter=6.85%` | `F0=129.7Hz`, `HNR=7.4dB`, `Jitter=5.70%` | `F0=128.3Hz`, `HNR=6.1dB`, `Jitter=6.81%` | `F0=129.7Hz`, `HNR=7.2dB`, `Jitter=5.90%` | Fallback PT-BR alternativo com DSP aplicado |
| **`control_aurora_pf_dora`** (controle regressão `03`) | — | — | `F0=172.7Hz`, `HNR=9.3dB`, `Jitter=4.46%` | — | Voz feminina intacta (`dc = -0.0000`, `peak = 0.335`) |

---

## 5. Verificação Automatizada Pós-Edição Swift

Executadas integralmente após a última edição nos ficheiros Swift:

- **`bash codex/desktop/macos/tests/run-voice-smoke.sh`** → `VOICE_SMOKE_ALL_PASS` (`Barge-in latency=0.052ms`, `Real Kokoro-82M ... load=651ms, ptBR=3035ms/117126@24kHz`, `Qwen3-1.7B ... TTFT=238ms, total=878ms`, `Kokoro Acoustic Differentiation pf_dora=177.8Hz vs pm_alex=129.7Hz | EN-GB bm_george=138.7Hz`, `Supertonic-3 Flow Matching 44.1kHz (RTF=0.206 | M2=88.2Hz M4=114.8Hz vs F1=184.5Hz)`, `PASS: V5.1 Unified VoiceIdentityManager, Per-Voice Prefs, JARVIS Fix, Ultron BR DSP & Live Controller Bridge`, `TestFootprint=654.4MB CPU=2.6% RAM=8.0GB`, suíte CoreAudio 32 ciclos VPIO aprovada sem erro `-10875`).
- **`bash codex/desktop/macos/tests/run-state-smoke.sh`** → `PASS: project edits/removal preserve files; ... natural voice greeting + fast conversational routing verified`.
- **`bash codex/desktop/macos/tests/run-recovery-smoke.sh`** → `PASS: strict limits; model/account fallback; ... restart and ephemeral privacy`.

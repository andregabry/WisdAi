# Benchmarks Reais e Metas de Desempenho — WisdAI Voice Intelligence Engine

> **Regra de Integridade:** Todos os números abaixo distinguem explicitamente **[Medido neste MacBook M2 8 GB]** de metas de engenharia e valores de terceiros.

---

## 1. Medições Reais Obtidas em Execução Direta (`2026-11-26`)

| Estágio / Operação | Meta de Engenharia | Resultado **Medido** (`VoicePoC` / `VoiceSmokeTests` / Sonda TTS) | Status vs Meta |
|---|---|---|---|
| **Inicialização Motor Local de Áudio (`startFullDuplex`)** | Conexão infinita não permitida | **`207.59 – 236.82 ms`** (determinístico, zero rede) | **Aprovado** |
| **Inicialização `SpeechAnalyzer + SpeechTranscriber` (`macOS 26+`)** | `< 300 ms` | **`66.76 – 103.04 ms`** (`pt_BR`, `pt_PT` instalados on-device) | **Aprovado** |
| **Ring Buffer 20 ms (`PreallocatedFloatRingBuffer`, 500 amostras)** | `< 1.0 ms` P95 | **P50 `0.0003 ms` / P95 `0.0003 ms`** | **Aprovado** |
| **Resample `48 kHz -> 16 kHz PCM16` (500 blocos 20 ms)** | `< 1.5 ms` P95 | **P50 `0.0010 ms` / P95 `0.0012 ms`** | **Aprovado** |
| **Cérebro Local `Apple FoundationModels` (Frio vs Warm)** | `< 600 ms` warm | Frio: `3887.8 ms` · **Warm 1º token: `470.2 – 538.4 ms`** · Total: `745.3 ms` | **Aprovado (com prewarm)** |
| **Síntese Vocal `Apple Natural PCM` (Frio vs Warm)** | `< 300 ms` chunk 1 warm | Frio daemon: `976 – 2811 ms` · **Warm curto: `157.8 ms`** · Médio: `176.0 ms` | **Aprovado (com warm-up)** |
| **Total Percebido Estimado Warm (Fim Turno -> 1º Áudio Audível)** | P50 `< 500 ms` / P95 `< 1.200 ms` | Soma pipeline aquecido: **`~630 – 750 ms` local on-device** *(antes de TTS streaming paralelo)* | **Dentro de P95 (< 1.2s); próximo à meta P50** |
| **Interrupção / Barge-in (`BargeInCoordinator` + Flush Buffer)** | P95 `< 150 ms` | **`0.118 – 0.469 ms`** | **Superou meta em > 300×** |
| **Consumo Adicional de Memória no Processo (`phys_footprint`)** | Controlado (`< 60 MB` em `low8GB`) | **`11.0 – 14.9 MB`** no processo de teste (`+12.7 MB` delta após áudio + FM + TTS) | **Aprovado** |
| **CPU Média Durante Teste / PoC** | Baixo impacto para não travar agentes | **`8.4% – 8.8%`** de 1 núcleo lógico | **Aprovado** |

---

## 2. Gargalos Identificados e Otimizações Aplicadas

1. **Gargalo 1 — Acordar Frio do Daemon `speechsynthesisd` e do `SystemLanguageModel` (`2.8s` + `3.8s`)**:
   - *Otimização:* Executar aquecimento silencioso assíncrono em background ao iniciar a sessão de voz sem bloquear o estado `.listening` nem reproduzir áudio no alto-falante, derrubando a latência real da 1ª conversa do utilizador para ~`158 ms` + ~`500 ms`.
2. **Gargalo 2 — Quebra de Cláusulas Longas na Fala**:
   - *Otimização:* `IncrementalSpeechSegmenter` extrai a 1ª cláusula já aos `28` caracteres em pausas naturais (`,`, `;`, `.`, `!`, `?`), permitindo iniciar a síntese do 1º bloco antes do término completo da geração textual do modelo.
3. **Gargalo 3 — Risco de Travamento Infinito na UI (`Conectando voz`)**:
   - *Otimização:* Substituir esperas bloqueantes por inicialização paralela com *watchdog* máximo de `2.5 s` e transições explícitas de estado (`loadingModel` / `listening` / `error`).

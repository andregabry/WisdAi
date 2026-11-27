# Metas de Desempenho, Instrumentação e Perfis de Hardware

> Hardware de referência auditado neste ambiente: **Apple M2 (8 cores), 8 GB RAM (`8,589,934,592 bytes`), microfone e alto-falantes nativos 48 kHz**.

---

## 1. Metas de Latência (End-to-End e Por Estágio)

| Métrica | Modo S2S Nativo (Meta Comercial) | Pipeline Desacoplado (Cloud Neural) | Pipeline Local / Híbrido (Apple Speech + Natural PCM) | Método de Medição Real |
|---|---|---|---|---|
| **Barge-in Stop Time (Hardware Flush + Cancel)** | `< 100 ms` P50 / **`< 150 ms` P95** | `< 100 ms` P50 / **`< 150 ms` P95** | `< 80 ms` P50 / **`< 150 ms` P95** | Timestamp da detecção de início de fala intencional até `jitterBuffer.flush()` + parada de áudio agendado + envio de cancelamento |
| **Captura → STT Parcial / Ingestão Áudio** | `< 60 ms` P95 (frame pacing 20 ms) | `< 220 ms` P95 (Deepgram) / `< 350 ms` (Apple) | `< 350 ms` P95 (Apple Speech on-device/local) | Delta do último frame vocal até emissão do primeiro evento parcial correspondente |
| **Fim de Turno Semântico → Início LLM / S2S** | `< 50 ms` (VAD nativo) + RTT | `< 120 ms` (classificador local + dispatch) | `< 120 ms` | Delta entre fechamento de turno no `HybridTurnTakingAnalyzer` e despacho do request |
| **LLM 1º Trecho Falável → Início Síntese TTS** | Integrado (S2S) | `< 250 ms` P95 (ElevenLabs WS) | `< 160 ms` P95 (`AVSpeechSynthesizer` PCM chunked) | Delta entre primeiro chunk frasal do LLM e 1º buffer PCM entregue ao `AdaptiveJitterBuffer` |
| **End-to-End (Fim da fala → 1º áudio ouvido)** | `300 – 550 ms` P50 / `< 850 ms` P95 | `650 – 1.150 ms` P50 / `< 1.600 ms` P95 | `800 ms – 1.800 ms` (dependente do LLM ativo, ex. `gemini-3.8-flash-low` vs modelos `high`) | Relógio monotônico `DispatchTime.now().uptimeNanoseconds` / `mach_continuous_time()` |
| **Taxa de Underruns / Cliques de Áudio** | `< 0.5%` dos chunks (meta ideal: `0`) | `< 0.5%` | **`0%`** (alvo em buffer local) | Contador atômico `underrunCount` no `AdaptiveJitterBuffer` |
| **Frame Rate da Orb UI (Sem engasgos)** | `60–120 fps` (`CADisplayLink`/SwiftUI Timeline) | `60–120 fps` | `60–120 fps` (reduzido se `ReduceMotion`) | Zero processamento de DSP/network na Main Thread |

> **Nota sobre honestidade em medições:** Tempos de resposta do LLM dependem diretamente do provedor/CLI escolhido pelo usuário (ex.: medições reais na máquina com `agy` mostraram ~2.3s em modelos flash leves e mais em modelos reasoning pesados). O sistema deve medir e exibir separadamente **Latência de Áudio/Sistema WisdAI** vs **Latência do Provedor LLM/CLI**, jamais mascarando latência externa.

---

## 2. Perfis Adaptativos por Memória Física (RAM)

O módulo `VoiceMemoryAndTelemetry` detectará `ProcessInfo.processInfo.physicalMemory` no startup e aplicará automaticamente o perfil correspondente:

| Perfil Detectado | Faixa de RAM | Capacidade Máxima Ring/Jitter Buffer Áudio | Histórico Ativo de Voz em Memória | Elegibilidade de Modelos Locais (Whisper/TTS Local) | Orçamento-Alvo Adicional do Subsistema de Voz |
|---|---|---|---|---|---|
| **Low / Entry (`profile8GB`)** *(Perfil ativo neste MacBook M2)* | `<= 10 GB` | `~6 s` saída + `2 s` entrada (~1.5 MB) | Últimos `24` turnos em RAM + compactação agressiva acima de `14` turnos | Desabilita LLM/STT local pesado por padrão; prioriza Apple Speech + `AVSpeechSynthesizer` PCM ou APIs cloud leves opt-in | `< 45 MB` RAM adicional, `< 6%` CPU média em escuta |
| **Balanced (`profile16GB`)** | `10 – 20 GB` | `~12 s` saída + `4 s` entrada | Últimos `48` turnos + compactação a partir de `24` turnos | Permite STT/TTS local compacto (ex. `whisper-tiny/base`, `piper`) mediante opt-in | `< 95 MB` RAM (ou `< 450 MB` com modelo local ativo) |
| **Performance (`profile24GB`)** | `20 – 28 GB` | `~20 s` saída + `6 s` entrada | Últimos `80` turnos + compactação a partir de `40` turnos | Permite STT local médio e cache de embeddings semântico leve | `< 140 MB` base |
| **Studio (`profile32GBPlus`)** | `>= 28 GB` | `~30 s` saída + `8 s` entrada | Últimos `120` turnos + resumos hierárquicos múltiplos | Suporta modelos locais médios/grandes simultâneos | `< 200 MB` base |

---

## 3. Protocolo de Benchmark Reproduzível

Todo ciclo de validação após a implementação executará um harness reproduzível (`tests/VoiceBenchmark` ou flag `--benchmark` em `VoiceSmokeTests`) coletando:
1. **Throughput & Zero-Allocation Check no Ring Buffer**: `10.000` frames PCM (20 ms cada) escritos/lidos concorrentemente verificando 0 perda involuntária e latência P99 de enqueue/dequeue `< 0.5 ms`.
2. **Adaptive Jitter Buffer Stability Test**: Simulação de jitter de rede (`10 ms` – `90 ms`) verificando adaptação de watermark e ausência de underruns após pré-buffering.
3. **Barge-In End-to-End Latency**: Tempo medido entre evento sintético de voz do usuário sobre áudio em reprodução e conclusão do flush de buffer + cancelamento + cálculo do prefixo ouvido (`target < 150 ms`).
4. **Resampler Accuracy & Speed**: Conversão `48 kHz Float32` ↔ `24 kHz / 16 kHz PCM16` em blocos de 20 ms (`target < 1 ms / bloco`).
5. **Memory & Footprint Probe**: Consumo residente (`task_vm_info` `phys_footprint`) antes e depois de ativar o motor de voz e simular 100 turnos compactados.

Todos os números reais obtidos serão registrados com data, hardware e condições em `docs/voice/progress.md`.

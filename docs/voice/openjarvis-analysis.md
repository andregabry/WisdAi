# Auditoria Técnica Profunda do Repositório OpenJarvis

> Repositório auditado: `https://github.com/open-jarvis/openjarvis`  
> Commit exato auditado (`git rev-parse HEAD`): **`556ddf32456bdf5c40195714a3385b339b5f98f9`** (`2026-11-26 06:11:46 +0000`)  
> Licença raiz (`LICENSE`): **Apache License 2.0** (`Copyright 2025 The OpenJarvis Authors`, sem ficheiro `NOTICE` adicional na raiz).

---

## 1. Visão Geral da Arquitetura do OpenJarvis

OpenJarvis é um runtime modular em **Python (`>=3.11,<3.14`)** (com ponte Rust opcional em `openjarvis._rust_bridge` para aceleração SQLite FTS5 e desktop wrapper Tauri em `desktop/src-tauri/` + `overlay.html` de chat textual) focado em assistentes locais, orquestração de agentes, memória persistente, telemetria energética Apple Silicon e otimização/aprendizagem baseada em traços (*traces*).

---

## 2. Verificação Crítica: O OpenJarvis Possui Motor Conversacional de Voz Full-Duplex?

**NÃO.** A leitura direta dos módulos em `src/openjarvis/speech/` e `src/openjarvis/cli/_voice_chat.py` confirma objetivamente:

- **`src/openjarvis/speech/voice_io.py`** implementa captura **half-duplex por turno em lote** usando `sounddevice.RawInputStream` (`16 kHz`, chunks de `1024` amostras, limiar escalar fixo `_SILENCE_THRESHOLD = 500`, tempo fixo `_SILENCE_SECONDS = 1.5`, `_STARTUP_SILENCE_SECONDS = 5.0`), grava tudo em WAV na memória, transcreve após terminar de falar e reproduz WAV bloqueando a thread até concluir via `play_audio_file`.
- **Não existem** no OpenJarvis: comunicação Full-Duplex simultânea, Acoustic Echo Cancellation (AEC), Silero/Semantic Turn-Taking acústico, deteção de interrupções em reprodução (barge-in com truncamento exato de contexto ouvido) ou pipeline de streaming contínuo bidirecional áudio-a-áudio.
- Portanto, o motor de áudio Full-Duplex nativo em CoreAudio/Swift do **WisdAI** já é tecnicamente superior ao `speech/voice_io.py` do OpenJarvis.

---

## 3. Análise Detalhada de Componentes Potencialmente Reutilizáveis

### 3.1 `src/openjarvis/speech/kokoro_tts.py` (`KokoroTTSBackend`)
- **Responsabilidade:** Síntese de fala local com **Kokoro-82M** (`hexgrad/Kokoro-82M`, `24 kHz`), cache LRU de pipelines por idioma (`_pipelines` limitado por `_max_cached_pipelines`), suporte explícito ao código `p` = **Português Brasileiro** (`_VOICE_PREFIX_TO_LANG["p"] = "p"`), e contorno engenhoso de dependência (`_import_kokoro`) evitando que falha de `spaCy` (necessário só para inglês `a`/`b`) quebre idiomas baseados em espeak como português!
- **Dependências:** Python `kokoro`, `torch` (`mps`/`cuda`/`cpu`), `numpy`, `soundfile`, `espeak-ng` para `pt-BR`.
- **Licença:** Código OpenJarvis em Apache-2.0; Kokoro-82M weights em Apache-2.0.
- **Compatibilidade com WisdAI:** Conceito e mapeamento `pt-BR` diretamente aplicáveis; porém em aplicativo nativo Swift macOS é mais eficiente executar Kokoro via CoreML/ONNX/C++ ou sidecar sob demanda em vez de exigir ambiente Python pesado no bundle (macOS atual só possui `Python 3.9.6` de sistema, incompatível com requisito `>=3.11` do OpenJarvis).
- **Consumo de recursos:** ~300–680 MB RAM em execução ativa; cabe em `>= 8 GB` sob demanda, exige ~320 MB em disco.
- **Benefícios / Limitações:** Voz natural multi-idioma gratuita com `pm_santa`/`pm_alex`/`pf_dora`, mas sem streaming true token-by-token sem adaptador de sentença.
- **Estratégia:** Adotar estratégia idêntica de segmentação chunk-by-chunk + LRU cache e suportar Kokoro-82M como motor vocal local opt-in na camada `Speech Generation`.

### 3.2 `src/openjarvis/cli/_voice_chat.py` (`_split_for_speech` & `_play_pipelined`)
- **Responsabilidade:** Divisão de resposta por sentença (`_MIN_SPEECH_CHUNK_CHARS = 20`), pré-busca em paralelo do próximo segmento de áudio (`Queue(maxsize=1)` + `Semaphore(1)`) e *warm-up* assíncrono em thread daemon apenas de backends locais (`_LOCAL_TTS_BACKENDS`), nunca disparando chamadas pagas no aquecimento!
- **Dependências / Licença:** Python stdlib (`threading`, `queue`, `re`); Apache-2.0.
- **Compatibilidade & Estratégia:** Padrão **100% compatível e já adaptado em Swift** no `WisdAI`: aquecimento apenas de motores locais (`FoundationModels.prewarm()` + `Speech` / `Voice` warm-up local silencioso reduzindo TTFA local de `2811 ms` para **`157.8 ms`**!).

### 3.3 `src/openjarvis/memory/store.py`, `service.py`, `extractor.py` e `tools/storage/context.py` + `hybrid.py` + `sqlite.py`
- **Responsabilidade:**
  - `store.py` & `context.py`: Sistema de **níveis de confiança (`TRUST_AUTO`, `TRUST_TRUSTED`, `TRUST_UNTRUSTED`)** que coloca em quarentena memórias suspeitas de injeção de prompt antes da injeção no contexto do modelo!
  - `hybrid.py`: **Reciprocal Rank Fusion (RRF)** (`RRF_score(d) = sum(w / (k + rank))`, `k=60`) combinando busca lexical esparsa (SQLite FTS5) e densa.
  - `service.py` & `extractor.py`: Extração assíncrona em background de fatos duradouros (`FactExtractor` com `max_facts_per_turn=10`, `max_fact_chars=200`) usando fila limitada (`maxsize=256`) sem jamais bloquear a conversa principal.
- **Dependências:** `sqlite3` / FTS5 (`porter unicode61` nativo no SQLite do macOS — WisdAI já linka `SQLite3` em Swift!), opcional `faiss`/`sentence-transformers`.
- **Licença:** Apache-2.0.
- **Estratégia:** **Alta prioridade de reutilização conceitual em Swift puro!** Portar: (1) índice SQLite FTS5 local nativo no `WisdAI` (`voice_memory.sqlite` com `trust_tier` + FTS5 + RRF simplificado) e (2) extrator em background via `FoundationModels` local, sem importar Python.

### 3.4 `src/openjarvis/engine/apple_fm.py` & `_apple_fm_support.py`
- **Responsabilidade:** Descoberta arquitetural crítica de que a Apple disponibiliza inferência **in-process via Apple Neural Engine (`Apple Foundation Models`)** sem processo HTTP extra e com medição real em `telemetry/energy_apple.py` (nota técnica do OpenJarvis: `stream_response` emite snapshots cumulativos, e o ANE consome energia fora da GPU padrão).
- **Licença:** Apache-2.0.
- **Estratégia:** Aplicado diretamente em **Swift nativo** usando `#if canImport(FoundationModels)` (`macOS 26+`), medido neste host com resposta aquecida em **~470–556 ms**!

### 3.5 `src/openjarvis/learning/routing/complexity.py` & `router.py`
- **Responsabilidade:** Classificador determinístico ultrarrápido de complexidade (`trivial`, `simple`, `moderate`, `complex`, `very_complex`) por regex de código/matemática/raciocínio multi-etapa + `RoutingContext`, sugerindo orçamento de tokens e decidindo se um turno simples fica no motor local leve ou exige modelo/agente maior.
- **Licença:** Apache-2.0.
- **Estratégia:** **Reutilizado diretamente** no `LocalIntelligenceEngine` em Swift (`LocalQueryComplexityAnalyzer`): saudações, dúvidas rápidas, controle de voz e respostas simples rodam localmente em `< 550 ms` no `FoundationModels` / motor local, enquanto código/pesquisa/edição de arquivos roteiam ao `AgentOrchestrator` (`Codex` / `Antigravity` / `Claude Code`).

### 3.6 `src/openjarvis/agents/orchestrator.py`, `executor.py` & `tools/approval_store.py`
- **Responsabilidade:** `OrchestratorAgent` (loop multi-turno tool-calling com máscara segura contra marcadores de protocolo falsos em texto cercado por crases), `ApprovalStore` (níveis de risco `trivial`, `low`, `medium`, `high` onde ações destrutivas nunca viram auto-aprovação silenciosa) e políticas `always_approve` / `always_deny` / `ask`.
- **Licença:** Apache-2.0.
- **Estratégia:** Adotar exatamente os 4 níveis de risco no validador de chamadas de ferramenta de voz, impedindo que prompt injection falado execute ações de risco alto.

### 3.7 Módulos Descartados para Importação Direta no WisdAI
- `learning/intelligence/grpo_trainer.py`, `sft_trainer.py`, `learning/training/lora.py` (exigem PyTorch + GPU CUDA/treino pesado incompatível com runtime desktop 8 GB RAM em tempo real).
- `engine/vllm.py`, `engine/ollama.py`, `engine/cloud.py`, `speech/voice_io.py`, `desktop/src-tauri/` (substituídos por implementações Swift/CoreAudio/Metal nativas e pelos clientes CLI já integrados ao WisdAI).

> **Conformidade de Licença Apache-2.0:** O código original do OpenJarvis não é copiado literalmente; todos os padrões arquiteturais adaptados em Swift mantêm atribuição documentada a `The OpenJarvis Authors (Apache-2.0, commit 556ddf32456bdf5c40195714a3385b339b5f98f9)`.

# Requisitos de Hardware e Perfis Adaptativos de Recursos

> Hardware base validado por medições reais neste ciclo: **Apple M2, 8 cores, 8 GB RAM (`8,589,934,592 bytes`), macOS 27.0.1, SSD com 8.5 GB livres**.

---

## 1. Matriz de Perfis de Memória (`HardwareMemoryProfile`)

| Perfil | RAM Física | Orçamento Máximo Alvo (Subsistema de Voz) | S2S Local Pesado (7B–9B) | Cérebro Conversacional Local | STT / VAD | TTS (Geração Vocal) | Política de Concorrência c/ Agentes de Código |
|---|---|---|---|---|---|---|---|
| **`low8GB`** *(Ativo neste Mac M2 8 GB)* | `<= 10.5 GB` | `< 60 MB` app + daemons SO | **Bloqueado por padrão** (causaria swap com IDE + agentes) | **`Apple FoundationModels`** (ANE do SO, zero bloat app) ou LLM leve remoto autorizado | `Apple SpeechAnalyzer / SpeechTranscriber` (`pt_BR`, `pt_PT` on-device) + `AcousticVADTracker` | `Apple Natural PCM` warm (**157.8 ms** TTFA, ~15 MB app); **Kokoro-82M sob demanda** c/ aviso se `> 1 GB` livre | **Protege agentes**: nunca carrega modelo 7B nem Whisper grande concorrente durante execução `Codex`/`Antigravity`/`Claude` |
| **`balanced16GB`** | `10.5 – 20 GB` | `< 450 MB` com modelos locais | Apenas Q4 experimental c/ aviso e descarga em ociosidade | `FoundationModels` ou `Qwen2.5-3B Q4_K_M` (`llama.cpp` Metal, ~2.0 GB) | `SpeechAnalyzer` / `whisper.cpp base/small Q5_0` | **Kokoro-82M CoreML/ONNX (~350 MB)** ou Apple Natural | Permite 1 LLM local compacto + Kokoro-82M mantendo agentes fluindo |
| **`performance24GB`** | `20 – 28 GB` | `< 1.5 GB` base | Elegível para testes PersonaPlex/Moshi Q4 ou MiniCPM-o Q4 | Modelo local 3B–7B Q4 + `FoundationModels` | `SpeechAnalyzer` / `mlx-whisper small/medium` + `Silero VAD` | **Kokoro-82M** / `CosyVoice` streaming | Até 2–3 agentes CLI simultâneos sem pressão crítica de swap |
| **`studio32GBPlus`** | `28 – 60 GB` | `< 4 GB` base | **Habilitado (Arquitetura C S2S/Híbrida avançada)** | LLM 7B–14B Q4 Metal + cache KV amplo | `mlx-whisper large-v3-turbo` / `SpeechAnalyzer` | `Kokoro-82M` + `CosyVoice` / clones autorizados | Concorrência plena de S2S local + múltiplos agentes |
| **`ultra64GBPlus`** | `>= 60 GB` | `< 10 GB` base | Completo BF16/FP16 | Múltiplos modelos pré-carregados | Pipeline duplo paralelo | Qualidade estúdio local multi-voz | Sem restrições práticas de memória |

---

## 2. Gestão Dinâmica e Regras de Pressão de Memória

1. **Deteção em Tempo Real (`ProcessInfo.processInfo.physicalMemory` + `task_vm_info`):**
   - O `WisdAI Voice Intelligence Engine` monitora continuamente memória residente (`phys_footprint`), pressão de memória do macOS (`DispatchSource.makeMemoryPressureSource` para eventos `.warning` e `.critical`), número de `activeTasks` em execução (`Codex`, `Antigravity`, `Claude`) e CPU.
2. **Ações Automáticas sob Pressão (`.warning` / `.critical`) ou Concorrência Alta:**
   - Reduz janela de histórico conversacional em RAM acionando compactação progressiva (`compactionTriggerTurns = 14` em `low8GB`).
   - Descarrega caches opcionais/pipelines pesados inativos (*Lazy Loading & Model Unloading*).
   - Limita buffers de áudio (`2.0 s` entrada + `6.0 s` saída em `low8GB`).
3. **Verificação Antes de Descarregar Modelos (`Disk Space Guard`):**
   - Este computador tem **8.5 GB livres em `/`**. Qualquer download futuro de pesos locais (ex. Kokoro ~320 MB ou Whisper GGUF ~500 MB) deverá verificar previamente `URLResourceKey.volumeAvailableCapacityForImportantUsageKey`, exibir tamanho, espaço livre, progresso real e exigir confirmação do utilizador.
4. **Compatibilidade Intel vs Apple Silicon:**
   - **Apple Silicon (`arm64`):** Suporte completo a `FoundationModels` (`macOS 26+`), `SpeechAnalyzer`, Metal (`llama.cpp`), MLX e Neural Engine.
   - **Mac Intel (`x86_64`):** Não possui Apple Neural Engine / MLX / `FoundationModels`; opera automaticamente com `AVAudioEngine` + `SFSpeechRecognizer` / `whisper.cpp` CPU + roteamento conversacional ao agente configurado ou endpoint local OpenAI-compatible (Ollama/LM Studio).

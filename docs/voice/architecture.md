# WisdAI Autonomous Voice Intelligence Engine — Arquitetura Definitiva

> Decisão Arquitetural Selecionada: **Arquitetura C — Motor Adaptativo Híbrido Contextual Local-First (`WisdomUpVoiceIntelligence`)**  
> Princípio Central: **A voz pertence ao WisdAI. A inteligência é extensível. Os agentes são intercambiáveis. A memória é independente.**

---

## 1. Visão Conceptual e Independência de Fornecedores

O **WisdAI Voice Intelligence Engine** (estruturado como núcleo reutilizável **WisdomUp Voice Intelligence**) desacopla integralmente a interface conversacional de voz do fornecedor ou agente de desenvolvimento selecionado pelo utilizador:

- **Zero dependência obrigatória** de APIs comerciais ou proprietárias de voz (`OpenAI Realtime`, `Gemini Live`, `ElevenLabs`, `Deepgram`, endpoints privados WebRTC de ChatGPT).
- **Inicialização 100% local e imediata** sem autenticação prévia em fornecedores de voz e sem estado bloqueante `"Conectando voz"`.
- **Invariância de Identidade Vocal:** alternar entre `Codex`, `Antigravity` (`Gemini`), `Claude Code`, `DeepSeek`, `Grok` ou múltiplas contas nunca altera a voz, personalidade, prosódia ou continuidade da conversa do WisdAI.

---

## 2. Topologia em Módulos (Reutilizável no Ecossistema WisdomUp)

```
WisdomUpVoiceIntelligence (sem dependência direta de UI SwiftUI do chat ou contas CLI)
│
├── Audio Core (`VoiceNativeAudioEngine.swift`)
│   ├── Full-Duplex CoreAudio + AVAudioEngine + AVAudioSourceNode (zero cliques / sample-accurate)
│   ├── PreallocatedFloatRingBuffer (anéis fixos sem alocação na thread de áudio)
│   ├── AdaptiveJitterBuffer (40–160ms dinâmico + backpressure + contador exato de amostras ouvidas)
│   └── CoreAudioDeviceCatalog (hot-plug, Bluetooth HFP/A2DP, fallback -10875/-10876)
│
├── Acoustic Intelligence (`VoiceAcousticIntelligence.swift`)
│   ├── VoiceProcessingIO Hardware AEC + fallback seguro para Spatial/Multi-Channel/Bluetooth
│   ├── Software Echo Reference Correlator (suprime eco residual da saída no microfone)
│   ├── AcousticVADTracker (piso adaptativo de ruído + banda vocal, rejeita cliques/tosse <115ms)
│   └── Apple SpeechDetector (nativo macOS 26+ quando disponível)
│
├── Speech Understanding (`VoiceSpeechUnderstanding.swift`)
│   ├── Primary Local Engine: Apple SpeechAnalyzer + SpeechTranscriber (macOS 26+, pt-BR/pt-PT/en/es on-device)
│   ├── Compatibility Fallback: Apple SFSpeechRecognizer (rotação contínua <48s anti-limite 60s)
│   └── Optional Opt-In Adapters (Deepgram, Whisper local caso habilitado no perfil compatível)
│
├── Conversational Runtime (`VoiceConversationEngine.swift` + `LocalIntelligenceEngine.swift`)
│   ├── ConversationStateMachine (11 estados auditáveis; transição inicialização <= 2.5s garantida)
│   ├── HybridTurnTakingAnalyzer (pausas reflexivas, reticências, hesitações, incerteza epistêmica, backchannels)
│   ├── LocalIntelligenceEngine (Apple FoundationModels ANE in-process em macOS 26+ + prewarm + roteamento de intenção)
│   ├── VoiceResponseAdapter (adaptação conversacional sem Markdown/URLs/código literal + resumo falado)
│   └── IncrementalSpeechSegmenter (chunking prosódico em streaming durante geração)
│
├── Interruption Management (`BargeInCoordinator`)
│   ├── Supressão e flush < 150ms no AdaptiveJitterBuffer (medido ~0.12–0.47ms)
│   ├── Cancelamento cooperativo de TTS + geração conversacional em curso
│   └── Truncagem exata de histórico ao prefixo efetivamente ouvido
│
├── Voice Identity & Speech Generation (`VoiceIdentityProfile.swift` + `VoiceGateway.swift`)
│   ├── Identidade Vocal Exclusiva WisdAI (timbre consistente, prosódia adaptativa, dicionário técnico)
│   ├── Motor Primário Zero-Download: Apple Natural Neural PCM + warm-up em background (~158ms TTFA aquecido)
│   ├── Motor Expressivo Local Extensível (Opt-In): Kokoro-82M (Apache-2.0) / sidecar local compatível com RAM
│   └── Adaptadores Opcionais Cloud (OpenAI/ElevenLabs apenas se explicitamente autorizados no futuro)
│
├── Memory Interfaces (`VoiceMemoryAndTelemetry.swift` — inspirado na arquitetura FTS5/proveniência do OpenJarvis)
│   ├── 5 Camadas: Sessão Atual, Histórico Recente, Preferências Persistentes (Opt-In + SQLite FTS5 local), Projeto, Tarefas
│   ├── Trust Tiers (`trusted` / `auto` / `untrusted`) para prevenir injeção persistente na memória
│   ├── Compactação progressiva orientada ao perfil de RAM
│   └── Snapshot portátil agnóstico de agente/fornecedor
│
└── WisdAI Platform Adapter & Agent Orchestrator (`VoiceOrchestrator.swift` + `WisdCode.swift`)
    ├── Seleção inteligente: conversa simples tratada localmente em <600ms; engenharia/código delegados aos agentes ativos
    ├── Execução assíncrona em background (`ActiveThreadTask`) mantendo diálogo vivo
    └── Enforçamento rigoroso de permissões (`Somente leitura`, `Escrita`, `Acesso total` e `pendingApprovals`)
```

---

## 3. Justificação da Escolha Arquitetural (Evidências Reais)

| Arquitetura | Viabilidade em 8 GB RAM (`Apple M2`) | PT-BR / PT-PT | Latência Warm Medida | Veredito |
|---|---|---|---|---|
| **A — Speech-to-Speech Open-Source Puro (Moshi / PersonaPlex 7B / MiniCPM-o 8B)** | Inviável simultaneamente com Xcode + Codex/Antigravity (consome 4–8+ GB sozinho) | Fraca / imatura em PT-BR e PT-PT | n/d (excede envelope 8 GB) | **Rejeitada como baseline universal** |
| **B — Híbrida Fixa Clássica (Audio → STT → Agente Pesado CLI → TTS)** | Viável | Boa | Alta (`~2.3–6.0s` quando depende de CLI externa para "Oi!") | **Insuficiente para fluidez conversacional** |
| **C — Motor Adaptativo Local-First (`FoundationModels` ANE / Local Brain + `SpeechTranscriber` + `Natural/Kokoro TTS` + Delegação Assíncrona)** | **Ótima (~15 MB app delta no M2 8 GB)** | **Excelente (`pt_BR` e `pt_PT` instalados on-device)** | **~538ms LLM + ~158ms TTS warm = ~696ms total local** | **SELECIONADA** |

Consulte os detalhes comparativos e evidências empíricas em [model-comparison.md](model-comparison.md), [proof-of-concept.md](proof-of-concept.md) e [openjarvis-analysis.md](openjarvis-analysis.md).

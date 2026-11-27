# Plano de Execução Incremental — WisdAI Autonomous Voice Intelligence Engine

Sincronizado exatamente com as 8 fases da especificação (Seção 20):

- **Fase 1 — Auditoria (`Concluída`)**
  - Mapeamento completo do WisdAI, descoberta das causas raiz do estado infinito `"Conectando voz"`, auditoria integral do repositório OpenJarvis (`556ddf32456bdf5c40195714a3385b339b5f98f9`, Apache-2.0) e inventário de reutilização.
- **Fase 2 — Investigação Tecnológica (`Concluída`)**
  - Análise comparativa (Moshi, PersonaPlex, MiniCPM-o, Sesame CSM-1B, CosyVoice, Kokoro-82M, F5-TTS, Piper, Whisper.cpp, MLX-Whisper, Faster-Whisper, SpeechAnalyzer/SpeechTranscriber, Silero/WebRTC VAD, Smart Turn, VoiceProcessingIO, FoundationModels ANE, MLX, llama.cpp), licenciamento e perfis de RAM (`8/16/24/32/64+ GB`).
- **Fase 3 — Provas de Conceito (`Concluída`)**
  - Execução real em `VoicePoC.swift` validando áudio local, `SpeechAnalyzer` (`pt-BR`/`pt-PT` já instalados), pausas reflexivas, raciocínio local aquecido em ~538 ms, TTS aquecido em ~158 ms e barge-in em `0.118 ms`.
- **Fase 4 — Decisão Arquitetural (`Concluída`)**
  - Adoção oficial da **Arquitetura C — Motor Adaptativo Local-First (`WisdomUpVoiceIntelligence`)** + registro completo nos 13 documentos em `docs/voice/`.
- **Fase 5 — Implementação do Voice Intelligence Engine (`Em Execução`)**
  - Criar módulos independentes desacoplados da UI WisdAI (namespace/camada `WisdomUpVoiceIntelligence`):
    1. `VoiceSpeechUnderstanding.swift`: Motor primário `Apple SpeechAnalyzer + SpeechTranscriber + SpeechDetector` (`macOS 26+`) com streaming real sem limite de 60s e sem hang de TCC, fallback automático em `macOS 14–25` via `SFSpeechRecognizer`, zero trava infinita (watchdog determinístico `<= 2.5 s`).
    2. `LocalIntelligenceEngine.swift`: Cérebro conversacional local autônomo (`Apple FoundationModels` ANE em `macOS 26+` + `prewarm()` assíncrono + fallback adaptativo para endpoints compatíveis/regras), analisador determinístico de complexidade (`LocalQueryComplexityAnalyzer` inspirado no OpenJarvis), classificador de intenção (`conversar`, `delegar_agente`, `consultar_status`, `controle_voz`) e prompt multilíngue dinâmico.
    3. `VoiceIdentityProfile.swift`: Identidade vocal própria (`Aurora`, `Atlas`, `Aria`), invariância entre agentes/contas, warm-up silencioso do `AppleNaturalPCMStreamingTTSProvider` (~158 ms) e interface plugável para `Kokoro-82M` / modelos expressivos locais futuros (com verificação de espaço/RAM + autorização).
    4. Aprimoramento de `VoiceNativeAudioEngine.swift`: Adicionar **Acoustic Echo Reference Correlator** (envelope de saída vs entrada do microfone) além do VPIO/AEC hardware para eliminar auto-acionamento da voz da IA no microfone.
    5. Evolução de `VoiceMemoryAndTelemetry.swift`: Desacoplar totalmente de tipos da UI do WisdAI (`Message`), adicionar banco SQLite FTS5 local (`VoiceSQLiteKnowledgeStore`) com níveis de confiança (`trusted` / `auto` / `untrusted`) e fusão RRF inspirados no OpenJarvis, além de monitor de pressão de memória (`DispatchSource.makeMemoryPressureSource`).
- **Fase 6 — Integração com WisdAI (`Em Execução`)**
  - Atualizar `VoiceOrchestrator.swift`, `DesktopVoice.swift`, `WisdCode.swift`, `VoiceHUDViews.swift`, `DesktopShell.swift` e `DesktopSettings.swift`:
    - **Eliminar completamente** `startCodexRealtimeOrFallback()` como caminho de voz (removendo a raiz do travamento `"Conectando"` e qualquer dependência de OpenAI/ChatGPT WebRTC).
    - Conectar `LocalIntelligenceEngine` como interface principal de conversa: saudações e diálogos simples respondidos diretamente em ~538–750 ms; solicitações técnicas/projetos encaminhadas em background aos agentes especializados ativos (`Codex`, `Antigravity`, `Claude Code`) mantendo o canal de voz vivo.
    - Enriquecer estados granulares da Orb (`loadingModel`, `initializingLocalEngine`, `listening`, `userSpeaking`, `interpreting`, `speaking`, `consultingAgent`, `interrupted`, `muted`, `error`, `ended`), indicador claro de microfone ativo e visual para download opcional de modelos quando aplicável.
- **Fase 7 — Otimização (`Próxima`)**
  - Warm-up paralelo no startup de sessão de voz (`FoundationModels.prewarm()` + TTS warm-up silencioso), ajuste fino de limiares de eco/barge-in e proteção de RAM em `low8GB`.
- **Fase 8 — Validação Completa (`Final`)**
  - Atualizar `VoiceSmokeTests.swift` cobrindo inicialização local sem rede (< 2.5s), anti-hang `"Conectando"`, `LocalIntelligenceEngine` routing, eco acústico, memória SQLite FTS5 + `trust_tier`, pausa natural, barge-in, invariância vocal entre contas/agentes e não-regressão em `StateSmoke.swift` e `RecoverySmoke.swift`; compilar e assinar `dist/WisdAI.app` com `-O`.

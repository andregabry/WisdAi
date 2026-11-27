# Auditoria da Implementação Atual e Causa Raiz de `"Conectando voz"`

> Escopo: Inspeção completa do código-fonte atual do WisdAI (`codex/desktop/macos/`) em execução em `macOS 27.0.1 (Apple M2, 8 GB RAM)`.

---

## 1. Diagnóstico Direto: Por Que o Sistema Ficava Preso em `"Conectando voz"`

A investigação linha a linha do fluxo de inicialização identificou **três causas raiz combinadas**:

### Causa Raiz 1 — Tentativa Obrigatória de WebRTC Realtime via `codex app-server` (`WisdCode.swift:1719` & `1853–1930`)
1. Ao ativar a voz em `Workspace.toggleVoiceConversation()`, o código verificava:
   ```swift
   let canTryRealtime = activeProvider == .openai && ready && codexRealtimeFallbackAccountID != activeAcc?.id
   ```
2. Quando a conta ativa era OpenAI, o sistema entrava em `startCodexRealtimeOrFallback()`, colocando imediatamente a UI em `voice.voicePhase = .starting` e `voice.isConnecting = true`, exibindo **"Conectando"** (`DesktopShell.swift:1239`) / **"Conectando assistente…"** (`DesktopShell.swift:3714`).
3. `startCodexRealtimeOrFallback()` aguardava duas barreiras simultâneas antes de avançar para `launchWebRTCRealtimeStart()` (onde ficava o único temporizador de segurança de 8s):
   - Barreira 1: `voice.prepareWebRTCRealtimeSession()` instanciava uma `WKWebView` oculta carregando `https://localhost`, chamando `navigator.mediaDevices.getUserMedia` + `RTCPeerConnection.createOffer()` sem nenhum *timeout* próprio caso a `WKWebView` não retornasse oferta SDP ou falhasse silenciosamente.
   - Barreira 2: `request("thread/start", ...)` no `codex app-server`.
   Qualquer bloqueio ou recusa silenciosa em uma das duas barreiras deixava `didLaunchStartRequest == false` e o estado preso em `"Conectando"` para sempre.

### Causa Raiz 2 — Bloqueio Síncrono/Indefinido de Inicialização no `WisdVoiceOrchestrator` (`VoiceOrchestrator.swift:284–310` & `VoiceGateway.swift:892–905`)
1. Ao migrar para `VoiceOrchestrator.startSessionWithContinuity()`, o sistema transicionava `stateMachine` para `.connecting` (**`"Conectando voz…"`**, `VoiceConversationEngine.swift:22`).
2. Antes de sair de `.connecting`, o método aguardava sequencialmente:
   - `VoiceNativeAudioEngine.requestMicrophonePermissionIfNeeded()`
   - `AppleSpeechStreamingSTTProvider.start(...)` -> `SFSpeechRecognizer.requestAuthorization`
3. Verificação real em runtime neste host (`swift -e`):
   - `AVCaptureDevice.authorizationStatus(for: .audio)` = `3` (autorizado)
   - **`SFSpeechRecognizer.authorizationStatus()` = `0` (`notDetermined`)**
   - Em macOS, chamar `SFSpeechRecognizer.requestAuthorization` a partir de contexto sem foco de diálogo ou quando o processo de reconhecimento do sistema demora a responder bloqueia a `CheckedContinuation` sem prazo limite (*no timeout / watchdog*), mantendo `state == .connecting` indefinidamente!
4. Mesmo quando autorizado, `AppleSpeechStreamingSTTProvider.start` verificava `if policy.preferOnDeviceSpeechOnly && !supportsLocal && !policy.externalAudioConsentGranted` para `pt-PT` (`onDevice=false`), bloqueando o fluxo.

### Causa Raiz 3 — Acoplamento Visual e Falta de Limite Determinístico de Startup
- `DesktopVoice.swift:604` mantinha `voicePhase = .starting` até a task assíncrona inteira retornar, e `VoiceController.bindOrchestratorState()` ignorava atualizações enquanto `isVoiceSessionActive` não concluísse, sem watchdog máximo de inicialização (violando o princípio *"Conexão infinita: Não permitida"*).

---

## 2. Inventário de Componentes Atuais e Decisão de Destino

| Componente / Arquivo | Responsabilidade Atual | Dependência Externa / Auth | Veredito |
|---|---|---|---|
| `VoiceNativeAudioEngine.swift` | CoreAudio, ring buffers lock-free, `AdaptiveJitterBuffer`, `AVAudioSourceNode`, hot-plug e Bluetooth | Nenhuma | **Preservar e Expandir** (adicionar Acoustic Echo Reference Correlator e integração limpa com `SpeechAnalyzer`) |
| `VoiceConversationEngine.swift` | FSM determinística, `HybridTurnTakingAnalyzer`, `BargeInCoordinator`, `VoiceResponseAdapter`, `IncrementalSpeechSegmenter` | Nenhuma | **Preservar e Aprimorar** (desacoplar dependência visual + suporte a pausas reflexivas + orçamento de contexto) |
| `VoiceMemoryAndTelemetry.swift` | Memória em camadas, compactação por perfil RAM, telemetria real (`mach_task`), redação de logs | Nenhuma | **Preservar e Evoluir** (adicionar busca local SQLite FTS5 + trust tiers estilo OpenJarvis + remover referência direta a `Message` do chat) |
| `VoiceGateway.swift` | `OpenAIRealtimeWS`, `GeminiLiveWS`, `Deepgram`, `ElevenLabs`, `AppleSpeechStreamingSTT`, `AppleNaturalPCM` | Chaves API opcionais (desativadas por padrão) | **Reestruturar**: remover foco S2S externo; tornar `SpeechTranscriber` (macOS 26+) + `Kokoro`/local + `AppleNatural` o núcleo nativo; manter APIs externas apenas como plugins opt-in opcionais |
| `DesktopCodexVoiceWebRTC.swift` | `WKWebView` RTCPeerConnection HTML, `CodexRealtimePromptCatalog`, `CodexVoiceAudioCues`, `CodexContinuityItem` | WebRTC Codex / ChatGPT | **Refatorar**: preservar cues sonoros e `CodexContinuityItem`; desativar chamada automática WebRTC Codex como padrão do assistente de voz |
| `DesktopVoice.swift` | `VoiceController`, ditado inline no composer, configurações legadas | `SFSpeechRecognizer` | **Manter Compatível e Limpar**: remover caminhos que forçam `.starting` eterno e delegar voz conversacional ao `WisdVoiceOrchestrator` independente |
| `WisdCode.swift` | Orquestração de `Workspace`, `codex app-server`, CLIs (`agy`, `claude`, `codex`), SQLite chat, aprovações | Contas e CLIs oficiais existentes | **Preservar Integralmente**: desacoplar voz de `startCodexRealtimeOrFallback()`, manter roteamento para agentes como especialistas assíncronos |
| `DesktopShell.swift`, `DesktopSettings.swift`, `VoiceHUDViews.swift` | Orb cromática WisdAI, overlay translúcido 60% + `"X"`, HUD compacta/expandida, preferências | Nenhuma | **Preservar e Aprimorar**: exibir estados reais detalhados (sem `"Conectando voz"` infinito), indicador de mic, carga de modelo e privacidade |

---

## 3. Análise de Impacto nas Funcionalidades Existentes

1. **Ditado pelo ícone de Microfone (`InlineDictationBarView`)**: Preservado sem regressões; beneficia-se do motor `SpeechAnalyzer` / `VoiceNativeAudioEngine` quando disponível no macOS 26+.
2. **Orquestração Multi-Agente (`Codex`, `Antigravity/Gemini`, `Claude`) e Recuperação (`RecoveryManager`)**: Nenhuma alteração destrutiva nos protocolos JSON-RPC ou CLI; agentes passam a receber tarefas delegadas pelo `LocalIntelligenceEngine` / `VoiceOrchestrator` respeitando `mode` (`Somente leitura`, `Escrita no projeto`, `Acesso total`) e `pendingApprovals`.
3. **Testes Existentes (`StateSmoke.swift` e `RecoverySmoke.swift`)**: Assinaturas públicas preservadas para manter compatibilidade total sem regressões.

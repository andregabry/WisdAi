# Perfis Adaptativos de Hardware e Interface **Laboratório de Voz**

## 1. Perfis Adaptativos por Memória Unificada (`VoiceHardwareTier`)

Em `VoiceIdentityProfile.swift`, os perfis escalam de 8 GB até 64+ GB (`Automático` detectado via `ProcessInfo.processInfo.physicalMemory` ou seleção explícita do usuário):

| Perfil | Faixa de RAM | Cérebro / TTS Recomendado | Política de Memória Ativa |
| :--- | :---: | :--- | :--- |
| **`Essential (8 GB RAM)`** | <= 10.5 GB (Apple M2 8 GB testado) | `Apple FoundationModels` ou `Qwen3-1.7B-Q4_K_M` (`llama.cpp Metal`) + `Kokoro-82M INT8` | Apenas 1 LLM GGUF carregado por vez, contexto 2048 tokens, descarga por ociosidade (`180s` Kokoro / `240s` `llama-server`) e descarga imediata em `.warning` / `.critical` via `VoiceMemoryPressureWatcher` |
| **`Advanced (16–24 GB RAM)`** | 12–24 GB | `Qwen3-4B` / `Gemma-3-4B` / `Phi-4-mini` Q4_K_M + `Kokoro FP32` ou `MLX Server` | Contexto 4096 tokens, 6 threads GPU/CPU equilibradas |
| **`Ultra (32–64+ GB RAM)`** | >= 32 GB | Modelos 7B–8B, múltiplos agentes e elegibilidade para S2S experimental (quando stack MLX/Python instalada) | Jitter buffer até 30 s, histórico em memória até 120 turnos |

---

## 2. Estados Reais de Ciclo de Vida (`VoiceModelInstallState`)

Todos os itens no catálogo exibem exclusivamente estados reais refletidos pelo sistema de arquivos e processos em execução:
- `Não instalado` (`notInstalled`)
- `Aguardando autorização` (`awaitingConsent`)
- `Instalando` (`installing` — com progresso `0...100%`, MB/s e botão `Cancelar`)
- `Disponível` (`available` — arquivo presente e `.wisdai-verified.json` validado via SHA-256)
- `Carregando` (`loading` — processo `llama-server` ou C `SherpaOnnxCreateOfflineTts` inicializando)
- `Operacional` (`operational` — carregado e pronto para inferência)
- `Incompatível` (`incompatible` — RAM insuficiente para `minimumRAMGB`, dependência ausente ou stack externa `.externalManual`)
- `Erro` (`error` — exibe mensagem real da falha)

---

## 3. Estrutura Integrada em **Configurações → Voz → Laboratório de Voz** (`VoiceLaboratoryView.swift`)

Integrada em `DesktopSettings.swift` dentro de `VoiceSettingsSection`:
1. **Motores & Voz:** troca dinâmica do cérebro (`VoiceBrainEngineKind`), carga/descarga de GGUF (`Qwen3`, `Gemma`, `Llama`, `Phi`), verificação loopback MLX, seletor de modo (`Híbrido Neural` vs `Speech-to-Speech`), seletor de motor TTS (`Kokoro-82M`, `Apple Natural PCM`, etc.) com avisos explícitos (`pt-PT`, `CC-BY-NC-4.0`), controle real de velocidade (sem sliders fictícios de emoção), campo de texto customizado + **Ouvir Motor Selecionado**, **Comparar Kokoro vs Apple**, **Parar Áudio** e **Salvar WAV…**.
2. **Modelos & Hardware:** seletor `VoiceHardwareTier`, barra de espaço livre em disco, botões individuais `Baixar…`, `Selecionar` e `Remover` com consentimento explícito SHA-256.
3. **Telemetria & Pipeline:** grades ao vivo de **STT**, **LLM TTFT**, **TTS TTFA**, **E2E P50/P95**, **Parada Barge-In**, tempos de carga/síntese Kokoro, RAM residente do processo (MB), CPU%, GPU Metal (`MTLCreateSystemDefaultDevice`), disco livre e toggle opt-in do **Diagnóstico Avançado (11 estágios)**.
4. **Higiene de Memória:** botão **Verificar Memória**, listagem de candidatos de deriva ASR / fragmentos com motivo estrutural e caixas de seleção para revisão e **Remover Selecionados** sem tocar em conversas legítimas.

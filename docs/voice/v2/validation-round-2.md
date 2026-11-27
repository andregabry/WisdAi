# Validação Real, Correções e Benchmark — Rodada 2 (`feature/voice-intelligence-v2`)

**Data:** 2026-11-27  
**Branch:** `feature/voice-intelligence-v2` (PR #15 — sem merge em `main`)  
**Hardware / SO avaliados:** Apple Silicon M2, 8.0 GB RAM unificada, macOS 27.0.1 (`26A434`)  
**Configuração neural:** Cérebro `Qwen3-1.7B-Q4_K_M` (`llama.cpp Metal b12809`), TTS `Kokoro-82M INT8` (`pf_dora` e `pm_alex` disponíveis para avaliação), STT `SpeechAnalyzer` (`pt-BR`), Idioma `pt-BR`.

---

## 1. Correções Aplicadas Após Revisão do App em Execução e Auditoria

1. **Build Info & Rastreabilidade do Binário (`build-dmg.sh`, `VoiceIdentityProfile.swift`, `VoiceLaboratoryView.swift`)**
   - `build-dmg.sh` passou a injetar `WisdAIGitCommit`, `WisdAIGitBranch` e `WisdAIBuildTimestamp` no `Contents/Info.plist` do bundle antes da assinatura (`codesign`).
   - `WisdVoiceBuildInfo` expõe commit/branch/timestamp diretamente no cabeçalho do **Laboratório de Voz** para eliminar ambiguidade sobre builds antigos.
2. **Hardening de Integridade, Extração Segura e Loopback (`VoiceIdentityProfile.swift`, `VoiceNeuralRuntime.swift`)**
   - `isModelInstalledOnDisk` e `verifyInstalledIntegrityOnDemand` agora validam recibos JSON `.wisdai-verified.json` com SHA-256, tamanho não-nulo e confinamento no diretório de destino.
   - `installVerifiedFile` realiza pré-auditoria com `tar -tf` / `tar -tvf` bloqueando traversal (`..`, caminhos absolutos), symlinks/hardlinks e arquivos especiais, aplica `--no-same-owner --no-same-permissions`, valida a árvore extraída antes do swap atômico e executa rollback seguro.
   - `llama-server` e cliente MLX/SSE exigem estritamente loopback `127.0.0.1` / `::1`, usam `URLSessionConfiguration.ephemeral` com `connectionProxyDictionary = [:]` (sem cookies/credenciais/cache) e sanitizam variáveis de ambiente removendo chaves de API do processo pai.
3. **Encerramento Limpo & Isolamento Somente-Leitura (`VoiceNeuralRuntime.swift`, `WisdCode.swift`, `VoiceOrchestrator.swift`)**
   - `LocalLlamaServerBrainRuntime.unloadModel()` e `deinit` realizam `SIGTERM` com espera limitada seguido de `SIGKILL`; `Workspace.shutdownGracefully()` é acionado em `NSApplication.willTerminateNotification`.
   - Escalonamento automático `[CONSULTAR_ESPECIALISTA: ...]` força política somente-leitura (`sandboxPolicy = "readOnly"` no Codex e `--mode plan --sandbox` no Antigravity) e preserva `activeVoiceDelegatedTaskTitle` durante a consulta.
4. **Suavidade e Confiabilidade do Qwen3-1.7B (`VoiceNeuralRuntime.swift`, `LocalIntelligenceEngine.swift`)**
   - Para modelos Qwen3 no `llama-server b12809`, o runtime passa `--reasoning off --reasoning-budget 0` com `temperature=0.5`, `top_p=0.9`, `max_tokens=440` e realiza uma nova tentativa limpa caso ocorra resposta vazia transitória.
   - Eliminada a falha pontual observada antes da correção (`TURN_11` agora responde com `0` fallbacks em 32 turnos).
5. **Sincronização do Laboratório de Voz & Higiene de Memória (`VoiceLaboratoryView.swift`, `DesktopVoice.swift`, `VoiceMemoryAndTelemetry.swift`, `WisdCode.swift`)**
   - Trocas de motor, modelo GGUF ou preset Kokoro atualizam imediatamente status e telemetria ativa; removida sobrescrita silenciosa de `speechRate` em `DesktopVoice`.
   - Adicionados botões PT-BR de avaliação (`Ouvir pf_dora` e `Ouvir pm_alex`) sem travar escolha definitiva antes da aprovação humana.
   - Inspeção de Higiene de Memória agora varre também o SQLite de histórico (`wisdai_history.sqlite`), permitindo ao usuário revisar e limpar os 8 registros antigos da thread `53C9FCCE` com `"Molina"` / `"Comendo"`, enquanto `filterCleanContextItems` impede o vazamento para novas sessões de voz.

---

## 2. Instrumentação Real dos 7 Marcos de Latência e Resultados (32 Intervenções)

Resultados obtidos após as últimas edições (`BENCH_32_TURNS_PASS`) usando estímulos PCM 24 kHz reais no `UnifiedLocalSTTCoordinator` (`SpeechAnalyzer` `pt_BR`), `Qwen3-1.7B-Q4_K_M` Metal, `Kokoro-82M` (`pf_dora` / `pm_alex`), `AdaptiveJitterBuffer` com callback real CoreAudio `renderPull` (`13.73 ms` HW DAC latency em `Alto-falantes (MacBook Pro)`) e `AcousticVADTracker`:

| Marco Instrumentado | Amostras | P50 | P95 | Observação Técnica |
| :--- | :---: | :---: | :---: | :--- |
| 1. Fim da fala → Transcrição final | `n=32` | **0.3 ms** | **0.7 ms** | Settling após término da entrega do áudio; no uso real ao vivo, o `HybridTurnTakingAnalyzer` adiciona ~520–920 ms de hold semântico |
| 2. Commit → Primeiro token LLM | `n=32` | **519.1 ms** | **1002.0 ms** | `Qwen3-1.7B-Q4_K_M` via `llama-server` loopback SSE |
| 3. Commit → Primeira cláusula pronta | `n=32` | **915.7 ms** | **1578.5 ms** | Segmentação incremental para envio imediato ao TTS |
| 4. Cláusula → Primeiro chunk de áudio | `n=32` | **2454.2 ms** | **5256.2 ms** | Callback C ABI do `sherpa-onnx` retorna o buffer PCM após sintetizar a cláusula |
| 5. Síntese completa da cláusula | `n=32` | **2479.3 ms** | **5256.5 ms** | Medido separadamente do primeiro chunk (praticamente idêntico no C ABI atual) |
| 6. Commit → 1º áudio reproduzido (+HW) | `n=32` | **3787.6 ms** | **6490.9 ms** | Inclui timestamp real de `renderPull` no CoreAudio + `13.73 ms` DAC |
| 7. Fim da fala → 1º áudio reproduzido | `n=32` | **3788.5 ms** | **6491.2 ms** | Soma fim de STT + LLM + síntese + 1º render CoreAudio + DAC |
| Barge-in (flush de software isolado) | `n=6` | **0.02 ms** | **0.03 ms** | Apenas limpeza do ring/jitter buffer (não confundido com silêncio audível) |
| Barge-in até interrupção audível percebida | `n=6` | **140.1 ms** | **142.3 ms** | Onset VAD (`122 ms`) + flush + próximo `renderPull` silencioso + `13.73 ms` DAC |

### Verificações Funcionais e Concorrência
- **Suítes de regressão após última edição:** `run-voice-smoke.sh` (`VOICE_SMOKE_ALL_PASS`), `run-state-smoke.sh` (`PASS`) e `run-recovery-smoke.sh` (`PASS`) com saída `0`.
- **Contexto multi-turno e troca de assunto:** `contextOK=true`, `topicFollowUpOK=true`, `molinaLeaks=0`, `unavailableFallbacks=0`, `voiceMismatch=0`.
- **Resiliência e honestidade de capacidade local:** ao ser questionado sobre contagem exata de linhas no disco, Qwen3 respondeu honestamente que não possui acesso aos arquivos (`"Não, não tenho acesso aos arquivos do disco..."`).
- **Concorrência com especialistas em modo somente leitura (`idx 14..31`):**
  - Antigravity (`agy --mode plan --sandbox`) executou em paralelo (`SPECIALIST_READONLY_OUTPUT_LEN=391`), manteve `workspaceUnchanged=true` e sua resposta foi incorporada na fala do WisdAI com a mesma voz `pf_dora` (`SPECIALIST_INCORPORATED ok=true`).
  - Codex CLI (`codex exec -s read-only --ephemeral`) foi disparado em paralelo (`CODEX_READONLY_OUTPUT_LEN=810`), reportando honestamente o limite de cota da conta ativa no servidor (`ERROR: You’ve hit your usage limit...`).
- **Pegada de memória e estado térmico (M2 8 GB sob concorrência):**
  - Picos medidos com `proc_pid_rusage (RUSAGE_INFO_V4)`: App+Kokoro `603.9 MB`, `llama-server` `780.8 MB`, `agy` `247.2 MB`, total da pilha `1300.9 MB`, estado térmico `0` (`Nominal`), `Pages throttled: 0`, swap criptografado em `2694.94M / 4096.00M`, `kern.memorystatus_level: 35`.
- **Limitação residual observada (sem ocultar):** no Turno 30, Qwen3-1.7B-Q4_K_M emitiu 2 ideogramas CJK fora do idioma (`"execução独立"`, `cjkBleeds=1`), que foram ignorados pelo léxico Kokoro como OOV (`Ignore OOV '独' / '立'`).

---

## 3. Auditoria Honesta de Segurança e Licenciamento Comercial

- **Distribuição do app (`Apache-2.0`):** o repositório e o `WisdAI.app` (`codex/LICENSE`) são licenciados em Apache-2.0 e **não** empacotam pesos, `llama-server` nem bibliotecas de terceiros dentro do `.dmg`/`.app`. Todos os downloads dependem de consentimento explícito e são validados com SHA-256 + recibo `.wisdai-verified.json` + extração tar endurecida.
- **Modelos e runtimes externos:** `llama.cpp` (MIT), pesos `Qwen3-1.7B` (Apache-2.0), pesos `Kokoro-82M` (Apache-2.0); modelos não comerciais (`F5-TTS`, `CC-BY-NC-4.0`) e S2S inviáveis em 8 GB permanecem bloqueados/sinalizados.
- **Ressalva honesta sobre `espeak-ng` (`GPL-3.0`) via `dlopen`:** embora o `libsherpa-onnx-c-api.dylib` (Apache-2.0) só seja baixado sob demanda no `Application Support` após consentimento do usuário, ele incorpora o fonemizador `espeak-ng` (GPL-3.0) e hoje é carregado in-process via `dlopen` pelo `KokoroNeuralTTSProvider`. Para distribuição comercial estrita sem qualquer exposição a interpretação de vinculação GPL-3.0 no processo principal, recomenda-se isolar o runtime Kokoro em um processo auxiliar XPC/loopback separado em etapa futura (fora do escopo desta validação sem nova refatoração arquitetural).

---

## 4. Pendência Exclusiva de Aprovação Humana

- Conversa ao vivo por microfone com o usuário no aplicativo recém-compilado (`/Applications/WisdAI.app`), avaliação auditiva direta entre `pf_dora` e `pm_alex` no Laboratório de Voz e confirmação explícita do usuário antes de qualquer decisão futura sobre merge do PR #15.

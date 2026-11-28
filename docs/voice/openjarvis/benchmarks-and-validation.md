# Benchmarks, Validação E2E e Auditoria Acústica

Todas as medições e resultados abaixo foram obtidos em execução real neste Mac (**Apple Silicon M2, 8 GB RAM, macOS**) sem mocks de agentes nem do runtime OpenJarvis.

## 1. Resumo das Suítes Automatizadas Executadas

| Suíte | Script / Alvo | Escopo verificado | Resultado observado |
| --- | --- | --- | --- |
| State Smoke | [run-state-smoke.sh](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/tests/run-state-smoke.sh) | Limites estritos, fallback, contexto no mesmo thread, modo texto | `PASS` (exit 0) |
| Recovery Smoke | [run-recovery-smoke.sh](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/tests/run-recovery-smoke.sh) | Preservação de política, auth, cooldown, restart, privacidade | `PASS` (exit 0) |
| Voice Smoke | [run-voice-smoke.sh](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/tests/run-voice-smoke.sh) | FSM, VAD F0 (`140–210 Hz`), barge-in (`0.070ms`), Ring/Jitter, OpenJarvis 12 contratos + host UDS, Kokoro, Qwen3-1.7B Metal, Apple PCM | `VOICE_SMOKE_ALL_PASS` (exit 0) |
| E2E Real A–I | [run-agentic-voice-e2e.sh](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/tests/run-agentic-voice-e2e.sh) | Antigravity (`agy`), Codex (`codex app-server`), Claude honesto, daemon OpenJarvis UDS + 12 tools + EN/PT-BR + barge-in + Clean TTS + FasterWhisper + `SIGKILL` recovery | `AGENTIC_VOICE_E2E_ALL_PASS` (exit 0) |
| App Bundle DMG | [build-dmg.sh](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/build-dmg.sh) | Compilação `WisdAI.app`, assinatura `codesign --verify --deep --strict`, bundling de `OpenJarvisRuntime/` + `bin/uv` + `NOTICE`, instalação e launch em `/Applications/WisdAI.app` | `APP_BUILD_INSTALL_LAUNCH_OK` (exit 0) |

## 2. Métricas Observadas do Subsistema OpenJarvis Real (Apple M2 8 GB)

### 2.1 Boot, Memória e Agentes Reais (`Tests A–I`)
- **Daemon OpenJarvis Python (pré-warmup STT):** `boot = 9731 ms`, **`RSS = 135,9 MB`**, **`tools_count = 12`** (`23` vozes registradas no `/v1/wisdai/health`).
- **Daemon OpenJarvis Python (pós-warmup FasterWhisper `base` `int8`):** **`RSS = 688,6 MB`**.
- **PoC isolada pré-integração:** daemon mínimo UDS `31,7 MB RSS` + `llama-server` Metal `Qwen3-1.7B-Q4_K_M` `1584,1 MB RSS` (`TTFT = 111–126 ms`).
- **Espaço em disco do runtime gerenciado (`~/Library/Application Support/WisdAI/OpenJarvis`):** `venv = 257 MB`, `bin/uv = 27 MB`, `OpenJarvisRuntime` fonte no app = `13 MB`.
- **Latência de barge-in SSE (`/v1/wisdai/voice/cancel` + fechamento POSIX):** **`0,1 ms`** preservando a tarefa do agente em background ativa; `cancel_task` explícito encerrou a tarefa em seguida com `.taskCancelled`.
- **Delegação real OpenJarvis → Antigravity (`agy` CLI):** leu `Sources/MeetSessionController.swift` em `WisdMeet` e retornou símbolo real `MeetSessionCoordinator_V6Sentinel` (zero alucinação em `Test G`).
- **Execução real Codex (`codex app-server`, `gpt-6-astra`):** leu `README.md` em `Test F-Codex` e `Sources/AudioJitterBridge.swift` via `execute_agent_task(agent="codex")` em `Test I-5`, retornando `AudioPipelineJitterBudget = 42`.
- **Honestidade sobre Claude Code (`Test F-Claude` & `Test I-3-EN`):** com binário `claude` ausente no macOS, informou explicitamente indisponibilidade sem simular execução.
- **Isolamento multi-projeto (`Test E` & `Test I-6`):** alternância entre `WisdMeet@main` e `WisdFin@feature/beta` com `get_active_project` retornando exclusivamente `"WisdFin"` e `"feature/beta"`, sem vazamento de `WisdMeet`.
- **Recuperação após crash (`SIGKILL`):** processo daemon PID `16624` encerrado abruptamente recuperou automaticamente com novo PID saudável `16696` (`toolsCount = 12`); `shutdown()` final encerrou ambos OpenJarvis e `llama-server` e removeu os sockets `.sock`.

### 2.2 Síntese Limpa, Remoção de DC e Transcrição (`Tests H & I-7`)
- **Remoção de viés DC no Kokoro-82M int8:** sem o antigo filtro DSP, o decoder bruto do `pf_dora` apresentava viés DC de `+0,024894`; após adicionar `centerAudioDCOffset` e subtração escalar em `tts_sherpa.py`, as amostras mediram **`DC = 0,00000`** sem qualquer coloração espectral.
- **Benchmarks de síntese (`Test H`, 24 kHz):**
  - `v6_jarvis_m4_ptbr_01_live_audit_summary.wav` (Supertonic M4): `23,92 s`, `RTF = 0,211`, `F0 = 116,5 Hz`, `peak = 0,354`.
  - `v6_ultron_br_m5_ptbr_03_audit_complete.wav` (Supertonic M5): `10,18 s`, `RTF = 0,216`, `F0 = 91,6 Hz`, `peak = 0,369`.
  - `v6_aurora_kokoro_ptbr_04_audit_complete.wav` (Kokoro `pf_dora`): `7,94 s`, `RTF = 0,596`, `F0 = 173,9 Hz`, `peak = 0,400`, `DC = 0,00000`.
  - `v6_jarvis_m4_en_05_audit_complete.wav` (Supertonic M4 EN): `9,71 s`, `RTF = 0,226`, `F0 = 112,7 Hz`, `peak = 0,321`.
- **Exportação e audição direta via `/v1/wisdai/synthesize` (`openjarvis_native_e2e_samples/`, `Test I-7`):**
  - `oj_01_supertonic_m4_ptbr.wav`: `586.212` bytes, `rms = 0,0597`, `peak = 0,336`
  - `oj_02_supertonic_m5_ptbr.wav`: `685.878` bytes, `rms = 0,0607`, `peak = 0,310`
  - `oj_03_supertonic_m4_en.wav`: `724.362` bytes, `rms = 0,0574`, `peak = 0,343`
  - `oj_04_kokoro_pm_alex_ptbr.wav`: `242.956` bytes, `rms = 0,0529`, `peak = 0,350`
  - `oj_05_kokoro_bm_george_en.wav`: `271.942` bytes, `rms = 0,0681`, `peak = 0,305`
  - **Audição direta confirmada:** todas as 5 amostras reproduzem fala natural, expressiva e inteligível em PT-BR e EN-GB sem zumbido metálico nem distorção robótica.
- **Round-trip STT (`FasterWhisperBackend` com hotwords):** transcrição direta de `oj_01_supertonic_m4_ptbr.wav` retornou `'Estou analisando o repositorio, Wisd com Antigravity e Codex usando OpenJarvis.'`.

## 3. Lista de Verificação (Checklist Final)

- [x] Código-fonte real dos 3 repositórios analisado individualmente antes da implementação ([audit-and-poc.md](file:///Users/andregabry/Project/WisdAI/docs/voice/openjarvis/audit-and-poc.md)).
- [x] Daemon OpenJarvis provisionado, iniciado, monitorado e encerrado automaticamente sem passos manuais.
- [x] Transporte local privado por Unix Domain Socket (`0700`/`0600`) com Bearer Token aleatório por sessão.
- [x] Todas as 12 `BaseTool` conectadas ao `Workspace`, `ProjectContextResolver`, `ExecutionEventBus` e `submitUnifiedMessage`.
- [x] Nenhuma dependência GPL/LGPL no runtime Python gerenciado (`requirements-clean.txt`).
- [x] Distúrbios metálicos/WSOLA removidos; audição direta confirmada em vozes EN-GB, EN-US e PT-BR.
- [x] Isolamento multi-projeto, preservação de tarefas durante barge-in, recuperação pós-`SIGKILL` e não-regressão do modo texto validados.
- [x] Aplicativo `/Applications/WisdAI.app` recompilado, assinado, validado (`codesign --verify --deep --strict`) e iniciado.

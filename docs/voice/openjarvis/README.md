# WisdAI — Integração Nativa OpenJarvis

Este diretório documenta a substituição arquitetural do subsistema fragmentado de voz V2–V6 do WisdAI por uma integração nativa, gerenciada e de baixa pegada baseada no framework [`open-jarvis/OpenJarvis`](https://github.com/open-jarvis/OpenJarvis) (`Apache-2.0`, commit `8b07c88e26e401ac00d2db558a069d604c4f0477`).

## Documentos da Integração

| Documento | Escopo |
| --- | --- |
| [audit-and-poc.md](file:///Users/andregabry/Project/WisdAI/docs/voice/openjarvis/audit-and-poc.md) | Auditoria comparativa (`open-jarvis/OpenJarvis`, `lancejames221b/openjarvis`, `jgkawell/jarvis`), classificação dos 16 componentes Swift e resultados da Prova de Conceito isolada. |
| [architecture.md](file:///Users/andregabry/Project/WisdAI/docs/voice/openjarvis/architecture.md) | Arquitetura nativa gerenciada, transporte privado por Unix Domain Socket, captura Full-Duplex VPIO AEC, STT/TTS neurais limpos e ciclo de vida automático. |
| [tools-and-orchestration.md](file:///Users/andregabry/Project/WisdAI/docs/voice/openjarvis/tools-and-orchestration.md) | Contratos completos das 12 `BaseTool` conectadas ao `Workspace`, `ProjectContextResolver`, `ExecutionEventBus` e `submitUnifiedMessage`. |
| [benchmarks-and-validation.md](file:///Users/andregabry/Project/WisdAI/docs/voice/openjarvis/benchmarks-and-validation.md) | Resultados observados nos testes reais não-mockados (`Smoke`, `E2E A–I`, `App Bundle`, latência, RAM, transcrição e inspeção acústica direta). |
| [licensing.md](file:///Users/andregabry/Project/WisdAI/docs/voice/openjarvis/licensing.md) | Matriz completa de licenciamento (`Apache-2.0`, `MIT`, `BSD`, `PSF-2.0`, `MPL-2.0`), exclusão de dependências GPL/LGPL e avaliação do `jgkawell/jarvis`. |
| [rollback.md](file:///Users/andregabry/Project/WisdAI/docs/voice/openjarvis/rollback.md) | Procedimento exato de rollback seguro para `feature/voice-identity-jarvis-v5` (`5e33caf10577b4425bfa1afd29ec32c65cc7b8af`). |

## Princípios Preservados

- **Experiência zero-CLI para o utilizador final:** provisionamento, inicialização, health check, recuperação automática após crash e desligamento do daemon Python do OpenJarvis são totalmente automáticos via `OpenJarvisProcessManager`.
- **Nenhuma regressão no produto:** UI do WisdAI, projetos, conversas, histórico, integração Git, contas/CLI (`Codex`, `Antigravity`), modelos, esforço de raciocínio, tarefas paralelas, aprovações, fallback e modo texto permanecem íntegros.
- **Voz neural limpa:** remoção definitiva de pós-processamento metálico/pitch-shift (`VoiceStudioDSPProcessor`) e uso nativo de `Supertonic-3` (`44,1 kHz`, `MIT`) e `Kokoro-int8` (`24 kHz`, `Apache-2.0`) via C-API do `sherpa-onnx`, com remoção escalar de viés DC (`centerAudioDCOffset`).

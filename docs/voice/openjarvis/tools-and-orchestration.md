# Ferramentas e Orquestração Bidirecional (12 Contratos OpenJarvis)

O pacote [tools.py](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/OpenJarvisRuntime/wisdai_bridge/tools.py) registra 12 instâncias `BaseTool` no `OrchestratorAgent` / `ToolExecutor` do OpenJarvis. Cada invocação é autenticada via `WisdAIHostClient` sobre `host-<pid>.sock` e executada diretamente em `@MainActor Workspace` através de [OpenJarvisWorkspaceAdapter.swift](file:///Users/andregabry/Project/WisdAI/codex/desktop/macos/OpenJarvisWorkspaceAdapter.swift).

## Matriz dos 12 Contratos

| Ferramenta (`OpenJarvisToolName`) | Parâmetros principais | Fonte real no WisdAI | Comportamento e garantias |
| --- | --- | --- | --- |
| `list_projects` | `—` | `localDataRef?.projects`, `ProjectContextResolver.validateDirectorySync` | Lista projetos configurados (`id`, `name`, `path`, `is_active`, existência/acesso do diretório). |
| `get_active_project` | `—` | `Workspace.resolvedProjectContext`, `selected` | Atualiza inspeção Git do projeto ativo e retorna nome, caminho, branch, repositório Git e thread selecionada. |
| `get_project_context` | `project?` | `Workspace.findProjectItem`, `ProjectContextResolver.resolve` | Inspeciona projeto específico (ou ativo), retornando `name`, `project_name`, status Git e validação real sem fallback oculto. |
| `list_available_agents` | `—` | `localDataRef?.aiAccounts`, `AgentCLIAuthenticator.locateCLI`, `Bundle.main` | Expõe listas explícitas `installed_agents` vs `unavailable_agents`, status de `codex`, `antigravity` e `claude_code`, modelo e esforço selecionados. |
| `execute_agent_task` | `instruction`, `project?`, `agent?`, `model?`, `effort?`, `read_only?` | `Workspace.submitUnifiedMessage(..., source: .voice)` | Roteia para `Antigravity`, `Codex`, `Claude` ou agente ativo; aplica modo `read_only`, valida diretório real (`.blockedDirectory`), respeita aprovações e preserva paridade integral com modo texto. |
| `get_task_status` | `task_id?` | `ExecutionEventBus.snapshot`, `activeTasks`, `pendingApprovals` | Consulta estado vivo de execução (fase, agente, modelo, leitura/edição de ficheiros, contagem de aprovações). |
| `get_task_events` | `task_id?`, `limit?` | `ExecutionEventBus.events(for:)` | Retorna histórico cronológico de eventos verificados (`task.started`, `file.read`, `command.completed`, etc.). |
| `send_task_instruction` | `instruction`, `task_id?` | `Workspace.submitUnifiedMessage(..., enqueueIfBusy: true)` | Enfileira instrução complementar à tarefa em andamento sem descartar contexto. |
| `cancel_task` | `task_id?` | `Workspace.cancelActiveTaskFromVoice()` / `ExecutionEventBus` | Cancela explicitamente a tarefa de engenharia ativa apenas sob pedido do utilizador. |
| `get_task_result` | `task_id?` | `Workspace.messages`, `ExecutionEventBus.snapshot` | Retorna resultado verificado, ficheiros lidos/modificados, comandos/testes executados e erro real (quando houver). |
| `list_running_tasks` | `—` | `Workspace.activeTasks`, `ExecutionEventBus` | Enumera todas as tarefas ativas em paralelo com thread, agente, modelo e projeto. |
| `request_task_approval` | `decision?` (`status`, `approve`, `deny`, `cancel`) | `Workspace.pendingApprovals`, `Workspace.respondApproval` | Consulta pendências de aprovação e encaminha decisão do utilizador sem contornar sandbox/permissões. |

## Integridade e Isolamento

1. **Corrupção de quota multi-provedor corrigida:** em `WisdCode.swift` (`ingestRateLimitsPayload`), respostas `account/rateLimits` do `codex app-server` foram restringidas a contas `.openai`, impedindo aplicação indevida de limites Codex em contas `.gemini` ou `.claude`.
2. **Isolamento multi-projeto:** `VoiceMemoryStore.updateWorkspaceContext` separa `sessionTurns` por caminho de projeto em `scopedProjectHistories`, enquanto `workspaceSnapshotProvider` injeta sempre o contexto vivo de `Workspace` em cada turno do OpenJarvis.
3. **Resgate de chamadas JSON em `delta.content`:** em `streaming_turn.py`, `_extract_text_tool_calls` retém prefixos `{` ou `<tool_call>` antes de enviar tokens ao cliente Swift, evitando síntese de JSON em voz alta e executando a ferramenta real quando modelos menores (`Qwen3-1.7B`) emitem tool calls como texto.
4. **Honestidade operacional:** quando um CLI não está instalado (ex.: `claude` ausente no macOS de validação), `execute_agent_task` e `list_available_agents` reportam explicitamente a indisponibilidade.

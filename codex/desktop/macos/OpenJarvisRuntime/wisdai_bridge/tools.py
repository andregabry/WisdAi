"""Twelve real OpenJarvis BaseTool contracts bridged to WisdAI's Task Orchestrator."""

from __future__ import annotations

import json
import logging
from typing import Any, Dict, List

from openjarvis.core.registry import ToolRegistry
from openjarvis.core.types import ToolResult
from openjarvis.tools._stubs import BaseTool, ToolSpec

from wisdai_bridge.host_client import WisdAIHostClient

logger = logging.getLogger(__name__)


class _WisdAIHostTool(BaseTool):
    """Base adapter forwarding tool invocations to the authenticated WisdAI host."""

    is_local = True

    def __init__(
        self,
        host_client: WisdAIHostClient,
        tool_name: str,
        description: str,
        parameters: Dict[str, Any],
        *,
        category: str = "wisdai_workspace",
        requires_confirmation: bool = False,
        timeout_seconds: float = 20.0,
    ) -> None:
        self._host = host_client
        self.tool_id = tool_name
        self._spec = ToolSpec(
            name=tool_name,
            description=description,
            parameters=parameters,
            category=category,
            requires_confirmation=requires_confirmation,
            timeout_seconds=timeout_seconds,
        )

    @property
    def spec(self) -> ToolSpec:
        return self._spec

    def execute(self, **params: Any) -> ToolResult:
        res = self._host.call_tool(self.tool_id, params)
        ok = bool(res.get("ok", True)) if "ok" in res else ("error" not in res)
        content = json.dumps(res, ensure_ascii=False)
        return ToolResult(
            tool_name=self.tool_id,
            content=content,
            success=ok,
            metadata={"source": "wisdai_host"},
        )


def _tool_specs() -> List[Dict[str, Any]]:
    return [
        {
            "name": "list_projects",
            "description": "List all configured projects registered in WisdAI (id, name, path, active flag).",
            "parameters": {"type": "object", "properties": {}, "required": []},
        },
        {
            "name": "get_active_project",
            "description": "Return the currently active project selected in WisdAI (id, name, path, git branch, active conversation).",
            "parameters": {"type": "object", "properties": {}, "required": []},
        },
        {
            "name": "get_project_context",
            "description": "Inspect real project context in WisdAI (directory validation, git status/branch, config highlights) for the active or specified project.",
            "parameters": {
                "type": "object",
                "properties": {
                    "project": {
                        "type": "string",
                        "description": "Optional project name, id, or directory path. Defaults to the active project.",
                    }
                },
                "required": [],
            },
        },
        {
            "name": "list_available_agents",
            "description": "List coding agents/backends configured in WisdAI (Codex, Gemini Antigravity, Claude Code), active account, selected model, effort, and CLI installation/authentication status.",
            "parameters": {"type": "object", "properties": {}, "required": []},
        },
        {
            "name": "execute_agent_task",
            "description": "Execute a real autonomous software engineering task (audit, code analysis, implementation, refactor, debugging, tests) inside WisdAI using the unified execution pipeline.",
            "parameters": {
                "type": "object",
                "properties": {
                    "instruction": {
                        "type": "string",
                        "description": "Clear engineering task instruction to execute in the workspace.",
                    },
                    "project": {
                        "type": "string",
                        "description": "Optional target project name, id, or path. Defaults to the currently active project.",
                    },
                    "agent": {
                        "type": "string",
                        "description": "Optional agent identifier: antigravity, codex, claude_code, or auto.",
                    },
                    "model": {
                        "type": "string",
                        "description": "Optional model identifier override if requested by the user.",
                    },
                    "effort": {
                        "type": "string",
                        "description": "Optional reasoning effort (minimal, low, medium, high, ultra).",
                    },
                    "read_only": {
                        "type": "boolean",
                        "description": "True if task should run strictly read-only (audit/inspection).",
                    },
                },
                "required": ["instruction"],
            },
            "timeout_seconds": 30.0,
        },
        {
            "name": "get_task_status",
            "description": "Get live execution status, current phase, active agent/model/project, and recent files/commands for an active or recent WisdAI task.",
            "parameters": {
                "type": "object",
                "properties": {
                    "task_id": {
                        "type": "string",
                        "description": "Optional task or conversation id. Defaults to the active task.",
                    }
                },
                "required": [],
            },
        },
        {
            "name": "get_task_events",
            "description": "Read recent chronological ExecutionEventBus events (files read, commands run, tests executed, warnings, errors) for an active or completed task.",
            "parameters": {
                "type": "object",
                "properties": {
                    "task_id": {
                        "type": "string",
                        "description": "Optional task or conversation id.",
                    },
                    "limit": {
                        "type": "integer",
                        "description": "Maximum number of recent events to return (default 15).",
                    },
                },
                "required": [],
            },
        },
        {
            "name": "send_task_instruction",
            "description": "Send a follow-up instruction or course correction to a running or active WisdAI agent conversation.",
            "parameters": {
                "type": "object",
                "properties": {
                    "instruction": {
                        "type": "string",
                        "description": "Follow-up instruction for the agent.",
                    },
                    "task_id": {
                        "type": "string",
                        "description": "Optional target task or conversation id.",
                    },
                },
                "required": ["instruction"],
            },
        },
        {
            "name": "cancel_task",
            "description": "Explicitly cancel/abort the running coding agent task in WisdAI when the user explicitly requests cancelling or stopping execution (NOT for audio-only speech interruption).",
            "parameters": {
                "type": "object",
                "properties": {
                    "task_id": {
                        "type": "string",
                        "description": "Optional target task or conversation id.",
                    }
                },
                "required": [],
            },
        },
        {
            "name": "get_task_result",
            "description": "Get the final grounded output, files analyzed/modified, commands/tests summary, and errors from a completed or running task.",
            "parameters": {
                "type": "object",
                "properties": {
                    "task_id": {
                        "type": "string",
                        "description": "Optional target task or conversation id.",
                    }
                },
                "required": [],
            },
        },
        {
            "name": "list_running_tasks",
            "description": "List all currently running or queued WisdAI coding tasks across projects and conversations.",
            "parameters": {"type": "object", "properties": {}, "required": []},
        },
        {
            "name": "request_task_approval",
            "description": "Inspect or submit an approval decision for a pending permission/approval prompt blocking a WisdAI task.",
            "parameters": {
                "type": "object",
                "properties": {
                    "task_id": {
                        "type": "string",
                        "description": "Optional target task or conversation id.",
                    },
                    "decision": {
                        "type": "string",
                        "description": "Decision action: status, approve, deny, or cancel.",
                    },
                    "reason": {
                        "type": "string",
                        "description": "Optional note explaining the decision.",
                    },
                },
                "required": [],
            },
        },
    ]


def build_wisdai_tools(host_client: WisdAIHostClient) -> List[BaseTool]:
    """Instantiate all 12 WisdAI tools and register them in OpenJarvis ToolRegistry."""
    tools: List[BaseTool] = []
    for spec_def in _tool_specs():
        tool = _WisdAIHostTool(
            host_client,
            spec_def["name"],
            spec_def["description"],
            spec_def["parameters"],
            timeout_seconds=float(spec_def.get("timeout_seconds", 20.0)),
        )
        ToolRegistry.register_value(spec_def["name"], type(tool))
        tools.append(tool)
    return tools

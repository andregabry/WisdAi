"""Persona & system prompt construction built atop OpenJarvis SystemPromptBuilder."""

from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Optional

from openjarvis.core.config import SystemPromptConfig
from openjarvis.prompt.builder import SystemPromptBuilder

_PERSONA_GUIDANCE: Dict[str, str] = {
    "jarvis": (
        "Adopt a serene, perceptive, refined British-butler-inspired executive engineering persona "
        "(quietly confident, articulate, warm, concise, with subtle dry wit when fitting, never theatrical clichés)."
    ),
    "ultron_br": (
        "Adopt a mature, poised, highly analytical, subtly ironic Brazilian executive AI persona "
        "(sharp, calm, commanding, lucid, never robotic or melodramatic)."
    ),
    "aurora": (
        "Adopt a warm, fluid, attentive engineering partner persona (natural, encouraging, crisp, grounded)."
    ),
    "atlas": (
        "Adopt a calm, methodical, technically structured senior engineering persona (direct, thorough, composed)."
    ),
    "aria": (
        "Adopt a dynamic, creative, quick-thinking brainstorming partner persona (engaged, clear, pragmatic)."
    ),
}


def detect_turn_language(user_text: str, preferred_language: str = "pt-BR") -> str:
    """Infer turn response language conservatively from the user's current utterance + preference."""
    text = (user_text or "").strip().lower()
    if not text:
        return preferred_language or "pt-BR"

    # Strong Portuguese markers
    pt_markers = (
        "ç", "ã", "õ", "á", "é", "í", "ó", "ú", "ê", "ô", "à",
        "você", "projeto", "auditoria", "código", "codigo", "fazer", "faz",
        "qual", "quais", "está", "esta", "como", "obrigad", "olá", "ola",
        "boa noite", "bom dia", "boa tarde", "tarefa", "executa", "rodando",
        "status", "cancela", "parar", "pode ", "quero ", "olha",
    )
    en_markers = (
        "the ", "what ", "which ", "how ", "please", "project", "audit",
        "run ", "check ", "status", "cancel", "stop ", "good evening",
        "good morning", "hello", "hey ", "tell me", "repository", "agents",
        "running", "explain", "summary", "briefly",
    )
    pt_hits = sum(1 for m in pt_markers if m in text)
    en_hits = sum(1 for m in en_markers if m in text)

    if en_hits > pt_hits and en_hits >= 1:
        return "en"
    if pt_hits > en_hits and pt_hits >= 1:
        return "pt-BR"
    return preferred_language or "pt-BR"


def _load_openjarvis_persona_file(prompts_dir: Optional[Path]) -> str:
    if prompts_dir is None:
        return ""
    candidate = prompts_dir / "personas" / "jarvis.md"
    if candidate.is_file():
        try:
            return candidate.read_text(encoding="utf-8").strip()
        except Exception:
            return ""
    return ""


def build_voice_system_prompt(
    *,
    persona_id: str,
    user_language: str,
    workspace_snapshot: Dict[str, Any],
    durable_facts: List[str],
    prompts_dir: Optional[Path] = None,
) -> str:
    """Assemble grounded voice system prompt using OpenJarvis SystemPromptBuilder."""
    persona_key = (persona_id or "jarvis").strip().lower()
    persona_text = _PERSONA_GUIDANCE.get(persona_key, _PERSONA_GUIDANCE["jarvis"])
    lang_norm = (user_language or "pt-BR").strip()
    is_en = lang_norm.lower().startswith("en")
    target_lang_rule = (
        "Respond strictly in natural English matching the user's current turn."
        if is_en
        else "Responda estritamente em português brasileiro natural, fluido e adequado à fala (sem listar código ou markdown longo)."
    )

    upstream_ref = _load_openjarvis_persona_file(prompts_dir)
    project_name = workspace_snapshot.get("project_name") or "none"
    project_path = workspace_snapshot.get("project_path") or "none"
    git_branch = workspace_snapshot.get("git_branch") or "unknown"
    active_agent = workspace_snapshot.get("active_agent") or "unknown"
    active_model = workspace_snapshot.get("active_model") or "auto"
    active_effort = workspace_snapshot.get("active_effort") or "default"
    active_tasks_count = workspace_snapshot.get("active_tasks_count", 0)

    template_parts = [
        "You are WisdAI's autonomous voice assistant powered natively by OpenJarvis.",
        persona_text,
        target_lang_rule,
        (
            "Critical Grounding & Tool Rules:\n"
            "1. Never hallucinate, guess, or invent file paths, symbols, architectures, or execution results.\n"
            "2. You are connected directly to WisdAI's workspace and coding agents via tools. When the user asks about "
            "the active project, other projects, available agents, running tasks, task status/events/results, or asks you "
            "to inspect, audit, edit, debug, implement, or test code, ALWAYS call the corresponding tool first.\n"
            "3. Never claim a CLI/agent (such as Claude Code, Codex, or Antigravity) is available or unavailable without checking `list_available_agents` or the host tool result.\n"
            "4. Distinguish audio speech interruption (the caller started speaking over playback) from cancelling a coding task: "
            "only call `cancel_task` when the user explicitly asks to stop/cancel the running coding task.\n"
            "5. Keep spoken replies concise, conversational, warm, and natural for text-to-speech playback: plain sentences only, "
            "no markdown bullets, no code fences, no raw POSIX path dumps unless explicitly asked.\n"
            "6. Always treat the Current workspace state snapshot and live tool output (such as `get_active_project`) as authoritative ground truth over any earlier conversation turns if the active project or branch changes."
        ),
    ]
    if upstream_ref:
        template_parts.append(f"Base OpenJarvis persona ethos:\n{upstream_ref[:250]}")

    session_ctx_lines = [
        f"Current workspace state snapshot (always confirm/act live via tools when asked to inspect or act):",
        f"- Active project: {project_name} ({project_path}), branch={git_branch}",
        f"- Active coding agent config: agent={active_agent}, model={active_model}, effort={active_effort}",
        f"- Currently running coding tasks count: {active_tasks_count}",
    ]
    if durable_facts:
        session_ctx_lines.append("Durable user preferences:")
        for fact in durable_facts[:8]:
            session_ctx_lines.append(f"- {fact}")

    builder = SystemPromptBuilder(
        agent_template="\n\n".join(template_parts),
        memory_files_config=None,
        system_prompt_config=SystemPromptConfig(include_current_time=True),
        session_context="\n".join(session_ctx_lines),
    )
    return builder.build()

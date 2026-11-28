"""Real-time token/sentence streaming conversational loop over OpenJarvis primitives."""

from __future__ import annotations

import asyncio
import json
import logging
import re
import time
import uuid
from typing import Any, AsyncIterator, Callable, Dict, List, Optional

from openjarvis.core.events import EventBus, EventType
from openjarvis.core.types import Message, Role, ToolCall
from openjarvis.tools._stubs import ToolExecutor

logger = logging.getLogger(__name__)

_SENTENCE_SPLIT_RX = re.compile(r"(?<=[.!?…])\s+")


def _sse_line(event_name: str, data: Dict[str, Any]) -> str:
    return f"event: {event_name}\ndata: {json.dumps(data, ensure_ascii=False)}\n\n"


def _merge_tool_call_deltas(
    buffers: Dict[int, Dict[str, str]],
    deltas: List[Dict[str, Any]],
) -> None:
    for item in deltas:
        idx = int(item.get("index", 0) or 0)
        slot = buffers.setdefault(idx, {"id": "", "name": "", "arguments": ""})
        if item.get("id"):
            slot["id"] = str(item["id"])
        fn = item.get("function") or {}
        if fn.get("name"):
            slot["name"] += str(fn["name"])
        if fn.get("arguments"):
            slot["arguments"] += str(fn["arguments"])


class _ThinkTagFilter:
    """Incrementally strips `<think>...</think>` blocks from streamed tokens."""

    def __init__(self) -> None:
        self._buf = ""
        self._in_think = False

    def feed(self, delta: str) -> str:
        self._buf += delta
        out: List[str] = []
        while self._buf:
            if self._in_think:
                end_idx = self._buf.find("</think>")
                if end_idx == -1:
                    if len(self._buf) > 16:
                        self._buf = self._buf[-8:]
                    break
                self._buf = self._buf[end_idx + len("</think>") :]
                self._in_think = False
            else:
                start_idx = self._buf.find("<think>")
                if start_idx == -1:
                    safe_len = max(0, len(self._buf) - 7)
                    if safe_len > 0:
                        out.append(self._buf[:safe_len])
                        self._buf = self._buf[safe_len:]
                    break
                if start_idx > 0:
                    out.append(self._buf[:start_idx])
                self._buf = self._buf[start_idx + len("<think>") :]
                self._in_think = True
        return "".join(out)

    def flush(self) -> str:
        if self._in_think:
            self._buf = ""
            return ""
        rem = self._buf
        self._buf = ""
        return rem.replace("<think>", "").replace("</think>", "")


class _SentenceAccumulator:
    """Accumulates streamed plain text into speakable sentence chunks."""

    def __init__(self, min_chars: int = 24) -> None:
        self._buf = ""
        self._min_chars = min_chars

    def push(self, piece: str) -> List[str]:
        if not piece:
            return []
        self._buf += piece
        emitted: List[str] = []
        while True:
            match = _SENTENCE_SPLIT_RX.search(self._buf)
            if not match:
                break
            candidate = self._buf[: match.start()].strip()
            rest = self._buf[match.end() :]
            if len(candidate) < self._min_chars and rest:
                # Merge short sentence fragment with next phrase unless nothing follows
                second = _SENTENCE_SPLIT_RX.search(rest)
                if second:
                    combined = (candidate + " " + rest[: second.start()].strip()).strip()
                    self._buf = rest[second.end() :]
                    if combined:
                        emitted.append(combined)
                    continue
                break
            if candidate:
                emitted.append(candidate)
            self._buf = rest
        return emitted

    def flush(self) -> str:
        rem = self._buf.strip()
        self._buf = ""
        return rem


class TurnCancellationRegistry:
    """Tracks active voice turn cancellation events for instant barge-in."""

    def __init__(self) -> None:
        self._events: Dict[str, asyncio.Event] = {}

    def register(self, turn_id: str) -> asyncio.Event:
        ev = asyncio.Event()
        self._events[turn_id] = ev
        return ev

    def cancel(self, turn_id: Optional[str] = None) -> int:
        cancelled = 0
        if turn_id:
            ev = self._events.get(turn_id)
            if ev is not None and not ev.is_set():
                ev.set()
                cancelled += 1
            return cancelled
        for ev in self._events.values():
            if not ev.is_set():
                ev.set()
                cancelled += 1
        return cancelled

    def unregister(self, turn_id: str) -> None:
        self._events.pop(turn_id, None)


def _extract_text_tool_calls(raw_text: str, valid_names: set[str]) -> List[ToolCall]:
    """Rescue bare JSON or `<tool_call>` blocks emitted in `delta.content` by small local models."""
    text = (raw_text or "").strip()
    if not text or not valid_names:
        return []
    candidates: List[str] = []
    for m in re.finditer(r"<tool_call>\s*(\{.*?\})\s*</tool_call>", text, flags=re.DOTALL):
        candidates.append(m.group(1))
    if not candidates and text.startswith("{") and text.endswith("}"):
        candidates.append(text)
    calls: List[ToolCall] = []
    for raw_json in candidates:
        try:
            obj = json.loads(raw_json)
        except Exception:
            continue
        if not isinstance(obj, dict):
            continue
        name = str(obj.get("name") or "").strip()
        if name not in valid_names:
            continue
        args = obj.get("arguments", {})
        args_str = args if isinstance(args, str) else json.dumps(args or {}, ensure_ascii=False)
        calls.append(ToolCall(id=f"call_{uuid.uuid4().hex[:8]}", name=name, arguments=args_str))
    return calls


async def stream_openjarvis_voice_turn(
    *,
    turn_id: str,
    engine: Any,
    model: str,
    system_prompt: str,
    history: List[Dict[str, str]],
    user_text: str,
    language: str,
    executor: ToolExecutor,
    bus: EventBus,
    cancel_event: asyncio.Event,
    memory_service: Any = None,
    max_turns: int = 5,
    temperature: float = 0.65,
    max_tokens: int = 640,
    before_tool_call: Optional[Callable[[str, dict[str, Any]], bool]] = None,
) -> AsyncIterator[str]:
    """Run an OpenJarvis multi-turn tool-capable conversational loop emitting incremental SSE events."""
    t_start = time.perf_counter()
    messages: List[Message] = [Message(role=Role.SYSTEM, content=system_prompt)]
    for item in history[-12:]:
        role_str = (item.get("role") or "user").strip().lower()
        content_str = (item.get("content") or "").strip()
        if not content_str:
            continue
        role = Role.ASSISTANT if role_str == "assistant" else Role.USER
        messages.append(Message(role=role, content=content_str))
    messages.append(Message(role=Role.USER, content=user_text))

    openai_tools = executor.get_openai_tools()
    valid_tool_names = {
        str(t.get("function", {}).get("name") or "")
        for t in openai_tools
        if isinstance(t, dict) and isinstance(t.get("function"), dict)
    }
    valid_tool_names.discard("")
    tool_events_summary: List[Dict[str, Any]] = []
    sent_idx = 0
    full_answer_parts: List[str] = []

    bus.publish(
        EventType.AGENT_TURN_START,
        {"agent_id": "openjarvis_voice", "turn_id": turn_id},
    )
    yield _sse_line("start", {"turn_id": turn_id, "language": language})

    try:
        for _step in range(max_turns):
            if cancel_event.is_set():
                yield _sse_line("cancelled", {"turn_id": turn_id, "reason": "barge_in"})
                return

            think_filter = _ThinkTagFilter()
            sentence_acc = _SentenceAccumulator()
            tool_call_buffers: Dict[int, Dict[str, str]] = {}
            step_raw_text: List[str] = []
            hold_prefix_buffer: Optional[str] = ""

            stream_kwargs: Dict[str, Any] = {}
            if openai_tools:
                stream_kwargs["tools"] = openai_tools

            async for chunk in engine.stream_full(
                messages,
                model=model,
                temperature=temperature,
                max_tokens=max_tokens,
                **stream_kwargs,
            ):
                if cancel_event.is_set():
                    yield _sse_line("cancelled", {"turn_id": turn_id, "reason": "barge_in"})
                    return

                if chunk.tool_calls:
                    _merge_tool_call_deltas(tool_call_buffers, chunk.tool_calls)

                if chunk.content and not tool_call_buffers:
                    clean_delta = think_filter.feed(chunk.content)
                    if clean_delta:
                        if hold_prefix_buffer is not None:
                            hold_prefix_buffer += clean_delta
                            stripped = hold_prefix_buffer.lstrip()
                            if not stripped:
                                continue
                            looks_like_tool_prefix = (
                                stripped.startswith("{")
                                or stripped.startswith("<tool_call")
                                or (stripped.startswith("<") and "<tool_call>".startswith(stripped[:11]))
                            )
                            if looks_like_tool_prefix and len(stripped) <= 600:
                                continue
                            flushed_prefix = hold_prefix_buffer
                            hold_prefix_buffer = None
                            step_raw_text.append(flushed_prefix)
                            full_answer_parts.append(flushed_prefix)
                            yield _sse_line("delta", {"text": flushed_prefix})
                            for sentence in sentence_acc.push(flushed_prefix):
                                yield _sse_line(
                                    "sentence",
                                    {"index": sent_idx, "text": sentence},
                                )
                                sent_idx += 1
                        else:
                            step_raw_text.append(clean_delta)
                            full_answer_parts.append(clean_delta)
                            yield _sse_line("delta", {"text": clean_delta})
                            for sentence in sentence_acc.push(clean_delta):
                                yield _sse_line(
                                    "sentence",
                                    {"index": sent_idx, "text": sentence},
                                )
                                sent_idx += 1

            # Check for raw JSON / <tool_call> fallback when delta.tool_calls wasn't populated
            fallback_calls: List[ToolCall] = []
            if not tool_call_buffers:
                tail_delta = think_filter.flush()
                if hold_prefix_buffer is not None:
                    combined_held = hold_prefix_buffer + tail_delta
                    fallback_calls = _extract_text_tool_calls(combined_held, valid_tool_names)
                    if not fallback_calls:
                        tail_delta = combined_held
                        hold_prefix_buffer = None
                if not fallback_calls:
                    if tail_delta:
                        step_raw_text.append(tail_delta)
                        full_answer_parts.append(tail_delta)
                        yield _sse_line("delta", {"text": tail_delta})
                        for sentence in sentence_acc.push(tail_delta):
                            yield _sse_line(
                                "sentence", {"index": sent_idx, "text": sentence}
                            )
                            sent_idx += 1
                    last_sentence = sentence_acc.flush()
                    if last_sentence:
                        yield _sse_line(
                            "sentence", {"index": sent_idx, "text": last_sentence}
                        )
                        sent_idx += 1

                    final_text = "".join(full_answer_parts).strip()
                    elapsed_ms = (time.perf_counter() - t_start) * 1000.0
                    if memory_service is not None and final_text:
                        memory_service.submit(user_text, final_text)
                    bus.publish(
                        EventType.AGENT_TURN_END,
                        {
                            "agent_id": "openjarvis_voice",
                            "turn_id": turn_id,
                            "elapsed_ms": round(elapsed_ms, 1),
                        },
                    )
                    yield _sse_line(
                        "done",
                        {
                            "turn_id": turn_id,
                            "language": language,
                            "full_text": final_text,
                            "tool_calls": tool_events_summary,
                            "latency_ms": round(elapsed_ms, 1),
                            "cancelled": False,
                        },
                    )
                    return

            # Tool calls accumulated (structured or rescued JSON) -> execute on worker thread
            parsed_calls: List[ToolCall] = list(fallback_calls)
            for idx in sorted(tool_call_buffers.keys()):
                slot = tool_call_buffers[idx]
                parsed_calls.append(
                    ToolCall(
                        id=slot["id"] or f"call_{uuid.uuid4().hex[:8]}",
                        name=slot["name"],
                        arguments=slot["arguments"] or "{}",
                    )
                )

            messages.append(
                Message(
                    role=Role.ASSISTANT,
                    content="".join(step_raw_text),
                    tool_calls=parsed_calls,
                )
            )

            for tc in parsed_calls:
                if cancel_event.is_set():
                    yield _sse_line("cancelled", {"turn_id": turn_id, "reason": "barge_in"})
                    return
                try:
                    args_dict = json.loads(tc.arguments) if tc.arguments else {}
                except Exception:
                    args_dict = {}

                if before_tool_call is not None and before_tool_call(tc.name, args_dict) is not True:
                    res_content = json.dumps({"ok": False, "error": "Tool denied by governance"})
                    res_ok = False
                else:
                    yield _sse_line(
                        "tool_start",
                        {"tool": tc.name, "arguments": args_dict},
                    )
                    tool_result = await asyncio.to_thread(executor.execute, tc)
                    res_content = tool_result.content
                    res_ok = tool_result.success

                summary_entry = {
                    "tool": tc.name,
                    "success": res_ok,
                    "output_preview": res_content[:240],
                }
                tool_events_summary.append(summary_entry)
                yield _sse_line("tool_result", summary_entry)

                messages.append(
                    Message(
                        role=Role.TOOL,
                        content=res_content,
                        tool_call_id=tc.id,
                        name=tc.name,
                    )
                )

        # Max tool turns reached -> emit concise graceful wrap-up
        fallback = (
            "Concluí a verificação pelas ferramentas e atualizei os dados."
            if not language.lower().startswith("en")
            else "I have finished querying the workspace tools."
        )
        yield _sse_line("sentence", {"index": sent_idx, "text": fallback})
        yield _sse_line(
            "done",
            {
                "turn_id": turn_id,
                "language": language,
                "full_text": fallback,
                "tool_calls": tool_events_summary,
                "latency_ms": round((time.perf_counter() - t_start) * 1000.0, 1),
                "cancelled": False,
            },
        )
    except asyncio.CancelledError:
        yield _sse_line("cancelled", {"turn_id": turn_id, "reason": "client_disconnect"})
    except Exception as exc:
        logger.exception("Voice streaming turn error: %s", exc)
        yield _sse_line("error", {"turn_id": turn_id, "message": str(exc)})

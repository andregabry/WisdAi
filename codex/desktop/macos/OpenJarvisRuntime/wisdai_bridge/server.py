"""Managed OpenJarvis FastAPI + UDS runtime server entrypoint for WisdAI."""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import os
import signal
import sys
import tempfile
import uuid
from pathlib import Path
from typing import Any, Dict, List, Optional

import psutil
import uvicorn
from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import Response, StreamingResponse
from pydantic import BaseModel, Field

from openjarvis.agents.orchestrator import OrchestratorAgent
from openjarvis.core.events import EventBus
from openjarvis.core.types import Message, Role
from openjarvis.engine.openai_compat_engines import LlamaCppEngine, OpenAICompatEngine
from openjarvis.server.app import create_app
from openjarvis.speech.faster_whisper import FasterWhisperBackend
from openjarvis.tools._stubs import ToolExecutor

from wisdai_bridge.host_client import WisdAIHostClient
from wisdai_bridge.memory_guard import create_scoped_memory_service
from wisdai_bridge.persona import build_voice_system_prompt, detect_turn_language
from wisdai_bridge.streaming_turn import (
    TurnCancellationRegistry,
    stream_openjarvis_voice_turn,
)
from wisdai_bridge.tools import build_wisdai_tools
from wisdai_bridge.tts_sherpa import SherpaOnnxCleanTTSBackend

logger = logging.getLogger("wisdai.openjarvis")


class VoiceStreamRequest(BaseModel):
    turn_id: Optional[str] = None
    user_text: str
    history: List[Dict[str, str]] = Field(default_factory=list)
    persona_id: str = "jarvis"
    preferred_language: str = "pt-BR"
    model: Optional[str] = None
    temperature: float = 0.65
    max_tokens: int = 640
    workspace_snapshot: Optional[Dict[str, Any]] = None


class CancelRequest(BaseModel):
    turn_id: Optional[str] = None


class TranscribeRequest(BaseModel):
    audio_base64: str
    language: Optional[str] = None
    hotwords: List[str] = Field(default_factory=list)


class SynthesizeRequest(BaseModel):
    text: str
    voice_id: str = "supertonic:m4"
    speed: float = 1.0
    language: str = "pt-BR"


class EngineReconfigureRequest(BaseModel):
    engine_kind: str = "llamacpp"
    host: str
    model: str
    api_key: Optional[str] = None


class WarmupRequest(BaseModel):
    warmup_stt: bool = True
    warmup_tts: bool = False


def _make_engine(kind: str, host: str, api_key: Optional[str] = None):
    k = (kind or "llamacpp").strip().lower()
    if k == "llamacpp":
        return LlamaCppEngine(host=host, api_key=api_key, timeout=180.0)
    return OpenAICompatEngine(host=host, api_key=api_key, timeout=180.0)


def create_wisdai_openjarvis_app(
    *,
    llm_kind: str,
    llm_host: str,
    model: str,
    api_token: str,
    host_uds: str,
    host_token: str,
    memory_path: Path,
    prompts_dir: Optional[Path] = None,
    llm_api_key: Optional[str] = None,
):
    bus = EventBus(record_history=False)
    engine = _make_engine(llm_kind, llm_host, llm_api_key)
    host_client = WisdAIHostClient(socket_path=host_uds, token=host_token)
    tools = build_wisdai_tools(host_client)
    executor = ToolExecutor(tools, bus=bus, default_timeout=25.0)
    _, memory_service = create_scoped_memory_service(
        str(memory_path), engine=engine, model=model, bus=bus
    )
    memory_service.start()

    stt_backend = FasterWhisperBackend(model_size="base", device="cpu", compute_type="int8")
    tts_backend = SherpaOnnxCleanTTSBackend()

    initial_prompt = build_voice_system_prompt(
        persona_id="jarvis",
        user_language="pt-BR",
        workspace_snapshot={},
        durable_facts=[],
        prompts_dir=prompts_dir,
    )
    agent = OrchestratorAgent(
        engine=engine,
        model=model,
        tools=tools,
        bus=bus,
        mode="function_calling",
        system_prompt=initial_prompt,
        max_turns=5,
    )

    app = create_app(
        engine=engine,
        model=model,
        agent=agent,
        bus=bus,
        memory_service=memory_service,
        speech_backend=stt_backend,
        api_key=api_token,
    )

    app.state.wisdai_host_client = host_client
    app.state.wisdai_tools = tools
    app.state.wisdai_executor = executor
    app.state.wisdai_tts = tts_backend
    app.state.wisdai_stt = stt_backend
    app.state.wisdai_prompts_dir = prompts_dir
    app.state.wisdai_cancel_registry = TurnCancellationRegistry()
    app.state.wisdai_current_model = model
    app.state.wisdai_llm_kind = llm_kind
    app.state.wisdai_llm_host = llm_host

    wisdai_router = APIRouter(prefix="/v1/wisdai", tags=["wisdai"])

    def _require_auth(request: Request) -> None:
        if not api_token:
            return
        auth = request.headers.get("authorization", "")
        if auth != f"Bearer {api_token}":
            raise HTTPException(status_code=401, detail="Unauthorized")

    @wisdai_router.get("/health")
    async def wisdai_health(request: Request):
        _require_auth(request)
        proc = psutil.Process()
        mem_rss_mb = round(proc.memory_info().rss / (1024 * 1024), 1)
        llm_ok = await asyncio.to_thread(app.state.engine.health)
        return {
            "status": "ok",
            "runtime": "openjarvis",
            "model": app.state.wisdai_current_model,
            "llm_kind": app.state.wisdai_llm_kind,
            "llm_host": app.state.wisdai_llm_host,
            "llm_healthy": llm_ok,
            "tools_count": len(app.state.wisdai_tools),
            "tools": [t.spec.name for t in app.state.wisdai_tools],
            "memory_facts_count": len(
                [f for f in app.state.memory_service.list_facts() if f.trusted_for_recall]
            ),
            "tts_clean_healthy": app.state.wisdai_tts.health(),
            "tts_voices": app.state.wisdai_tts.available_voices(),
            "stt_backend": "faster-whisper",
            "stt_loaded": getattr(app.state.wisdai_stt, "_model", None) is not None,
            "rss_mb": mem_rss_mb,
            "pid": proc.pid,
        }

    @wisdai_router.post("/context")
    async def update_context(snapshot: Dict[str, Any], request: Request):
        _require_auth(request)
        app.state.wisdai_host_client.update_cached_snapshot(snapshot)
        return {"ok": True}

    @wisdai_router.post("/engine/reconfigure")
    async def reconfigure_engine(req: EngineReconfigureRequest, request: Request):
        _require_auth(request)
        new_engine = _make_engine(req.engine_kind, req.host, req.api_key)
        app.state.engine = new_engine
        app.state.model = req.model
        app.state.wisdai_current_model = req.model
        app.state.wisdai_llm_kind = req.engine_kind
        app.state.wisdai_llm_host = req.host
        if getattr(app.state, "agent", None) is not None:
            app.state.agent._engine = new_engine
            app.state.agent._model = req.model
        if getattr(app.state.memory_service, "_extractor", None) is not None:
            app.state.memory_service._extractor._engine = new_engine
            app.state.memory_service._extractor._model = req.model
        return {"ok": True, "model": req.model, "llm_kind": req.engine_kind}

    @wisdai_router.post("/warmup")
    async def warmup(req: WarmupRequest, request: Request):
        _require_auth(request)
        if req.warmup_stt:
            await asyncio.to_thread(app.state.wisdai_stt._ensure_model)
        return {"ok": True, "stt_loaded": getattr(app.state.wisdai_stt, "_model", None) is not None}

    @wisdai_router.post("/voice/stream")
    async def voice_stream(req: VoiceStreamRequest, request: Request):
        _require_auth(request)
        turn_id = req.turn_id or f"turn-{uuid.uuid4().hex[:10]}"
        snapshot = req.workspace_snapshot or app.state.wisdai_host_client.cached_snapshot()
        lang = detect_turn_language(req.user_text, req.preferred_language)
        durable_facts = [
            f.text for f in app.state.memory_service.list_facts() if f.trusted_for_recall
        ]
        sys_prompt = build_voice_system_prompt(
            persona_id=req.persona_id,
            user_language=lang,
            workspace_snapshot=snapshot,
            durable_facts=durable_facts,
            prompts_dir=app.state.wisdai_prompts_dir,
        )
        registry: TurnCancellationRegistry = app.state.wisdai_cancel_registry
        cancel_ev = registry.register(turn_id)

        async def _gen():
            try:
                async for line in stream_openjarvis_voice_turn(
                    turn_id=turn_id,
                    engine=app.state.engine,
                    model=req.model or app.state.wisdai_current_model,
                    system_prompt=sys_prompt,
                    history=req.history,
                    user_text=req.user_text,
                    language=lang,
                    executor=app.state.wisdai_executor,
                    bus=app.state.bus,
                    cancel_event=cancel_ev,
                    memory_service=app.state.memory_service,
                    temperature=req.temperature,
                    max_tokens=req.max_tokens,
                ):
                    if await request.is_disconnected():
                        cancel_ev.set()
                        break
                    yield line
            finally:
                registry.unregister(turn_id)

        return StreamingResponse(_gen(), media_type="text/event-stream")

    @wisdai_router.post("/voice/cancel")
    async def voice_cancel(req: CancelRequest, request: Request):
        _require_auth(request)
        count = app.state.wisdai_cancel_registry.cancel(req.turn_id)
        return {"ok": True, "cancelled_turns": count}

    @wisdai_router.post("/transcribe")
    async def transcribe_audio(req: TranscribeRequest, request: Request):
        _require_auth(request)
        import base64

        raw = base64.b64decode(req.audio_base64)
        hotword_str = ", ".join(h for h in req.hotwords if h.strip()) if req.hotwords else None
        lang_code = req.language.split("-")[0].lower() if req.language else None
        result = await asyncio.to_thread(
            app.state.wisdai_stt.transcribe,
            raw,
            format="wav",
            language=lang_code,
            hotwords=hotword_str,
        )
        return {
            "text": (result.text or "").strip(),
            "language": result.language,
            "duration_seconds": result.duration_seconds,
        }

    @wisdai_router.post("/synthesize")
    async def synthesize_speech(req: SynthesizeRequest, request: Request):
        _require_auth(request)
        tts_res = await asyncio.to_thread(
            app.state.wisdai_tts.synthesize,
            req.text,
            voice_id=req.voice_id,
            speed=req.speed,
            language=req.language,
        )
        return Response(
            content=tts_res.audio,
            media_type="audio/wav",
            headers={
                "X-WisdAI-Voice-ID": tts_res.voice_id,
                "X-WisdAI-Sample-Rate": str(tts_res.sample_rate),
                "X-WisdAI-Duration": f"{tts_res.duration_seconds:.3f}",
            },
        )

    @wisdai_router.get("/memory/facts")
    async def get_facts(request: Request):
        _require_auth(request)
        facts = [
            {"text": f.text, "source": f.source, "created_at": f.created_at}
            for f in app.state.memory_service.list_facts()
            if f.trusted_for_recall
        ]
        return {"facts": facts}

    @wisdai_router.post("/memory/reset")
    async def reset_facts(request: Request):
        _require_auth(request)
        removed = app.state.memory_service._store.clear()
        return {"ok": True, "removed": removed}

    @app.on_event("shutdown")
    async def _on_shutdown():
        try:
            app.state.wisdai_host_client.close()
        except Exception:
            pass
        try:
            app.state.memory_service.stop(timeout=1.5)
        except Exception:
            pass

    app.include_router(wisdai_router)
    return app


def main() -> None:
    parser = argparse.ArgumentParser(description="WisdAI OpenJarvis Managed Runtime Server")
    parser.add_argument("--uds", required=True, help="Unix Domain Socket path to bind")
    parser.add_argument("--llm-kind", default="llamacpp")
    parser.add_argument("--llm-host", required=True)
    parser.add_argument("--model", default="Qwen3-1.7B-Q4_K_M.gguf")
    parser.add_argument("--api-token", required=True)
    parser.add_argument("--host-uds", default="")
    parser.add_argument("--host-token", default="")
    parser.add_argument("--memory-path", required=True)
    parser.add_argument("--prompts-dir", default="")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        stream=sys.stderr,
    )

    uds_file = Path(args.uds)
    uds_file.parent.mkdir(parents=True, exist_ok=True)
    if uds_file.exists():
        uds_file.unlink()

    prompts_dir = Path(args.prompts_dir) if args.prompts_dir else None
    app = create_wisdai_openjarvis_app(
        llm_kind=args.llm_kind,
        llm_host=args.llm_host,
        model=args.model,
        api_token=args.api_token,
        host_uds=args.host_uds,
        host_token=args.host_token,
        memory_path=Path(args.memory_path),
        prompts_dir=prompts_dir,
    )

    server = uvicorn.Server(
        uvicorn.Config(
            app,
            uds=str(uds_file),
            log_level="warning",
            timeout_graceful_shutdown=3.0,
        )
    )

    def _handle_sig(_signum, _frame):
        server.should_exit = True

    signal.signal(signal.SIGTERM, _handle_sig)
    signal.signal(signal.SIGINT, _handle_sig)

    try:
        server.run()
    finally:
        if uds_file.exists():
            try:
                uds_file.unlink()
            except OSError:
                pass


if __name__ == "__main__":
    main()

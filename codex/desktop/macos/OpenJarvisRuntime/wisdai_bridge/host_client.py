"""Authenticated Unix Domain Socket RPC client calling WisdAI's Swift Workspace host."""

from __future__ import annotations

import json
import logging
import os
import threading
from typing import Any, Dict, Optional

import httpx

logger = logging.getLogger(__name__)


class WisdAIHostClient:
    """Thread-safe synchronous & async client to WisdAI's Swift host tool callback UDS."""

    def __init__(
        self,
        socket_path: str | None = None,
        token: str | None = None,
        timeout: float = 15.0,
    ) -> None:
        self._socket_path = (
            socket_path or os.environ.get("WISDAI_HOST_UDS", "")
        ).strip()
        self._token = (
            token if token is not None else os.environ.get("WISDAI_HOST_TOKEN", "")
        ).strip()
        self._timeout = timeout
        self._lock = threading.Lock()
        self._local_snapshot: Dict[str, Any] = {}
        self._client: Optional[httpx.Client] = None

    def configure(
        self,
        *,
        socket_path: str | None = None,
        token: str | None = None,
    ) -> None:
        with self._lock:
            changed = False
            if socket_path is not None and socket_path.strip() != self._socket_path:
                self._socket_path = socket_path.strip()
                changed = True
            if token is not None and token.strip() != self._token:
                self._token = token.strip()
                changed = True
            if changed and self._client is not None:
                try:
                    self._client.close()
                except Exception:
                    pass
                self._client = None

    def update_cached_snapshot(self, snapshot: Dict[str, Any]) -> None:
        with self._lock:
            self._local_snapshot = dict(snapshot or {})

    def cached_snapshot(self) -> Dict[str, Any]:
        with self._lock:
            return dict(self._local_snapshot)

    def _get_client(self) -> Optional[httpx.Client]:
        with self._lock:
            if not self._socket_path or not os.path.exists(self._socket_path):
                return None
            if self._client is None:
                transport = httpx.HTTPTransport(uds=self._socket_path)
                headers = {"Content-Type": "application/json"}
                if self._token:
                    headers["Authorization"] = f"Bearer {self._token}"
                self._client = httpx.Client(
                    transport=transport,
                    base_url="http://wisdai-host.local",
                    headers=headers,
                    timeout=self._timeout,
                )
            return self._client

    def call_tool(self, tool_name: str, params: Dict[str, Any] | None = None) -> Dict[str, Any]:
        """Execute one tool contract against the active WisdAI Swift host."""
        client = self._get_client()
        if client is None:
            return {
                "ok": False,
                "error": "WisdAI host callback socket is not connected.",
                "tool": tool_name,
            }
        payload = {"tool": tool_name, "params": params or {}}
        try:
            resp = client.post("/v1/host/tool", json=payload)
            if not resp.is_success:
                return {
                    "ok": False,
                    "error": f"Host callback HTTP {resp.status_code}: {resp.text[:300]}",
                    "tool": tool_name,
                }
            data = resp.json()
            if isinstance(data, dict):
                return data
            return {"ok": True, "result": data}
        except Exception as exc:
            logger.warning("Host callback error for %s: %s", tool_name, exc)
            # Drop stale pooled connection so next turn reconnects cleanly
            with self._lock:
                if self._client is not None:
                    try:
                        self._client.close()
                    except Exception:
                        pass
                    self._client = None
            return {
                "ok": False,
                "error": f"Failed calling WisdAI host for tool '{tool_name}': {exc}",
                "tool": tool_name,
            }

    def close(self) -> None:
        with self._lock:
            if self._client is not None:
                try:
                    self._client.close()
                except Exception:
                    pass
                self._client = None

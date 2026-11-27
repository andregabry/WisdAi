#!/usr/bin/env python3
"""Exercise the packaged backend without inference or access to user history."""
import json
import os
from pathlib import Path
import queue
import subprocess
import sys
import tempfile
import threading

binary = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix="wisdai-thread-test-") as root:
    root = Path(root)
    project = root / "project"
    project.mkdir()
    subprocess.run(["git", "init", "-q", str(project)], check=True)
    codex_home = root / "codex-home"
    codex_home.mkdir(mode=0o700)
    env = dict(os.environ, CODEX_HOME=str(codex_home))
    # Never inherit an API key into this offline lifecycle test.
    for key in list(env):
        if key.endswith("API_KEY") or key in ("CODEX_AUTH_JSON", "OPENAI_ACCESS_TOKEN"):
            del env[key]
    with (root / "stderr.log").open("w") as stderr:
        proc = subprocess.Popen([str(binary), "-c", "features.code_mode=false", "app-server"], stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE, stderr=stderr, text=True, env=env, cwd=project)
        messages = queue.Queue()
        def read():
            for line in proc.stdout:
                try:
                    messages.put(json.loads(line))
                except ValueError:
                    pass
        threading.Thread(target=read, daemon=True).start()
        next_id = 0
        def call(method, params):
            global next_id
            next_id += 1
            request_id = next_id
            proc.stdin.write(json.dumps(dict(id=request_id, method=method, params=params)) + "\n")
            proc.stdin.flush()
            while True:
                reply = messages.get(timeout=30)
                if reply.get("id") == request_id:
                    assert "error" not in reply, (method, reply.get("error"))
                    return reply["result"]
        try:
            call("initialize", {"clientInfo": {"name": "wisdai-lifecycle-test", "version": "0.1"}, "capabilities": {"experimentalApi": True}})
            proc.stdin.write('{"method":"initialized"}\n')
            proc.stdin.flush()
            result = call("thread/start", {"cwd": str(project), "sandbox": "read-only", "approvalPolicy": "never"})
            thread_id = result["thread"]["id"]
            call("thread/name/set", {"threadId": thread_id, "name": "Disposable lifecycle fixture"})
            call("thread/read", {"threadId": thread_id, "includeTurns": True})
            call("thread/archive", {"threadId": thread_id})
            archived = call("thread/list", {"archived": True, "limit": 50})
            assert any(t["id"] == thread_id for t in archived["data"])
            call("thread/unarchive", {"threadId": thread_id})
            call("thread/unsubscribe", {"threadId": thread_id})
            call("thread/delete", {"threadId": thread_id})
            for is_archived in (False, True):
                result = call("thread/list", {"archived": is_archived, "limit": 50})
                assert all(t["id"] != thread_id for t in result["data"])
            print("PASS: create/read/rename/archive/unarchive/delete; deleted thread absent from both lists; no inference")
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()

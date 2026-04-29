#!/usr/bin/env python3
"""Local web UI for the PVOGame sprite pipeline.

Shows which sprites are already generated (with thumbnails), lets you inspect
each sprite's assembled prompt, and runs generation with the same flags as
the CLI (--force, --reprocess, --skip-generation, --seed, --delay, --timeout,
--max-retries). Live log is streamed via Server-Sent Events.

Usage:
    python3 sprites/web_ui.py              # opens on http://127.0.0.1:8765
    python3 sprites/web_ui.py --port 9000
"""

from __future__ import annotations

import argparse
import contextlib
import json
import queue
import sys
import threading
import time
import webbrowser
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

SCRIPT_DIR = Path(__file__).parent
sys.path.insert(0, str(SCRIPT_DIR))

from sprite_prompts import (  # noqa: E402
    API_KEY_CONFIG_FILE,
    build_prompt,
    ensure_api_key_config_file,
    make_client,
    postprocess,
    resolve_api_key,
)
from generate_sprites import (  # noqa: E402
    BY_NAME,
    CATEGORY_MAP,
    DEFAULT_OUT,
    SPRITES,
    category_of,
    generate_with_retry,
    load_log,
    missing_refs,
    processed_path,
    raw_path,
    resolve_refs,
    save_log,
)
from PIL import Image  # noqa: E402


# ---------------------------------------------------------------------------
# Job state
# ---------------------------------------------------------------------------

JOB_LOCK = threading.Lock()
JOB_STATE = {
    "status": "idle",            # idle | running | done | error
    "current_sprite": None,
    "started_at": None,
    "finished_at": None,
    "progress": {"done": 0, "failed": 0, "skipped": 0, "total": 0},
    "cancel_requested": False,
}
LOG_BUFFER: list[str] = []              # full session log (for late subscribers)
LOG_SUBSCRIBERS: list[queue.Queue] = []  # live SSE queues

OUT_DIR = DEFAULT_OUT


def log(msg: str) -> None:
    line = f"[{datetime.now().strftime('%H:%M:%S')}] {msg}"
    # Write to the real stdout, bypassing any active contextlib.redirect_stdout
    # (e.g. _LogRedirectStream during generate_with_retry). Using print() here
    # would route back through the redirect and recurse into log() forever.
    sys.__stdout__.write(line + "\n")
    sys.__stdout__.flush()
    with JOB_LOCK:
        LOG_BUFFER.append(line)
        dead = []
        for q in LOG_SUBSCRIBERS:
            try:
                q.put_nowait(line)
            except queue.Full:
                dead.append(q)
        for q in dead:
            LOG_SUBSCRIBERS.remove(q)


class _LogRedirectStream:
    """File-like stream that routes each written line into `log()` so stdout
    prints from deeper layers (generate_with_retry, postprocess) surface in
    the web UI's SSE stream, not just the terminal. Line-buffered to avoid
    emitting partial chunks for progress bars — lines arriving without a
    trailing newline are held until the next write or flush."""

    def __init__(self) -> None:
        self._buf = ""

    def write(self, s: str) -> int:
        if not s:
            return 0
        self._buf += s
        while "\n" in self._buf:
            line, self._buf = self._buf.split("\n", 1)
            if line.strip():
                log(line.rstrip())
        return len(s)

    def flush(self) -> None:
        if self._buf.strip():
            log(self._buf.rstrip())
        self._buf = ""

    def isatty(self) -> bool:
        return False


# ---------------------------------------------------------------------------
# Sprite status
# ---------------------------------------------------------------------------

def sprite_status_map() -> dict[str, dict]:
    log_data = load_log(OUT_DIR)
    out = {}
    for sp in SPRITES:
        rp = raw_path(OUT_DIR, sp)
        pp = processed_path(OUT_DIR, sp)
        if pp.exists():
            status = "complete"
        elif rp.exists():
            status = "raw-only"
        else:
            status = "missing"
        entry = log_data.get(sp.name, {})
        out[sp.name] = {
            "name": sp.name,
            "category": category_of(sp.name),
            "status": status,
            "aspect": sp.aspect,
            "view": sp.view,
            "bg": sp.bg,
            "image_size": sp.image_size,
            "refs": list(sp.refs),
            "has_raw": rp.exists(),
            "has_processed": pp.exists(),
            "log_status": entry.get("status"),
            "log_timestamp": entry.get("timestamp"),
        }
    return out


def sprite_detail(name: str) -> dict | None:
    sp = BY_NAME.get(name)
    if sp is None:
        return None
    base = sprite_status_map()[name]
    base["subject"] = sp.subject
    base["palette"] = sp.palette
    base["extra"] = sp.extra
    base["prompt"] = build_prompt(sp)
    return base


# ---------------------------------------------------------------------------
# Generation worker
# ---------------------------------------------------------------------------

def toposort_selection(names: list[str]) -> list[str]:
    """Order a selected batch so every sprite's in-selection refs run first.

    The UI selection is a Set — its iteration order is click-order, not
    ref-order. When the user shift-clicks several dependent sprites (or uses
    "↓ select subtree" on an anchor), we need to reorder so that parents in
    the DAG are generated before their children. Otherwise the child picks up
    the stale on-disk ref (or no ref at all), and style transfer is broken.

    Algorithm: Kahn's topological sort restricted to the selection.
    - Refs pointing OUTSIDE the selection are ignored (those are assumed to
      already exist on disk or to be intentionally skipped).
    - On a cycle, the remaining nodes are appended in their original order —
      generation will still run, the cycle just won't resolve cleanly.
    - When multiple nodes are ready simultaneously, we emit them in the
      registry order (matches SPRITES list), so runs stay deterministic.
    """
    name_set = set(names)
    # Preserve original (selection) order for stable tie-breaking on cycles.
    original_order = {n: i for i, n in enumerate(names)}
    # Registry order across all sprites — used when multiple nodes are ready.
    registry_order = {sp.name: i for i, sp in enumerate(SPRITES)}

    in_deg: dict[str, int] = {}
    for n in names:
        sp = BY_NAME.get(n)
        refs = list(sp.refs) if sp else []
        in_deg[n] = sum(1 for r in refs if r in name_set)

    # Initial queue: zero in-degree, sorted by registry order.
    ready = sorted([n for n in names if in_deg[n] == 0], key=lambda x: registry_order.get(x, 0))
    result: list[str] = []
    while ready:
        n = ready.pop(0)
        result.append(n)
        # Every in-selection sprite that refs `n` loses one pending dep.
        for other in names:
            if other in result or other not in name_set:
                continue
            sp = BY_NAME.get(other)
            if sp and n in sp.refs:
                in_deg[other] -= 1
                if in_deg[other] == 0:
                    # Insert maintaining registry order
                    ready.append(other)
                    ready.sort(key=lambda x: registry_order.get(x, 0))

    if len(result) != len(names):
        # Cycle — append the unresolved names in their original selection order.
        leftover = [n for n in names if n not in result]
        leftover.sort(key=lambda x: original_order[x])
        result.extend(leftover)
    return result


def run_job(names: list[str], options: dict) -> None:
    total = len(names)
    with JOB_LOCK:
        JOB_STATE.update(
            status="running",
            started_at=datetime.now().isoformat(timespec="seconds"),
            finished_at=None,
            current_sprite=None,
            progress={"done": 0, "failed": 0, "skipped": 0, "total": total},
            cancel_requested=False,
        )

    client = None
    if not options["skip_generation"]:
        try:
            client = make_client(
                options["api_key"],
                timeout_ms=int(options["timeout"] * 1000),
            )
        except Exception as e:
            log(f"[ERROR] could not build API client: {e}")
            with JOB_LOCK:
                JOB_STATE["status"] = "error"
                JOB_STATE["finished_at"] = datetime.now().isoformat(timespec="seconds")
            return

    raw_cache: dict[str, bytes] = {}
    # Track sprites that failed or got blocked during THIS batch. When a later
    # sprite refs one of these, the old on-disk file is treated as stale —
    # we don't want a child generated against a ref whose parent just failed
    # under --force. Propagates blockage downstream so one bad anchor doesn't
    # silently burn tokens on a whole subtree of misaligned children.
    batch_failed: set[str] = set()
    gen_log = load_log(OUT_DIR)

    for idx, name in enumerate(names, 1):
        sp = BY_NAME.get(name)
        if sp is None:
            log(f"[SKIP] unknown sprite {name}")
            with JOB_LOCK:
                JOB_STATE["progress"]["skipped"] += 1
            continue

        with JOB_LOCK:
            if JOB_STATE["cancel_requested"]:
                log("[CANCEL] stopping before next sprite")
                break
            JOB_STATE["current_sprite"] = name

        log(f"[{idx}/{total}] {name}  (aspect={sp.aspect}, size={sp.image_size}, "
            f"view={sp.view}, bg={sp.bg})")

        rp = raw_path(OUT_DIR, sp)
        pp = processed_path(OUT_DIR, sp)

        existing_status = gen_log.get(sp.name, {}).get("status", "")
        force = options["force"]
        reprocess = options["reprocess"]
        skip_gen = options["skip_generation"]

        if existing_status == "complete" and not (force or reprocess):
            log(f"  [SKIP] already complete")
            with JOB_LOCK:
                JOB_STATE["progress"]["skipped"] += 1
            continue

        need_gen = not skip_gen and (force or not rp.exists())
        if skip_gen and not rp.exists():
            log(f"  [SKIP] no raw file at {rp}")
            with JOB_LOCK:
                JOB_STATE["progress"]["skipped"] += 1
            continue

        if need_gen:
            # Strict refs policy: a ref is "satisfied" only if it's in raw_cache
            # (just generated this batch) or on disk AND NOT in batch_failed.
            # missing_refs() handles the first two; we overlay batch_failed
            # here so cascading failures block downstream children even if an
            # old stale ref file still sits in raw/.
            missing = missing_refs(sp, OUT_DIR, raw_cache)
            stale = [r for r in sp.refs if r in batch_failed]
            all_missing = list(dict.fromkeys(missing + stale))
            if all_missing:
                reason = "refs not generated" if missing else "refs failed earlier in this batch"
                log(f"  [BLOCKED] {reason}: {', '.join(all_missing)}")
                log(f"            generate them first — skipping {sp.name}")
                batch_failed.add(sp.name)
                with JOB_LOCK:
                    JOB_STATE["progress"]["skipped"] += 1
                continue

            refs = []
            for ref_name in sp.refs:
                if ref_name in raw_cache:
                    refs.append(raw_cache[ref_name])
                    continue
                ref_sp = BY_NAME.get(ref_name)
                if ref_sp is None:
                    continue
                blob = raw_path(OUT_DIR, ref_sp).read_bytes()
                raw_cache[ref_name] = blob
                refs.append(blob)
                log(f"  [REF] loaded {ref_name}")

            log(f"  generating...")
            # Route generate_with_retry's inner prints (STREAM DEADLINE,
            # WARN, ERROR, etc.) through log() so they land in the SSE stream,
            # not just the terminal where web_ui.py is running.
            _redir = _LogRedirectStream()
            try:
                with contextlib.redirect_stdout(_redir):
                    data = generate_with_retry(
                        client, sp, refs, options["seed"],
                        max_retries=options["max_retries"],
                    )
            finally:
                _redir.flush()
            if data is None:
                log(f"  [FAIL] generation failed")
                batch_failed.add(sp.name)
                with JOB_LOCK:
                    JOB_STATE["progress"]["failed"] += 1
                continue
            rp.parent.mkdir(parents=True, exist_ok=True)
            rp.write_bytes(data)
            raw_cache[sp.name] = data
            gen_log[sp.name] = {
                "status": "generated",
                "timestamp": datetime.now().isoformat(),
            }
            save_log(OUT_DIR, gen_log)
            log(f"  raw -> {rp}")

            if idx < total and options["delay"] > 0:
                time.sleep(options["delay"])
        else:
            log(f"  raw exists: {rp}")

        log(f"  post-processing (bg={sp.bg})...")
        try:
            img = Image.open(rp).convert("RGBA")
            img = postprocess(img, sp.bg, sp.alpha_mode)
            pp.parent.mkdir(parents=True, exist_ok=True)
            img.save(pp, "PNG")
        except Exception as e:
            log(f"  [FAIL] post-process: {e}")
            with JOB_LOCK:
                JOB_STATE["progress"]["failed"] += 1
            continue

        gen_log[sp.name] = {
            "status": "complete",
            "timestamp": datetime.now().isoformat(),
        }
        save_log(OUT_DIR, gen_log)
        log(f"  processed -> {pp}")
        with JOB_LOCK:
            JOB_STATE["progress"]["done"] += 1

    with JOB_LOCK:
        JOB_STATE["status"] = "done"
        JOB_STATE["current_sprite"] = None
        JOB_STATE["finished_at"] = datetime.now().isoformat(timespec="seconds")
    log(f"=== DONE. done={JOB_STATE['progress']['done']} "
        f"failed={JOB_STATE['progress']['failed']} "
        f"skipped={JOB_STATE['progress']['skipped']} ===")


# ---------------------------------------------------------------------------
# HTTP handler
# ---------------------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    server_version = "PVOSpriteUI/1.0"

    def log_message(self, fmt, *args):
        # silence default access log — we have our own
        pass

    # ---- helpers ----
    def _send_json(self, obj, status=200):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _send_text(self, text, status=200, ctype="text/plain; charset=utf-8"):
        body = text.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _send_png(self, path: Path):
        if not path.exists():
            self._send_json({"error": "not found", "path": str(path)}, status=404)
            return
        data = path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "image/png")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def _read_json_body(self) -> dict:
        length = int(self.headers.get("Content-Length", "0") or 0)
        if length <= 0:
            return {}
        try:
            return json.loads(self.rfile.read(length).decode("utf-8"))
        except Exception:
            return {}

    # ---- routing ----
    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/" or path == "/index.html":
            self._send_text(HTML_PAGE, ctype="text/html; charset=utf-8")
            return
        if path == "/api/sprites":
            self._send_json({
                "sprites": sprite_status_map(),
                "categories": sorted({c for _, c in CATEGORY_MAP}),
                "out_dir": str(OUT_DIR),
                "has_api_key": resolve_api_key() is not None,
                "api_key_config_file": str(API_KEY_CONFIG_FILE),
            })
            return
        if path.startswith("/api/sprite/"):
            name = path[len("/api/sprite/"):]
            detail = sprite_detail(name)
            if detail is None:
                self._send_json({"error": "unknown sprite"}, status=404)
                return
            self._send_json(detail)
            return
        if path == "/api/status":
            with JOB_LOCK:
                self._send_json(dict(JOB_STATE))
            return
        if path == "/api/log":
            with JOB_LOCK:
                self._send_text("\n".join(LOG_BUFFER[-1000:]))
            return
        if path == "/api/stream":
            self._stream_log()
            return
        if path.startswith("/image/raw/"):
            name = path[len("/image/raw/"):]
            sp = BY_NAME.get(name)
            if sp is None:
                self._send_json({"error": "unknown sprite"}, status=404)
                return
            self._send_png(raw_path(OUT_DIR, sp))
            return
        if path.startswith("/image/processed/"):
            name = path[len("/image/processed/"):]
            sp = BY_NAME.get(name)
            if sp is None:
                self._send_json({"error": "unknown sprite"}, status=404)
                return
            self._send_png(processed_path(OUT_DIR, sp))
            return
        self._send_json({"error": "not found"}, status=404)

    def do_POST(self):
        path = urlparse(self.path).path
        if path == "/api/generate":
            body = self._read_json_body()
            names = body.get("names") or []
            if not isinstance(names, list) or not names:
                self._send_json({"error": "names[] required"}, status=400)
                return
            names = [str(n) for n in names if n in BY_NAME]
            if not names:
                self._send_json({"error": "no valid sprite names"}, status=400)
                return
            # Always reorder the batch so refs resolve correctly. See
            # toposort_selection docstring — the UI selection is a Set with
            # click-order iteration, which doesn't match the DAG.
            names = toposort_selection(names)

            api_key = resolve_api_key(str(body.get("api_key", "") or ""))
            options = {
                "api_key": api_key or "",
                "force": bool(body.get("force", False)),
                "reprocess": bool(body.get("reprocess", False)),
                "skip_generation": bool(body.get("skip_generation", False)),
                "seed": body.get("seed") if body.get("seed") not in ("", None) else None,
                "delay": float(body.get("delay", 2.0) or 0.0),
                "timeout": float(body.get("timeout", 600.0) or 600.0),
                "max_retries": int(body.get("max_retries", 8) or 8),
            }
            if options["seed"] is not None:
                try:
                    options["seed"] = int(options["seed"])
                except (TypeError, ValueError):
                    options["seed"] = None

            if not options["skip_generation"] and not options["api_key"]:
                self._send_json({
                    "error": (
                        "No API key. Paste it into the form field, set "
                        "GEMINI_API_KEY in the environment, or edit "
                        f"{API_KEY_CONFIG_FILE}."
                    )
                }, status=400)
                return

            with JOB_LOCK:
                if JOB_STATE["status"] == "running":
                    self._send_json({"error": "job already running"}, status=409)
                    return

            t = threading.Thread(target=run_job, args=(names, options), daemon=True)
            t.start()
            self._send_json({"ok": True, "names": names})
            return

        if path == "/api/cancel":
            with JOB_LOCK:
                if JOB_STATE["status"] != "running":
                    self._send_json({"error": "no job running"}, status=409)
                    return
                JOB_STATE["cancel_requested"] = True
            log("[CANCEL] requested by user — will stop after current sprite")
            self._send_json({"ok": True})
            return

        self._send_json({"error": "not found"}, status=404)

    # ---- SSE ----
    def _stream_log(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.end_headers()

        q: queue.Queue = queue.Queue(maxsize=500)
        with JOB_LOCK:
            # replay recent lines so the UI catches up on connect
            for line in LOG_BUFFER[-200:]:
                try:
                    q.put_nowait(line)
                except queue.Full:
                    break
            LOG_SUBSCRIBERS.append(q)

        try:
            while True:
                try:
                    line = q.get(timeout=15)
                    payload = f"data: {json.dumps(line)}\n\n".encode("utf-8")
                    self.wfile.write(payload)
                    self.wfile.flush()
                except queue.Empty:
                    # keepalive comment
                    self.wfile.write(b": keepalive\n\n")
                    self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            with JOB_LOCK:
                if q in LOG_SUBSCRIBERS:
                    LOG_SUBSCRIBERS.remove(q)


# ---------------------------------------------------------------------------
# HTML page (served inline)
# ---------------------------------------------------------------------------

HTML_PAGE = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>PVOGame Sprite Generator</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
:root {
  --bg: #0e1116;
  --panel: #161b22;
  --panel-2: #1f262f;
  --border: #2a323d;
  --text: #dbe4ef;
  --dim: #8b99ab;
  --accent: #4a9eff;
  --ok: #5dd39e;
  --warn: #f0c67a;
  --bad: #e86a6a;
  --missing: #6b7685;
}
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; background: var(--bg); color: var(--text);
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
body { display: grid; grid-template-columns: 1fr 420px; grid-template-rows: auto 1fr;
  grid-template-areas: "top top" "main side"; height: 100vh; }
header { grid-area: top; background: var(--panel); border-bottom: 1px solid var(--border);
  padding: 12px 20px; display: flex; flex-wrap: wrap; gap: 14px; align-items: center; }
header h1 { font-size: 15px; margin: 0; font-weight: 600; letter-spacing: .03em;
  color: var(--accent); }
header .meta { color: var(--dim); font-size: 12px; }
header .fill { flex: 1; }

.opts { display: flex; gap: 10px; flex-wrap: wrap; align-items: center; font-size: 12px; }
.opts label { display: flex; align-items: center; gap: 5px; color: var(--dim); }
.opts input[type=text], .opts input[type=number], .opts input[type=password] {
  background: var(--panel-2); border: 1px solid var(--border); color: var(--text);
  padding: 5px 8px; border-radius: 4px; font-size: 12px; font-family: inherit; }
.opts input[type=password] { width: 180px; font-family: monospace; }
.opts input[type=number] { width: 72px; }
.opts input[type=checkbox] { accent-color: var(--accent); }

main { grid-area: main; overflow: auto; padding: 20px; }
aside { grid-area: side; background: var(--panel); border-left: 1px solid var(--border);
  display: flex; flex-direction: column; overflow: hidden; }

.toolbar { display: flex; gap: 10px; align-items: center; margin-bottom: 16px; flex-wrap: wrap; }
.toolbar button, .gen-btn, .cancel-btn {
  background: var(--panel-2); border: 1px solid var(--border); color: var(--text);
  padding: 7px 12px; border-radius: 5px; font: inherit; font-size: 12px; cursor: pointer; }
.toolbar button:hover, .gen-btn:hover { border-color: var(--accent); color: var(--accent); }
.gen-btn.primary { background: var(--accent); color: #fff; border-color: var(--accent); }
.gen-btn.primary:hover { filter: brightness(1.1); }
.cancel-btn { border-color: var(--bad); color: var(--bad); }
.toolbar .count { color: var(--dim); font-size: 12px; }

.filters { display: flex; gap: 6px; flex-wrap: wrap; }
.filters button { padding: 4px 10px; font-size: 11px; }
.filters button.active { border-color: var(--accent); color: var(--accent); background: var(--panel); }

.category { margin-bottom: 26px; }
.category h2 { font-size: 13px; font-weight: 600; color: var(--dim);
  text-transform: uppercase; letter-spacing: .08em; margin: 0 0 10px 0; border-bottom: 1px solid var(--border);
  padding-bottom: 6px; }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
  gap: 12px; }
.card { background: var(--panel); border: 1px solid var(--border); border-radius: 6px;
  padding: 10px; cursor: pointer; transition: border-color .12s, transform .12s;
  position: relative; display: flex; flex-direction: column; }
.card:hover { border-color: var(--accent); transform: translateY(-1px); }
.card.selected { border-color: var(--accent); box-shadow: 0 0 0 1px var(--accent); }
.card .thumb { width: 100%; aspect-ratio: 1; background: #0a0d12;
  border-radius: 4px; display: flex; align-items: center; justify-content: center;
  margin-bottom: 8px; overflow: hidden;
  background-image:
    linear-gradient(45deg, #1a1f26 25%, transparent 25%),
    linear-gradient(-45deg, #1a1f26 25%, transparent 25%),
    linear-gradient(45deg, transparent 75%, #1a1f26 75%),
    linear-gradient(-45deg, transparent 75%, #1a1f26 75%);
  background-size: 16px 16px;
  background-position: 0 0, 0 8px, 8px -8px, -8px 0; }
.card .thumb img { max-width: 100%; max-height: 100%; image-rendering: pixelated; }
.card .thumb .placeholder { color: var(--missing); font-size: 11px; text-align: center; padding: 4px; }
.card .name { font-size: 12px; font-weight: 500; word-break: break-word; line-height: 1.3; }
.card .meta { font-size: 10px; color: var(--dim); margin-top: 3px; }
.card .check { position: absolute; top: 6px; right: 6px; width: 18px; height: 18px;
  border: 2px solid var(--border); border-radius: 4px; background: rgba(14,17,22,0.8); }
.card.selected .check { background: var(--accent); border-color: var(--accent); }
.card.selected .check::after { content: "✓"; color: #fff; font-size: 12px;
  display: flex; align-items: center; justify-content: center; height: 100%; font-weight: bold; }

.badge { position: absolute; top: 6px; left: 6px; padding: 2px 7px;
  border-radius: 3px; font-size: 9px; font-weight: 600; text-transform: uppercase;
  letter-spacing: .05em; }
.badge.complete { background: var(--ok); color: #0d1f17; }
.badge.raw-only { background: var(--warn); color: #2a220d; }
.badge.missing { background: #2a323d; color: var(--dim); }

aside .tabs { display: flex; border-bottom: 1px solid var(--border); }
aside .tabs button { flex: 1; background: transparent; border: none; color: var(--dim);
  padding: 12px; cursor: pointer; font-family: inherit; font-size: 12px;
  border-bottom: 2px solid transparent; }
aside .tabs button.active { color: var(--accent); border-bottom-color: var(--accent); }
aside .tab-content { flex: 1; overflow: auto; }
aside .tab-content > div { display: none; padding: 16px; }
aside .tab-content > div.active { display: block; }

.detail h3 { font-size: 14px; margin: 0 0 12px 0; }
.detail .kv { display: grid; grid-template-columns: 90px 1fr; gap: 5px 10px;
  font-size: 12px; color: var(--dim); margin-bottom: 12px; }
.detail .kv span:nth-child(2n) { color: var(--text); }
.detail h4 { font-size: 11px; text-transform: uppercase; letter-spacing: .05em;
  color: var(--dim); margin: 16px 0 6px 0; }
.detail pre { background: var(--panel-2); border: 1px solid var(--border);
  padding: 10px; border-radius: 4px; font-size: 11px; line-height: 1.5;
  max-height: 260px; overflow: auto; white-space: pre-wrap; word-break: break-word; }
.detail .imgs { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-top: 10px; }
.detail .imgs figure { margin: 0; background:
    linear-gradient(45deg, #1a1f26 25%, transparent 25%),
    linear-gradient(-45deg, #1a1f26 25%, transparent 25%),
    linear-gradient(45deg, transparent 75%, #1a1f26 75%),
    linear-gradient(-45deg, transparent 75%, #1a1f26 75%);
  background-size: 16px 16px; border: 1px solid var(--border);
  border-radius: 4px; padding: 6px; text-align: center; }
.detail .imgs figure img { max-width: 100%; }
.detail .imgs figcaption { font-size: 10px; color: var(--dim); margin-top: 4px; }

.log { font-family: SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 11px; line-height: 1.5; white-space: pre-wrap;
  color: var(--text); padding: 12px !important; }
.log .line { padding: 1px 0; }
.log .line.err { color: var(--bad); }
.log .line.warn { color: var(--warn); }
.log .line.ok { color: var(--ok); }
.log .line.dim { color: var(--dim); }

.progress { padding: 12px; border-bottom: 1px solid var(--border); background: var(--panel-2);
  font-size: 12px; }
.progress .label { color: var(--dim); margin-bottom: 6px; }
.progress .bar { height: 6px; background: #0a0d12; border-radius: 3px; overflow: hidden; }
.progress .bar > div { height: 100%; background: var(--accent); width: 0%; transition: width .2s; }
.progress .nums { color: var(--dim); margin-top: 4px; font-size: 11px; }

.empty { color: var(--dim); padding: 40px 20px; text-align: center; font-size: 12px; }

/* ---- view toggle (grid | tree) in the toolbar ---- */
.view-toggle { display: inline-flex; border: 1px solid var(--border); border-radius: 5px;
  overflow: hidden; margin-right: 10px; }
.view-toggle button { background: var(--panel-2); border: none; color: var(--dim);
  padding: 6px 12px; font-size: 12px; font-family: inherit; cursor: pointer; }
.view-toggle button.active { background: var(--accent); color: #fff; }
.view-toggle button:not(.active):hover { color: var(--accent); }

/* ---- dependency tree ---- */
.tree { display: flex; flex-direction: column; gap: 3px; position: relative; }
.tree-section { margin-bottom: 20px; }
.tree-section > h2 { font-size: 13px; font-weight: 600; color: var(--dim);
  text-transform: uppercase; letter-spacing: .08em; margin: 0 0 10px 0;
  border-bottom: 1px solid var(--border); padding-bottom: 6px; }
.tree-section > h2 .sub { color: var(--text); font-weight: normal; text-transform: none;
  letter-spacing: 0; margin-left: 8px; font-size: 12px; }
.tree-section > h3 { color: var(--dim); font-size: 11px; margin: 14px 0 6px 0;
  text-transform: uppercase; letter-spacing: .05em; font-weight: 600; }

/* Row indents by depth via a CSS variable. No elbow connectors — just
   a subtle left border on non-root nodes so the hierarchy reads visually. */
.tree-node { display: flex; align-items: center; gap: 10px;
  padding: 6px 10px; border: 1px solid transparent; border-radius: 5px;
  background: var(--panel); position: relative;
  margin-left: calc(var(--depth, 0) * 22px); }
.tree-node[data-depth]:not([data-depth="0"]) { border-left: 2px solid var(--border); }
.tree-node:hover { border-color: var(--accent); }
.tree-node.selected { border-color: var(--accent); box-shadow: 0 0 0 1px var(--accent); background: var(--panel-2); }
.tree-node.active { outline: 1px dashed var(--accent); outline-offset: -2px; }
.tree-node.dim { opacity: 0.45; }

.tree-node .thumb-sm { width: 40px; height: 40px; border-radius: 3px;
  background: #0a0d12; flex-shrink: 0; display: flex; align-items: center;
  justify-content: center; overflow: hidden;
  background-image:
    linear-gradient(45deg, #1a1f26 25%, transparent 25%),
    linear-gradient(-45deg, #1a1f26 25%, transparent 25%),
    linear-gradient(45deg, transparent 75%, #1a1f26 75%),
    linear-gradient(-45deg, transparent 75%, #1a1f26 75%);
  background-size: 10px 10px;
  background-position: 0 0, 0 5px, 5px -5px, -5px 0; }
.tree-node .thumb-sm img { max-width: 100%; max-height: 100%; image-rendering: pixelated; }
.tree-node .thumb-sm .placeholder { color: var(--missing); font-size: 8px; text-align: center; }

.tree-node .info { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 2px; }
.tree-node .info .name { font-size: 12px; font-weight: 500; }
.tree-node .info .meta { font-size: 10px; color: var(--dim); }
.tree-node .info .refs-inline { font-size: 10px; color: var(--dim); }
.tree-node .info .refs-inline span { color: var(--text); }

.tree-node .tree-badge { padding: 2px 7px; border-radius: 3px; font-size: 9px;
  font-weight: 600; text-transform: uppercase; letter-spacing: .05em;
  flex-shrink: 0; }
.tree-node .tree-badge.complete { background: var(--ok); color: #0d1f17; }
.tree-node .tree-badge.raw-only { background: var(--warn); color: #2a220d; }
.tree-node .tree-badge.missing { background: #2a323d; color: var(--dim); }

.tree-node .tree-check { width: 18px; height: 18px; border: 2px solid var(--border);
  border-radius: 4px; background: rgba(14,17,22,0.8); flex-shrink: 0;
  display: flex; align-items: center; justify-content: center;
  color: #fff; font-size: 11px; font-weight: bold; cursor: pointer; user-select: none; }
.tree-node.selected .tree-check { background: var(--accent); border-color: var(--accent); }
.tree-node.selected .tree-check::after { content: "✓"; }

.tree-node .subtree-actions { display: flex; gap: 4px; flex-shrink: 0; }
.tree-node .subtree-actions button {
  background: var(--panel-2); border: 1px solid var(--border); color: var(--dim);
  padding: 3px 7px; border-radius: 3px; font-size: 10px; font-family: inherit;
  cursor: pointer; white-space: nowrap; }
.tree-node .subtree-actions button:hover { border-color: var(--accent); color: var(--accent); }

.tree-legend { color: var(--dim); font-size: 11px; padding: 10px 14px;
  background: var(--panel); border: 1px solid var(--border);
  border-radius: 5px; margin-bottom: 16px; line-height: 1.6; }
.tree-legend code { background: var(--panel-2); padding: 1px 5px; border-radius: 3px;
  font-size: 10px; color: var(--text); }

details.advanced { margin-top: 8px; color: var(--dim); font-size: 11px; }
details.advanced summary { cursor: pointer; user-select: none; }

.help {
  display: inline-flex; align-items: center; justify-content: center;
  width: 14px; height: 14px; border-radius: 50%;
  background: var(--panel-2); border: 1px solid var(--border); color: var(--dim);
  font-size: 10px; font-weight: 600; font-family: serif; font-style: italic;
  cursor: help; position: relative; margin-left: 4px; vertical-align: middle;
  user-select: none; line-height: 1;
}
.help:hover { color: var(--accent); border-color: var(--accent); }
.help:hover::before {
  content: ""; position: absolute; top: calc(100% + 4px); left: 50%;
  transform: translateX(-50%);
  border: 5px solid transparent; border-bottom-color: #000; z-index: 1001;
}
.help:hover::after {
  content: attr(data-tip);
  position: absolute; top: calc(100% + 8px); left: 50%;
  transform: translateX(-50%);
  background: #000; color: #fff;
  padding: 7px 10px; border-radius: 4px; font-size: 11px; font-weight: normal;
  font-style: normal; font-family: inherit; line-height: 1.4;
  white-space: normal; width: max-content; max-width: 280px; text-align: left;
  box-shadow: 0 4px 16px rgba(0,0,0,0.5); z-index: 1000;
  pointer-events: none;
}
.help.right-edge:hover::after { left: auto; right: 0; transform: none; }
.help.right-edge:hover::before { left: auto; right: 6px; transform: none; }
/* when the icon sits near the right edge of the viewport, shift the tooltip to the left */
.help.left-shift:hover::after { left: auto; right: -6px; transform: none; }
.help.left-shift:hover::before { left: auto; right: 4px; transform: none; }
</style>
</head>
<body>

<header>
  <h1>PVO Sprite Generator</h1>
  <span class="meta" id="outDir"></span>
  <div class="fill"></div>
  <span class="count" id="selCount" style="color: var(--dim); font-size: 12px;">0 selected</span>
  <button class="gen-btn primary" id="btnGen">▶ generate selected</button>
  <span class="help right-edge" data-tip="Запустить генерацию для всех выделенных спрайтов с текущими опциями справа. Прогресс виден в правой панели, лог — во вкладке «log».">i</span>
  <button class="cancel-btn" id="btnCancel" style="display:none">■ cancel</button>
  <span class="help right-edge" id="btnCancelHelp" style="display:none" data-tip="Остановить генерацию: текущий спрайт доработает до конца или до таймаута (до 3 мин), оставшиеся в очереди будут пропущены. Failed requests через artemox не биллятся.">i</span>
  <div class="opts">
    <label>API Key
      <input type="password" id="apiKey" placeholder="sk-..." autocomplete="off">
      <span class="help" data-tip="Ключ Gemini API (LiteLLM/artemox). Запоминается только в этой вкладке и отправляется на локальный сервер, не сохраняется на диск.">i</span>
    </label>
    <label><input type="checkbox" id="force"> force
      <span class="help" data-tip="Перегенерировать спрайт через API, даже если raw-файл уже есть. Учти: каждый запуск тратит токены.">i</span>
    </label>
    <label><input type="checkbox" id="reprocess"> reprocess
      <span class="help" data-tip="Заново прогнать постобработку (удаление фона, альфа-канал) по уже существующему raw-файлу. API НЕ вызывается, токены не тратятся.">i</span>
    </label>
    <label><input type="checkbox" id="skipGen"> skip-generation
      <span class="help" data-tip="Полностью пропустить вызов API — только постобработать те спрайты, у которых уже есть raw-файл. Работает без ключа.">i</span>
    </label>
    <label>seed
      <input type="number" id="seed" placeholder="">
      <span class="help" data-tip="Фиксированный seed модели для воспроизводимости: одинаковый seed даёт похожий результат при повторной генерации. Пусто = случайный.">i</span>
    </label>
    <label>delay
      <input type="number" id="delay" value="2" step="0.5">
      <span class="help" data-tip="Пауза в секундах между соседними вызовами API в пакетной генерации. Нужна, чтобы не упираться в лимит RPM (у тебя 24 запроса/мин).">i</span>
    </label>
    <label>timeout
      <input type="number" id="timeout" value="600">
      <span class="help" data-tip="Таймаут HTTP-клиента в секундах. ВНИМАНИЕ: Cloudflare перед прокси режет соединение через 100 с (ошибка 524), это не обойти клиентом.">i</span>
    </label>
    <label>retries
      <input type="number" id="maxRetries" value="8" min="1">
      <span class="help right-edge" data-tip="Сколько раз повторить запрос при серверных ошибках (500/502/503/520/524) и rate-limit. Ставь 1, чтобы не заплатить дважды при 524 (upstream мог успеть посчитать).">i</span>
    </label>
  </div>
</header>

<main>
  <div class="toolbar">
    <div class="view-toggle" id="viewToggle">
      <button data-view="grid" class="active">grid</button>
      <button data-view="tree">tree</button>
    </div>
    <span class="help" data-tip="Переключить режим отображения: grid — плитка по категориям; tree — дерево зависимостей по refs (anchor → children → grandchildren). В tree-режиме каждая нода даёт кнопки выбора подветки/предков.">i</span>
    <div class="filters" id="filters"></div>
    <span class="fill"></span>
    <button id="selAll">select all</button>
    <span class="help" data-tip="Выделить все спрайты, которые видны при текущем фильтре/режиме.">i</span>
    <button id="selMissing">select missing</button>
    <span class="help" data-tip="Очистить выделение и выбрать только несгенерированные (статус не complete) из видимых при текущем фильтре/режиме.">i</span>
    <button id="selNone">clear</button>
    <span class="help" data-tip="Снять выделение со всех спрайтов.">i</span>
  </div>
  <div id="categories"></div>
</main>

<aside>
  <div class="tabs">
    <button class="active" data-tab="detail">detail</button>
    <button data-tab="log">log</button>
  </div>
  <div class="progress" id="progress" style="display:none">
    <div class="label" id="progressLabel">idle</div>
    <div class="bar"><div id="progressBar"></div></div>
    <div class="nums" id="progressNums"></div>
  </div>
  <div class="tab-content">
    <div id="tab-detail" class="active detail">
      <div class="empty">click a sprite to inspect its prompt, refs, and images</div>
    </div>
    <div id="tab-log" class="log"></div>
  </div>
</aside>

<script>
const CAT_ORDER = ["towers","drones","projectiles","vfx","settlements","tiles","ui","special"];
const STATE = {
  sprites: {},
  selected: new Set(),
  activeCat: "all",
  detailName: null,
  apiKeyStored: "",
  lastStatus: null,       // previous /api/status.status — used to edge-trigger refresh
  cacheBust: Date.now(),  // appended to image URLs; bumped ONLY when sprites change
  hasServerKey: false,    // server has a key resolvable from env or ~/.google-genai/config
  apiKeyConfigFile: "",   // path to the config file, shown in the prompt dialog
  view: "grid",           // "grid" | "tree"
};

function el(tag, attrs = {}, ...children) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === "class") e.className = v;
    else if (k === "text") e.textContent = v;
    else if (k.startsWith("on") && typeof v === "function") e.addEventListener(k.substring(2), v);
    else if (v !== null && v !== undefined) e.setAttribute(k, v);
  }
  for (const c of children) if (c != null) e.append(c);
  return e;
}

async function fetchSprites() {
  const r = await fetch("/api/sprites");
  const data = await r.json();
  STATE.sprites = data.sprites;
  STATE.hasServerKey = Boolean(data.has_api_key);
  STATE.apiKeyConfigFile = data.api_key_config_file || "";
  document.getElementById("outDir").textContent = "out: " + data.out_dir;

  // Reflect "key is already on server" in the form field as a placeholder hint.
  const keyField = document.getElementById("apiKey");
  if (STATE.hasServerKey && !keyField.value) {
    keyField.placeholder = "(using key from server config)";
  } else if (!STATE.hasServerKey) {
    keyField.placeholder = "sk-...";
  }
  renderFilters();
  renderGrid();
}

function countByStatus() {
  const counts = {all: 0, complete: 0, "raw-only": 0, missing: 0};
  for (const sp of Object.values(STATE.sprites)) {
    counts.all++;
    counts[sp.status] = (counts[sp.status] || 0) + 1;
  }
  return counts;
}

const FILTER_TIPS = {
  "all": "Показать все спрайты.",
  "__complete": "Показать только полностью готовые спрайты (есть файл в processed/).",
  "__raw": "Показать спрайты, у которых есть raw-файл, но постобработка не завершена или сломалась.",
  "__missing": "Показать спрайты, которые ещё ни разу не генерировались.",
  "towers": "Фильтр по категории «towers» — башни ПВО и их компоненты.",
  "drones": "Фильтр по категории «drones» — летающие цели и ракеты врага.",
  "projectiles": "Фильтр по категории «projectiles» — снаряды игрока (ракеты, трассеры).",
  "vfx": "Фильтр по категории «vfx» — эффекты (дым, искры, кадры взрывов).",
  "settlements": "Фильтр по категории «settlements» — поселения / защищаемые объекты.",
  "tiles": "Фильтр по категории «tiles» — бесшовные тайлы ландшафта.",
  "ui": "Фильтр по категории «ui» — элементы интерфейса в стиле Soviet CRT.",
  "special": "Фильтр по категории «special» — особые спрайты (истребитель, иконка приложения).",
};

function renderFilters() {
  const counts = countByStatus();
  const cats = {};
  for (const sp of Object.values(STATE.sprites)) cats[sp.category] = (cats[sp.category] || 0) + 1;
  const container = document.getElementById("filters");
  container.innerHTML = "";
  const makeBtn = (key, label, count) => {
    const wrap = el("span", {style: "display:inline-flex; align-items:center;"});
    const b = el("button", {
      class: STATE.activeCat === key ? "active" : "",
      text: `${label} (${count})`,
      onclick: () => { STATE.activeCat = key; renderFilters(); renderGrid(); },
    });
    wrap.append(b);
    const tip = FILTER_TIPS[key];
    if (tip) {
      const h = el("span", {class: "help", "data-tip": tip, text: "i"});
      wrap.append(h);
    }
    return wrap;
  };
  container.append(makeBtn("all", "all", counts.all));
  container.append(makeBtn("__complete", "✓ complete", counts.complete || 0));
  container.append(makeBtn("__raw", "raw-only", counts["raw-only"] || 0));
  container.append(makeBtn("__missing", "missing", counts.missing || 0));
  const orderedCats = CAT_ORDER.filter(c => cats[c]).concat(Object.keys(cats).filter(c => !CAT_ORDER.includes(c)));
  for (const cat of orderedCats) container.append(makeBtn(cat, cat, cats[cat]));
}

function spriteMatchesFilter(sp) {
  const f = STATE.activeCat;
  if (f === "all") return true;
  if (f === "__complete") return sp.status === "complete";
  if (f === "__raw") return sp.status === "raw-only";
  if (f === "__missing") return sp.status === "missing";
  return sp.category === f;
}

function renderGrid() {
  // Dispatch to tree view when the toggle is on tree mode. Every existing call
  // site (toggleSelect, fetchSprites, selAll/Missing/None, filter buttons)
  // flows through renderGrid, so one check here covers the whole UI.
  if (STATE.view === "tree") return renderTree();

  const root = document.getElementById("categories");
  root.innerHTML = "";
  const grouped = {};
  for (const sp of Object.values(STATE.sprites)) {
    if (!spriteMatchesFilter(sp)) continue;
    (grouped[sp.category] ||= []).push(sp);
  }
  const orderedCats = CAT_ORDER.filter(c => grouped[c])
    .concat(Object.keys(grouped).filter(c => !CAT_ORDER.includes(c)));
  if (orderedCats.length === 0) {
    root.append(el("div", {class: "empty", text: "no sprites match this filter"}));
    updateSelCount();
    return;
  }
  for (const cat of orderedCats) {
    const section = el("section", {class: "category"});
    section.append(el("h2", {text: `${cat} (${grouped[cat].length})`}));
    const grid = el("div", {class: "grid"});
    for (const sp of grouped[cat].sort((a,b) => a.name.localeCompare(b.name))) {
      grid.append(renderCard(sp));
    }
    section.append(grid);
    root.append(section);
  }
  updateSelCount();
}

function renderCard(sp) {
  const selected = STATE.selected.has(sp.name);
  const card = el("div", {
    class: "card" + (selected ? " selected" : ""),
    onclick: (ev) => {
      if (ev.shiftKey || ev.metaKey || ev.ctrlKey) {
        toggleSelect(sp.name);
      } else {
        STATE.detailName = sp.name;
        toggleSelect(sp.name);
        showDetail(sp.name);
      }
    },
    ondblclick: () => showDetail(sp.name),
  });
  const thumb = el("div", {class: "thumb"});
  if (sp.has_processed) {
    thumb.append(el("img", {src: `/image/processed/${sp.name}?t=${STATE.cacheBust}`, alt: sp.name}));
  } else if (sp.has_raw) {
    thumb.append(el("img", {src: `/image/raw/${sp.name}?t=${STATE.cacheBust}`, alt: sp.name}));
  } else {
    thumb.append(el("div", {class: "placeholder", text: "— not generated —"}));
  }
  const badge = el("span", {class: `badge ${sp.status}`, text: sp.status});
  card.append(el("span", {class: "check"}));
  card.append(badge);
  card.append(thumb);
  card.append(el("div", {class: "name", text: sp.name}));
  card.append(el("div", {class: "meta", text: `${sp.aspect} · ${sp.view} · bg:${sp.bg}`}));
  return card;
}

function toggleSelect(name) {
  if (STATE.selected.has(name)) STATE.selected.delete(name);
  else STATE.selected.add(name);
  renderGrid();
}

// =============== Dependency tree view ===============

// Build two adjacency maps from the current STATE.sprites refs data.
// - primaryChildren: parent -> [children], where "parent" is each sprite's FIRST ref.
//   This gives a clean single-parent tree (refs beyond index 0 show up as an
//   inline "also refs" caption on the node, to avoid duplicating subtrees).
// - reverseDeps: name -> [all sprites that list it anywhere in refs].
//   This is the full DAG and is what "select subtree" walks, so you get every
//   downstream dependent regardless of primary-parent choice.
function buildDepsGraph() {
  const primaryChildren = {};
  const reverseDeps = {};
  for (const sp of Object.values(STATE.sprites)) {
    if (sp.refs && sp.refs.length > 0) {
      (primaryChildren[sp.refs[0]] ||= []).push(sp.name);
      for (const r of sp.refs) {
        (reverseDeps[r] ||= []).push(sp.name);
      }
    }
  }
  for (const arr of Object.values(primaryChildren)) arr.sort();
  return { primaryChildren, reverseDeps };
}

function computeSubtree(rootName) {
  const { reverseDeps } = buildDepsGraph();
  const result = new Set();
  const stack = [rootName];
  while (stack.length) {
    const n = stack.pop();
    if (result.has(n)) continue;
    result.add(n);
    for (const c of (reverseDeps[n] || [])) stack.push(c);
  }
  return result;
}

function computeAncestors(startName) {
  const result = new Set();
  const stack = [startName];
  while (stack.length) {
    const n = stack.pop();
    if (result.has(n)) continue;
    result.add(n);
    const sp = STATE.sprites[n];
    if (!sp || !sp.refs) continue;
    for (const r of sp.refs) stack.push(r);
  }
  return result;
}

function countDescendants(name, primaryChildren) {
  let count = 0;
  const stack = [name];
  const visited = new Set();
  while (stack.length) {
    const n = stack.pop();
    if (visited.has(n)) continue;
    visited.add(n);
    for (const c of (primaryChildren[n] || [])) {
      count++;
      stack.push(c);
    }
  }
  return count;
}

// Filter pass that keeps a node if EITHER it matches the current filter, OR
// any of its primary-descendants does. Applied to tree roots so we don't show
// empty branches under a filter like "missing".
function subtreeHasMatch(name, primaryChildren) {
  const sp = STATE.sprites[name];
  if (sp && spriteMatchesFilter(sp)) return true;
  for (const c of (primaryChildren[name] || [])) {
    if (subtreeHasMatch(c, primaryChildren)) return true;
  }
  return false;
}

function selectSubtree(name) {
  for (const n of computeSubtree(name)) STATE.selected.add(n);
  renderGrid();
}

function selectAncestors(name) {
  for (const n of computeAncestors(name)) STATE.selected.add(n);
  renderGrid();
}

function renderTree() {
  const root = document.getElementById("categories");
  root.innerHTML = "";

  const { primaryChildren } = buildDepsGraph();

  // Root = sprite with no refs. Split into "connected" (has dependents) and
  // "standalone" (no dependents either) for a cleaner layout: the interesting
  // VFX anchor + muzzle/tracer/puff chain lives under "connected", while the
  // 80+ isolated tower/drone/tile sprites go into a collapsible standalone
  // block grouped by category.
  const connectedRoots = [];
  const standalones = [];
  for (const sp of Object.values(STATE.sprites)) {
    if (sp.refs && sp.refs.length > 0) continue;
    const hasChildren = (primaryChildren[sp.name] || []).length > 0;
    if (hasChildren) connectedRoots.push(sp.name);
    else standalones.push(sp.name);
  }
  connectedRoots.sort();
  standalones.sort();

  // Intro legend — repeated here because the tree view is a different mental
  // model from the grid; users need to know what the arrows do before clicking.
  const legend = el("div", {class: "tree-legend"});
  legend.innerHTML =
    "Дерево строится по <code>refs</code>: первый reference спрайта становится его родителем, остальные показаны как <i>also refs</i>. " +
    "Клик на чекбокс — выбор одной ноды. " +
    "<code>↓ select subtree</code> — выбрать узел и всех его потомков по полному DAG (этим мы перегенерим всё, что зависит от anchor'а после его изменения). " +
    "<code>↑ select deps</code> — выбрать все транзитивные refs узла (чтобы гарантировать правильный порядок при первом запуске). " +
    "Флаги генерации (force / reprocess / seed / delay) читаются из той же шапки что и в grid-режиме.";
  root.append(legend);

  // Connected tree section
  if (connectedRoots.length > 0) {
    const visibleRoots = connectedRoots.filter(r => subtreeHasMatch(r, primaryChildren));
    const section = el("section", {class: "tree-section"});
    const h2 = el("h2");
    h2.append(document.createTextNode("dependency graph"));
    h2.append(el("span", {class: "sub", text: `${visibleRoots.length} / ${connectedRoots.length} roots visible`}));
    section.append(h2);
    const tree = el("div", {class: "tree"});
    for (const r of visibleRoots) {
      renderTreeNode(tree, r, primaryChildren, 0);
    }
    if (visibleRoots.length === 0) {
      tree.append(el("div", {class: "empty", text: "no connected roots match the current filter"}));
    }
    section.append(tree);
    root.append(section);
  }

  // Standalone (no refs, not referenced) — show last, grouped by category.
  // Apply the same filter as the grid so the "missing" etc. filters work here too.
  const filteredStandalones = standalones.filter(n => spriteMatchesFilter(STATE.sprites[n]));
  if (filteredStandalones.length > 0) {
    const byCat = {};
    for (const n of filteredStandalones) {
      const cat = STATE.sprites[n].category;
      (byCat[cat] ||= []).push(n);
    }
    const section = el("section", {class: "tree-section"});
    const h2 = el("h2");
    h2.append(document.createTextNode("standalone"));
    h2.append(el("span", {class: "sub",
      text: `${filteredStandalones.length} / ${standalones.length} — no refs, not referenced`}));
    section.append(h2);
    const ordered = CAT_ORDER.filter(c => byCat[c])
      .concat(Object.keys(byCat).filter(c => !CAT_ORDER.includes(c)));
    for (const cat of ordered) {
      section.append(el("h3", {text: `${cat} (${byCat[cat].length})`}));
      const tree = el("div", {class: "tree"});
      for (const n of byCat[cat]) renderTreeNode(tree, n, primaryChildren, 0);
      section.append(tree);
    }
    root.append(section);
  }

  updateSelCount();
}

function renderTreeNode(container, name, primaryChildren, depth) {
  const sp = STATE.sprites[name];
  if (!sp) return;
  const selected = STATE.selected.has(name);
  const isActive = STATE.detailName === name;
  const children = (primaryChildren[name] || []).slice();
  const matchesFilter = spriteMatchesFilter(sp);

  const node = el("div", {
    class: "tree-node"
      + (selected ? " selected" : "")
      + (isActive ? " active" : "")
      + (matchesFilter ? "" : " dim"),
    "data-depth": String(depth),
  });
  node.style.setProperty("--depth", depth);

  // Checkbox — stopPropagation so body-click (detail) doesn't also fire
  const check = el("div", {
    class: "tree-check",
    title: "select / deselect",
    onclick: (ev) => { ev.stopPropagation(); toggleSelect(name); },
  });
  node.append(check);

  // Thumb
  const thumb = el("div", {class: "thumb-sm"});
  if (sp.has_processed) {
    thumb.append(el("img", {src: `/image/processed/${name}?t=${STATE.cacheBust}`, alt: name}));
  } else if (sp.has_raw) {
    thumb.append(el("img", {src: `/image/raw/${name}?t=${STATE.cacheBust}`, alt: name}));
  } else {
    thumb.append(el("div", {class: "placeholder", text: "none"}));
  }
  node.append(thumb);

  // Info block (name + meta + inline "also refs" for multi-parent nodes)
  const info = el("div", {class: "info"});
  info.append(el("div", {class: "name", text: name}));
  info.append(el("div", {class: "meta",
    text: `${sp.category} · ${sp.aspect} · bg:${sp.bg}`}));
  if (sp.refs && sp.refs.length > 1) {
    const refsInline = el("div", {class: "refs-inline"});
    refsInline.append(document.createTextNode("also refs: "));
    refsInline.append(el("span", {text: sp.refs.slice(1).join(", ")}));
    info.append(refsInline);
  }
  node.append(info);

  // Status badge
  node.append(el("span", {class: `tree-badge ${sp.status}`, text: sp.status}));

  // Subtree actions
  const actions = el("div", {class: "subtree-actions"});
  const descendants = countDescendants(name, primaryChildren);
  if (descendants > 0) {
    actions.append(el("button", {
      text: `↓ subtree (+${descendants})`,
      title: "Выделить этот узел и все транзитивные потомки по полному DAG. "
        + "Полезно после правки anchor'а — чтобы перегенерить всё, что от него зависит.",
      onclick: (ev) => { ev.stopPropagation(); selectSubtree(name); },
    }));
  }
  if (sp.refs && sp.refs.length > 0) {
    actions.append(el("button", {
      text: `↑ deps`,
      title: "Выделить все транзитивные refs (родители, дедушки ...). "
        + "Гарантирует, что к моменту генерации этого узла все зависимости уже готовы.",
      onclick: (ev) => { ev.stopPropagation(); selectAncestors(name); },
    }));
  }
  node.append(actions);

  // Whole-row click = open detail
  node.addEventListener("click", (ev) => {
    if (ev.target.closest(".tree-check, .subtree-actions")) return;
    showDetail(name);
  });

  container.append(node);

  // Recurse into primary children
  for (const child of children) renderTreeNode(container, child, primaryChildren, depth + 1);
}

// =============== / Dependency tree view ===============

function updateSelCount() {
  document.getElementById("selCount").textContent = `${STATE.selected.size} selected`;
}

async function showDetail(name) {
  STATE.detailName = name;
  switchTab("detail");
  const pane = document.getElementById("tab-detail");
  pane.innerHTML = "loading...";
  const r = await fetch(`/api/sprite/${encodeURIComponent(name)}`);
  if (!r.ok) { pane.innerHTML = "<div class='empty'>not found</div>"; return; }
  const d = await r.json();
  pane.innerHTML = "";
  pane.append(el("h3", {text: d.name}));
  const kv = el("div", {class: "kv"});
  const pair = (k, v) => { kv.append(el("span", {text: k})); kv.append(el("span", {text: String(v)})); };
  pair("category", d.category);
  pair("status", d.status);
  pair("view", d.view);
  pair("aspect", d.aspect);
  pair("bg", d.bg);
  pair("size", d.image_size);
  pair("refs", d.refs.length ? d.refs.join(", ") : "—");
  if (d.log_timestamp) pair("last gen", d.log_timestamp);
  pane.append(kv);

  if (d.has_raw || d.has_processed) {
    pane.append(el("h4", {text: "images"}));
    const imgs = el("div", {class: "imgs"});
    if (d.has_raw) {
      const fig = el("figure");
      fig.append(el("img", {src: `/image/raw/${d.name}?t=${STATE.cacheBust}`, alt: "raw"}));
      fig.append(el("figcaption", {text: "raw"}));
      imgs.append(fig);
    }
    if (d.has_processed) {
      const fig = el("figure");
      fig.append(el("img", {src: `/image/processed/${d.name}?t=${STATE.cacheBust}`, alt: "processed"}));
      fig.append(el("figcaption", {text: "processed"}));
      imgs.append(fig);
    }
    pane.append(imgs);
  }

  pane.append(el("h4", {text: "subject"}));
  pane.append(el("pre", {text: d.subject || "(empty)"}));
  if (d.palette) {
    pane.append(el("h4", {text: "palette"}));
    pane.append(el("pre", {text: d.palette}));
  }
  if (d.extra) {
    pane.append(el("h4", {text: "extra"}));
    pane.append(el("pre", {text: d.extra}));
  }
  const adv = el("details", {class: "advanced"});
  adv.append(el("summary", {text: "show assembled prompt"}));
  adv.append(el("pre", {text: d.prompt}));
  pane.append(adv);

  pane.append(el("h4", {text: "actions"}));
  const actions = el("div", {style: "display: flex; gap: 8px; flex-wrap: wrap; align-items: center;"});
  const addAction = (btn, tip) => {
    actions.append(btn);
    actions.append(el("span", {class: "help", "data-tip": tip, text: "i"}));
  };
  addAction(
    el("button", {
      class: "gen-btn", text: "generate (force)",
      onclick: () => runGenerate([d.name], {force: true}),
    }),
    "Перегенерировать именно этот спрайт через API (--force), независимо от текущего статуса. Тратит токены."
  );
  addAction(
    el("button", {
      class: "gen-btn", text: "post-process only",
      onclick: () => runGenerate([d.name], {skip_generation: true, reprocess: true}),
    }),
    "Только перепрогнать удаление фона и альфа-канал на существующем raw-файле. API не вызывается, токены не тратятся — полезно после правок алгоритма постобработки."
  );
  addAction(
    el("button", {
      class: "gen-btn", text: (STATE.selected.has(d.name) ? "deselect" : "select"),
      onclick: () => { toggleSelect(d.name); showDetail(d.name); },
    }),
    "Добавить этот спрайт в массовое выделение (или убрать из него). Массовую генерацию запускает кнопка ▶ сверху."
  );
  pane.append(actions);
}

function switchTab(key) {
  for (const b of document.querySelectorAll("aside .tabs button")) {
    b.classList.toggle("active", b.dataset.tab === key);
  }
  for (const d of document.querySelectorAll("aside .tab-content > div")) {
    d.classList.toggle("active", d.id === `tab-${key}`);
  }
}

document.querySelectorAll("aside .tabs button").forEach(b => {
  b.addEventListener("click", () => switchTab(b.dataset.tab));
});

// View toggle: grid | tree — swap the main-area renderer, everything else
// (filters, selection, generate) keeps working because renderGrid dispatches.
document.querySelectorAll("#viewToggle button").forEach(b => {
  b.addEventListener("click", () => {
    STATE.view = b.dataset.view;
    for (const sib of document.querySelectorAll("#viewToggle button")) {
      sib.classList.toggle("active", sib === b);
    }
    renderGrid();
  });
});

document.getElementById("selAll").addEventListener("click", () => {
  for (const sp of Object.values(STATE.sprites)) if (spriteMatchesFilter(sp)) STATE.selected.add(sp.name);
  renderGrid();
});
document.getElementById("selMissing").addEventListener("click", () => {
  STATE.selected.clear();
  for (const sp of Object.values(STATE.sprites)) if (spriteMatchesFilter(sp) && sp.status !== "complete") STATE.selected.add(sp.name);
  renderGrid();
});
document.getElementById("selNone").addEventListener("click", () => { STATE.selected.clear(); renderGrid(); });

function readOpts() {
  return {
    api_key: document.getElementById("apiKey").value || STATE.apiKeyStored,
    force: document.getElementById("force").checked,
    reprocess: document.getElementById("reprocess").checked,
    skip_generation: document.getElementById("skipGen").checked,
    seed: document.getElementById("seed").value || null,
    delay: parseFloat(document.getElementById("delay").value || "2") || 0,
    timeout: parseFloat(document.getElementById("timeout").value || "600") || 600,
    max_retries: parseInt(document.getElementById("maxRetries").value || "8") || 8,
  };
}

async function runGenerate(names, overrides = {}) {
  const opts = { ...readOpts(), ...overrides, names };
  if (opts.api_key) STATE.apiKeyStored = opts.api_key;
  // A key in the form field OR a server-side key (env / ~/.google-genai/config) is enough.
  // If neither is set and we're not in skip-generation, warn the user with the exact
  // config-file path so they know where to put the key.
  if (!opts.skip_generation && !opts.api_key && !STATE.hasServerKey) {
    const path = STATE.apiKeyConfigFile || "~/.google-genai/config";
    alert(
      "No API key configured. Either:\n" +
      "  • paste the key into the field at the top, or\n" +
      "  • edit " + path + " and restart the UI, or\n" +
      "  • tick skip-generation."
    );
    return;
  }
  switchTab("log");
  const r = await fetch("/api/generate", {
    method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify(opts),
  });
  const data = await r.json();
  if (!r.ok) { alert("error: " + (data.error || r.status)); return; }
}

document.getElementById("btnGen").addEventListener("click", () => {
  if (STATE.selected.size === 0) { alert("select at least one sprite first"); return; }
  runGenerate([...STATE.selected]);
});

// Cancel the currently running job. The server's cancel is non-violent — it
// stops BEFORE the next sprite, so the sprite in flight finishes on its own
// (or hits its deadline within ~3 min). The button disables itself after
// click so the user can't spam /api/cancel mid-request.
document.getElementById("btnCancel").addEventListener("click", async () => {
  const btn = document.getElementById("btnCancel");
  btn.disabled = true;
  btn.textContent = "cancelling...";
  try {
    const r = await fetch("/api/cancel", {method: "POST"});
    if (!r.ok) {
      const d = await r.json().catch(() => ({}));
      alert("cancel failed: " + (d.error || r.status));
      btn.disabled = false;
      btn.textContent = "■ cancel";
    }
  } catch (e) {
    alert("cancel error: " + e);
    btn.disabled = false;
    btn.textContent = "■ cancel";
  }
});

// --- live log via SSE ---
function colorizeLine(s) {
  const cls = /\[ERROR|\[FAIL|\[SERVER/.test(s) ? "err"
    : /\[WARN|\[RATE|\[CANCEL/.test(s) ? "warn"
    : /\[OK\]|processed ->|=== DONE/.test(s) ? "ok"
    : /\[SKIP|\[REF|\[DRY/.test(s) ? "dim"
    : "";
  return cls;
}
function appendLog(line) {
  const pane = document.getElementById("tab-log");
  const isAtBottom = pane.scrollTop + pane.clientHeight >= pane.scrollHeight - 10;
  const div = el("div", {class: "line " + colorizeLine(line), text: line});
  pane.append(div);
  if (pane.children.length > 2000) pane.removeChild(pane.firstChild);
  if (isAtBottom) pane.scrollTop = pane.scrollHeight;
}

function openStream() {
  const es = new EventSource("/api/stream");
  es.onmessage = e => { try { appendLog(JSON.parse(e.data)); } catch {} };
  es.onerror = () => { setTimeout(openStream, 2000); es.close(); };
}

async function pollStatus() {
  try {
    const r = await fetch("/api/status");
    const s = await r.json();
    const progEl = document.getElementById("progress");
    const prev = STATE.lastStatus;
    // Swap Generate ↔ Cancel depending on whether a job is active. The whole
    // header ".gen-btn.primary" stays in the DOM so layout doesn't jump.
    const btnGen = document.getElementById("btnGen");
    const btnCancel = document.getElementById("btnCancel");
    const btnCancelHelp = document.getElementById("btnCancelHelp");
    const isRunning = s.status === "running";
    btnGen.style.display = isRunning ? "none" : "";
    btnCancel.style.display = isRunning ? "" : "none";
    btnCancelHelp.style.display = isRunning ? "" : "none";
    if (!isRunning && btnCancel.disabled) {
      // Reset state for the next run
      btnCancel.disabled = false;
      btnCancel.textContent = "■ cancel";
    }
    // Reflect cancel_requested in the label so the user sees their click landed
    if (isRunning && s.cancel_requested && !btnCancel.disabled) {
      btnCancel.disabled = true;
      btnCancel.textContent = "cancelling...";
    }

    if (s.status === "running") {
      progEl.style.display = "block";
      const p = s.progress;
      const total = Math.max(1, p.total);
      const done = (p.done + p.failed + p.skipped);
      const suffix = s.cancel_requested ? " — cancelling after current" : "";
      document.getElementById("progressLabel").textContent =
        `running — ${s.current_sprite || "..."}` + suffix;
      document.getElementById("progressBar").style.width = (done / total * 100) + "%";
      document.getElementById("progressNums").textContent =
        `${done}/${total}  (ok:${p.done}  fail:${p.failed}  skip:${p.skipped})`;
    } else if (s.status === "done") {
      progEl.style.display = "block";
      document.getElementById("progressLabel").textContent = `done`;
      document.getElementById("progressBar").style.width = "100%";
      const p = s.progress;
      document.getElementById("progressNums").textContent =
        `total:${p.total}  ok:${p.done}  fail:${p.failed}  skip:${p.skipped}`;

      // Edge-trigger: only refresh sprites and detail panel on the
      // running→done transition. Previously ran every poll (1.5s), which
      // re-rendered all <img> tags with a fresh cache-buster and caused
      // constant thumbnail flicker.
      if (prev === "running") {
        STATE.cacheBust = Date.now();
        fetchSprites();
        if (STATE.detailName) showDetail(STATE.detailName);
      }
    } else if (s.status === "error") {
      progEl.style.display = "block";
      document.getElementById("progressLabel").textContent = "error";
    } else {
      progEl.style.display = "none";
    }

    STATE.lastStatus = s.status;
  } catch {}
}

setInterval(pollStatus, 1500);
openStream();
fetchSprites();
</script>
</body>
</html>
"""


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT,
                        help=f"Output directory (default: {DEFAULT_OUT})")
    parser.add_argument("--no-browser", action="store_true",
                        help="Don't try to open the browser automatically")
    args = parser.parse_args()

    global OUT_DIR
    OUT_DIR = args.out

    ensure_api_key_config_file()
    key_status = "set" if resolve_api_key() else "missing"

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    url = f"http://{args.host}:{args.port}/"
    print(f"\n  PVO sprite UI  →  {url}")
    print(f"  out dir:           {OUT_DIR}")
    print(f"  sprite registry:   {len(SPRITES)} entries")
    print(f"  api key config:    {API_KEY_CONFIG_FILE}  ({key_status})")
    print(f"  press Ctrl-C to stop\n")
    log(f"server started on {url}")

    if not args.no_browser:
        try:
            webbrowser.open(url)
        except Exception:
            pass

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nstopping...")
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())

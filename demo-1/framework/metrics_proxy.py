#!/usr/bin/env python3
"""
Lightweight metrics proxy for LLM inference endpoints.
Sits between Hermes agents and model backends, capturing:
- Time to First Token (TTFT)
- Tokens Per Second (TPS)
- Total tokens generated
- Request duration

Writes per-request metrics to a JSONL file and prints a summary on SIGINT/exit.

Usage:
    python3 metrics_proxy.py --listen 0.0.0.0:9100 --backend http://gpu-host:8080/v1 --label 27b --metrics-dir ./metrics
"""

import argparse
import json
import signal
import statistics
import sys
import threading
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import URLError
import io


class MetricsStore:
    def __init__(self, label: str, metrics_dir: Path):
        self.label = label
        self.metrics_dir = metrics_dir
        self.metrics_dir.mkdir(parents=True, exist_ok=True)
        self.jsonl_path = self.metrics_dir / f"{label}.jsonl"
        self.lock = threading.Lock()
        self.records = []
        # Clear previous run
        self.jsonl_path.write_text("")

    def record(self, entry: dict):
        entry["label"] = self.label
        entry["timestamp"] = time.time()
        with self.lock:
            self.records.append(entry)
            with open(self.jsonl_path, "a") as f:
                f.write(json.dumps(entry) + "\n")

    def summary(self) -> dict:
        with self.lock:
            recs = list(self.records)
        if not recs:
            return {"label": self.label, "request_count": 0}

        ttfts = [r["ttft_ms"] for r in recs if r.get("ttft_ms") is not None]
        tps_vals = [r["tps"] for r in recs if r.get("tps") is not None and r["tps"] > 0]
        durations = [r["duration_ms"] for r in recs if r.get("duration_ms") is not None]
        total_tokens = sum(r.get("completion_tokens", 0) for r in recs)

        def calc_stats(vals):
            if not vals:
                return {"min": None, "max": None, "median": None, "avg": None, "count": 0}
            return {
                "min": round(min(vals), 2),
                "max": round(max(vals), 2),
                "median": round(statistics.median(vals), 2),
                "avg": round(statistics.mean(vals), 2),
                "count": len(vals),
            }

        return {
            "label": self.label,
            "request_count": len(recs),
            "total_completion_tokens": total_tokens,
            "ttft_ms": calc_stats(ttfts),
            "tps": calc_stats(tps_vals),
            "duration_ms": calc_stats(durations),
        }


class ProxyHandler(BaseHTTPRequestHandler):
    backend_url = ""
    store = None

    def log_message(self, format, *args):
        pass  # Suppress default access logs

    def do_POST(self):
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length) if content_length > 0 else b""

        # Build backend URL
        target = self.backend_url.rstrip("/") + self.path

        # Check if client requested streaming
        try:
            req_json = json.loads(body) if body else {}
        except json.JSONDecodeError:
            req_json = {}

        is_stream = req_json.get("stream", False)

        # Disable Qwen3.5 thinking mode for reliable tool calling
        if "/chat/completions" in self.path:
            req_json["chat_template_kwargs"] = {"enable_thinking": False}

        # Force non-streaming for simpler metrics capture
        # (llama.cpp returns timings in non-stream responses)
        if is_stream:
            req_json["stream"] = False
        body = json.dumps(req_json).encode()

        # Forward request
        req = Request(target, data=body, method="POST")
        for key in ("Content-Type", "Authorization", "Accept"):
            val = self.headers.get(key)
            if val:
                req.add_header(key, val)

        t_start = time.time()
        try:
            resp = urlopen(req, timeout=300)
            resp_body = resp.read()
            t_end = time.time()
        except URLError as e:
            self.send_error(502, f"Backend error: {e}")
            return
        except Exception as e:
            self.send_error(500, f"Proxy error: {e}")
            return

        duration_ms = (t_end - t_start) * 1000

        # Parse response for metrics
        ttft_ms = None
        tps = None
        completion_tokens = None
        prompt_tokens = None

        try:
            resp_json = json.loads(resp_body)

            # llama.cpp includes timings directly
            timings = resp_json.get("timings", {})
            if timings:
                ttft_ms = timings.get("prompt_ms")
                tps = timings.get("predicted_per_second")
                completion_tokens = timings.get("predicted_n")
                prompt_tokens = timings.get("prompt_n")
            else:
                # Anthropic/OpenAI: estimate from usage + timing
                usage = resp_json.get("usage", {})
                completion_tokens = usage.get("completion_tokens")
                prompt_tokens = usage.get("prompt_tokens")
                if completion_tokens and completion_tokens > 0:
                    # Rough TPS estimate (includes prompt time for non-llama backends)
                    tps = completion_tokens / (duration_ms / 1000)
                    # No real TTFT available for non-streaming non-llama backends
                    ttft_ms = None
        except (json.JSONDecodeError, KeyError):
            pass

        # Record metrics
        self.store.record({
            "ttft_ms": round(ttft_ms, 2) if ttft_ms is not None else None,
            "tps": round(tps, 2) if tps is not None else None,
            "completion_tokens": completion_tokens,
            "prompt_tokens": prompt_tokens,
            "duration_ms": round(duration_ms, 2),
            "path": self.path,
        })

        # Always return as non-streaming JSON — the OpenAI SDK handles
        # receiving a non-stream response even when stream=True was requested.
        self.send_response(resp.status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(resp_body)))
        self.end_headers()
        self.wfile.write(resp_body)

    def do_GET(self):
        """Forward GET requests (e.g., /models)"""
        target = self.backend_url.rstrip("/") + self.path
        req = Request(target, method="GET")
        for key in ("Authorization", "Accept"):
            val = self.headers.get(key)
            if val:
                req.add_header(key, val)
        try:
            resp = urlopen(req, timeout=30)
            resp_body = resp.read()
            self.send_response(resp.status)
            self.send_header("Content-Type", resp.headers.get("Content-Type", "application/json"))
            self.end_headers()
            self.wfile.write(resp_body)
        except Exception as e:
            self.send_error(502, f"Backend error: {e}")


def run_proxy(listen_host, listen_port, backend_url, label, metrics_dir):
    store = MetricsStore(label, Path(metrics_dir))

    handler = type("Handler", (ProxyHandler,), {
        "backend_url": backend_url,
        "store": store,
    })

    server = HTTPServer((listen_host, listen_port), handler)
    print(f"📊 Metrics proxy [{label}] listening on {listen_host}:{listen_port} → {backend_url}")

    def shutdown(sig, frame):
        print(f"\n📈 Final metrics for [{label}]:")
        summary = store.summary()
        print(json.dumps(summary, indent=2))
        summary_path = Path(metrics_dir) / f"{label}_summary.json"
        summary_path.write_text(json.dumps(summary, indent=2))
        print(f"   Saved to {summary_path}")
        os._exit(0)

    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)

    server.serve_forever()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="LLM metrics proxy")
    parser.add_argument("--listen", default="127.0.0.1:9100", help="host:port to listen on")
    parser.add_argument("--backend", required=True, help="Backend URL (e.g., http://gpu-host:8080/v1)")
    parser.add_argument("--label", required=True, help="Label for this model (e.g., '27b')")
    parser.add_argument("--metrics-dir", default="./metrics", help="Directory for metrics output")
    args = parser.parse_args()

    host, port = args.listen.rsplit(":", 1)
    run_proxy(host, int(port), args.backend, args.label, args.metrics_dir)

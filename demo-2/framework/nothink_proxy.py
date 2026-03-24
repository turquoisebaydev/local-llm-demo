#!/usr/bin/env python3
"""
Minimal transparent proxy that injects chat_template_kwargs to disable
Qwen3.5 thinking mode. Passes everything else through untouched,
including streaming responses.

Usage:
    python3 nothink_proxy.py --listen 127.0.0.1:9101 --backend http://10.0.20.9:18080/v1
"""

import argparse
import json
import http.client
import signal
import sys
import os
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse


class ProxyHandler(BaseHTTPRequestHandler):
    backend_url = ""
    _parsed = None

    def log_message(self, format, *args):
        pass

    def _get_backend(self):
        p = urlparse(self.backend_url)
        return p.hostname, p.port or 80, p.path.rstrip("/")

    def _proxy(self, method):
        host, port, base_path = self._get_backend()
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length) if content_length > 0 else b""

        # Inject chat_template_kwargs for chat completions
        if method == "POST" and "/chat/completions" in self.path:
            try:
                req_json = json.loads(body)
                req_json["chat_template_kwargs"] = {"enable_thinking": False}
                body = json.dumps(req_json).encode()
            except (json.JSONDecodeError, UnicodeDecodeError):
                pass

        target_path = base_path + self.path
        conn = http.client.HTTPConnection(host, port, timeout=300)

        headers = {}
        for key in ("Content-Type", "Authorization", "Accept"):
            val = self.headers.get(key)
            if val:
                headers[key] = val
        headers["Content-Length"] = str(len(body))

        conn.request(method, target_path, body=body, headers=headers)
        resp = conn.getresponse()

        # Stream the response back transparently
        self.send_response(resp.status)
        for key, val in resp.getheaders():
            if key.lower() not in ("transfer-encoding",):
                self.send_header(key, val)
        self.end_headers()

        # Stream in chunks
        while True:
            chunk = resp.read(4096)
            if not chunk:
                break
            self.wfile.write(chunk)
        conn.close()

    def do_POST(self):
        self._proxy("POST")

    def do_GET(self):
        self._proxy("GET")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--listen", default="127.0.0.1:9101")
    parser.add_argument("--backend", required=True)
    args = parser.parse_args()

    host, port = args.listen.rsplit(":", 1)

    handler = type("H", (ProxyHandler,), {"backend_url": args.backend})
    server = HTTPServer((host, int(port)), handler)
    print(f"🔇 NoThink proxy on {args.listen} → {args.backend}")

    def stop(sig, frame):
        os._exit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    server.serve_forever()


if __name__ == "__main__":
    main()

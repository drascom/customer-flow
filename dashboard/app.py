#!/usr/bin/env python3
"""Customer Flow web client and same-origin API gateway."""

import argparse
import json
import mimetypes
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


MAX_BODY_BYTES = 25 * 1024 * 1024
FORWARDED_HEADERS = (
    "Authorization", "Content-Type", "Idempotency-Key", "X-Message-Text",
    "If-None-Match", "Accept",
)


class DashboardServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, admin_dir, api_url):
        super().__init__(address, DashboardHandler)
        self.admin_dir = Path(admin_dir).resolve()
        self.api_url = api_url.rstrip("/")


class DashboardHandler(BaseHTTPRequestHandler):
    server_version = "CustomerFlowWeb/2.0"

    def do_GET(self):
        if self.path in {"/", "/admin", "/admin/"}:
            return self._serve_asset("index.html", "text/html; charset=utf-8")
        if self.path in {"/admin/admin.css", "/admin/admin.js"}:
            return self._serve_asset(self.path.rsplit("/", 1)[-1])
        if self.path == "/dashboard/health":
            return self._json(200, {"status": "ok", "service": "customer-flow-dashboard"})
        return self._proxy("GET") if self.path.startswith("/api/v1/") else self._not_found()

    def do_POST(self):
        return self._proxy_mutation("POST")

    def do_PATCH(self):
        return self._proxy_mutation("PATCH")

    def do_DELETE(self):
        return self._proxy_mutation("DELETE")

    def _proxy_mutation(self, method):
        if not self.path.startswith("/api/v1/"):
            return self._not_found()
        if not self._same_origin():
            return self._json(403, {"error": {"message": "Cross-origin requests are not allowed."}})
        return self._proxy(method)

    def _same_origin(self):
        origin = self.headers.get("Origin")
        if not origin:
            return True
        host = self.headers.get("Host", "")
        return origin in {f"http://{host}", f"https://{host}"}

    def _read_body(self):
        length = int(self.headers.get("Content-Length", "0") or 0)
        if length > MAX_BODY_BYTES:
            raise ValueError("Request body is too large")
        return self.rfile.read(length) if length else None

    def _proxy(self, method):
        try:
            body = self._read_body()
            headers = {key: self.headers[key] for key in FORWARDED_HEADERS if self.headers.get(key)}
            request = Request(f"{self.server.api_url}{self.path}", data=body, headers=headers, method=method)
            try:
                response = urlopen(request, timeout=45)
            except HTTPError as error:
                response = error
            payload = response.read()
            self.send_response(response.status)
            self._security_headers()
            self.send_header("Content-Type", response.headers.get("Content-Type", "application/octet-stream"))
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        except ValueError as error:
            self._json(413, {"error": {"message": str(error)}})
        except (URLError, RuntimeError, OSError) as error:
            self._json(502, {"error": {"message": f"Customer Flow API unavailable: {error}"}})

    def _serve_asset(self, filename, forced_type=None):
        path = (self.server.admin_dir / filename).resolve()
        if path.parent != self.server.admin_dir or not path.is_file():
            return self._not_found()
        content_type = forced_type or mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        if content_type.startswith(("text/", "application/javascript")) and "charset" not in content_type:
            content_type += "; charset=utf-8"
        self._send_bytes(200, content_type, path.read_bytes())

    def _send_bytes(self, status, content_type, content):
        self.send_response(status)
        self._security_headers()
        self.send_header("Content-Type", content_type)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(content)))
        self.end_headers()
        self.wfile.write(content)

    def _json(self, status, payload):
        self._send_bytes(status, "application/json; charset=utf-8", json.dumps(payload).encode())

    def _not_found(self):
        self._json(404, {"error": {"message": "Not found"}})

    def _security_headers(self):
        self.send_header("Content-Security-Policy", "default-src 'self'; connect-src 'self'; img-src 'self' data: blob:; style-src 'self'; script-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Referrer-Policy", "no-referrer")

    def log_message(self, fmt, *args):
        print(f"{self.address_string()} - {fmt % args}")


def create_server(host, port, api_url, admin_dir, *_legacy):
    return DashboardServer((host, port), admin_dir, api_url)


def main():
    parser = argparse.ArgumentParser(description="Customer Flow role-based web client")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=80)
    parser.add_argument("--api-url", default="http://127.0.0.1:8080")
    parser.add_argument("--admin-dir", default=str(Path(__file__).resolve().parents[1] / "admin-panel"))
    args = parser.parse_args()
    server = create_server(args.host, args.port, args.api_url, args.admin_dir)
    print(f"Customer Flow web client listening on http://{args.host}:{args.port}")
    server.serve_forever()


if __name__ == "__main__":
    main()

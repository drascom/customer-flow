#!/usr/bin/env python3
"""Private staging dashboard with a server-side Customer Flow admin session."""

import argparse
import base64
import hmac
import json
import mimetypes
import os
import re
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


MAX_BODY_BYTES = 2 * 1024 * 1024
ALLOWED_ROUTES = {
    "GET": (
        re.compile(r"^/api/v1/admin/(?:users|agencies|cases)(?:\?.*)?$"),
        re.compile(r"^/api/v1/admin/agencies/[A-Za-z0-9-]+/mcp$"),
        re.compile(r"^/api/v1/(?:photos|message-photos)/[A-Za-z0-9-]+(?:\?.*)?$"),
        re.compile(r"^/api/v1/health(?:\?.*)?$"),
    ),
    "POST": (
        re.compile(r"^/api/v1/admin/(?:users|agencies)$"),
        re.compile(r"^/api/v1/admin/agencies/[A-Za-z0-9-]+/mcp/rotate$"),
    ),
    "PATCH": (
        re.compile(r"^/api/v1/admin/(?:users|agencies|patients)/[A-Za-z0-9-]+$"),
    ),
    "DELETE": (
        re.compile(r"^/api/v1/admin/(?:users|photos|cases)/[A-Za-z0-9-]+$"),
    ),
}


class AdminAPIClient:
    def __init__(self, api_url, username, password):
        self.api_url = api_url.rstrip("/")
        self.username = username
        self.password = password
        self.token = None
        self.lock = threading.Lock()

    def _login_locked(self):
        body = json.dumps({"username": self.username, "password": self.password}).encode()
        request = Request(
            f"{self.api_url}/api/v1/auth/login",
            data=body,
            headers={"Accept": "application/json", "Content-Type": "application/json"},
            method="POST",
        )
        with urlopen(request, timeout=10) as response:
            payload = json.load(response)
        if payload.get("user", {}).get("role") != "admin":
            raise RuntimeError("Dashboard credentials must belong to an admin account")
        self.token = payload["token"]

    def token_value(self, refresh=False):
        with self.lock:
            if refresh or not self.token:
                self._login_locked()
            return self.token

    def request(self, method, path, body, content_type):
        for attempt in range(2):
            token = self.token_value(refresh=attempt == 1)
            headers = {"Accept": "application/json", "Authorization": f"Bearer {token}"}
            if content_type:
                headers["Content-Type"] = content_type
            request = Request(f"{self.api_url}{path}", data=body, headers=headers, method=method)
            try:
                with urlopen(request, timeout=30) as response:
                    return response.status, response.headers.get("Content-Type"), response.read()
            except HTTPError as error:
                payload = error.read()
                if error.code == 401 and attempt == 0:
                    continue
                return error.code, error.headers.get("Content-Type"), payload
        raise RuntimeError("Could not establish an admin API session")


class DashboardServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, admin_dir, api_client, dashboard_pin):
        super().__init__(address, DashboardHandler)
        self.admin_dir = Path(admin_dir).resolve()
        self.api_client = api_client
        self.dashboard_pin = dashboard_pin


class DashboardHandler(BaseHTTPRequestHandler):
    server_version = "CustomerFlowDashboard/1.0"

    def do_GET(self):
        if not self._authorized():
            return self._request_pin()
        if self.path in {"/", "/admin", "/admin/"}:
            return self._serve_index()
        if self.path in {"/admin/admin.css", "/admin/admin.js"}:
            return self._serve_asset(self.path.rsplit("/", 1)[-1])
        if self.path == "/dashboard/health":
            return self._json(200, {"status": "ok", "service": "customer-flow-dashboard"})
        return self._proxy("GET") if self._route_allowed("GET") else self._not_found()

    def do_POST(self):
        if not self._authorized():
            return self._request_pin()
        return self._proxy_mutation("POST")

    def do_PATCH(self):
        if not self._authorized():
            return self._request_pin()
        return self._proxy_mutation("PATCH")

    def do_DELETE(self):
        if not self._authorized():
            return self._request_pin()
        return self._proxy_mutation("DELETE")

    def _authorized(self):
        header = self.headers.get("Authorization", "")
        if not header.startswith("Basic "):
            return False
        try:
            username, pin = base64.b64decode(header[6:], validate=True).decode("utf-8").split(":", 1)
        except (ValueError, UnicodeDecodeError):
            return False
        return hmac.compare_digest(username, "admin") and hmac.compare_digest(pin, self.server.dashboard_pin)

    def _request_pin(self):
        payload = b"Customer Flow dashboard PIN required."
        self.send_response(401)
        self._security_headers()
        self.send_header("WWW-Authenticate", 'Basic realm="Customer Flow Admin", charset="UTF-8"')
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def _proxy_mutation(self, method):
        if not self._route_allowed(method):
            return self._not_found()
        if not self._same_origin():
            return self._json(403, {"error": {"message": "Cross-origin requests are not allowed."}})
        return self._proxy(method)

    def _route_allowed(self, method):
        return any(pattern.fullmatch(self.path) for pattern in ALLOWED_ROUTES.get(method, ()))

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
            status, content_type, payload = self.server.api_client.request(
                method, self.path, body, self.headers.get("Content-Type")
            )
            self.send_response(status)
            self._security_headers()
            self.send_header("Content-Type", content_type or "application/octet-stream")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        except ValueError as error:
            self._json(413, {"error": {"message": str(error)}})
        except (URLError, RuntimeError, OSError) as error:
            self._json(502, {"error": {"message": f"Admin API unavailable: {error}"}})

    def _serve_index(self):
        path = self.server.admin_dir / "index.html"
        try:
            content = path.read_text(encoding="utf-8")
            content = content.replace("<body>", '<body data-direct-admin="true">', 1)
            content = content.replace('<main id="loginView"', '<main id="loginView" hidden', 1)
            content = content.replace('<div id="appView" class="app-shell" hidden>', '<div id="appView" class="app-shell">', 1)
            content = content.encode()
        except OSError:
            return self._not_found()
        self._send_bytes(200, "text/html; charset=utf-8", content)

    def _serve_asset(self, filename):
        path = self.server.admin_dir / filename
        if path.parent != self.server.admin_dir or not path.is_file():
            return self._not_found()
        content_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        self._send_bytes(200, f"{content_type}; charset=utf-8", path.read_bytes())

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
        self.send_header("Content-Security-Policy", "default-src 'self'; connect-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Referrer-Policy", "no-referrer")

    def log_message(self, fmt, *args):
        print(f"{self.address_string()} - {fmt % args}")


def create_server(host, port, api_url, admin_dir, username, password, dashboard_pin):
    return DashboardServer(
        (host, port),
        admin_dir,
        AdminAPIClient(api_url, username, password),
        dashboard_pin,
    )


def main():
    parser = argparse.ArgumentParser(description="Customer Flow private admin dashboard")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=80)
    parser.add_argument("--api-url", default="http://127.0.0.1:8080")
    parser.add_argument("--admin-dir", default=str(Path(__file__).resolve().parents[1] / "admin-panel"))
    args = parser.parse_args()
    username = os.environ.get("CF_DASHBOARD_ADMIN_USERNAME", "admin")
    password = os.environ.get("CF_DASHBOARD_ADMIN_PASSWORD", "demo123")
    dashboard_pin = os.environ.get("CF_DASHBOARD_PIN")
    if not dashboard_pin:
        raise SystemExit("CF_DASHBOARD_PIN must be set")
    server = create_server(args.host, args.port, args.api_url, args.admin_dir, username, password, dashboard_pin)
    print(f"Customer Flow dashboard listening on http://{args.host}:{args.port}")
    server.serve_forever()


if __name__ == "__main__":
    main()

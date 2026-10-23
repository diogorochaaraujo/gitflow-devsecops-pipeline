"""Aplicacao de exemplo: responde `/` e `/health` com a versao em execucao."""

import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

VERSION = os.environ.get("APP_VERSION", "dev")
ENVIRONMENT = os.environ.get("APP_ENV", "local")

SECURITY_HEADERS = {
    "Content-Type": "application/json",
    "Cache-Control": "no-store",
    "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'",
    "X-Content-Type-Options": "nosniff",
    "Cross-Origin-Resource-Policy": "same-origin",
}


def route(path):
    if path == "/health":
        return 200, {"status": "ok", "version": VERSION}
    if path == "/":
        return 200, {"app": "web-api", "version": VERSION, "env": ENVIRONMENT}
    return 404, {"error": "not found"}


class Handler(BaseHTTPRequestHandler):
    server_version = "web-api"
    sys_version = ""

    def do_GET(self):
        status, body = route(self.path)
        data = json.dumps(body).encode()
        self.send_response(status)
        for name, value in SECURITY_HEADERS.items():
            self.send_header(name, value)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8080"))
    HTTPServer(("0.0.0.0", port), Handler).serve_forever()

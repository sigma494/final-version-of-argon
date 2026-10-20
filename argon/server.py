"""argon/server.py - the local web UI, standard library only.

Threat model for a local web app
--------------------------------
* Any page in your browser can send requests to 127.0.0.1, so every /api call
  must carry a random per-process token (`X-Argon-Token`). The token is printed
  on startup and embedded in the URL you open. Cross-site requests cannot read it.
* The vault password and key live only in this process's memory. Locking drops
  the key and every decrypted entry.
* Request bodies are capped, JSON only, and every handler validates types.
* Bind to 127.0.0.1 by default. `--host 0.0.0.0` is available for containers and
  sandboxes but then the token is the only thing standing between the network
  and your vault - it is long and random, but treat that choice accordingly.
"""

from __future__ import annotations

import json
import mimetypes
import os
import sys
import threading
import webbrowser
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

from argon import crypto, generator, totp
from argon.vault import ArgonError, BadPasswordError, Entry, EntryNotFound, Vault, VaultExistsError

WEB_DIR = Path(__file__).resolve().parent / "web"
MAX_BODY = 64 * 1024
API_PREFIX = "/api/"

CONTENT_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".svg": "image/svg+xml",
    ".ico": "image/x-icon",
    ".json": "application/json; charset=utf-8",
}


class AppState:
    """Process-wide vault session. One unlocked vault at a time."""

    def __init__(self, path: Path) -> None:
        self.path = path
        self.token = crypto.random_token(24)
        self.vault: Vault | None = None
        self.lock = threading.RLock()
        self.failures = 0
        self.last_failure = 0.0

    def status(self) -> dict[str, Any]:
        vault = self.vault
        return {
            "exists": self.path.exists(),
            "unlocked": vault is not None and vault.is_unlocked,
            "path": str(self.path),
            "count": len(vault) if vault else 0,
            "needs_kdf_upgrade": bool(vault and vault.needs_kdf_upgrade),
        }

    def require(self) -> Vault:
        if self.vault is None or not self.vault.is_unlocked:
            raise ApiError(HTTPStatus.UNAUTHORIZED, "vault is locked")
        return self.vault


class ApiError(Exception):
    def __init__(self, status: HTTPStatus, message: str) -> None:
        super().__init__(message)
        self.status = status
        self.message = message


class Handler(BaseHTTPRequestHandler):
    server_version = "Argon/1.0"
    sys_version = ""
    protocol_version = "HTTP/1.1"

    # -- plumbing ------------------------------------------------------
    @property
    def state(self) -> AppState:
        return self.server.state  # type: ignore[attr-defined]

    def log_message(self, fmt: str, *args: Any) -> None:  # quieter, no secrets in logs
        sys.stderr.write("[argon] %s - %s\n" % (self.address_string(), fmt % args))

    def _send(self, status: HTTPStatus | int, body: bytes, content_type: str, extra: dict[str, str] | None = None) -> None:
        self.send_response(int(status))
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "SAMEORIGIN")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header(
            "Content-Security-Policy",
            "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; "
            "connect-src 'self'; frame-ancestors 'self'; base-uri 'none'; form-action 'none'",
        )
        for key, value in (extra or {}).items():
            self.send_header(key, value)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def json(self, payload: Any, status: HTTPStatus = HTTPStatus.OK) -> None:
        blob = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self._send(status, blob, "application/json; charset=utf-8")

    def error(self, status: HTTPStatus, message: str) -> None:
        self.close_connection = True
        blob = json.dumps({"error": message}).encode("utf-8")
        self.send_response(int(status))
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(blob)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "close")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(blob)

    def read_json(self) -> dict[str, Any]:
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            raise ApiError(HTTPStatus.BAD_REQUEST, "bad Content-Length")
        if length <= 0:
            return {}
        if length > MAX_BODY:
            raise ApiError(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, "request body too large")
        raw = self.rfile.read(length)
        try:
            data = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            raise ApiError(HTTPStatus.BAD_REQUEST, "body must be JSON")
        if not isinstance(data, dict):
            raise ApiError(HTTPStatus.BAD_REQUEST, "body must be a JSON object")
        return data

    def check_token(self) -> None:
        supplied = self.headers.get("X-Argon-Token", "")
        if not supplied or not crypto.secure_compare(supplied.encode(), self.state.token.encode()):
            raise ApiError(HTTPStatus.FORBIDDEN, "invalid or missing session token")

    # -- HTTP verbs ----------------------------------------------------
    def do_GET(self) -> None:  # noqa: N802
        self._dispatch("GET")

    def do_HEAD(self) -> None:  # noqa: N802
        self._dispatch("GET")

    def do_POST(self) -> None:  # noqa: N802
        self._dispatch("POST")

    def do_PUT(self) -> None:  # noqa: N802
        self._dispatch("PUT")

    def do_DELETE(self) -> None:  # noqa: N802
        self._dispatch("DELETE")

    LOOPBACK_HOSTS = {"127.0.0.1", "localhost", "::1", "[::1]"}

    def host_allowed(self) -> bool:
        if not getattr(self.server, "strict_host", False):
            return True
        host = (self.headers.get("Host") or "").split(":")[0].strip().lower()
        return host in self.LOOPBACK_HOSTS

    def _dispatch(self, method: str) -> None:
        parsed = urlparse(self.path)
        path = parsed.path
        try:
            if not self.host_allowed():
                raise ApiError(HTTPStatus.FORBIDDEN, "unexpected Host header (DNS rebinding defence)")
            if path.startswith(API_PREFIX):
                self.check_token()
                self.handle_api(method, path[len(API_PREFIX):], parse_qs(parsed.query))
            elif method == "GET":
                self.serve_static(path)
            else:
                self.error(HTTPStatus.METHOD_NOT_ALLOWED, "method not allowed")
        except ApiError as exc:
            self.error(exc.status, exc.message)
        except BadPasswordError as exc:
            self.error(HTTPStatus.UNAUTHORIZED, str(exc))
        except EntryNotFound as exc:
            self.error(HTTPStatus.NOT_FOUND, str(exc))
        except (ValueError, ArgonError) as exc:
            self.error(HTTPStatus.BAD_REQUEST, str(exc))
        except BrokenPipeError:
            pass
        except Exception as exc:  # never leak a traceback to the client
            self.log_message("unhandled error: %r", exc)
            self.error(HTTPStatus.INTERNAL_SERVER_ERROR, "internal error")

    # -- static --------------------------------------------------------
    def serve_static(self, path: str) -> None:
        relative = "index.html" if path in {"", "/"} else path.lstrip("/")
        target = (WEB_DIR / relative).resolve()
        if WEB_DIR not in target.parents and target != WEB_DIR:
            self.error(HTTPStatus.FORBIDDEN, "forbidden")
            return
        if not target.is_file():
            self.error(HTTPStatus.NOT_FOUND, "not found")
            return
        body = target.read_bytes()
        ctype = CONTENT_TYPES.get(target.suffix, mimetypes.guess_type(str(target))[0] or "application/octet-stream")
        if target.name == "index.html":
            body = body.replace(b"__ARGON_TOKEN__", self.state.token.encode())
        self._send(HTTPStatus.OK, body, ctype)

    # -- api -----------------------------------------------------------
    def handle_api(self, method: str, route: str, query: dict[str, list[str]]) -> None:
        route = route.strip("/")
        parts = route.split("/") if route else []

        if method == "GET" and route == "status":
            self.json(self.state.status())
            return

        if method == "POST" and route == "unlock":
            self.api_unlock()
            return

        if method == "POST" and route == "lock":
            with self.state.lock:
                if self.state.vault:
                    self.state.vault.close()
                self.state.vault = None
            self.json({"ok": True})
            return

        if method == "POST" and route == "init":
            self.api_init()
            return

        if method == "POST" and route == "generate":
            body = self.read_json()
            length = int(body.get("length", 20))
            length = max(8, min(length, 256))
            password = generator.generate_password(
                length,
                upper=bool(body.get("upper", True)),
                lower=bool(body.get("lower", True)),
                digits=bool(body.get("digits", True)),
                symbols=bool(body.get("symbols", True)),
                exclude_ambiguous=bool(body.get("exclude_ambiguous", False)),
            )
            self.json({"password": password, "strength": generator.password_strength(password).as_dict()})
            return

        if method == "GET" and route == "entries":
            vault = self.state.require()
            q = (query.get("q") or [""])[0]
            tag = (query.get("tag") or [""])[0]
            entries = vault.search(q, tag)
            self.json({"entries": [e.to_public_dict() for e in entries]})
            return

        if method == "POST" and route == "entries":
            vault = self.state.require()
            body = self.read_json()
            entry = Entry(
                name=str(body.get("name", "")),
                username=str(body.get("username", "")),
                password=str(body.get("password", "")),
                url=str(body.get("url", "")),
                notes=str(body.get("notes", "")),
                totp=str(body.get("totp", "")),
                tags=_tags(body.get("tags")),
            )
            if entry.totp:
                totp.normalize_secret(entry.totp)
            with self.state.lock:
                vault.add(entry)
                vault.save()
            self.json({"entry": entry.to_public_dict()}, HTTPStatus.CREATED)
            return

        if len(parts) == 2 and parts[0] == "entries":
            entry_id = parts[1]

            if method == "GET":
                vault = self.state.require()
                entry = vault.get(entry_id)
                self.json({"entry": {**entry.to_public_dict(), **{
                    "password": entry.password,
                    "notes": entry.notes,
                }}})
                return

            if method == "PUT":
                vault = self.state.require()
                body = self.read_json()
                fields: dict[str, Any] = {}
                for key in ("name", "username", "password", "url", "notes", "totp"):
                    if key in body:
                        fields[key] = str(body[key])
                if "tags" in body:
                    fields["tags"] = _tags(body["tags"])
                if fields.get("totp"):
                    totp.normalize_secret(fields["totp"])
                with self.state.lock:
                    entry = vault.update(entry_id, **fields)
                    vault.save()
                self.json({"entry": entry.to_public_dict()})
                return

            if method == "DELETE":
                vault = self.state.require()
                with self.state.lock:
                    entry = vault.delete(entry_id)
                    vault.save()
                self.json({"deleted": entry.id})
                return

        if method == "GET" and len(parts) == 3 and parts[0] == "entries" and parts[2] == "totp":
            vault = self.state.require()
            entry = vault.get(parts[1])
            if not entry.totp:
                raise ApiError(HTTPStatus.NOT_FOUND, "this entry has no TOTP secret")
            self.json({
                "code": totp.totp(entry.totp),
                "remaining": totp.totp_remaining(),
                "period": 30,
            })
            return

        if method == "GET" and route == "audit":
            vault = self.state.require()
            ok, message = vault.verify_audit_chain()
            self.json({"ok": ok, "message": message, "records": vault.audit[-100:]})
            return

        raise ApiError(HTTPStatus.NOT_FOUND, "unknown endpoint")

    def api_unlock(self) -> None:
        with self.state.lock:
            body = self.read_json()
            password = str(body.get("password", ""))
            if not password:
                raise ApiError(HTTPStatus.BAD_REQUEST, "password required")
            if not self.state.path.exists():
                raise ApiError(HTTPStatus.NOT_FOUND, "no vault yet - create one first")
            self.state.vault = Vault.open(self.state.path, password)
        self.json(self.state.status())

    def api_init(self) -> None:
        with self.state.lock:
            body = self.read_json()
            password = str(body.get("password", ""))
            confirm = str(body.get("confirm", password))
            if not password or len(password) < 8:
                raise ApiError(HTTPStatus.BAD_REQUEST, "master password must be at least 8 characters")
            if password != confirm:
                raise ApiError(HTTPStatus.BAD_REQUEST, "passwords do not match")
            if self.state.path.exists():
                raise VaultExistsError("a vault already exists at this path")
            self.state.vault = Vault.create(self.state.path, password)
        self.json(self.state.status())


def _tags(value: Any) -> list[str]:
    if isinstance(value, list):
        return [str(t).strip() for t in value if str(t).strip()]
    if isinstance(value, str):
        return [t.strip() for t in value.split(",") if t.strip()]
    return []


def serve(path: Path, host: str = "127.0.0.1", port: int = 8420, open_browser: bool = False) -> int:
    state = AppState(path)
    httpd = ThreadingHTTPServer((host, port), Handler)
    httpd.daemon_threads = True
    httpd.state = state  # type: ignore[attr-defined]
    httpd.strict_host = host in {"127.0.0.1", "localhost", "::1"}  # type: ignore[attr-defined]

    url = f"http://{'127.0.0.1' if host in {'0.0.0.0', '::'} else host}:{port}/?token={state.token}"
    print(f"Argon UI  ->  {url}", flush=True)
    print(f"vault     ->  {path} ({'exists' if path.exists() else 'not created yet'})", flush=True)
    print(f"token     ->  {state.token} (required in X-Argon-Token for every /api call)", flush=True)
    if host not in {"127.0.0.1", "localhost", "::1"}:
        print(
            "warning: bound to a non-loopback address; anyone who learns the token can try the vault",
            flush=True,
        )
    print("press Ctrl+C to stop", flush=True)
    if open_browser:
        threading.Timer(0.5, lambda: webbrowser.open(url)).start()
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nshutting down")
    finally:
        if state.vault:
            state.vault.close()
        httpd.server_close()
    return 0


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Run the Argon web UI")
    parser.add_argument("--vault", default=str(Path.home() / ".argon" / "vault.json"))
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8420)
    parser.add_argument("--open", action="store_true")
    ns = parser.parse_args()
    raise SystemExit(serve(Path(ns.vault).expanduser(), ns.host, ns.port, ns.open))

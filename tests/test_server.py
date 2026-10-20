"""tests/test_server.py - end-to-end tests against the real HTTP server."""

from __future__ import annotations

import json
import threading
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer

import pytest

from argon.server import AppState, Handler


@pytest.fixture()
def server(tmp_path):
    state = AppState(tmp_path / "vault.json")
    httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    httpd.state = state  # type: ignore[attr-defined]
    httpd.strict_host = True  # type: ignore[attr-defined]
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    base = f"http://127.0.0.1:{httpd.server_address[1]}"
    try:
        yield base, state
    finally:
        httpd.shutdown()
        httpd.server_close()
        thread.join(timeout=5)


def call(base, state, path, method="GET", body=None, token=True):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(base + path, data=data, method=method)
    if token:
        request.add_header("X-Argon-Token", state.token)
    if data:
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            return response.status, json.loads(response.read() or b"{}")
    except urllib.error.HTTPError as exc:
        return exc.code, json.loads(exc.read() or b"{}")


def test_requires_token(server):
    base, state = server
    status, _ = call(base, state, "/api/status", token=False)
    assert status == 403


def test_full_lifecycle(server):
    base, state = server

    status, body = call(base, state, "/api/status")
    assert status == 200 and body["exists"] is False

    # too-short password is rejected
    status, body = call(base, state, "/api/init", "POST", {"password": "short"})
    assert status == 400

    status, body = call(base, state, "/api/init", "POST", {"password": "a good long password"})
    assert status == 200 and body["unlocked"] is True

    status, body = call(base, state, "/api/entries", "POST", {
        "name": "GitHub", "username": "octocat", "password": "hunter2", "tags": "dev,work",
    })
    assert status == 201
    entry_id = body["entry"]["id"]
    assert body["entry"]["has_password"] is True
    assert "password" not in body["entry"]

    status, body = call(base, state, "/api/entries")
    assert len(body["entries"]) == 1

    status, body = call(base, state, f"/api/entries/{entry_id}")
    assert body["entry"]["password"] == "hunter2"

    status, body = call(base, state, f"/api/entries/{entry_id}", "PUT", {"notes": "2fa on"})
    assert status == 200

    status, body = call(base, state, f"/api/entries/{entry_id}", "DELETE")
    assert status == 200
    status, body = call(base, state, "/api/entries")
    assert body["entries"] == []


def test_duplicate_name_is_400(server):
    base, state = server
    call(base, state, "/api/init", "POST", {"password": "a good long password"})
    call(base, state, "/api/entries", "POST", {"name": "Mail"})
    status, body = call(base, state, "/api/entries", "POST", {"name": "mail"})
    assert status == 400 and "already exists" in body["error"]


def test_lock_and_unlock(server):
    base, state = server
    call(base, state, "/api/init", "POST", {"password": "a good long password"})
    call(base, state, "/api/lock", "POST")
    status, _ = call(base, state, "/api/entries")
    assert status == 401

    status, _ = call(base, state, "/api/unlock", "POST", {"password": "wrong password"})
    assert status == 401

    status, _ = call(base, state, "/api/unlock", "POST", {"password": "a good long password"})
    assert status == 200


def test_totp_and_generate(server):
    base, state = server
    call(base, state, "/api/init", "POST", {"password": "a good long password"})
    status, body = call(base, state, "/api/entries", "POST", {
        "name": "Auth", "totp": "JBSWY3DPEHPK3PXP",
    })
    entry_id = body["entry"]["id"]
    assert body["entry"]["has_totp"] is True

    status, body = call(base, state, f"/api/entries/{entry_id}/totp")
    assert status == 200 and len(body["code"]) == 6 and 0 < body["remaining"] <= 30

    status, body = call(base, state, "/api/generate", "POST", {"length": 32, "symbols": False})
    assert len(body["password"]) == 32 and body["strength"]["bits"] > 100


def test_audit_endpoint(server):
    base, state = server
    call(base, state, "/api/init", "POST", {"password": "a good long password"})
    call(base, state, "/api/entries", "POST", {"name": "X"})
    status, body = call(base, state, "/api/audit")
    assert status == 200 and body["ok"] is True
    assert any(r["action"] == "add" for r in body["records"])


def test_unknown_endpoint_and_bad_json(server):
    base, state = server
    status, _ = call(base, state, "/api/nope")
    assert status == 404
    request = urllib.request.Request(base + "/api/unlock", data=b"not json", method="POST")
    request.add_header("X-Argon-Token", state.token)
    with pytest.raises(urllib.error.HTTPError) as info:
        urllib.request.urlopen(request, timeout=5)
    assert info.value.code in (400, 404, 401)


def test_index_injects_token(server):
    base, state = server
    with urllib.request.urlopen(base + "/", timeout=10) as response:
        html = response.read().decode()
    assert state.token in html
    assert "__ARGON_TOKEN__" not in html
    assert "Content-Security-Policy" in response.headers


def test_path_traversal_blocked(server):
    base, state = server
    try:
        with urllib.request.urlopen(base + "/../argon/server.py", timeout=5) as response:
            body = response.read()
        assert b"import" not in body[:200]
    except urllib.error.HTTPError as exc:
        assert exc.code in (403, 404)

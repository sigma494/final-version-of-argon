"""tests/test_cli.py - the CLI wired end to end through main()."""

from __future__ import annotations

import json

import pytest

from argon.cli import main

PW = "an adequately long passphrase"


@pytest.fixture()
def env(tmp_path, monkeypatch):
    vault = tmp_path / "vault.json"
    monkeypatch.setenv("ARGON_VAULT", str(vault))
    monkeypatch.setenv("ARGON_MASTER_PASSWORD", PW)
    return vault


def test_init_add_get_list(env, capsys):
    assert main(["init"]) == 0
    assert env.exists()
    capsys.readouterr()

    assert main(["add", "GitHub", "-u", "octocat", "-p", "hunter2", "--url", "https://github.com",
                 "--tags", "dev,work"]) == 0
    assert main(["add", "Bank", "-g", "24", "--tags", "money"]) == 0
    capsys.readouterr()

    # non-interactive with no password source is a clean error, not a hang
    assert main(["add", "Silent"]) == 1
    assert "no password supplied" in capsys.readouterr().err

    assert main(["get", "GitHub", "-s"]) == 0
    out = capsys.readouterr().out
    assert "hunter2" in out and "octocat" in out

    assert main(["get", "GitHub", "-f", "password"]) == 0
    assert capsys.readouterr().out.strip() == "hunter2"

    assert main(["list", "--long"]) == 0
    out = capsys.readouterr().out
    assert "GitHub" in out and "2 entries" in out


def test_wrong_password_exit_code(env, monkeypatch, capsys):
    main(["init"])
    monkeypatch.setenv("ARGON_MASTER_PASSWORD", "definitely wrong")
    assert main(["list"]) == 1
    assert "wrong master password" in capsys.readouterr().err


def test_missing_entry(env, capsys):
    main(["init"])
    assert main(["get", "Nope"]) == 1
    assert "no entry matching" in capsys.readouterr().err


def test_gen_and_strength(capsys):
    assert main(["gen", "-l", "24"]) == 0
    assert len(capsys.readouterr().out.strip()) == 24

    assert main(["gen", "--passphrase", "6"]) == 0
    assert len(capsys.readouterr().out.strip().split("-")) >= 6

    assert main(["strength", "password"]) == 0
    assert json.loads(capsys.readouterr().out)["label"] == "very weak"


def test_export_import_roundtrip(env, tmp_path, capsys):
    main(["init"])
    main(["add", "One", "-p", "1"])
    main(["add", "Two", "-p", "2"])
    capsys.readouterr()

    export_file = tmp_path / "export.json"
    assert main(["export", "-o", str(export_file)]) == 0
    payload = json.loads(export_file.read_text())
    assert {e["name"] for e in payload["entries"]} == {"One", "Two"}

    second = tmp_path / "second.json"
    import os

    os.environ["ARGON_VAULT"] = str(second)
    main(["init"])
    assert main(["import", str(export_file)]) == 0
    assert "imported 2" in capsys.readouterr().out
    assert main(["get", "Two", "-f", "password"]) == 0
    assert capsys.readouterr().out.strip() == "2"


def test_audit_verify(env, capsys):
    main(["init"])
    main(["add", "A", "-p", "x"])
    capsys.readouterr()
    assert main(["audit", "--verify"]) == 0
    assert capsys.readouterr().out.startswith("OK")


def test_info_without_unlocking(env, monkeypatch, capsys):
    main(["init"])
    monkeypatch.delenv("ARGON_MASTER_PASSWORD")
    capsys.readouterr()
    assert main(["info"]) == 0
    out = capsys.readouterr().out
    assert "argon2id" in out and "entries: 0" in out


def test_init_force_backs_up(env, capsys):
    main(["init"])
    env.write_text(env.read_text())
    assert main(["init"]) == 1  # already exists
    assert main(["init", "--force"]) == 0
    assert env.with_suffix(".json.bak").exists()


def test_totp_command(env, capsys):
    main(["init"])
    assert main(["add", "Auth", "--totp", "JBSWY3DPEHPK3PXP", "--no-password"]) == 0
    capsys.readouterr()
    assert main(["totp", "Auth"]) == 0
    code = capsys.readouterr().out.strip().splitlines()[0]
    assert len(code) == 6 and code.isdigit()

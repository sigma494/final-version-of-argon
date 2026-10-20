"""tests/test_vault.py - vault lifecycle, tamper detection, import/export."""

from __future__ import annotations

import json
import os

import pytest

from argon.crypto import KdfParams
from argon.vault import (
    BadPasswordError,
    Entry,
    EntryNotFound,
    Vault,
    VaultExistsError,
    VaultFormatError,
)

FAST = KdfParams(time_cost=1, memory_cost=8192, parallelism=1)
PW = "correct horse battery staple"


@pytest.fixture()
def vault(tmp_path):
    return Vault.create(tmp_path / "vault.json", PW, kdf=FAST)


def test_create_writes_private_file(tmp_path):
    path = tmp_path / "sub" / "vault.json"
    Vault.create(path, PW, kdf=FAST)
    assert path.exists()
    if os.name == "posix":
        assert (path.stat().st_mode & 0o777) == 0o600


def test_create_refuses_overwrite(vault):
    with pytest.raises(VaultExistsError):
        Vault.create(vault.path, PW, kdf=FAST)


def test_empty_password_rejected(tmp_path):
    with pytest.raises(ValueError):
        Vault.create(tmp_path / "v.json", "")


def test_add_get_roundtrip_after_reopen(tmp_path):
    path = tmp_path / "vault.json"
    vault = Vault.create(path, PW, kdf=FAST)
    vault.add(Entry(name="GitHub", username="octocat", password="hunter2", tags=["work"]))
    vault.save()

    reopened = Vault.open(path, PW)
    entry = reopened.get("GitHub")
    assert entry.username == "octocat"
    assert entry.password == "hunter2"
    assert entry.tags == ["work"]


def test_wrong_password(vault):
    vault.save()
    with pytest.raises(BadPasswordError):
        Vault.open(vault.path, "wrong")


def test_missing_vault(tmp_path):
    with pytest.raises(Exception):
        Vault.open(tmp_path / "nope.json", PW)


def test_not_a_vault(tmp_path):
    path = tmp_path / "junk.json"
    path.write_text('{"hello": "world"}')
    with pytest.raises(VaultFormatError):
        Vault.open(path, PW)


def test_plaintext_never_hits_disk(vault):
    vault.add(Entry(name="AWS", username="root", password="super-secret-value", notes="rotated-me"))
    vault.save()
    blob = vault.path.read_text("utf-8")
    for needle in ("super-secret-value", "rotated-me", "AWS", "root"):
        assert needle not in blob


def test_entry_ciphertext_is_bound_to_id(vault):
    a = vault.add(Entry(name="A", password="one"))
    b = vault.add(Entry(name="B", password="two"))
    vault.save()
    raw = json.loads(vault.path.read_text("utf-8"))
    records = {r["id"]: r for r in raw["entries"]}
    records[a.id]["nonce"], records[b.id]["nonce"] = records[b.id]["nonce"], records[a.id]["nonce"]
    records[a.id]["ct"], records[b.id]["ct"] = records[b.id]["ct"], records[a.id]["ct"]
    raw["entries"] = list(records.values())
    vault.path.write_text(json.dumps(raw))
    with pytest.raises(VaultFormatError):
        Vault.open(vault.path, PW)


def test_duplicate_names_rejected(vault):
    vault.add(Entry(name="GitHub"))
    with pytest.raises(ValueError):
        vault.add(Entry(name="github"))


def test_update_and_reject_bad_fields(vault):
    entry = vault.add(Entry(name="Mail", username="old"))
    vault.update(entry.id, username="new", notes="hello")
    assert vault.get("Mail").username == "new"
    with pytest.raises(ValueError):
        vault.update(entry.id, id="hacked")
    with pytest.raises(ValueError):
        vault.update(entry.id, nonsense="x")


def test_update_duplicate_name_rejected(vault):
    vault.add(Entry(name="A"))
    b = vault.add(Entry(name="B"))
    with pytest.raises(ValueError):
        vault.update(b.id, name="A")


def test_get_by_prefix_and_ambiguity(vault):
    vault.add(Entry(name="Alpha"))
    vault.add(Entry(name="Alphabet"))
    with pytest.raises(EntryNotFound):
        vault.get("Alp")
    assert vault.get("Alpha").name == "Alpha"


def test_delete(vault):
    entry = vault.add(Entry(name="Temp"))
    vault.delete(entry.id)
    assert vault.find("Temp") is None
    assert len(vault) == 0


def test_search(vault):
    vault.add(Entry(name="GitHub", username="octocat", tags=["dev"]))
    vault.add(Entry(name="Bank", url="bank.example", tags=["money"]))
    assert [e.name for e in vault.search("octo")] == ["GitHub"]
    assert [e.name for e in vault.search("", "money")] == ["Bank"]
    assert len(vault.search()) == 2


def test_rekey_reencrypts_and_old_password_dies(vault):
    vault.add(Entry(name="Secret", password="value"))
    vault.save()
    vault.change_password(PW, "a much better long passphrase")
    with pytest.raises(BadPasswordError):
        Vault.open(vault.path, PW)
    reopened = Vault.open(vault.path, "a much better long passphrase")
    assert reopened.get("Secret").password == "value"


def test_change_password_requires_old(vault):
    with pytest.raises(BadPasswordError):
        vault.change_password("not-it", "another long password")


def test_export_import(tmp_path):
    src = Vault.create(tmp_path / "a.json", PW, kdf=FAST)
    src.add(Entry(name="One", password="1", tags=["x"]))
    src.add(Entry(name="Two", password="2"))
    payload = src.export_plaintext()

    dst = Vault.create(tmp_path / "b.json", PW, kdf=FAST)
    added, skipped = dst.import_plaintext(payload)
    assert (added, skipped) == (2, 0)
    assert dst.get("One").password == "1"

    added, skipped = dst.import_plaintext(payload)
    assert (added, skipped) == (0, 2)

    added, _ = dst.import_plaintext({"entries": [{"name": "One", "password": "updated"}]},
                                    overwrite_existing=True)
    assert added == 1
    assert dst.get("One").password == "updated"


def test_import_skips_junk(tmp_path, vault):
    added, skipped = vault.import_plaintext({"entries": [{"nope": 1}, "string", {"name": "Ok"}]})
    assert (added, skipped) == (1, 2)


def test_audit_chain_verifies_and_detects_edits(vault):
    vault.add(Entry(name="A"))
    vault.update("A", username="x")
    vault.save()
    ok, message = vault.verify_audit_chain()
    assert ok, message

    vault.audit[0]["detail"] = "forged"
    ok, message = vault.verify_audit_chain()
    assert not ok and "modified" in message


def test_audit_chain_detects_truncation(vault):
    vault.add(Entry(name="A"))
    vault.add(Entry(name="B"))
    vault.audit.pop()
    ok, _ = vault.verify_audit_chain()
    assert not ok


def test_close_drops_state(vault):
    vault.add(Entry(name="A"))
    vault.close()
    assert not vault.is_unlocked
    assert len(vault) == 0


def test_save_is_atomic_no_temp_left(vault, tmp_path):
    vault.add(Entry(name="A"))
    vault.save()
    leftovers = [p for p in tmp_path.iterdir() if p.name.startswith(".vault-")]
    assert leftovers == []

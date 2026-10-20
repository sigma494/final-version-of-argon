"""argon/vault.py - the encrypted vault container.

File layout (JSON, all binary fields base64):

    {
      "format": "argon-vault",
      "version": 1,
      "created": "2026-01-01T00:00:00Z",
      "kdf": {"algo": "argon2id", "time_cost": 3, "memory_cost": 65536,
              "parallelism": 4, "hash_len": 32, "salt": "..."},
      "verifier": "...",                       # HMAC of the vault key
      "entries": [{"id": "...", "nonce": "...", "ct": "...", "updated": "..."}],
      "audit":   [{"ts": "...", "action": "...", "detail": "...",
                   "prev": "...", "digest": "..."}]
    }

What the file leaks on purpose: how many entries exist, their random ids, and
when they changed. Everything a human cares about (names, usernames, passwords,
notes, TOTP secrets) lives only inside `ct`.
"""

from __future__ import annotations

import json
import os
import re
import stat
import tempfile
import threading
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
import hmac
from hashlib import sha256
from pathlib import Path
from typing import Any, Iterable, Iterator

from argon import crypto
from argon.crypto import InvalidTag, KdfParams

FORMAT = "argon-vault"
VERSION = 1
ENTRY_AAD_PREFIX = b"argon:entry:v1:"

__all__ = [
    "ArgonError",
    "BadPasswordError",
    "VaultFormatError",
    "VaultExistsError",
    "EntryNotFound",
    "Entry",
    "Vault",
    "FORMAT",
    "VERSION",
]

_ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")


class ArgonError(Exception):
    """Base error for the Argon package."""


class BadPasswordError(ArgonError):
    """Wrong master password (or a corrupted verifier)."""


class VaultFormatError(ArgonError):
    """The file is not an Argon vault, or is structurally invalid."""


class VaultExistsError(ArgonError):
    """A vault already exists at that path."""


class EntryNotFound(ArgonError):
    """No entry matches that id or query."""


def _now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


@dataclass
class Entry:
    """One secret. Plaintext exists only in memory while the vault is unlocked."""

    name: str
    username: str = ""
    password: str = ""
    url: str = ""
    notes: str = ""
    totp: str = ""
    tags: list[str] = field(default_factory=list)
    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    created: str = field(default_factory=_now)
    updated: str = field(default_factory=_now)

    def __post_init__(self) -> None:
        self.name = (self.name or "").strip()
        if not self.name:
            raise ValueError("entry name is required")
        if not _ID_RE.match(self.id):
            self.id = str(uuid.uuid4())
        if not isinstance(self.tags, list):
            self.tags = [str(self.tags)]
        self.tags = [str(t).strip() for t in self.tags if str(t).strip()]

    # -- serialization -------------------------------------------------
    def to_plaintext(self) -> bytes:
        payload = {
            "name": self.name,
            "username": self.username,
            "password": self.password,
            "url": self.url,
            "notes": self.notes,
            "totp": self.totp,
            "tags": self.tags,
            "id": self.id,
            "created": self.created,
            "updated": self.updated,
        }
        return json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")

    @classmethod
    def from_plaintext(cls, raw: bytes) -> "Entry":
        try:
            data = json.loads(raw.decode("utf-8"))
        except Exception as exc:
            raise VaultFormatError("entry payload is not valid JSON") from exc
        if not isinstance(data, dict):
            raise VaultFormatError("entry payload is not an object")
        allowed = {f for f in cls.__dataclass_fields__}
        try:
            return cls(**{k: v for k, v in data.items() if k in allowed})
        except (TypeError, ValueError) as exc:
            raise VaultFormatError(f"invalid entry payload: {exc}") from exc

    def to_public_dict(self) -> dict[str, Any]:
        """Metadata only - safe to render in a list without revealing the secret."""
        return {
            "id": self.id,
            "name": self.name,
            "username": self.username,
            "url": self.url,
            "tags": self.tags,
            "has_password": bool(self.password),
            "has_totp": bool(self.totp),
            "created": self.created,
            "updated": self.updated,
        }

    def to_export_dict(self) -> dict[str, Any]:
        """Full plaintext export. Callers must treat this as radioactive."""
        return json.loads(self.to_plaintext().decode("utf-8"))


class Vault:
    """An unlocked vault. Construct via :meth:`create` or :meth:`open`."""

    def __init__(self, path: os.PathLike[str] | str) -> None:
        self.path = Path(path).expanduser()
        self.kdf = KdfParams()
        self.created = _now()
        self.entries: dict[str, Entry] = {}
        self.audit: list[dict[str, str]] = []
        self.audit_seal: str = ""      # keyed commitment to (count, head digest)
        self.audit_tampered: bool = False
        self._key: bytes = b""
        self._lock = threading.RLock()
        self.dirty = False

    # ------------------------------------------------------------------
    # lifecycle
    # ------------------------------------------------------------------
    @classmethod
    def create(
        cls,
        path: os.PathLike[str] | str,
        password: str,
        *,
        kdf: KdfParams | None = None,
        overwrite: bool = False,
    ) -> "Vault":
        """Create a brand-new empty vault and write it to disk."""
        vault = cls(path)
        if vault.path.exists() and not overwrite:
            raise VaultExistsError(f"vault already exists: {vault.path}")
        if vault.path.exists():
            backup = vault.path.with_suffix(vault.path.suffix + ".bak")
            backup.write_bytes(vault.path.read_bytes())
        if not password:
            raise ValueError("master password must not be empty")
        vault.kdf = kdf or KdfParams()
        vault._key = crypto.derive_key(password, vault.kdf)
        vault._write()
        vault.path.chmod(stat.S_IRUSR | stat.S_IWUSR)
        return vault

    @classmethod
    def open(cls, path: os.PathLike[str] | str, password: str) -> "Vault":
        """Decrypt and load an existing vault. Raises BadPasswordError on a wrong password."""
        vault = cls(path)
        if not vault.path.exists():
            raise ArgonError(f"no vault at {vault.path} (run `argon init`)")
        try:
            raw = json.loads(vault.path.read_text("utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise VaultFormatError(f"cannot read vault: {exc}") from exc
        if not isinstance(raw, dict) or raw.get("format") != FORMAT:
            raise VaultFormatError("not an Argon vault")
        if raw.get("version") != VERSION:
            raise VaultFormatError(f"unsupported vault version: {raw.get('version')!r}")

        try:
            vault.kdf = KdfParams.from_dict(raw["kdf"])
            verifier = str(raw["verifier"])
            vault.created = str(raw.get("created", _now()))
        except (KeyError, TypeError, ValueError) as exc:
            raise VaultFormatError(f"vault header is invalid: {exc}") from exc

        key = crypto.derive_key(password, vault.kdf)
        if not crypto.verify_key(key, verifier):
            raise BadPasswordError("wrong master password")
        vault._key = key

        for record in raw.get("entries", []):
            try:
                entry = vault._decrypt_record(record)
            except (InvalidTag, ValueError, KeyError) as exc:
                raise VaultFormatError("entry failed authentication (file corrupted?)") from exc
            vault.entries[entry.id] = entry

        vault.audit = [r for r in raw.get("audit", []) if isinstance(r, dict)]
        vault.audit_seal = str(raw.get("audit_seal", ""))
        if vault.audit_seal and not crypto.secure_compare(
            vault._compute_seal().encode(), vault.audit_seal.encode()
        ):
            # The log was truncated or rewritten. Do not block access to the
            # secrets - surface it loudly instead (see verify_audit_chain).
            vault.audit_tampered = True
        vault.dirty = False
        return vault

    def close(self) -> None:
        """Drop the key and all plaintext from memory."""
        with self._lock:
            self._key = b""
            self.entries.clear()

    def __enter__(self) -> "Vault":
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()

    @property
    def is_unlocked(self) -> bool:
        return len(self._key) == crypto.KEY_LEN

    @property
    def needs_kdf_upgrade(self) -> bool:
        d = KdfParams()
        return (
            self.kdf.time_cost < d.time_cost
            or self.kdf.memory_cost < d.memory_cost
            or self.kdf.parallelism < d.parallelism
        )

    # ------------------------------------------------------------------
    # entry crypto
    # ------------------------------------------------------------------
    def _aad(self, entry_id: str) -> bytes:
        return ENTRY_AAD_PREFIX + entry_id.encode("ascii")

    def _encrypt_entry(self, entry: Entry) -> dict[str, str]:
        nonce, ct = crypto.seal(self._key, entry.to_plaintext(), self._aad(entry.id))
        return {
            "id": entry.id,
            "nonce": crypto.b64e(nonce),
            "ct": crypto.b64e(ct),
            "updated": entry.updated,
        }

    def _decrypt_record(self, record: dict[str, Any]) -> Entry:
        entry_id = str(record["id"])
        if not _ID_RE.match(entry_id):
            raise VaultFormatError("invalid entry id")
        nonce = crypto.b64d(str(record["nonce"]))
        ct = crypto.b64d(str(record["ct"]))
        plaintext = crypto.unseal(self._key, nonce, ct, self._aad(entry_id))
        return Entry.from_plaintext(plaintext)

    # ------------------------------------------------------------------
    # CRUD
    # ------------------------------------------------------------------
    def add(self, entry: Entry | None = None, **fields: Any) -> Entry:
        """Add an entry. Raises ValueError on a duplicate name (case-insensitive)."""
        entry = entry or Entry(**fields)
        with self._lock:
            if any(e.name.casefold() == entry.name.casefold() for e in self.entries.values()):
                raise ValueError(f"an entry named {entry.name!r} already exists")
            self.entries[entry.id] = entry
            self._audit("add", entry.id)
            self.dirty = True
        return entry

    def get(self, key: str) -> Entry:
        """Fetch by id, else by exact name, else by unique prefix."""
        with self._lock:
            if key in self.entries:
                return self.entries[key]
            folded = key.casefold()
            exact = [e for e in self.entries.values() if e.name.casefold() == folded]
            if len(exact) == 1:
                return exact[0]
            prefix = [e for e in self.entries.values() if e.name.casefold().startswith(folded)]
            if len(prefix) == 1:
                return prefix[0]
            if len(prefix) > 1:
                names = ", ".join(sorted(e.name for e in prefix))
                raise EntryNotFound(f"ambiguous name {key!r}: {names}")
            raise EntryNotFound(f"no entry matching {key!r}")

    def find(self, query: str) -> Entry | None:
        try:
            return self.get(query)
        except EntryNotFound:
            return None

    def search(self, query: str = "", tag: str = "") -> list[Entry]:
        """Case-insensitive substring search across name/username/url/tags/notes."""
        q = query.strip().casefold()
        results = []
        with self._lock:
            for entry in self.entries.values():
                if tag and tag.casefold() not in [t.casefold() for t in entry.tags]:
                    continue
                if not q:
                    results.append(entry)
                    continue
                haystack = "\n".join(
                    [entry.name, entry.username, entry.url, " ".join(entry.tags), entry.notes, entry.id]
                ).casefold()
                if q in haystack:
                    results.append(entry)
        return sorted(results, key=lambda e: e.name.casefold())

    def update(self, key: str, **fields: Any) -> Entry:
        """Patch fields on an entry. Unknown fields are rejected."""
        entry = self.get(key)
        immutable = {"id", "created"}
        payload = {}
        for k, v in fields.items():
            if k in immutable:
                raise ValueError(f"{k} cannot be changed")
            if not hasattr(entry, k):
                raise ValueError(f"unknown field: {k}")
            if v is not None:
                payload[k] = v
        new_name = str(payload.get("name", entry.name)).strip()
        if not new_name:
            raise ValueError("entry name is required")
        with self._lock:
            if any(
                e.id != entry.id and e.name.casefold() == new_name.casefold()
                for e in self.entries.values()
            ):
                raise ValueError(f"an entry named {new_name!r} already exists")
            if "tags" in payload:
                tags = payload["tags"]
                payload["tags"] = [str(t).strip() for t in tags] if isinstance(tags, list) else [str(tags)]
            for k, v in payload.items():
                setattr(entry, k, v)
            entry.name = new_name
            entry.updated = _now()
            self._audit("update", entry.id)
            self.dirty = True
        return entry

    def delete(self, key: str) -> Entry:
        entry = self.get(key)
        with self._lock:
            del self.entries[entry.id]
            self._audit("delete", entry.id)
            self.dirty = True
        return entry

    def __len__(self) -> int:
        return len(self.entries)

    def __iter__(self) -> Iterator[Entry]:
        return iter(self.search())

    # ------------------------------------------------------------------
    # persistence
    # ------------------------------------------------------------------
    def _write(self) -> None:
        """Atomically write the vault: temp file -> fsync -> os.replace (0600)."""
        payload: dict[str, Any] = {
            "format": FORMAT,
            "version": VERSION,
            "created": self.created,
            "kdf": self.kdf.to_dict(),
            "verifier": crypto.b64e(crypto.key_verifier(self._key)),
            "entries": [self._encrypt_entry(e) for e in self.entries.values()],
            "audit": self.audit,
            "audit_seal": self.audit_seal or self._compute_seal(),
        }
        blob = json.dumps(payload, indent=2, ensure_ascii=False).encode("utf-8")

        parent = self.path.parent
        parent.mkdir(parents=True, exist_ok=True)
        try:
            parent.chmod(stat.S_IRWXU)
        except OSError:
            pass

        fd, tmp_name = tempfile.mkstemp(dir=str(parent), prefix=".vault-", suffix=".tmp")
        try:
            with os.fdopen(fd, "wb") as handle:
                handle.write(blob)
                handle.flush()
                os.fsync(handle.fileno())
            os.chmod(tmp_name, stat.S_IRUSR | stat.S_IWUSR)
            os.replace(tmp_name, self.path)
            try:
                dir_fd = os.open(parent, os.O_RDONLY)
                try:
                    os.fsync(dir_fd)
                finally:
                    os.close(dir_fd)
            except OSError:
                pass
        except BaseException:
            try:
                os.unlink(tmp_name)
            except OSError:
                pass
            raise
        self.dirty = False

    def save(self) -> None:
        with self._lock:
            if self.entries:
                self._audit("save", f"{len(self.entries)} entries")
            self._write()

    def rekey(self, new: str) -> None:
        """Re-derive the key with a fresh salt and re-encrypt every entry.

        Only valid on an already unlocked vault: the caller has proven possession
        of the master password by opening it.
        """
        if not new or len(new) < 8:
            raise ValueError("new master password must be at least 8 characters")
        with self._lock:
            self.kdf = self.kdf.with_new_salt()
            self._key = crypto.derive_key(new, self.kdf)
            self._audit("rekey", f"{len(self.entries)} entries")
            self._write()

    def change_password(self, old: str, new: str) -> None:
        """Verify `old`, then rekey to `new`."""
        if not crypto.secure_compare(crypto.derive_key(old, self.kdf), self._key):
            raise BadPasswordError("wrong master password")
        self.rekey(new)

    # ------------------------------------------------------------------
    # audit trail (hash chained, metadata only)
    # ------------------------------------------------------------------
    def _audit(self, action: str, detail: str = "") -> None:
        prev = self.audit[-1]["digest"] if self.audit else "genesis"
        record = {"ts": _now(), "action": action, "detail": detail, "prev": prev}
        body = json.dumps(record, sort_keys=True, separators=(",", ":")).encode("utf-8")
        record["digest"] = sha256(body).hexdigest()
        self.audit.append(record)
        self.audit_seal = self._compute_seal()

    def _compute_seal(self) -> str:
        """HMAC over (record count, head digest) with the vault key.

        The hash chain alone cannot detect truncation (removing the last record
        still leaves a valid chain), so the head is committed to with a keyed
        MAC. Without the master password an attacker cannot forge a new seal.
        """
        head = self.audit[-1]["digest"] if self.audit else "genesis"
        message = f"argon:audit:v1:{len(self.audit)}:{head}".encode()
        if not self.is_unlocked:
            return ""
        return hmac.new(self._key, message, sha256).hexdigest()

    def verify_audit_chain(self) -> tuple[bool, str]:
        """Return (ok, message). Detects edits, reordering, and truncation."""
        if self.audit_tampered:
            return False, "audit seal does not match the log (truncated or rewritten on disk)"
        prev = "genesis"
        for i, record in enumerate(self.audit):
            if not isinstance(record, dict) or set(record) != {"ts", "action", "detail", "prev", "digest"}:
                return False, f"audit record {i} is malformed"
            if record["prev"] != prev:
                return False, f"audit record {i} breaks the chain"
            body = json.dumps(
                {k: record[k] for k in ("ts", "action", "detail", "prev")},
                sort_keys=True,
                separators=(",", ":"),
            ).encode("utf-8")
            if sha256(body).hexdigest() != record["digest"]:
                return False, f"audit record {i} was modified"
            prev = record["digest"]
        if self.audit_seal and not crypto.secure_compare(
            self._compute_seal().encode(), self.audit_seal.encode()
        ):
            return False, "audit seal does not match the log (truncated or rewritten)"
        return True, f"{len(self.audit)} records verified"

    # ------------------------------------------------------------------
    # import / export
    # ------------------------------------------------------------------
    def export_plaintext(self) -> dict[str, Any]:
        """Full decrypted export. Anyone with this JSON owns every secret in it."""
        with self._lock:
            return {
                "format": "argon-export",
                "version": 1,
                "exported": _now(),
                "entries": [e.to_export_dict() for e in self.search()],
            }

    def import_plaintext(
        self,
        data: dict[str, Any] | list[Any],
        *,
        merge: bool = True,
        overwrite_existing: bool = False,
    ) -> tuple[int, int]:
        """Import entries from an Argon export or a plain list. Returns (added, skipped)."""
        if isinstance(data, dict):
            raw_entries = data.get("entries", [])
        elif isinstance(data, list):
            raw_entries = data
        else:
            raise VaultFormatError("import payload must be an object or list")
        if not isinstance(raw_entries, list):
            raise VaultFormatError("import payload has no entry list")

        added = skipped = 0
        with self._lock:
            if not merge:
                self.entries.clear()
            existing = {e.name.casefold(): e for e in self.entries.values()}
            for item in raw_entries:
                if not isinstance(item, dict) or not str(item.get("name", "")).strip():
                    skipped += 1
                    continue
                fields = {k: v for k, v in item.items() if k in Entry.__dataclass_fields__}
                fields.pop("created", None)
                fields.pop("updated", None)
                try:
                    entry = Entry(**fields)
                except (TypeError, ValueError):
                    skipped += 1
                    continue
                clash = existing.get(entry.name.casefold())
                if clash is not None:
                    if not overwrite_existing:
                        skipped += 1
                        continue
                    try:
                        self.update(
                            clash.id,
                            **{
                                k: getattr(entry, k)
                                for k in ("username", "password", "url", "notes", "totp", "tags")
                            },
                        )
                    except ValueError:
                        skipped += 1
                        continue
                    added += 1
                    continue
                self.entries[entry.id] = entry
                existing[entry.name.casefold()] = entry
                added += 1
            if added:
                self._audit("import", f"{added} added, {skipped} skipped")
            self.dirty = True
        return added, skipped

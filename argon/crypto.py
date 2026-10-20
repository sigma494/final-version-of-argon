"""argon/crypto.py - key derivation, authenticated encryption, constant-time compare.

Design notes
------------
* Master password -> 32-byte vault key via Argon2id (memory-hard, GPU resistant).
* Each entry is sealed separately with AES-256-GCM. The entry id is bound in as
  associated data, so ciphertext blobs cannot be swapped between entries without
  the tag check failing.
* The vault key is verified with HMAC-SHA256 over a fixed domain-separated
  string. That value is public, so it leaks nothing beyond "is this the key".
* Nothing here ever writes the password or the key to disk or to logs.
"""

from __future__ import annotations

import base64
import hmac
import os
import secrets
import unicodedata
from dataclasses import asdict, dataclass, field
from hashlib import sha256
from typing import Any

from argon2.low_level import Type, hash_secret_raw
from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

KEY_LEN = 32
SALT_LEN = 16
NONCE_LEN = 12
VERIFIER_MESSAGE = b"argon:vault:verify:v1"

__all__ = [
    "KdfParams",
    "KEY_LEN",
    "NONCE_LEN",
    "VERIFIER_MESSAGE",
    "derive_key",
    "new_salt",
    "new_nonce",
    "seal",
    "unseal",
    "key_verifier",
    "verify_key",
    "b64e",
    "b64d",
    "secure_compare",
    "normalize_password",
    "InvalidTag",
]


def normalize_password(password: str) -> bytes:
    """NFC-normalize so the same visual password derives the same key everywhere."""
    if not isinstance(password, str):
        raise TypeError("password must be a string")
    return unicodedata.normalize("NFC", password).encode("utf-8")


@dataclass(frozen=True)
class KdfParams:
    """Argon2id parameters, stored in the vault header so old vaults stay readable."""

    algo: str = "argon2id"
    time_cost: int = 3
    memory_cost: int = 65536  # KiB -> 64 MiB
    parallelism: int = 4
    hash_len: int = KEY_LEN
    salt: str = field(default_factory=lambda: b64e(new_salt()))

    def __post_init__(self) -> None:
        if self.algo != "argon2id":
            raise ValueError(f"unsupported kdf algo: {self.algo!r}")
        if not (1 <= self.time_cost <= 64):
            raise ValueError("time_cost out of range (1..64)")
        if not (8192 <= self.memory_cost <= 4_194_304):
            raise ValueError("memory_cost out of range (8192..4194304 KiB)")
        if not (1 <= self.parallelism <= 64):
            raise ValueError("parallelism out of range (1..64)")
        if not (16 <= self.hash_len <= 64):
            raise ValueError("hash_len out of range (16..64)")
        if len(b64d(self.salt)) != SALT_LEN:
            raise ValueError("bad salt length")

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "KdfParams":
        allowed = {f for f in cls.__dataclass_fields__}  # ignore unknown future fields
        return cls(**{k: v for k, v in data.items() if k in allowed})

    def with_new_salt(self) -> "KdfParams":
        return KdfParams(
            algo=self.algo,
            time_cost=self.time_cost,
            memory_cost=self.memory_cost,
            parallelism=self.parallelism,
            hash_len=self.hash_len,
            salt=b64e(new_salt()),
        )


def new_salt() -> bytes:
    """Fresh 16-byte KDF salt."""
    return secrets.token_bytes(SALT_LEN)


def new_nonce() -> bytes:
    """Fresh 12-byte AES-GCM nonce. Never reuse a nonce with the same key."""
    return secrets.token_bytes(NONCE_LEN)


def derive_key(password: str, params: KdfParams) -> bytes:
    """Derive the vault key with Argon2id. This is deliberately slow (~0.1-0.4s)."""
    return hash_secret_raw(
        secret=normalize_password(password),
        salt=b64d(params.salt),
        time_cost=params.time_cost,
        memory_cost=params.memory_cost,
        parallelism=params.parallelism,
        hash_len=params.hash_len,
        type=Type.ID,
    )


def key_verifier(key: bytes) -> bytes:
    """Public check value stored in the vault header."""
    if len(key) != KEY_LEN:
        raise ValueError("key must be 32 bytes")
    return hmac.new(key, VERIFIER_MESSAGE, sha256).digest()


def verify_key(key: bytes, stored_b64: str) -> bool:
    """Constant-time comparison of the derived key against the stored verifier."""
    try:
        expected = b64d(stored_b64)
    except ValueError:
        return False
    return secure_compare(key_verifier(key), expected)


def seal(key: bytes, plaintext: bytes, aad: bytes = b"") -> tuple[bytes, bytes]:
    """AES-256-GCM encrypt. Returns (nonce, ciphertext_with_tag)."""
    if len(key) != KEY_LEN:
        raise ValueError("key must be 32 bytes")
    nonce = new_nonce()
    return nonce, AESGCM(key).encrypt(nonce, plaintext, aad)


def unseal(key: bytes, nonce: bytes, ciphertext: bytes, aad: bytes = b"") -> bytes:
    """AES-256-GCM decrypt. Raises InvalidTag if the data or AAD was tampered with."""
    if len(key) != KEY_LEN:
        raise ValueError("key must be 32 bytes")
    if len(nonce) != NONCE_LEN:
        raise ValueError("bad nonce length")
    return AESGCM(key).decrypt(nonce, ciphertext, aad)


def b64e(raw: bytes) -> str:
    return base64.b64encode(raw).decode("ascii")


def b64d(data: str) -> bytes:
    try:
        return base64.b64decode(data, validate=True)
    except Exception as exc:  # binascii.Error, ValueError, TypeError
        raise ValueError("invalid base64") from exc


def secure_compare(a: bytes, b: bytes) -> bool:
    """Timing-safe equality."""
    return hmac.compare_digest(a, b)


def random_token(nbytes: int = 32) -> str:
    """URL-safe random token (used for web session ids)."""
    return secrets.token_urlsafe(nbytes)


def wipe(buffer: bytearray) -> None:
    """Best-effort overwrite of a mutable key buffer (Python cannot guarantee this)."""
    for i in range(len(buffer)):
        buffer[i] = 0

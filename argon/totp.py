"""argon/totp.py - RFC 6238 TOTP + RFC 4226 HOTP, stdlib only.

Works with the usual `otpauth://` URIs that authenticator apps export, and with
bare base32 secrets (spaces and padding tolerated, case-insensitive).
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import struct
import time
import urllib.parse
from typing import Optional

__all__ = ["TotpError", "normalize_secret", "hotp", "totp", "totp_remaining", "parse_otpauth"]


class TotpError(ValueError):
    """Raised for malformed secrets or otpauth URIs."""


def normalize_secret(secret: str) -> bytes:
    """Decode a base32 secret, tolerating spaces, dashes, and missing padding."""
    if not secret:
        raise TotpError("empty TOTP secret")
    cleaned = "".join(ch for ch in secret.upper() if ch.isalnum() or ch == "=")
    cleaned = cleaned.rstrip("=")
    cleaned += "=" * (-len(cleaned) % 8)
    try:
        return base64.b32decode(cleaned)
    except Exception as exc:
        raise TotpError("invalid base32 TOTP secret") from exc


def hotp(secret: str | bytes, counter: int, digits: int = 6, algorithm: str = "sha1") -> str:
    """RFC 4226 HOTP value for a counter."""
    key = normalize_secret(secret) if isinstance(secret, str) else secret
    if counter < 0:
        raise TotpError("counter must be >= 0")
    if not (6 <= digits <= 10):
        raise TotpError("digits must be 6..10")
    digestmod = {"sha1": hashlib.sha1, "sha256": hashlib.sha256, "sha512": hashlib.sha512}.get(
        algorithm.lower()
    )
    if digestmod is None:
        raise TotpError(f"unsupported algorithm: {algorithm!r}")
    mac = hmac.new(key, struct.pack(">Q", counter), digestmod).digest()
    offset = mac[-1] & 0x0F
    code = struct.unpack(">I", mac[offset : offset + 4])[0] & 0x7FFFFFFF
    return str(code % (10**digits)).zfill(digits)


def totp(
    secret: str | bytes,
    at: Optional[float] = None,
    period: int = 30,
    digits: int = 6,
    algorithm: str = "sha1",
) -> str:
    """RFC 6238 TOTP value at a Unix timestamp (default: now)."""
    if period <= 0:
        raise TotpError("period must be positive")
    now = time.time() if at is None else at
    return hotp(secret, int(now // period), digits=digits, algorithm=algorithm)


def totp_remaining(at: Optional[float] = None, period: int = 30) -> int:
    """Seconds until the current TOTP window rolls over."""
    now = time.time() if at is None else at
    return int(period - (now % period))


def parse_otpauth(uri: str) -> dict[str, object]:
    """Parse an `otpauth://totp/...` URI into secret/period/digits/algorithm/label."""
    if not uri.startswith("otpauth://"):
        raise TotpError("not an otpauth URI")
    parsed = urllib.parse.urlparse(uri)
    if parsed.netloc.lower() not in {"totp", "hotp"}:
        raise TotpError("only totp/hotp otpauth URIs are supported")
    query = urllib.parse.parse_qs(parsed.query)
    secret = (query.get("secret") or [""])[0]
    if not secret:
        raise TotpError("otpauth URI has no secret")
    label = urllib.parse.unquote(parsed.path.lstrip("/"))
    digits = int((query.get("digits") or ["6"])[0])
    period = int((query.get("period") or ["30"])[0])
    algorithm = (query.get("algorithm") or ["SHA1"])[0].lower()
    issuer = (query.get("issuer") or [""])[0]
    if ":" in label:
        label_issuer, _, account = label.partition(":")
        issuer = issuer or label_issuer.strip()
        label = account.strip()
    return {
        "secret": secret,
        "digits": digits,
        "period": period,
        "algorithm": algorithm,
        "issuer": issuer,
        "label": label or issuer,
        "type": parsed.netloc.lower(),
    }

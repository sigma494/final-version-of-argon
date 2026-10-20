"""tests/test_crypto.py - KDF, AEAD, and verifier behaviour."""

from __future__ import annotations

import pytest

from argon import crypto
from argon.crypto import InvalidTag, KdfParams


FAST = KdfParams(time_cost=1, memory_cost=8192, parallelism=1)


def test_derive_is_deterministic_for_same_salt():
    a = crypto.derive_key("correct horse", FAST)
    b = crypto.derive_key("correct horse", FAST)
    assert a == b
    assert len(a) == 32


def test_derive_differs_with_new_salt_or_password():
    other_salt = crypto.derive_key("correct horse", FAST.with_new_salt())
    other_pw = crypto.derive_key("correct horsE", FAST)
    base = crypto.derive_key("correct horse", FAST)
    assert base != other_salt
    assert base != other_pw


def test_password_is_normalized():
    composed = "caf\u00e9"
    decomposed = "cafe\u0301"
    assert crypto.derive_key(composed, FAST) == crypto.derive_key(decomposed, FAST)


def test_non_string_password_rejected():
    with pytest.raises(TypeError):
        crypto.derive_key(b"bytes", FAST)  # type: ignore[arg-type]


def test_seal_unseal_roundtrip_and_unique_nonces():
    key = crypto.derive_key("pw", FAST)
    n1, c1 = crypto.seal(key, b"secret", b"aad")
    n2, c2 = crypto.seal(key, b"secret", b"aad")
    assert n1 != n2 and c1 != c2
    assert crypto.unseal(key, n1, c1, b"aad") == b"secret"


def test_aad_mismatch_fails():
    key = crypto.derive_key("pw", FAST)
    nonce, ct = crypto.seal(key, b"secret", b"entry-a")
    with pytest.raises(InvalidTag):
        crypto.unseal(key, nonce, ct, b"entry-b")


def test_tampered_ciphertext_fails():
    key = crypto.derive_key("pw", FAST)
    nonce, ct = crypto.seal(key, b"secret")
    broken = bytearray(ct)
    broken[0] ^= 0xFF
    with pytest.raises(InvalidTag):
        crypto.unseal(key, nonce, bytes(broken))


def test_verifier_accepts_only_the_right_key():
    key = crypto.derive_key("pw", FAST)
    stored = crypto.b64e(crypto.key_verifier(key))
    assert crypto.verify_key(key, stored)
    assert not crypto.verify_key(crypto.derive_key("nope", FAST), stored)
    assert not crypto.verify_key(key, "not base64!!")


def test_kdf_params_validation():
    with pytest.raises(ValueError):
        KdfParams(algo="scrypt")
    with pytest.raises(ValueError):
        KdfParams(memory_cost=1024)
    with pytest.raises(ValueError):
        KdfParams(time_cost=0)
    with pytest.raises(ValueError):
        KdfParams(salt="AAAA")


def test_kdf_params_roundtrip_ignores_unknown_fields():
    params = KdfParams.from_dict({**FAST.to_dict(), "future_field": 1})
    assert params == FAST


def test_secure_compare():
    assert crypto.secure_compare(b"abc", b"abc")
    assert not crypto.secure_compare(b"abc", b"abd")


def test_random_token_unique():
    assert crypto.random_token() != crypto.random_token()
    assert len(crypto.random_token(16)) >= 20

"""tests/test_totp_generator.py - RFC 4226/6238 vectors + password generation."""

from __future__ import annotations

import re

import pytest

from argon import generator, totp

# RFC 6238 test secret is the ASCII string "12345678901234567890".
RFC_SECRET = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"  # base32 of the RFC seed


def test_rfc6238_sha1_vectors():
    vectors = [
        (59, "94287082"),
        (1111111109, "07081804"),
        (1111111111, "14050471"),
        (1234567890, "89005924"),
        (2000000000, "69279037"),
        (20000000000, "65353130"),
    ]
    for at, expected in vectors:
        assert totp.totp(RFC_SECRET, at=at, digits=8) == expected


def test_rfc4226_hotp_vectors():
    expected = ["755224", "287082", "359152", "969429", "338314", "254676",
                "287922", "162583", "399871", "520489"]
    for counter, code in enumerate(expected):
        assert totp.hotp(RFC_SECRET, counter) == code


def test_secret_normalization():
    spaced = "gezd gnbv gy3t qojq gezd gnbv gy3t qojq"
    assert totp.totp(spaced, at=59, digits=8) == "94287082"
    assert totp.normalize_secret(RFC_SECRET.lower()) == totp.normalize_secret(RFC_SECRET)


def test_bad_secrets_raise():
    with pytest.raises(totp.TotpError):
        totp.totp("", at=1)
    with pytest.raises(totp.TotpError):
        totp.totp("not-base32!!", at=1)


def test_remaining_counts_down():
    assert totp.totp_remaining(at=0) == 30
    assert totp.totp_remaining(at=29) == 1


def test_parse_otpauth():
    uri = "otpauth://totp/GitHub:octocat?secret=JBSWY3DPEHPK3PXP&issuer=GitHub&digits=6&period=30"
    parsed = totp.parse_otpauth(uri)
    assert parsed["secret"] == "JBSWY3DPEHPK3PXP"
    assert parsed["issuer"] == "GitHub"
    assert parsed["label"] == "octocat"
    assert parsed["digits"] == 6

    with pytest.raises(totp.TotpError):
        totp.parse_otpauth("https://example.com")
    with pytest.raises(totp.TotpError):
        totp.parse_otpauth("otpauth://totp/NoSecret")


def test_generated_password_has_every_class():
    for _ in range(50):
        pwd = generator.generate_password(16)
        assert len(pwd) == 16
        assert re.search(r"[A-Z]", pwd)
        assert re.search(r"[a-z]", pwd)
        assert re.search(r"\d", pwd)
        assert re.search(r"[^A-Za-z0-9]", pwd)


def test_generated_password_is_unique():
    passwords = {generator.generate_password(24) for _ in range(200)}
    assert len(passwords) == 200


def test_length_and_class_validation():
    with pytest.raises(ValueError):
        generator.generate_password(3)
    with pytest.raises(ValueError):
        generator.generate_password(20, upper=False, lower=False, digits=False, symbols=False)
    exact = generator.generate_password(8, symbols=False)
    assert len(exact) == 8


def test_exclude_ambiguous():
    pwd = generator.generate_password(64, exclude_ambiguous=True)
    assert not set(pwd) & set(generator.AMBIGUOUS)


def test_passphrase():
    phrase = generator.generate_passphrase(6)
    assert len(phrase.split("-")) == 6
    numbered = generator.generate_passphrase(4, with_number=True)
    parts = numbered.split("-")
    assert len(parts) == 5
    assert parts[-1].isdigit()


def test_entropy_and_strength():
    assert generator.password_strength("").label == "very weak"
    weak = generator.password_strength("password")
    assert weak.label == "very weak"
    assert "common password" in weak.warnings

    strong = generator.password_strength(generator.generate_password(28))
    assert strong.bits > 80
    assert strong.label == "excellent"

    seq = generator.password_strength("abcdefghijkl")
    assert any("sequence" in w for w in seq.warnings)

    personal = generator.password_strength("MyName12345!x", user_inputs=["myname"])
    assert any("myname" in w for w in personal.warnings)


def test_strength_report_dict():
    report = generator.password_strength("Tr0ub4dor&3-horse-Battery")
    payload = report.as_dict()
    assert set(payload) == {"bits", "label", "warnings"}
    assert isinstance(payload["bits"], float)

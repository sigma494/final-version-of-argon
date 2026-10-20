"""argon/generator.py - password and passphrase generation + a small strength estimator.

Everything uses `secrets`, never `random`.
"""

from __future__ import annotations

import math
import re
import secrets
import string
from dataclasses import dataclass
from typing import Iterable

__all__ = [
    "AMBIGUOUS",
    "SYMBOLS",
    "generate_password",
    "generate_passphrase",
    "entropy_bits",
    "password_strength",
    "StrengthReport",
]

AMBIGUOUS = "Il1O0o|`'\";:.>"
SYMBOLS = "!@#$%^&*()-_=+[]{};:,.?/"

# 270 short, easy-to-type words -> ~8.08 bits of entropy per word.
WORDLIST: tuple[str, ...] = (
    "acid", "aged", "ally", "also", "apex", "aqua", "arch", "army", "atom", "aunt",
    "auto", "avid", "away", "axis", "baby", "back", "bake", "bald", "ball", "band",
    "bank", "barn", "base", "bath", "beam", "bean", "bear", "beat", "beef", "bell",
    "belt", "bend", "best", "bike", "bird", "blue", "boat", "body", "bold", "bolt",
    "bone", "book", "boot", "bore", "boss", "both", "bowl", "bulk", "burn", "bush",
    "busy", "cafe", "cage", "cake", "calm", "camp", "card", "care", "cart", "case",
    "cash", "cast", "cave", "cell", "chef", "chip", "city", "clad", "clam", "clay",
    "clip", "club", "coal", "coat", "code", "coil", "cold", "cole", "come", "cone",
    "cope", "copy", "cord", "core", "cork", "corn", "cost", "cozy", "crab", "crew",
    "crop", "crow", "cube", "cure", "curl", "cute", "dare", "dark", "dart", "dash",
    "data", "date", "dawn", "deal", "dean", "dear", "debt", "deck", "deep", "deer",
    "desk", "dial", "dice", "diet", "dirt", "disc", "dish", "dock", "does", "dome",
    "door", "dose", "dove", "down", "drag", "draw", "drew", "drop", "drum", "dual",
    "duck", "dull", "dune", "dusk", "dust", "duty", "each", "earl", "earn", "ease",
    "east", "easy", "echo", "edge", "else", "emit", "epic", "even", "ever", "exam",
    "exit", "face", "fact", "fade", "fair", "fall", "fame", "farm", "fast", "fate",
    "fawn", "feed", "feel", "feet", "fell", "felt", "fern", "file", "fill", "film",
    "find", "fine", "fire", "firm", "fish", "fist", "five", "flag", "flat", "flew",
    "flow", "foam", "fold", "folk", "font", "food", "foot", "ford", "fork", "form",
    "fort", "foul", "four", "free", "frog", "from", "fuel", "full", "fund", "gain",
    "game", "gate", "gave", "gear", "gift", "girl", "give", "glad", "glow", "goal",
    "goat", "gold", "golf", "gone", "good", "grab", "gray", "grew", "grid", "grip",
    "grow", "gulf", "hair", "half", "hall", "hand", "hang", "hard", "harm", "hawk",
    "head", "heap", "heat", "heel", "held", "helm", "herb", "hero", "hide", "high",
    "hill", "hint", "hire", "hold", "hole", "home", "hook", "hope", "horn", "host",
    "hour", "huge", "hull", "hunt", "hurd", "ice", "idea", "inch", "iron", "item",
    "jade", "jazz", "join", "joke", "jump", "june", "jury", "just", "keen", "keep",
)


@dataclass(frozen=True)
class StrengthReport:
    """Result of :func:`password_strength`."""

    bits: float
    label: str  # "very weak" | "weak" | "fair" | "strong" | "excellent"
    warnings: tuple[str, ...]

    def as_dict(self) -> dict[str, object]:
        return {"bits": round(self.bits, 1), "label": self.label, "warnings": list(self.warnings)}


def generate_password(
    length: int = 20,
    *,
    upper: bool = True,
    lower: bool = True,
    digits: bool = True,
    symbols: bool = True,
    exclude_ambiguous: bool = False,
) -> str:
    """Generate a random password that provably contains every enabled class."""
    if not (4 <= length <= 1024):
        raise ValueError("length must be 4..1024")
    pools: list[str] = []
    if upper:
        pools.append(string.ascii_uppercase)
    if lower:
        pools.append(string.ascii_lowercase)
    if digits:
        pools.append(string.digits)
    if symbols:
        pools.append(SYMBOLS)
    if not pools:
        raise ValueError("enable at least one character class")
    if exclude_ambiguous:
        pools = ["".join(c for c in p if c not in AMBIGUOUS) for p in pools]
    if length < len(pools):
        raise ValueError(f"length must be >= {len(pools)} with the selected classes")

    alphabet = "".join(pools)
    while True:
        chars = [secrets.choice(pool) for pool in pools]
        chars += [secrets.choice(alphabet) for _ in range(length - len(pools))]
        secrets.SystemRandom().shuffle(chars)
        candidate = "".join(chars)
        if all(any(c in pool for c in candidate) for pool in pools):
            return candidate


def generate_passphrase(
    words: int = 6,
    separator: str = "-",
    capitalize: bool = True,
    with_number: bool = False,
) -> str:
    """Diceware-style passphrase from the built-in 270-word list (~8.1 bits/word)."""
    if not (3 <= words <= 20):
        raise ValueError("words must be 3..20")
    picked = [secrets.choice(WORDLIST) for _ in range(words)]
    if capitalize:
        picked = [w.capitalize() for w in picked]
    phrase = separator.join(picked)
    if with_number:
        phrase += separator + str(secrets.randbelow(90) + 10)
    return phrase


def entropy_bits(password: str, alphabet_size: int | None = None) -> float:
    """Shannon-style search-space entropy estimate in bits."""
    if not password:
        return 0.0
    if alphabet_size is None:
        classes = 0
        if re.search(r"[a-z]", password):
            classes += 26
        if re.search(r"[A-Z]", password):
            classes += 26
        if re.search(r"\d", password):
            classes += 10
        if re.search(r"[^A-Za-z0-9]", password):
            classes += len(SYMBOLS) + 3
        alphabet_size = max(classes, 1)
    return len(password) * math.log2(alphabet_size)


_COMMON = {
    "password", "123456", "12345678", "qwerty", "letmein", "admin", "welcome",
    "monkey", "dragon", "iloveyou", "sunshine", "princess", "football", "charlie",
    "abc123", "password1", "qwerty123", "111111", "123123", "passw0rd", "trustno1",
    "master", "shadow", "superman", "batman", "hunter2", "correcthorsebatterystaple",
}
_SEQUENCES = (
    "abcdefghijklmnopqrstuvwxyz",
    "0123456789",
    "qwertyuiop",
    "asdfghjkl",
    "zxcvbnm",
)


def _has_sequence(password: str, run: int = 4) -> bool:
    """True if any `run`-long slice of a known sequence appears in the password."""
    lowered = password.lower()
    for seq in _SEQUENCES:
        for i in range(len(seq) - run + 1):
            if seq[i : i + run] in lowered:
                return True
    return False


def password_strength(password: str, user_inputs: Iterable[str] = ()) -> StrengthReport:
    """Small heuristic estimator. Not zxcvbn, but catches the usual disasters."""
    warnings: list[str] = []
    if not password:
        return StrengthReport(0.0, "very weak", ("empty",))

    lower = password.lower()
    bits = entropy_bits(password)

    if lower in _COMMON:
        bits = min(bits, 12.0)
        warnings.append("common password")
    if _has_sequence(password):
        bits -= 12
        warnings.append("keyboard or alphabet sequence")
    if re.search(r"(.)\1{2,}", password):
        bits -= 8
        warnings.append("repeated characters")
    if re.fullmatch(r"[A-Za-z]+", password) and bits < 60:
        warnings.append("letters only")
    for item in user_inputs:
        item = (item or "").strip().lower()
        if len(item) >= 3 and item in lower:
            bits -= 15
            warnings.append(f"contains '{item}'")

    bits = max(bits, 0.0)
    if bits < 28:
        label = "very weak"
    elif bits < 40:
        label = "weak"
    elif bits < 60:
        label = "fair"
    elif bits < 80:
        label = "strong"
    else:
        label = "excellent"
    return StrengthReport(round(bits, 1), label, tuple(dict.fromkeys(warnings)))

"""Argon - a local-first, zero-knowledge secrets vault.

Argon keeps every secret encrypted at rest with a key that only exists while a
vault is unlocked. The key is derived from the master password with Argon2id and
used to seal each entry independently with AES-256-GCM.

Public surface:

    from argon.vault import Vault
    vault = Vault.create("vault.json", "correct horse battery staple")
    vault.add(Entry(name="GitHub", username="me", password="hunter2"))
    vault.save()

    vault = Vault.open("vault.json", "correct horse battery staple")
    print(vault.find("GitHub").password)
"""

from __future__ import annotations

__version__ = "1.0.0"
__all__ = ["__version__"]

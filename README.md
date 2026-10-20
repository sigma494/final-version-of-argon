# Argon

A local-first, zero-knowledge secrets vault: Argon2id key derivation, AES-256-GCM
per-entry encryption, a full CLI, TOTP codes, a password generator, a tamper-evident
audit log, and a dependency-free local web UI.

No account. No server. No telemetry. The master password never leaves the process,
and there is no recovery path if you lose it — that is the point.

```
   plaintext never touches disk
   ┌──────────────┐   argon2id    ┌──────────────┐   AES-256-GCM   ┌────────────────┐
   │ master pass  │ ────────────► │   vault key  │ ──────────────► │ entries on disk│
   └──────────────┘  m=64MiB t=3  └──────────────┘   per-entry AAD └────────────────┘
```

## Install

```bash
python3 -m venv .venv
.venv/bin/pip install -e .          # or: pip install argon-vault
```

Requirements: Python 3.10+, `argon2-cffi`, `cryptography`. Nothing else.

## Quickstart (under a minute)

```bash
argon init                                   # create ~/.argon/vault.json
argon add GitHub -u octocat -g 24 --tags dev # generates and stores a 24-char password
argon add Auth --totp JBSWY3DPEHPK3PXP --no-password
argon get GitHub -s                          # show it
argon get GitHub -c                          # copy password to the clipboard (30s clear hint)
argon list --long
argon serve                                  # web UI at http://127.0.0.1:8420/?token=...
```

Vault location: `~/.argon/vault.json`, or `--vault PATH`, or `$ARGON_VAULT`.

## CLI

| command | what it does |
| --- | --- |
| `argon init [--force] [--time-cost N] [--memory-cost KiB] [--parallelism N]` | create a vault (tunes Argon2id) |
| `argon add NAME [-u USER] [-p PASS] [-g [LEN]] [--url URL] [--notes TEXT] [--totp SECRET] [--tags a,b] [--no-password] [-i]` | add an entry |
| `argon get NAME [-s] [-f FIELD] [-c] [--json]` | read one entry; `-f totp` computes the live code |
| `argon list [-q TEXT] [--tag TAG] [-l] [--json]` | search and list (metadata only) |
| `argon edit NAME [-u ...] [-p ...] [--totp ...] [--tags ...] [-g [LEN]]` | patch fields |
| `argon rm NAME [-y]` | delete |
| `argon gen [-l LEN] [--no-symbols] [--passphrase [N]] [--strength]` | generate a password or passphrase |
| `argon totp NAME [-w]` | print/watch a TOTP code |
| `argon export [-o FILE] [--encrypted]` | plaintext JSON export, or an encrypted copy of the vault |
| `argon import FILE [--replace] [--overwrite]` | merge an export back in |
| `argon passwd` | change the master password (fresh salt, full re-encrypt) |
| `argon audit [--verify] [--json]` | show or verify the hash-chained audit log |
| `argon info` | vault metadata without unlocking |
| `argon strength PASS` | entropy estimate + warnings |
| `argon serve [--host H] [--port N] [--open]` | local web UI |

`NAME` can be an id, an exact name, or an unambiguous name prefix.
Exit codes: `0` ok, `1` error (bad password, missing entry), `2` usage.

### Scripting

```bash
ARGON_VAULT=./team.json ARGON_MASTER_PASSWORD="$(pass show argon)" \
  argon get deploy-key -f password
```

`$ARGON_MASTER_PASSWORD` exists so pipelines do not have to synthesize a TTY. It is
visible in `/proc/<pid>/environ` and in shell history — prefer a TTY for interactive
use, and prefer `pass`/`op`/`systemd-creds` over literals for automation.

## Web UI

```bash
argon serve --port 8420
```

Open the printed URL (it carries the session token). The UI gives you search, an editor
with a built-in generator and strength meter, reveal/copy per field, live TOTP
countdowns, a tag filter, and an audit-log viewer.

How it stays safe on a machine where any browser tab can reach `127.0.0.1`:

* every `/api/*` call needs `X-Argon-Token`, a fresh 192-bit token generated per process
  and injected into the page shell — a cross-origin page cannot read it;
* no CORS headers are sent, and the CSP forbids inline script, external script, and
  framing from other origins;
* the `Host` header is checked against loopback names when bound to loopback
  (DNS-rebinding defence) and `Connection: close` is forced on error paths;
* static file serving is path-traversal checked; request bodies are capped at 64 KiB;
* auto-lock after 15 minutes idle; `POST /api/lock` drops the key and all plaintext.

`--host 0.0.0.0` is supported for containers/sandboxes; then the token is the only
barrier, and the server says so at startup.

## Crypto

| piece | choice | why |
| --- | --- | --- |
| KDF | Argon2id, t=3, m=64 MiB, p=4, 16-byte salt | memory-hard, GPU-resistant; params live in the header so old vaults keep working |
| Cipher | AES-256-GCM, 12-byte random nonce per entry | authenticated; tampering is fatal, not silent |
| Binding | entry id as AAD | ciphertexts cannot be swapped between entries |
| Key check | `HMAC-SHA256(key, "argon:vault:verify:v1")` | verifies the password without storing it or a hash of it |
| Audit | SHA-256 hash chain + HMAC seal over `(count, head)` | detects edits, reordering, *and* truncation |
| Password normalization | NFC | the same visual passphrase derives the same key on every platform |

Vault file (`JSON`, `0600`, written atomically via `mkstemp` → `fsync` → `os.replace`):

```json
{
  "format": "argon-vault",
  "version": 1,
  "kdf": { "algo": "argon2id", "time_cost": 3, "memory_cost": 65536,
           "parallelism": 4, "hash_len": 32, "salt": "…" },
  "verifier": "…",
  "entries": [ { "id": "…", "nonce": "…", "ct": "…", "updated": "…" } ],
  "audit": [ { "ts": "…", "action": "add", "detail": "…", "prev": "…", "digest": "…" } ],
  "audit_seal": "…"
}
```

What leaks by design: entry count, random entry ids, and update timestamps. Names,
usernames, passwords, URLs, notes, tags, and TOTP secrets exist only inside `ct`.

## Threat model

**Protected against:** stolen/backed-up vault file without the master password; offline
brute force (bounded by Argon2id cost, not by luck); silent bit-flips and edits (GCM
tags); ciphertext swapping between entries (AAD); local web pages poking the running UI
(token + no CORS); accidental logging of secrets (nothing is logged); backups that
capture a half-written file (atomic replace).

**Not protected against:** a compromised machine with a keylogger, a debugger, or root;
memory scraping while unlocked (Python cannot reliably zero `str`/`bytes`); someone who
knows your master password; a malicious `argon` binary; clipboard snoopers between copy
and paste; filesystems that ignore `0600`.

## Development

```bash
.venv/bin/python -m pytest -q       # 66 tests: crypto, vault, CLI, HTTP, RFC vectors
make test
make demo                           # seeded throwaway vault + UI, password printed
```

Layout:

```
argon/
  crypto.py     Argon2id, AES-GCM, verifier, base64, constant-time compare
  vault.py      file format, CRUD, atomic save, rekey, import/export, audit chain
  generator.py  passwords, passphrases, entropy + strength heuristics
  totp.py       RFC 4226/6238 + otpauth:// parsing (stdlib only)
  server.py     local HTTP API + static serving + session token
  cli.py        argparse front end
  web/          index.html, app.js, style.css (no build step, no CDN)
tests/          pytest suite
```

## Assumptions

* "Argon" here means the secrets vault; the repo shipped empty except for a Luau
  `.gitignore`, which this build replaces with Python ignores.
* Single-user, single-machine, file-based storage — sync it yourself if you want it on
  two devices, and remember the vault is only as safe as its weakest copy.

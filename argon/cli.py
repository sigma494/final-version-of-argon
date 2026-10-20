"""argon/cli.py - the `argon` command line interface.

    argon init
    argon add GitHub -u octocat --generate
    argon get GitHub --copy
    argon list
    argon serve

Exit codes: 0 success, 1 error (wrong password, missing entry, ...), 2 usage.
"""

from __future__ import annotations

import argparse
import getpass
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Sequence

from argon import crypto, generator, totp
from argon.vault import (
    ArgonError,
    BadPasswordError,
    Entry,
    EntryNotFound,
    Vault,
    VaultExistsError,
    VaultFormatError,
)

DEFAULT_VAULT = Path.home() / ".argon" / "vault.json"
ENV_VAULT = "ARGON_VAULT"
ENV_PASSWORD = "ARGON_MASTER_PASSWORD"  # convenience for scripts/CI; see README caveat


# ----------------------------------------------------------------------
# helpers
# ----------------------------------------------------------------------
def vault_path(args: argparse.Namespace) -> Path:
    configured = getattr(args, "vault", None) or os.environ.get(ENV_VAULT)
    return Path(configured).expanduser() if configured else DEFAULT_VAULT


def master_password(confirm: bool = False, allow_env: bool = True) -> str:
    if allow_env and os.environ.get(ENV_PASSWORD):
        return os.environ[ENV_PASSWORD]
    if not sys.stdin.isatty():
        line = sys.stdin.readline().rstrip("\n")
        if line:
            return line
        raise ArgonError("no master password available (stdin is not a TTY)")
    prompt = "New master password: " if confirm else "Master password: "
    first = getpass.getpass(prompt)
    if confirm:
        again = getpass.getpass("Repeat master password: ")
        if first != again:
            raise ArgonError("passwords did not match")
        report = generator.password_strength(first)
        if report.label in {"very weak", "weak"}:
            print(
                f"  warning: {report.label} master password (~{report.bits:.0f} bits). "
                "Argon2id slows attackers down but cannot save a weak phrase.",
                file=sys.stderr,
            )
    if not first:
        raise ArgonError("master password must not be empty")
    return first


def prompt(label: str, default: str = "", secret: bool = False) -> str:
    suffix = f" [{default}]" if default else ""
    if secret and sys.stdin.isatty():
        value = getpass.getpass(f"{label}{suffix}: ")
    else:
        value = input(f"{label}{suffix}: ")
    return value if value else default


def copy_to_clipboard(text: str) -> str | None:
    """Best-effort clipboard write. Returns the tool used, or None."""
    candidates = [
        (["wl-copy"], "wl-copy"),
        (["xclip", "-selection", "clipboard"], "xclip"),
        (["xsel", "--clipboard", "--input"], "xsel"),
        (["pbcopy"], "pbcopy"),
        (["clip.exe"], "clip.exe"),
        (["clip"], "clip"),
    ]
    for argv, name in candidates:
        if shutil.which(argv[0]):
            try:
                subprocess.run(argv, input=text.encode("utf-8"), check=True, timeout=5)
                return name
            except (subprocess.SubprocessError, OSError):
                continue
    return None


def open_vault(args: argparse.Namespace, password: str | None = None) -> Vault:
    path = vault_path(args)
    return Vault.open(path, password if password is not None else master_password())


def print_table(headers: Sequence[str], rows: Sequence[Sequence[str]]) -> None:
    data = [[str(c) for c in row] for row in rows]
    widths = [len(h) for h in headers]
    for row in data:
        for i, cell in enumerate(row):
            widths[i] = max(widths[i], len(cell))
    print("  ".join(h.ljust(widths[i]) for i, h in enumerate(headers)))
    print("  ".join("-" * w for w in widths))
    for row in data:
        print("  ".join(cell.ljust(widths[i]) for i, cell in enumerate(row)))


def parse_tags(value: str | None) -> list[str] | None:
    if value is None:
        return None
    return [t.strip() for t in value.split(",") if t.strip()]


def emit(entry: Entry, field: str, show: bool, as_json: bool) -> None:
    if as_json:
        print(json.dumps(entry.to_export_dict(), indent=2, ensure_ascii=False))
        return
    if field:
        value = getattr(entry, field, "")
        if field == "totp" and value:
            value = totp.totp(value)
        print(value)
        return
    masked = "********" if entry.password and not show else entry.password
    print(f"name:     {entry.name}")
    if entry.username:
        print(f"username: {entry.username}")
    if entry.password:
        print(f"password: {masked}")
    if entry.url:
        print(f"url:      {entry.url}")
    if entry.tags:
        print(f"tags:     {', '.join(entry.tags)}")
    if entry.totp:
        try:
            print(f"totp:     {totp.totp(entry.totp)}  ({totp.totp_remaining(period=30)}s left)")
        except totp.TotpError:
            print("totp:     <invalid secret>")
    if entry.notes:
        print(f"notes:    {entry.notes}")
    print(f"updated:  {entry.updated}")


# ----------------------------------------------------------------------
# commands
# ----------------------------------------------------------------------
def cmd_init(args: argparse.Namespace) -> int:
    path = vault_path(args)
    if path.exists() and not args.force:
        raise VaultExistsError(f"{path} already exists (use --force to replace it)")
    password = master_password(confirm=True)
    kdf = crypto.KdfParams(
        time_cost=args.time_cost,
        memory_cost=args.memory_cost,
        parallelism=args.parallelism,
    )
    started = time.perf_counter()
    Vault.create(path, password, kdf=kdf, overwrite=args.force)
    elapsed = time.perf_counter() - started
    print(f"vault created: {path}")
    print(f"kdf: argon2id t={args.time_cost} m={args.memory_cost}KiB p={args.parallelism} ({elapsed:.2f}s)")
    print("next: argon add GitHub -u you --generate")
    return 0


def cmd_add(args: argparse.Namespace) -> int:
    vault = open_vault(args)
    name = args.name or prompt("Name")
    if not name:
        raise ArgonError("entry name is required")
    username = args.username
    url = args.url
    notes = args.notes
    totp_secret = args.totp
    tags = parse_tags(args.tags) or []

    if args.interactive:
        username = username or prompt("Username", "")
        url = url or prompt("URL", "")
        notes = notes or prompt("Notes", "")

    password = args.password
    if args.generate:
        password = generator.generate_password(args.generate, exclude_ambiguous=True)
        print(f"generated: {password}", file=sys.stderr)
    if not password and not args.no_password:
        if args.interactive:
            password = prompt("Password", "", secret=True)
        elif sys.stdin.isatty():
            entered = getpass.getpass("Password (leave blank to generate): ")
            password = entered or generator.generate_password(20)
        else:
            raise ArgonError(
                "no password supplied (use -p, -g LEN, --no-password, or -i for prompts)"
            )

    if totp_secret:
        parsed = totp.parse_otpauth(totp_secret) if totp_secret.startswith("otpauth://") else None
        if parsed:
            totp_secret = str(parsed["secret"])
        totp.normalize_secret(totp_secret)  # validate early, fail loudly

    entry = Entry(
        name=name,
        username=username or "",
        password=password or "",
        url=url or "",
        notes=notes or "",
        totp=totp_secret or "",
        tags=tags,
    )
    vault.add(entry)
    vault.save()
    print(f"added {entry.name!r} ({entry.id})")
    return 0


def cmd_get(args: argparse.Namespace) -> int:
    vault = open_vault(args)
    entry = vault.get(args.name)
    if args.copy:
        value = entry.password if not args.field else getattr(entry, args.field, "")
        if args.field == "totp":
            value = totp.totp(entry.totp)
        if not value:
            raise ArgonError("nothing to copy")
        tool = copy_to_clipboard(value)
        if tool:
            vault._audit("copy", entry.id)  # metadata only, no secret
            vault.save()
            print(f"copied {args.field or 'password'} for {entry.name!r} via {tool}", file=sys.stderr)
            return 0
        print("no clipboard tool found; printing instead", file=sys.stderr)
        print(value)
        return 0
    emit(entry, args.field or "", args.show, args.json)
    return 0


def cmd_list(args: argparse.Namespace) -> int:
    vault = open_vault(args)
    entries = vault.search(args.query or "", args.tag or "")
    if args.json:
        print(json.dumps([e.to_public_dict() for e in entries], indent=2, ensure_ascii=False))
        return 0
    if not entries:
        print("no entries yet - `argon add <name>`")
        return 0
    if args.long:
        rows = [
            (e.name, e.username or "-", e.url or "-", ",".join(e.tags) or "-", e.updated[:10])
            for e in entries
        ]
        print_table(("name", "username", "url", "tags", "updated"), rows)
    else:
        print_table(("name", "username", "updated"), [(e.name, e.username or "-", e.updated[:10]) for e in entries])
    print(f"\n{len(entries)} entr{'y' if len(entries) == 1 else 'ies'} in {vault.path}")
    return 0


def cmd_edit(args: argparse.Namespace) -> int:
    vault = open_vault(args)
    entry = vault.get(args.name)
    updates: dict[str, Any] = {}
    for field in ("username", "url", "notes", "totp"):
        value = getattr(args, field, None)
        if value is not None:
            updates[field] = value
    if args.new_name is not None:
        updates["name"] = args.new_name
    if args.tags is not None:
        updates["tags"] = parse_tags(args.tags)
    if args.password is not None:
        updates["password"] = args.password
    if args.generate:
        updates["password"] = generator.generate_password(args.generate, exclude_ambiguous=True)
        print(f"generated: {updates['password']}", file=sys.stderr)
    if not updates:
        print("nothing to change (use -u/--url/--notes/--totp/--tags/--password/--generate)", file=sys.stderr)
        return 2
    if updates.get("totp"):
        totp.normalize_secret(updates["totp"])
    vault.update(entry.id, **updates)
    vault.save()
    print(f"updated {entry.name!r}")
    return 0


def cmd_rm(args: argparse.Namespace) -> int:
    vault = open_vault(args)
    entry = vault.get(args.name)
    if not args.yes:
        if not sys.stdin.isatty():
            raise ArgonError("refusing to delete without --yes when stdin is not a TTY")
        if prompt(f"Delete {entry.name!r}? [y/N]", "N").strip().lower() not in {"y", "yes"}:
            print("cancelled")
            return 1
    vault.delete(entry.id)
    vault.save()
    print(f"deleted {entry.name!r}")
    return 0


def cmd_gen(args: argparse.Namespace) -> int:
    if args.passphrase:
        out = generator.generate_passphrase(args.passphrase, with_number=args.with_number)
    else:
        out = generator.generate_password(
            args.length,
            upper=not args.no_upper,
            lower=not args.no_lower,
            digits=not args.no_digits,
            symbols=not args.no_symbols,
            exclude_ambiguous=args.exclude_ambiguous,
        )
    print(out)
    if args.strength:
        report = generator.password_strength(out)
        print(f"strength: {report.label} (~{report.bits:.0f} bits)", file=sys.stderr)
    return 0


def cmd_totp(args: argparse.Namespace) -> int:
    vault = open_vault(args)
    entry = vault.get(args.name)
    if not entry.totp:
        raise ArgonError(f"{entry.name!r} has no TOTP secret")
    if not args.watch:
        print(totp.totp(entry.totp))
        print(f"{totp.totp_remaining()}s remaining", file=sys.stderr)
        return 0
    try:
        while True:
            code = totp.totp(entry.totp)
            left = totp.totp_remaining()
            bar = "#" * left + "." * (30 - left)
            print(f"\r{code}  [{bar}] {left:2d}s ", end="", flush=True)
            time.sleep(1)
    except KeyboardInterrupt:
        print()
    return 0


def cmd_export(args: argparse.Namespace) -> int:
    path = vault_path(args)
    if not args.encrypted:
        vault = open_vault(args)
        payload = vault.export_plaintext()
        blob = json.dumps(payload, indent=2, ensure_ascii=False)
        if args.output:
            out = Path(args.output).expanduser()
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_text(blob, encoding="utf-8")
            out.chmod(0o600)
            print(f"wrote {len(payload['entries'])} PLAINTEXT entries to {out}", file=sys.stderr)
            print("delete it once imported", file=sys.stderr)
        else:
            print(blob)
        return 0
    target = Path(args.output).expanduser() if args.output else path.with_suffix(".backup.json")
    shutil.copy2(path, target)
    target.chmod(0o600)
    print(f"copied encrypted vault to {target}")
    return 0


def cmd_import(args: argparse.Namespace) -> int:
    source = Path(args.file).expanduser()
    if not source.exists():
        raise ArgonError(f"no such file: {source}")
    try:
        data = json.loads(source.read_text("utf-8"))
    except json.JSONDecodeError as exc:
        raise VaultFormatError(f"import file is not JSON: {exc}") from exc
    vault = open_vault(args)
    added, skipped = vault.import_plaintext(
        data, merge=not args.replace, overwrite_existing=args.overwrite
    )
    vault.save()
    print(f"imported {added}, skipped {skipped}, vault now holds {len(vault)}")
    return 0


def cmd_passwd(args: argparse.Namespace) -> int:
    vault = open_vault(args)  # proves possession of the current password
    new = master_password(confirm=True, allow_env=False)
    vault.rekey(new)
    print("master password changed; every entry was re-encrypted with a fresh salt")
    return 0


def cmd_audit(args: argparse.Namespace) -> int:
    vault = open_vault(args)
    if args.verify:
        ok, message = vault.verify_audit_chain()
        print(("OK: " if ok else "FAILED: ") + message)
        return 0 if ok else 1
    if args.json:
        print(json.dumps(vault.audit, indent=2))
        return 0
    rows = [(r["ts"], r["action"], r["detail"]) for r in vault.audit[-args.limit :]]
    print_table(("when", "action", "detail"), rows)
    return 0


def cmd_info(args: argparse.Namespace) -> int:
    path = vault_path(args)
    size = path.stat().st_size if path.exists() else 0
    print(f"vault:  {path}")
    print(f"exists: {path.exists()}" + (f" ({size} bytes)" if path.exists() else ""))
    if not path.exists():
        return 0
    raw = json.loads(path.read_text("utf-8"))
    kdf = raw.get("kdf", {})
    print(f"format: {raw.get('format')} v{raw.get('version')}")
    print(f"created: {raw.get('created')}")
    print(f"kdf: {kdf.get('algo')} t={kdf.get('time_cost')} m={kdf.get('memory_cost')}KiB p={kdf.get('parallelism')}")
    print(f"entries: {len(raw.get('entries', []))}")
    return 0


def cmd_serve(args: argparse.Namespace) -> int:
    from argon.server import serve

    return serve(
        path=vault_path(args),
        host=args.host,
        port=args.port,
        open_browser=args.open,
    )


def cmd_strength(args: argparse.Namespace) -> int:
    report = generator.password_strength(args.password)
    print(json.dumps(report.as_dict(), indent=2))
    return 0


# ----------------------------------------------------------------------
# parser
# ----------------------------------------------------------------------
def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="argon",
        description="Argon - local-first, zero-knowledge secrets vault.",
        epilog="Vault defaults to ~/.argon/vault.json (override with --vault or $ARGON_VAULT).",
    )
    parser.add_argument("--vault", help="path to the vault file")
    parser.add_argument("--version", action="version", version="argon 1.0.0")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("init", help="create a new vault")
    p.add_argument("--force", action="store_true", help="overwrite an existing vault (keeps a .bak)")
    p.add_argument("--time-cost", type=int, default=3)
    p.add_argument("--memory-cost", type=int, default=65536, help="KiB of RAM for Argon2id")
    p.add_argument("--parallelism", type=int, default=4)
    p.set_defaults(func=cmd_init)

    p = sub.add_parser("add", help="add an entry")
    p.add_argument("name", nargs="?")
    p.add_argument("-u", "--username")
    p.add_argument("-p", "--password")
    p.add_argument("--url")
    p.add_argument("--notes")
    p.add_argument("--totp", help="base32 secret or otpauth:// URI")
    p.add_argument("--tags", help="comma separated")
    p.add_argument("-g", "--generate", nargs="?", type=int, const=20, metavar="LEN",
                   help="generate a password instead of asking (default 20)")
    p.add_argument("--no-password", action="store_true", help="store an entry with no password")
    p.add_argument("-i", "--interactive", action="store_true", help="prompt for every field")
    p.set_defaults(func=cmd_add)

    p = sub.add_parser("get", help="show one entry")
    p.add_argument("name")
    p.add_argument("-s", "--show", action="store_true", help="print the password in clear")
    p.add_argument("-f", "--field", choices=["username", "password", "url", "notes", "totp"])
    p.add_argument("-c", "--copy", action="store_true", help="copy to clipboard")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_get)

    p = sub.add_parser("list", help="list entries")
    p.add_argument("-q", "--query", nargs="?", const="")
    p.add_argument("--tag")
    p.add_argument("-l", "--long", action="store_true")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_list)

    p = sub.add_parser("edit", help="change fields on an entry")
    p.add_argument("name")
    p.add_argument("--name-new", dest="new_name")
    p.add_argument("-u", "--username")
    p.add_argument("-p", "--password")
    p.add_argument("--url")
    p.add_argument("--notes")
    p.add_argument("--totp")
    p.add_argument("--tags")
    p.add_argument("-g", "--generate", nargs="?", type=int, const=20, metavar="LEN")
    p.set_defaults(func=cmd_edit)

    p = sub.add_parser("rm", help="delete an entry")
    p.add_argument("name")
    p.add_argument("-y", "--yes", action="store_true")
    p.set_defaults(func=cmd_rm)

    p = sub.add_parser("gen", help="generate a password or passphrase")
    p.add_argument("-l", "--length", type=int, default=20)
    p.add_argument("--no-symbols", action="store_true")
    p.add_argument("--no-digits", action="store_true")
    p.add_argument("--no-upper", action="store_true")
    p.add_argument("--no-lower", action="store_true")
    p.add_argument("--exclude-ambiguous", action="store_true")
    p.add_argument("--passphrase", nargs="?", type=int, const=6, metavar="WORDS")
    p.add_argument("--with-number", action="store_true")
    p.add_argument("--strength", action="store_true")
    p.set_defaults(func=cmd_gen)

    p = sub.add_parser("totp", help="print the current TOTP code for an entry")
    p.add_argument("name")
    p.add_argument("-w", "--watch", action="store_true")
    p.set_defaults(func=cmd_totp)

    p = sub.add_parser("export", help="export entries (plaintext JSON or encrypted copy)")
    p.add_argument("-o", "--output")
    p.add_argument("--encrypted", action="store_true", help="copy the encrypted vault file instead")
    p.set_defaults(func=cmd_export)

    p = sub.add_parser("import", help="import a JSON export")
    p.add_argument("file")
    p.add_argument("--replace", action="store_true", help="wipe existing entries first")
    p.add_argument("--overwrite", action="store_true", help="overwrite entries with the same name")
    p.set_defaults(func=cmd_import)

    p = sub.add_parser("passwd", help="change the master password")
    p.set_defaults(func=cmd_passwd)

    p = sub.add_parser("audit", help="show or verify the hash-chained audit log")
    p.add_argument("--verify", action="store_true")
    p.add_argument("--limit", type=int, default=30)
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_audit)

    p = sub.add_parser("info", help="show vault metadata without unlocking")
    p.set_defaults(func=cmd_info)

    p = sub.add_parser("strength", help="score a password")
    p.add_argument("password")
    p.set_defaults(func=cmd_strength)

    p = sub.add_parser("serve", help="run the local web UI")
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=8420)
    p.add_argument("--open", action="store_true", help="open a browser")
    p.set_defaults(func=cmd_serve)

    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return int(args.func(args) or 0)
    except (ArgonError, ValueError, OSError, totp.TotpError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("\ninterrupted", file=sys.stderr)
        return 130


if __name__ == "__main__":
    raise SystemExit(main())

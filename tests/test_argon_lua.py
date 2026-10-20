"""tests/test_argon_lua.py - run Argon.lua against a fake Roblox API.

Requires `lupa` (dev-only). The library itself has no dependency on Python; this
exists so a Lua UI library gets an actual test suite instead of vibes.
"""

from __future__ import annotations

from pathlib import Path

import pytest

lupa = pytest.importorskip("lupa", reason="pip install lupa to run the Luau smoke suite")

ROOT = Path(__file__).resolve().parent.parent
ARGON = ROOT / "Argon.lua"
MOCK = ROOT / "tests" / "roblox_mock.lua"
SMOKE = ROOT / "tests" / "smoke.lua"


def build_runtime():
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute("loadstring = load; getgenv = function() return _G end")
    lua.globals().robloxMock = lua.execute(MOCK.read_text(encoding="utf-8"))

    # expose the mock's globals (Vector2, Color3, Instance, Enum, task, ...) like Roblox does
    for name in (
        "Vector2", "UDim", "UDim2", "Color3", "ColorSequence", "NumberSequence",
        "NumberSequenceKeypoint", "ColorSequenceKeypoint", "NumberRange", "TweenInfo",
        "Enum", "typeof", "Instance", "game", "task", "wait",
        "UserInputService", "TweenService", "RunService", "HttpService", "CoreGui",
        "Players", "Workspace", "readfile", "writefile", "isfile", "isfolder",
        "makefolder", "listfiles", "delfile",
    ):
        lua.execute(f"{name} = robloxMock.{name}")

    lua.globals().ARGON_SOURCE = ARGON.read_text(encoding="utf-8")
    return lua


@pytest.fixture(scope="module")
def smoke_results():
    lua = build_runtime()
    # smoke.lua ends with `return results`, so execute() hands back the table itself
    results = lua.execute(SMOKE.read_text(encoding="utf-8"))
    return {
        "passed": int(results["passed"]),
        "failed": int(results["failed"]),
        "messages": [str(m) for m in results["messages"].values()],
        "mock_errors": [str(e) for e in results["mockErrors"].values()],
    }


def test_smoke_suite_reports_success(smoke_results):
    assert smoke_results["failed"] == 0, "\n".join(smoke_results["messages"])


def test_no_unhandled_lua_errors(smoke_results):
    assert smoke_results["mock_errors"] == [], "\n".join(smoke_results["mock_errors"])


def test_smoke_suite_actually_tests_something(smoke_results):
    assert smoke_results["passed"] >= 60, f"only {smoke_results['passed']} assertions ran"


def strip_lua_comments(source: str) -> str:
    """Drop block and line comments so static checks only see executable code."""
    import re

    source = re.sub(r"--\[(=*)\[.*?\]\1\]", "", source, flags=re.S)
    return "\n".join(line.split("--")[0] for line in source.splitlines())


def test_library_is_single_file_and_self_contained():
    source = ARGON.read_text(encoding="utf-8")
    code = strip_lua_comments(source)
    assert "HttpGet" not in code, "no self-fetch at load time"
    assert "require(" not in code, "no module dependencies"
    assert "loadstring(" not in code, "no nested loadstring"
    assert "getgenv()" in code, "library publishes itself to getgenv()"
    assert len(source.splitlines()) < 4000, "keep the single file reviewable"


def test_library_has_no_placeholder_leftovers():
    source = strip_lua_comments(ARGON.read_text(encoding="utf-8"))
    for marker in ("TODO", "FIXME", "rest of the code", "<insert", "chevronSwap"):
        assert marker not in source, f"leftover marker: {marker}"


def test_public_api_surface():
    lua = build_runtime()
    lib = lua.execute("return loadstring(ARGON_SOURCE)()")
    for method in ("Window", "Notify", "GetFlag", "SetFlag", "GetFlags", "Unload", "Destroy", "SetAccent"):
        assert lib[method] is not None, f"Argon:{method} missing"

    window = lua.eval("Argon:Window({})")
    for method in ("Tab", "Notify", "SelectTab", "SetTitle", "SetSubtitle", "SetVisible", "Toggle",
                   "SaveConfig", "LoadConfig", "GetConfigs", "DeleteConfig", "SetAccent", "Destroy"):
        assert window[method] is not None, f"Window:{method} missing"

    tab = window.Tab(window, lua.eval("{Name = 'T'}"))
    for method in ("Section", "Refresh", "Destroy"):
        assert tab[method] is not None, f"Tab:{method} missing"

    section = tab.Section(tab, lua.eval("{Name = 'S'}"))
    for method in ("Toggle", "Slider", "Dropdown", "Input", "Button", "Label", "Paragraph",
                   "Divider", "Space", "ColorPicker", "Keybind", "Search", "Refresh",
                   "SetName", "Collapse", "SetVisible", "UpdateOrder"):
        assert section[method] is not None, f"Section:{method} missing"

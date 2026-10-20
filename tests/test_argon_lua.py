"""tests/test_argon_lua.py - run Argon.lua against a fake Roblox API.

Requires `lupa` (dev only). Argon itself has no Python dependency; this suite
exists so the library is exercised instead of eyeballed.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

lupa = pytest.importorskip("lupa", reason="pip install lupa to run the Lua suite")

ROOT = Path(__file__).resolve().parent.parent
ARGON = ROOT / "Argon.lua"
MOCK = ROOT / "tests" / "roblox_mock.lua"
SMOKE = ROOT / "tests" / "smoke.lua"
DOCS = ROOT / "tests" / "docs_api.lua"
CHROME = ROOT / "tests" / "chrome.lua"

EXPORTS = (
    "Vector2", "Vector3", "UDim", "UDim2", "Color3", "ColorSequence", "NumberSequence",
    "NumberSequenceKeypoint", "ColorSequenceKeypoint", "NumberRange", "TweenInfo",
    "Enum", "typeof", "Instance", "game", "task", "wait",
    "UserInputService", "TweenService", "RunService", "HttpService", "CoreGui",
    "Players", "Workspace", "readfile", "writefile", "isfile", "isfolder",
    "makefolder", "listfiles", "delfile", "click",
)


def build_runtime():
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute("loadstring = load; getgenv = function() return _G end")
    lua.globals().robloxMock = lua.execute(MOCK.read_text(encoding="utf-8"))

    for name in EXPORTS:
        lua.execute(f"{name} = robloxMock.{name}")

    lua.execute("workspace = robloxMock.Workspace")
    lua.globals().ARGON_SOURCE = ARGON.read_text(encoding="utf-8")
    lua.execute("loadstring = function() return function() return load(ARGON_SOURCE)() end end")
    return lua


@pytest.fixture(scope="module")
def smoke_results():
    lua = build_runtime()
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


def test_smoke_suite_is_substantial(smoke_results):
    assert smoke_results["passed"] >= 120, f"only {smoke_results['passed']} assertions ran"


def run_lua_suite(lua, source: str, name: str) -> dict:
    lua.globals().SUITE_SOURCE = source
    lua.globals().SUITE_NAME = name
    results = lua.execute("""
        local chunk, compileError = load(SUITE_SOURCE, SUITE_NAME)
        if not chunk then
            return { passed = 0, failed = 1, messages = { "COMPILE: " .. tostring(compileError) }, mockErrors = {} }
        end
        local ok, res = xpcall(chunk, function(err) return debug.traceback(tostring(err)) end)
        if not ok then
            return { passed = 0, failed = 1, messages = { "RUNTIME: " .. tostring(res) }, mockErrors = {} }
        end
        return res
    """)
    return {
        "passed": int(results["passed"]),
        "failed": int(results["failed"]),
        "messages": [str(m) for m in results["messages"].values()],
        "mock_errors": [str(e) for e in results["mockErrors"].values()]
        if results["mockErrors"] is not None
        else [],
    }


@pytest.fixture(scope="module")
def chrome_results():
    lua = build_runtime()
    return run_lua_suite(lua, CHROME.read_text(encoding="utf-8"), "chrome")


def test_chrome_state_machine(chrome_results):
    """The four reference states: rail, rail+sidebar, rail+page, rail+sidebar+page."""
    assert chrome_results["failed"] == 0, "\n".join(chrome_results["messages"])


def test_chrome_suite_is_substantial(chrome_results):
    assert chrome_results["passed"] >= 80, f"only {chrome_results['passed']} chrome assertions ran"


def test_hover_state_machine_exists():
    """Regression guard: the sidebar must be pointer-rect driven, not per-child
    MouseEnter, or a collapsing panel strands the hover flag mid-transition."""
    code = strip_lua_comments(ARGON.read_text(encoding="utf-8"))
    for symbol in ("ProbePointer", "SetHovered", "UpdateChrome", "GetMouseLocation"):
        assert symbol in code, f"hover machinery missing: {symbol}"


def strip_lua_comments(source: str) -> str:
    source = re.sub(r"--\[(=*)\[.*?\]\1\]", "", source, flags=re.S)
    return "\n".join(line.split("--")[0] for line in source.splitlines())


def test_library_is_single_file_and_self_contained():
    source = ARGON.read_text(encoding="utf-8")
    code = strip_lua_comments(source)
    assert "HttpGet" not in code, "no self-fetch at load time"
    assert "require(" not in code, "no module dependencies"
    assert "loadstring(" not in code, "no nested loadstring"
    assert "getgenv()" in code, "publishes itself to getgenv()"


def test_library_size_matches_the_brief():
    source = ARGON.read_text(encoding="utf-8")
    lines = source.splitlines()
    assert len(lines) >= 8000, f"expected a full library, got {len(lines)} lines"
    assert len(source) > 200_000, "unexpectedly small source"


def test_no_placeholders_left():
    source = strip_lua_comments(ARGON.read_text(encoding="utf-8"))
    for marker in ("TODO", "FIXME", "rest of the code", "<insert", "not implemented"):
        assert marker.lower() not in source.lower(), f"leftover marker: {marker}"


def test_public_api_surface():
    lua = build_runtime()
    lib = lua.execute("return loadstring()()")
    for method in (
        "Window", "Notify", "Dialog", "Toolbar", "Watermark", "SetTheme", "GetTheme",  # noqa
        "GetThemeNames", "SetAccent", "RegisterTheme", "ThemeTemplate", "BuildConfigPage",
        "GetFlag", "SetFlag", "GetFlags", "OnFlagChanged", "SaveConfig", "LoadConfig",
        "GetConfigs", "DeleteConfig", "EnableAutoSave", "BindKey", "UnbindKey",
        "GetUptime", "IsMobile", "GetViewportSize", "ShowLoading", "Unload", "GetVersion",
    ):
        assert lib[method] is not None, f"Argon:{method} missing"

    window = lib.Window(lib, lua.eval("{Title = 'API'}"))
    for method in (
        "Page", "SelectPage", "GetPage", "SetTitle", "SetSubtitle", "SetUser", "SetTheme",
        "SetAccent", "SetMinimized", "SetVisible", "Toggle", "Refresh", "Notify", "Dialog",
        "OnFlagChanged", "Destroy",
    ):
        assert window[method] is not None, f"Window:{method} missing"

    page = window.Page(window, lua.eval("{Name = 'P'}"))
    for method in (
        "Section", "Pills", "Search", "Action", "SetActionEnabled", "SetPill", "ApplyFilter",
        "Refresh", "ScrollToTop", "SetSubtitle", "SetVisible", "Destroy",
        # v3 chrome + wizard surface
        "Footer", "Steps", "StatCard", "FileRow", "Callout", "CardList",
        "SetPrimaryText", "SetPrimaryEnabled", "SetBackVisible", "SetBackText",
        "IsActionEnabled",
    ):
        assert page[method] is not None, f"Page:{method} missing"

    for method in ("SetLayout", "SetRailOnly", "SetHovered", "ClosePage", "UpdateChrome",
                   "CurrentWidth", "PaneWidth", "StartPointerTracking", "DestroyProbe"):
        assert window[method] is not None, f"Window:{method} missing"

    section = page.Section(page, lua.eval("{Name = 'S'}"))

    for method in ("Steps", "StatCard", "FileRow", "Callout", "CardList"):
        assert section[method] is not None, f"Section:{method} missing"
    for method in (
        "Toggle", "Checkbox", "Slider", "Input", "Textarea", "Keybind", "Button",
        "DualButton", "ColorPicker", "ThemePicker", "Card", "Table", "Label", "Paragraph",
        "Divider", "Space", "Progress", "Tag", "UserRow", "Banner", "Image",
        "Collapse", "SetName", "SetVisible", "Refresh", "Clear", "UpdateOrder", "Destroy",
    ):
        assert section[method] is not None, f"Section:{method} missing"


def test_examples_load_without_errors():
    """Every shipped example must build against the mock without throwing."""
    lua = build_runtime()
    lib = lua.execute("return loadstring()()")
    for example in sorted((ROOT / "examples").glob("*.lua")):
        source = example.read_text(encoding="utf-8")
        result = lua.execute(source)
        assert result is not None, f"{example.name} returned nothing"
        assert lua.globals().robloxMock.errors is not None
        errors = [str(e) for e in lua.globals().robloxMock.errors.values()]
        assert errors == [], f"{example.name} raised: {errors}"
    assert lib is not None


def test_documented_api_matches_implementation():
    """Every call in README.md / examples must run (tests/docs_api.lua mirrors them)."""
    lua = build_runtime()
    results = lua.execute(DOCS.read_text(encoding="utf-8"))
    failures = [str(m) for m in results["messages"].values()]
    assert int(results["failed"]) == 0, "\n".join(failures)
    assert int(results["passed"]) >= 120, f"only {int(results['passed'])} doc assertions ran"
    errors = [str(e) for e in results["mockErrors"].values()]
    assert errors == [], "\n".join(errors)

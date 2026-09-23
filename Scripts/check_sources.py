#!/usr/bin/env python3
"""Static checks for the JARVIS sources.

This runs without Xcode, so it works on any machine and in CI. It catches
the mistakes that are easy to make in a large SwiftUI codebase and that a
compiler is not always strict about:

  * unbalanced brackets, braces, or parentheses
  * emoji or pictographic characters anywhere in the sources or docs
  * API keys accidentally committed
  * leftover TODO and FIXME markers
  * invalid JSON assets and plists
  * symbols that are referenced but never defined

Exit status is non zero when any check fails.
"""

from __future__ import annotations

import json
import plistlib
import re
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIR = ROOT / "Jarvis"
TEXT_SUFFIXES = {".swift", ".md", ".plist", ".entitlements", ".json", ".yml", ".yaml", ".sh", ".py"}

failures: list[str] = []
notes: list[str] = []


def fail(message: str) -> None:
    failures.append(message)


def text_files() -> list[Path]:
    files = []
    for path in ROOT.rglob("*"):
        if not path.is_file():
            continue
        if ".git" in path.parts or path.name.startswith("."):
            continue
        if path.suffix in TEXT_SUFFIXES:
            files.append(path)
    return sorted(files)


def swift_files() -> list[Path]:
    return sorted(p for p in SOURCE_DIR.rglob("*.swift") if p.is_file())


def strip_swift_noise(source: str) -> str:
    """Removes comments and string literals so bracket checks are meaningful."""
    result = []
    index = 0
    length = len(source)
    while index < length:
        char = source[index]
        two = source[index : index + 2]
        if two == "//":
            while index < length and source[index] != "\n":
                index += 1
            continue
        if two == "/*":
            depth = 1
            index += 2
            while index < length and depth:
                if source[index : index + 2] == "/*":
                    depth += 1
                    index += 2
                elif source[index : index + 2] == "*/":
                    depth -= 1
                    index += 2
                else:
                    index += 1
            continue
        if char == '"':
            if source[index : index + 3] == '"""':
                end = source.find('"""', index + 3)
                index = length if end == -1 else end + 3
                continue
            index += 1
            while index < length:
                if source[index] == "\\":
                    index += 2
                    continue
                if source[index] == '"':
                    index += 1
                    break
                index += 1
            continue
        result.append(char)
        index += 1
    return "".join(result)


def check_brackets() -> None:
    pairs = {")": "(", "]": "[", "}": "{"}
    for path in swift_files():
        cleaned = strip_swift_noise(path.read_text(encoding="utf-8"))
        stack: list[tuple[str, int]] = []
        line = 1
        for char in cleaned:
            if char == "\n":
                line += 1
            elif char in "([{":
                stack.append((char, line))
            elif char in ")]}":
                if not stack or stack[-1][0] != pairs[char]:
                    fail(f"{path.relative_to(ROOT)}:{line}: unmatched {char}")
                    break
                stack.pop()
        if stack:
            char, line = stack[-1]
            fail(f"{path.relative_to(ROOT)}:{line}: unclosed {char}")


def is_emoji(char: str) -> bool:
    code = ord(char)
    if code in (0x200D, 0xFE0F, 0x20E3):
        return True
    if 0x1F000 <= code <= 0x1FAFF:
        return True
    if 0x2600 <= code <= 0x27BF:
        return True
    if 0x1F1E6 <= code <= 0x1F1FF:
        return True
    if unicodedata.category(char) == "So":
        return True
    return False


def check_emoji() -> None:
    for path in text_files():
        try:
            content = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for number, line in enumerate(content.splitlines(), start=1):
            for char in line:
                if is_emoji(char):
                    fail(
                        f"{path.relative_to(ROOT)}:{number}: emoji or pictograph "
                        f"{char!r} (U+{ord(char):04X}) is not allowed"
                    )
                    break


KEY_PATTERN = re.compile(r"(sk-[A-Za-z0-9]{8,}|sk-ant-[A-Za-z0-9\-_]{8,}|AIza[A-Za-z0-9\-_]{20,}|gsk_[A-Za-z0-9]{20,})")


def check_secrets() -> None:
    for path in text_files():
        if path.suffix not in {".swift", ".md", ".json", ".plist", ".yml", ".yaml", ".sh"}:
            continue
        try:
            content = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for number, line in enumerate(content.splitlines(), start=1):
            match = KEY_PATTERN.search(line)
            if match and "placeholder" not in line.lower():
                fail(f"{path.relative_to(ROOT)}:{number}: looks like a committed API key")


def check_markers() -> None:
    for path in swift_files():
        content = path.read_text(encoding="utf-8")
        for number, line in enumerate(content.splitlines(), start=1):
            stripped = line.strip()
            if stripped.startswith("// TODO") or stripped.startswith("// FIXME") or "XXX" in stripped:
                fail(f"{path.relative_to(ROOT)}:{number}: unresolved marker: {stripped[:80]}")


def check_assets() -> None:
    for path in ROOT.rglob("*.json"):
        if ".git" in path.parts:
            continue
        try:
            json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as error:
            fail(f"{path.relative_to(ROOT)}: invalid JSON ({error})")

    for path in list(ROOT.rglob("*.plist")) + list(ROOT.rglob("*.entitlements")):
        if ".git" in path.parts:
            continue
        try:
            with path.open("rb") as handle:
                plistlib.load(handle)
        except Exception as error:  # noqa: BLE001 - reported to the user
            fail(f"{path.relative_to(ROOT)}: invalid plist ({error})")


APP_TYPE_DECLARATION = re.compile(
    r"\b(?:struct|class|enum|actor|protocol|typealias)\s+([A-Z]\w*)"
)
MEMBER_DECLARATION = re.compile(
    r"\b(?:let|var|func|case|enum|struct|class|actor|protocol|typealias|init)\s+([A-Za-z_]\w*)"
)
MEMBER_ACCESS = re.compile(r"\b([A-Z]\w*)\.([a-zA-Z_]\w*)")

# Members that come from the language or the standard library rather than
# from a declaration in this project.
INHERITED_MEMBERS = {
    "allCases", "id", "rawValue", "self", "init", "count", "isEmpty", "first", "last",
    "description", "hashValue", "Type", "none", "any", "some", "debugDescription",
    "localizedDescription", "errorDescription",
}

TUPLE_KEYPATH = re.compile(r"id:\s*\\\.[0-9]")


def check_namespaced_members() -> None:
    """Reports `Type.member` accesses where the member is never declared.

    This catches typos in the project's own namespaced API, which the
    compiler cannot check when the name happens to exist elsewhere.
    """
    sources = {path: strip_swift_noise(path.read_text(encoding="utf-8")) for path in swift_files()}

    app_types: set[str] = set()
    members: set[str] = set()
    for content in sources.values():
        app_types.update(APP_TYPE_DECLARATION.findall(content))
        members.update(MEMBER_DECLARATION.findall(content))

    for path, content in sources.items():
        for match in MEMBER_ACCESS.finditer(content):
            namespace, member = match.group(1), match.group(2)
            if namespace not in app_types:
                continue
            if member in INHERITED_MEMBERS or member in members:
                continue
            fail(
                f"{path.relative_to(ROOT)}: {namespace}.{member} is used but never "
                f"declared in the project"
            )


def check_tuple_key_paths() -> None:
    """Swift key paths cannot address tuple elements, so they are rejected."""
    for path in swift_files():
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            if TUPLE_KEYPATH.search(line):
                fail(f"{path.relative_to(ROOT)}:{number}: key path into a tuple element is not allowed")


def check_references() -> None:
    """Verifies that every type referenced in the app exists in the module."""
    content = "\n".join(path.read_text(encoding="utf-8") for path in swift_files())
    required = [
        "JarvisApp", "ContentView", "AppEnvironment", "AppSettings", "APIKeyStore",
        "KeychainStore", "PermissionService", "AIChatService", "AIProviderFactory",
        "AnthropicProvider", "OpenAIProvider", "OpenAICompatibleProvider", "GeminiProvider",
        "AssistantToolCatalog", "AssistantContext", "AutomationToolBridge", "AutomationConfirmationCenter",
        "AppleScriptRunner", "ApplicationLauncher", "BrowserAutomation", "FinderAutomation",
        "MusicAutomation", "CalendarAutomation", "CommandWhitelist", "ShellCommandRunner",
        "ProcessExecutor", "PathGuard", "TaskService", "HomeworkService", "NoteService",
        "CalendarStore", "SystemMonitorService", "SystemMetricsSampler", "WeatherService",
        "ClockService", "SpeechRecognitionService", "FocusTimerService", "QuickToolsService",
        "DashboardView", "AssistantPanel", "SettingsView", "TasksView", "HomeworkView",
        "FilesView", "AppsView", "CalendarScreenView", "JarvisTheme", "AppState",
        "TaskItem", "HomeworkItem", "NoteItem", "CalendarEventItem", "FocusSessionRecord",
        "ChatMessageRecord", "AppShortcut", "SystemMetrics", "WeatherSnapshot",
    ]
    for name in required:
        if not re.search(r"\b(struct|class|enum|actor|protocol)\s+" + name + r"\b", content):
            fail(f"expected type {name} is not defined in the sources")



TOOL_CONSTANT = re.compile(r"static let (\w+) = \"(\w+)\"")
SCHEMA_ENTRY = re.compile(r"^\s{12}(\w+),?$", re.M)
BRIDGE_CASE = re.compile(r"case AssistantToolName\.(\w+):")


def check_tool_wiring() -> None:
    """Every declared tool must have a schema and a bridge handler."""
    tools_path = SOURCE_DIR / "AI" / "AssistantTools.swift"
    bridge_path = SOURCE_DIR / "Automation" / "AutomationToolBridge.swift"
    if not tools_path.exists() or not bridge_path.exists():
        fail("tool definition files are missing")
        return

    tools_source = tools_path.read_text(encoding="utf-8")
    bridge_source = bridge_path.read_text(encoding="utf-8")

    constants = TOOL_CONSTANT.findall(tools_source)
    if not constants:
        fail("no assistant tool names were found")

    catalog_block = tools_source.split("static var allSchemas")[1].split("static func schemas")[0]
    catalog_entries = set()
    for line in catalog_block.splitlines():
        token = line.strip().rstrip(",")
        if re.fullmatch(r"[a-zA-Z_]\w*", token):
            catalog_entries.add(token)

    handled = set(BRIDGE_CASE.findall(bridge_source))

    for identifier, wire_name in constants:
        if identifier not in catalog_entries:
            fail(f"tool {identifier} ({wire_name}) is missing from AssistantToolCatalog.allSchemas")
        if identifier not in handled:
            fail(f"tool {identifier} ({wire_name}) has no handler in AutomationToolBridge")


def main() -> int:
    check_brackets()
    check_emoji()
    check_secrets()
    check_markers()
    check_assets()
    check_namespaced_members()
    check_tuple_key_paths()
    check_references()
    check_tool_wiring()

    print(f"Checked {len(swift_files())} Swift files in {SOURCE_DIR.relative_to(ROOT)}")

    for note in notes:
        print(f"note: {note}")

    if failures:
        print("\nFAILURES")
        for failure in failures:
            print(f"  {failure}")
        return 1

    print("All checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

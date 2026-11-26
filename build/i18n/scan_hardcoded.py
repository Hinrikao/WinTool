#!/usr/bin/env python3
"""Fail if new user-visible English literals are not in the i18n table."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EN = json.loads((ROOT / "data/i18n/en.json").read_text(encoding="utf-8"))
ALLOW = ROOT / "build/i18n/scan-allowlist.txt"

# Values and keys already accounted for
ENGLISH_VALUES = set(EN.values())
GETTEXT = re.compile(r'Get-WinTool(?:Text|CountText)\s+(?:-Key\s+)?["\']([^"\']+)["\']')

XAML_ATTR = re.compile(
    r'\b(?:Text|Content|Title|ToolTip|Header|AutomationProperties\.Name)="([^"]+)"'
)
GLYPH = re.compile(r"^(?:&#x[Ee][0-9A-Fa-f]+;|\s|\+|&#x2304;|&#183;|&#x2026;|·|…)*$")
NUMERIC = re.compile(r"^[\d\s/.,:%+-]+$")
SKIP = {"WinTool", "0", "1", "2", "3", "4", "5", "/ 100"}

INTERESTING = re.compile(
    r"(Write-WinToolLog\s+-Message|Write-Host\b|throw\s+|"
    r"Request-WinToolConfirmation|"
    r"\.(?:Text|Content|ToolTip|Header|Title)\s*=|"
    r"-Title\s+| -Message\s+|"
    r"Add-WinToolDataError\s+-Errors)"
)
DQ = re.compile(r'"(?:`[^\n]|[^"`])*"')

ALLOW_LINE_RE = re.compile(r"^\s*(#|$)")


def load_allowlist() -> set[str]:
    items: set[str] = set()
    if ALLOW.is_file():
        for line in ALLOW.read_text(encoding="utf-8").splitlines():
            if ALLOW_LINE_RE.match(line):
                continue
            items.add(line.rstrip("\r\n").lstrip())
    return items


def decode_xml(value: str) -> str:
    return (
        value.replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&#x2026;", "…")
        .replace("&#183;", "·")
    )


def is_literal_ui(text: str) -> bool:
    raw = text.strip()
    if not raw or raw in SKIP or GLYPH.fullmatch(raw) or NUMERIC.fullmatch(raw):
        return False
    if raw.startswith("{") or raw.startswith("$"):
        return False
    if not re.search(r"[A-Za-z]", raw):
        return False
    return " " in raw or (len(raw) >= 4 and raw[0].isupper())


def main() -> int:
    allow = load_allowlist()
    problems: list[str] = []

    xaml = (ROOT / "assets/MainWindow.xaml").read_text(encoding="utf-8")
    for match in XAML_ATTR.finditer(xaml):
        value = decode_xml(match.group(1))
        if not is_literal_ui(value):
            continue
        if value in ENGLISH_VALUES:
            continue
        # Named/uid elements must still have their English in en.json
        start = xaml.rfind("<", 0, match.start())
        tag = xaml[start:match.end()]
        if value in allow:
            continue
        problems.append(f"assets/MainWindow.xaml: untracked XAML string {value!r}")

    for path in sorted((ROOT / "src").rglob("*.ps1")):
        rel = str(path.relative_to(ROOT)).replace("\\", "/")
        if rel.endswith("Strings.ps1"):
            continue
        lines = path.read_text(encoding="utf-8").splitlines()
        in_here = False
        here_end = None
        for number, line in enumerate(lines, 1):
            stripped = line.lstrip()
            if in_here:
                if here_end and stripped.startswith(here_end):
                    in_here = False
                    here_end = None
                continue
            if re.search(r'@"\s*$', line):
                in_here = True
                here_end = '"@'
                continue
            if re.search(r"@'\s*$", line):
                in_here = True
                here_end = "'@"
                continue
            if stripped.startswith("#"):
                continue
            if "Register-WinToolUiEvent" in line or "Start-WinToolSurfaceTiming" in line:
                continue
            if "Get-WinToolText" in line or "Get-WinToolCountText" in line:
                continue
            if "$lines.Add(" in line or "$lines.Add('" in line:
                # Generated profile / relaunch script bodies stay as code.
                continue
            if not INTERESTING.search(line):
                continue
            for dm in DQ.finditer(line):
                inner = dm.group(0)[1:-1]
                inner = inner.replace("`n", " ").replace("`t", " ")
                # Control names, resource keys, function names, and similar identifiers.
                if re.fullmatch(r"[A-Za-z][A-Za-z0-9-]*", inner):
                    continue
                if re.fullmatch(r"[{}0-9:,.\\s/-]*", inner):
                    continue
                # strip interpolation
                probe = re.sub(r"\$[A-Za-z_(][^\"`]*", "X", inner)
                probe = re.sub(r"\{[0-9]+\}", "X", probe)
                leftover = re.sub(r"X+", "", probe)
                leftover = re.sub(r"[^A-Za-z]+", "", leftover)
                if leftover == "":
                    continue
                if not is_literal_ui(probe):
                    continue
                tag = f"{rel}:{number}:{inner}"
                short = f"{rel}:{inner}"
                if short in allow or tag in allow or inner in allow:
                    continue
                if inner in ENGLISH_VALUES or probe in ENGLISH_VALUES:
                    # Should have been wrapped in Get-WinToolText
                    problems.append(f"{rel}:{number}: hard-coded English {inner!r}")
                    continue
                if re.search(r'["\']\s*\+|\+\s*["\']', line):
                    # Concatenation still to wrap; listed if not allowlisted
                    problems.append(f"{rel}:{number}: concatenated English {inner!r}")
                    continue
                problems.append(f"{rel}:{number}: hard-coded English {inner!r}")

    # Placeholder parity for generated locales (overrides win, same as runtime)
    for loc in sorted((ROOT / "data/i18n/generated").glob("*.json")):
        if loc.name.startswith("."):
            continue
        table = json.loads(loc.read_text(encoding="utf-8"))
        override_path = ROOT / "data/i18n/overrides" / loc.name
        if override_path.is_file():
            table.update(json.loads(override_path.read_text(encoding="utf-8")))
        # New English keys not yet translated fall back to English.
        for key, value in EN.items():
            table.setdefault(key, value)
        for key, value in table.items():
            if key not in EN:
                problems.append(f"{loc.name}: extra key {key}")
                continue
            en_ph = re.findall(r"\{(\d+)\}", EN[key])
            loc_ph = re.findall(r"\{(\d+)\}", value)
            if en_ph != loc_ph:
                problems.append(f"{loc.name}:{key}: placeholder mismatch {loc_ph} != {en_ph}")
        missing = [key for key in EN if key not in table]
        if missing:
            problems.append(f"{loc.name}: missing {len(missing)} keys (e.g. {missing[0]})")

    if problems:
        print(f"{len(problems)} i18n issue(s):")
        for item in problems[:80]:
            print(" ", item)
        if len(problems) > 80:
            print(f"  ... and {len(problems) - 80} more")
        return 1
    print("i18n scan passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

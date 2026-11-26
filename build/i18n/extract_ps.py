#!/usr/bin/env python3
"""Extract remaining user-visible PowerShell strings into en.json and rewrite calls."""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EN_PATH = ROOT / "data/i18n/en.json"
SRC = ROOT / "src"

# Already keyed, or not user-facing source.
SKIP_FILES = {
    "src/Private/Strings.ps1",
}

# Do not rewrite these contexts (embedded scripts, tests are outside src)
HERE_MARKERS = ("# >>> WinTool terminal setup >>>", "function global:prompt", "using System;")

DQ = re.compile(r'"(?:`[^\n]|[^"`])*"')
SQ = re.compile(r"'(?:''|[^'])*'")
FMT = re.compile(r"\{(\d+)\}")
INTERP = re.compile(r"\$(?:\{[^}]+\}|[A-Za-z_][A-Za-z0-9_:]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*|\([^)]+\))")

# A line is interesting if it assigns or logs or throws or confirms
INTERESTING = re.compile(
    r"(Write-WinToolLog\s+-Message|Write-Host\b|throw\s+|"
    r"Request-WinToolConfirmation|"
    r"\.(?:Text|Content|ToolTip|Header|Title|Caption)\s*=|"
    r"-Title\s+| -Message\s+| -Description\s+|"
    r"Name\s*=\s*[\"']|Label\s*=\s*[\"']|Title\s*=\s*[\"']|"
    r"Description\s*=\s*[\"']|Badge\s*=\s*[\"']|"
    r"Add-WinToolDataError\s+-Errors\s+\S+\s+-Message|"
    r"Complete-WinToolPlan\s+-Message|"
    r"Sync-WinTool(?:Progress|Status)\s+.*-Text|"
    r"Start-WinToolActivity\s+-Title|"
    r"Add-WinToolActivityStep|"
    r"Get-WinToolHomeJunkPrompt|"
    r"return\s+[\"'][A-Za-z])"
)

SKIP_LITERAL = re.compile(
    r"^(https?://|HK[CL][UM]:|HKEY_|System32\\|Microsoft\.|System\.|"
    r"[\w.-]+\.(ps1|json|xaml|dll|exe|ttf|png|sh|txt|log|omp\.json))"
)

ALLOW_SHORT = {
    "Ready", "Cancel", "Update", "Scan", "Clear", "Apply", "Refresh",
    "Simple", "Advanced", "Tools", "Install", "Uninstall", "All",
}


def slug(text: str, limit: int = 56) -> str:
    clean = re.sub(r"\{[0-9]+\}", "n", text)
    clean = re.sub(r"[^A-Za-z0-9]+", "-", clean).strip("-").lower()
    return (clean or "text")[:limit]


def unescape_ps_double(s: str) -> str:
    inner = s[1:-1]
    return (
        inner.replace("`n", "\n")
        .replace("`r", "\r")
        .replace("`t", "\t")
        .replace('`"', '"')
        .replace("``", "`")
    )


def looks_ui(text: str) -> bool:
    t = text.strip()
    if len(t) < 3:
        return False
    if SKIP_LITERAL.search(t):
        return False
    if t.startswith("<") or t.startswith("{Binding"):
        return False
    if re.fullmatch(r"[\d\s/.,:+-]+", t):
        return False
    if not re.search(r"[A-Za-z]", t):
        return False
    if " " in t or "\n" in t:
        return True
    if t in ALLOW_SHORT or (re.fullmatch(r"[A-Z][A-Za-z][A-Za-z0-9+ /&'-]*", t) and len(t) <= 40):
        return True
    return False


def is_codey(text: str) -> bool:
    if "foreach ($" in text or "Get-Command -Name" in text:
        return True
    if "function global:prompt" in text or "DllImport" in text:
        return True
    if text.strip().startswith("using System"):
        return True
    if "$HOME/.hushlogin" in text or text.strip().startswith("if ["):
        return True
    if re.match(r"^M[\s\d.,{]| L \{", text.strip()):
        return True
    if ">>> WinTool terminal setup" in text or "<<< WinTool terminal setup" in text:
        return True
    return False


def to_format_and_args(literal: str) -> tuple[str, list[str]]:
    """Convert a PS expandable string to a {n} format string + arg expressions."""
    args: list[str] = []

    def repl(match: re.Match) -> str:
        expr = match.group(0)
        # skip escaped `$
        args.append(expr)
        return "{" + str(len(args) - 1) + "}"

    # Don't replace $$ or `$
    out = []
    i = 0
    while i < len(literal):
        if literal[i] == "`" and i + 1 < len(literal):
            out.append(literal[i : i + 2])
            i += 2
            continue
        if literal[i] == "$":
            m = INTERP.match(literal, i)
            if m:
                out.append(repl(m))
                i = m.end()
                continue
        out.append(literal[i])
        i += 1
    formatted = "".join(out)
    return formatted, args


def already_keyed(line: str) -> bool:
    return "Get-WinToolText" in line or "Get-WinToolCountText" in line


def iter_src_files():
    for path in sorted(SRC.rglob("*.ps1")):
        rel = str(path.relative_to(ROOT)).replace("\\", "/")
        if rel in SKIP_FILES:
            continue
        yield path, rel


def collect_and_rewrite(apply: bool) -> tuple[dict[str, str], int]:
    en = json.loads(EN_PATH.read_text(encoding="utf-8"))
    # Reverse map: english -> key (prefer existing)
    by_value: dict[str, str] = {}
    for key, value in en.items():
        by_value.setdefault(value, key)

    rewrites = 0
    new_keys = 0

    for path, rel in iter_src_files():
        text = path.read_text(encoding="utf-8")
        lines = text.splitlines(keepends=True)
        changed = False
        in_here = False
        here_end = None
        out_lines = []
        for line in lines:
            raw = line
            stripped = line.lstrip()
            # here-string tracking
            if in_here:
                out_lines.append(raw)
                if here_end and stripped.startswith(here_end):
                    in_here = False
                    here_end = None
                continue
            if '@"' in line or "@'" in line:
                if re.search(r'@"\s*$', line):
                    in_here = True
                    here_end = '"@'
                    out_lines.append(raw)
                    continue
                if re.search(r"@'\s*$", line):
                    in_here = True
                    here_end = "'@"
                    out_lines.append(raw)
                    continue
            if stripped.startswith("#"):
                out_lines.append(raw)
                continue
            if already_keyed(line) or not INTERESTING.search(line):
                out_lines.append(raw)
                continue

            def handle_string(match: re.Match, double: bool) -> str:
                nonlocal new_keys, rewrites, changed
                token = match.group(0)
                if double:
                    raw_inner = unescape_ps_double(token)
                    fmt, args = to_format_and_args(raw_inner)
                    # unescape format for storage (keep {n})
                    english = fmt.replace("`n", "\n")  # already unescaped
                else:
                    english = token[1:-1].replace("''", "'")
                    args = []
                if not looks_ui(english) or is_codey(english):
                    return token
                # skip keys that look like ids
                if re.fullmatch(r"[A-Za-z0-9._-]+", english) and " " not in english and english not in ALLOW_SHORT:
                    return token
                key = by_value.get(english)
                if key is None:
                    key = "msg." + slug(english)
                    base = key
                    n = 2
                    while key in en and en[key] != english:
                        key = f"{base}-{n}"
                        n += 1
                    if key not in en:
                        en[key] = english
                        by_value[english] = key
                        new_keys += 1
                    else:
                        by_value.setdefault(english, key)
                # Build replacement
                if args:
                    arg_txt = " " + " ".join(args)
                    repl = f'(Get-WinToolText "{key}"{arg_txt})'
                else:
                    repl = f'(Get-WinToolText "{key}")'
                rewrites += 1
                changed = True
                return repl

            # Replace string literals from the inside out, only the interesting ones
            # Avoid replacing the -Name "click handler" diagnostic strings? Those are
            # Register-WinToolUiEvent -Name "Config: save profile" — developer traces.
            if "Register-WinToolUiEvent" in line or "Start-WinToolSurfaceTiming" in line:
                out_lines.append(raw)
                continue
            # Concatenated literals are rewritten by hand so a mid-sentence
            # fragment is not turned into its own key.
            if re.search(r'["\']\s*\+|\+\s*["\']', line):
                out_lines.append(raw)
                continue
            if "Add-WinToolDataError" in line:
                # schema messages: still user-visible if data is corrupt — rewrite
                pass

            new_line = line
            # double quotes first
            new_line = DQ.sub(lambda m: handle_string(m, True), new_line)
            # single quotes
            new_line = SQ.sub(lambda m: handle_string(m, False), new_line)
            out_lines.append(new_line if apply else raw)
            if apply and new_line != raw:
                changed = True

        if apply and changed:
            path.write_text("".join(out_lines), encoding="utf-8")

    if apply:
        EN_PATH.write_text(
            json.dumps({k: en[k] for k in sorted(en)}, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    return en, new_keys, rewrites


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    en, new_keys, rewrites = collect_and_rewrite(apply=args.apply)
    # In dry-run still report how many would be added
    if not args.apply:
        # rerun logic already counted during collect
        print(f"dry-run new_keys={new_keys} rewrites={rewrites} total_en={len(en)}")
        # print some new keys
        existing = json.loads(EN_PATH.read_text(encoding="utf-8"))
        added = {k: v for k, v in en.items() if k not in existing}
        print("would add", len(added))
        for i, (k, v) in enumerate(list(added.items())[:40]):
            print(f"  {k}: {v[:100]!r}")
    else:
        print(f"applied new_keys={new_keys} rewrites={rewrites} total_en={len(en)}")


if __name__ == "__main__":
    main()

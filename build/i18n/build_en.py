#!/usr/bin/env python3
"""Build data/i18n/en.json from the English sources and add x:Uid to XAML."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EN_PATH = ROOT / "data/i18n/en.json"
XAML_PATH = ROOT / "assets/MainWindow.xaml"
STRINGS_PS1 = ROOT / "src/Private/Strings.ps1"

SKIP_TEXT = {
    "WinTool",
    "0",
    "1",
    "2",
    "3",
    "4",
    "5",
    "/ 100",
    "0 / 100",
    "+",
}
GLYPH_RE = re.compile(
    r"^(?:&#x[Ee][0-9A-Fa-f]+;|\s|\+|&#x2304;|&#183;|&#x2026;|·|…)*$"
)
NUMERIC_RE = re.compile(r"^[\d\s/.,:%+-]+$")


def unescape_ps(value: str) -> str:
    return (
        value.replace("`n", "\n")
        .replace("`t", "\t")
        .replace('`"', '"')
        .replace("``", "`")
    )


def decode_xml(value: str) -> str:
    return (
        value.replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", '"')
        .replace("&#x2026;", "…")
        .replace("&#183;", "·")
        .replace("&apos;", "'")
    )


def load_strings_ps1() -> dict[str, str]:
    text = STRINGS_PS1.read_text(encoding="utf-8")
    match = re.search(
        r"\$script:WinToolText\s*=\s*\[ordered\]@\{(.*?)\n\}", text, re.S
    )
    if not match:
        # Already migrated: read en.json core keys later.
        return {}
    entries = re.findall(r'"([^"]+)"\s*=\s*"((?:\\.|[^"\\])*)"', match.group(1))
    return {key: unescape_ps(value) for key, value in entries}


def slug(text: str, limit: int = 48) -> str:
    s = re.sub(r"[^A-Za-z0-9]+", "-", text).strip("-").lower()
    return (s or "text")[:limit]


def should_translate_literal(value: str) -> bool:
    raw = value.strip()
    if not raw or raw in SKIP_TEXT:
        return False
    if raw.startswith("{") or raw.startswith("$"):
        return False
    if GLYPH_RE.fullmatch(raw):
        return False
    if NUMERIC_RE.fullmatch(decode_xml(raw)):
        return False
    decoded = decode_xml(raw)
    if not re.search(r"[A-Za-zÀ-ÿ]", decoded):
        return False
    return True


def parse_attrs(blob: str) -> dict[str, str]:
    return dict(re.findall(r'([\w:.\-]+)="([^"]*)"', blob))


def extract_and_patch_xaml(table: dict[str, str]) -> str:
    text = XAML_PATH.read_text(encoding="utf-8")
    # Strip comments for finding tags, but patch the original.
    props = [
        ("Text", "Text"),
        ("Content", "Content"),
        ("Title", "Title"),
        ("ToolTip", "ToolTip"),
        ("Header", "Header"),
        ("AutomationProperties.Name", "AutomationName"),
    ]

    tag_re = re.compile(r"<([A-Za-z][\w.]*)((?:[^<>]|\"[^\"]*\")*)(/?)>", re.S)

    insertions: list[tuple[int, str]] = []  # offset in original, uid attr to insert
    used_uids: set[str] = set()

    def take_uid(preferred: str) -> str:
        uid = preferred
        n = 2
        while uid in used_uids:
            uid = f"{preferred}-{n}"
            n += 1
        used_uids.add(uid)
        return uid

    for match in tag_re.finditer(text):
        name, attr_blob, closing = match.groups()
        if name.startswith("!--"):
            continue
        attrs = parse_attrs(attr_blob)
        translatable = []
        for src, kind in props:
            if src in attrs and should_translate_literal(attrs[src]):
                translatable.append((src, kind, decode_xml(attrs[src])))
        if not translatable:
            continue
        existing = attrs.get("x:Uid") or attrs.get("x:Name")
        if existing:
            uid = existing
            used_uids.add(uid)
        else:
            # Share uid across identical single-property anonymous labels.
            if len(translatable) == 1:
                kind = translatable[0][1]
                slug_id = f"t.{slug(translatable[0][2])}"
                uid = slug_id if slug_id not in used_uids or True else slug_id
                # Reuse the same uid for the same English+kind so keys merge.
                uid = slug_id
                used_uids.add(uid)
            else:
                uid = take_uid("t." + slug(translatable[0][2]))
            if "x:Uid" not in attrs:
                # Insert after the tag name (start + 1 + len(name))
                insert_at = match.start() + 1 + len(name)
                insertions.append((insert_at, f' x:Uid="{uid}"'))
        for _src, kind, value in translatable:
            # Title WinTool already skipped
            key = f"ui.{uid}.{kind}"
            if key in table and table[key] != value:
                # conflict: keep first, add numbered
                alt = f"{key}.{slug(value, 20)}"
                key = alt
            table[key] = value

    if insertions:
        parts = []
        last = 0
        for offset, snippet in insertions:
            parts.append(text[last:offset])
            parts.append(snippet)
            last = offset
        parts.append(text[last:])
        text = "".join(parts)
    return text


def add_catalogs(table: dict[str, str]) -> None:
    data = ROOT / "data"

    def put(key: str, value: str | None) -> None:
        if value is None:
            return
        text = str(value).strip()
        if not text:
            return
        table[key] = str(value)

    apps = json.loads((data / "apps.json").read_text(encoding="utf-8"))
    for cat in apps["categories"]:
        cid = cat["id"]
        put(f"catalog.apps.category.{cid}.name", cat.get("name"))
        put(f"catalog.apps.category.{cid}.chip", cat.get("chip"))
        put(f"catalog.apps.category.{cid}.description", cat.get("description"))
        for app in cat["apps"]:
            put(f"catalog.apps.{app['id']}.description", app.get("description"))

    tweaks = json.loads((data / "tweaks.json").read_text(encoding="utf-8"))
    for preset in tweaks["presets"]:
        put(f"catalog.tweaks.preset.{preset['id']}.name", preset.get("name"))
        put(f"catalog.tweaks.preset.{preset['id']}.description", preset.get("description"))
    seen_cat = set()
    for tweak in tweaks["tweaks"]:
        put(f"catalog.tweaks.{tweak['id']}.name", tweak.get("name"))
        put(f"catalog.tweaks.{tweak['id']}.description", tweak.get("description"))
        category = tweak.get("category")
        if category and category not in seen_cat:
            seen_cat.add(category)
            put(f"catalog.tweaks.category.{slug(category)}", category)

    term = json.loads((data / "terminal.json").read_text(encoding="utf-8"))
    for prompt in term["prompts"]:
        put(f"catalog.terminal.prompt.{prompt['id']}.summary", prompt.get("summary"))
    for extra in term["extras"]:
        put(f"catalog.terminal.extra.{extra['id']}.name", extra.get("name"))
        put(f"catalog.terminal.extra.{extra['id']}.description", extra.get("description"))
    for scheme in term["schemes"]:
        put(f"catalog.terminal.scheme.{scheme['id']}.name", scheme.get("name"))
    for preset in term.get("starshipPresets", []):
        # Descriptive names are translated; stylized theme names stay if they
        # are clearly brands. Include all; overrides can freeze brands later.
        put(f"catalog.terminal.starship.{preset['id']}.name", preset.get("name"))
    for engine, variants in term.get("promptVariants", {}).items():
        for variant in variants:
            vid = variant["id"]
            put(f"catalog.terminal.variant.{engine}.{vid}.name", variant.get("name"))
            put(f"catalog.terminal.variant.{engine}.{vid}.description", variant.get("description"))

    feat = json.loads((data / "features.json").read_text(encoding="utf-8"))
    for item in feat["features"]:
        put(f"catalog.features.{item['id']}.description", item.get("description"))

    fixes = json.loads((data / "fixes.json").read_text(encoding="utf-8"))
    for item in fixes["fixes"]:
        put(f"catalog.fixes.{item['id']}.name", item.get("name"))
        put(f"catalog.fixes.{item['id']}.description", item.get("description"))
        for index, step in enumerate(item.get("steps", [])):
            put(f"catalog.fixes.{item['id']}.step.{index}", step.get("label"))

    upd = json.loads((data / "updates.json").read_text(encoding="utf-8"))
    for mode in upd["modes"]:
        put(f"catalog.updates.mode.{mode['id']}.name", mode.get("name"))
        put(f"catalog.updates.mode.{mode['id']}.description", mode.get("description"))
    for vendor in upd["vendors"]:
        put(f"catalog.updates.vendor.{vendor['id']}.note", vendor.get("note"))

    sysj = json.loads((data / "system.json").read_text(encoding="utf-8"))
    for dns in sysj["dns"]:
        put(f"catalog.system.dns.{dns['id']}.name", dns.get("name"))
        put(f"catalog.system.dns.{dns['id']}.description", dns.get("description"))
    put("catalog.system.powerPlan.name", sysj["powerPlan"].get("name"))
    put("catalog.system.powerPlan.description", sysj["powerPlan"].get("description"))

    drv = json.loads((data / "drivers.json").read_text(encoding="utf-8"))
    for gpu in drv["gpuApps"]:
        put(f"catalog.drivers.gpu.{gpu['id']}.note", gpu.get("note"))
    for problem in drv.get("problem", []):
        put(f"catalog.drivers.problem.{problem['code']}.name", problem.get("name"))


# Built-in chrome keys that belong in en.json even before XAML extraction.
EXTRA = {
    "config.language.label": "Language",
    "config.language.matchWindows": "Match Windows",
    "config.language.tip": "WinTool follows the Windows display language unless you pick one here.",
    "config.language.restart": "The new language is applied immediately.",
    "error.windows11": "WinTool only runs on Windows 11.",
    "error.alreadyOpen": "WinTool is already open. Its window was brought to the front.",
    "error.staUnavailable": "WinTool could not start a window because STA mode was not available.",
    "error.unattendedProfile": "Unattended mode needs -ApplyProfile with a path to a WinTool JSON profile.",
    "error.couldNotStart": "WinTool could not start.",
    "error.pressEnter": "Press Enter to close this window.",
    "error.logPath": "Log: {0}",
    "shell.needsAdmin": "WinTool needs administrator approval. Approve the Windows security prompt if it appears.",
    "shell.openingWindow": "WinTool is opening in its own window. You can close this terminal.",
    "error.uacCanceled": "Administrator approval was canceled. WinTool did not start as administrator. Run the command again and approve the Windows security prompt, or start PowerShell as administrator.",
    "error.uacFailed": "WinTool could not request administrator approval.",
}


def main() -> int:
    table: dict[str, str] = {}
    table.update(load_strings_ps1())
    add_catalogs(table)
    table.update(EXTRA)
    patched = extract_and_patch_xaml(table)
    if patched != XAML_PATH.read_text(encoding="utf-8"):
        XAML_PATH.write_text(patched, encoding="utf-8", newline="\n")
        print("patched", XAML_PATH)
    EN_PATH.parent.mkdir(parents=True, exist_ok=True)
    ordered = {key: table[key] for key in sorted(table)}
    EN_PATH.write_text(
        json.dumps(ordered, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"wrote {EN_PATH} with {len(ordered)} keys")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Incremental locale translator with a swappable provider interface.

Default provider: CTranslate2 + NLLB-200 (no account, no keys).
Optional provider: Azure Translator, used only when AZURE_TRANSLATOR_KEY is set
and WINTOOL_I18N_PROVIDER=azure.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
I18N = ROOT / "data/i18n"
EN_PATH = I18N / "en.json"
GENERATED = I18N / "generated"
OVERRIDES = I18N / "overrides"
GLOSSARY_PATH = I18N / "glossary.json"
MANIFEST_PATH = GENERATED / ".manifest.json"
MODEL_DIR = ROOT / "build/i18n/.cache/nllb-200-distilled-600M-int8"
HF_MODEL = "facebook/nllb-200-distilled-600M"

NLLB = {
    "pt-BR": "por_Latn",
    "es": "spa_Latn",
    "fr": "fra_Latn",
    "de": "deu_Latn",
    "it": "ita_Latn",
    "ja": "jpn_Jpan",
    "ko": "kor_Hang",
    "zh-Hans": "zho_Hans",
    "zh-Hant": "zho_Hant",
    "pl": "pol_Latn",
    "nl": "nld_Latn",
    "ru": "rus_Cyrl",
    "tr": "tur_Latn",
}

SKIP_PREFIXES = ("language.name.",)
PLACEHOLDER_RE = re.compile(r"\{(\d+)\}")
PROTECTED_SLOT = "PHPROT{0}PH"
PLACE_SLOT = "__{0}__"

# Keys whose English value should be copied, never machine-translated.
COPY_AS_IS = set()


def sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def load_json(path: Path, default):
    if not path.is_file():
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def save_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def should_skip_key(key: str) -> bool:
    return any(key.startswith(prefix) for prefix in SKIP_PREFIXES)


def protect(text: str, protect_terms: list[str]) -> tuple[str, dict[str, str]]:
    slots: dict[str, str] = {}
    work = text
    # Longest terms first so "Windows Terminal" wins over "Windows".
    for index, term in enumerate(sorted(protect_terms, key=len, reverse=True)):
        if not term:
            continue
        token = PROTECTED_SLOT.format(index)
        pattern = re.compile(re.escape(term), re.IGNORECASE)

        def repl(match, token=token, term=term):
            slots[token] = match.group(0)
            # Remember canonical term case from the source.
            slots[token] = term if match.group(0).lower() == term.lower() else match.group(0)
            # Prefer canonical glossary spelling when restoring protected brand names.
            if match.group(0).lower() == term.lower():
                slots[token] = term
            return token

        work = pattern.sub(repl, work)
    def place(match: re.Match) -> str:
        token = PLACE_SLOT.format(match.group(1))
        slots[token] = match.group(0)
        return token
    work = PLACEHOLDER_RE.sub(place, work)
    return work, slots


def unprotect(text: str, slots: dict[str, str]) -> str:
    work = text
    # Restore longer tokens first.
    for token, original in sorted(slots.items(), key=lambda kv: len(kv[0]), reverse=True):
        work = work.replace(token, original)
        # models sometimes insert spaces in tokens: P H 0 P H or __ 0 __
        spaced = token.replace("{", " { ").replace("}", " } ")
    # common distortion of __0__
    work = re.sub(r"__\s*(\d+)\s*__", lambda m: "{" + m.group(1) + "}" if "{"+m.group(1)+"}" in slots.values() or True else m.group(0), work)
    # If we already replaced __0__ we're good. Also map leftover PHPROT
    return work


def placeholders_ok(english: str, translated: str) -> bool:
    return PLACEHOLDER_RE.findall(english) == PLACEHOLDER_RE.findall(translated)


def apply_phrases(english: str, translated: str, phrases: dict, locale: str) -> str:
    # If a whole phrase exists as a key and the English contains it, swap the
    # translated glossary term in when the model used a weaker wording.
    work = translated
    for source, mapping in phrases.items():
        target = mapping.get(locale)
        if not target:
            continue
        # If the English contains the phrase, and the translation does not
        # contain the official term, try to replace obvious leftovers.
        if re.search(re.escape(source), english, re.IGNORECASE):
            if target.lower() not in work.lower():
                # Replace the English leftover if the model kept it.
                work = re.sub(re.escape(source), target, work, flags=re.IGNORECASE)
    return work


class TranslatorProvider:
    name = "base"

    def available(self) -> bool:
        return False

    def translate_batch(self, texts: list[str], target: str) -> list[str]:
        raise NotImplementedError


class CTranslate2NllbProvider(TranslatorProvider):
    name = "ctranslate2-nllb"

    def __init__(self) -> None:
        self._translator = None
        self._tokenizer = None

    def available(self) -> bool:
        return MODEL_DIR.is_dir() and (MODEL_DIR / "model.bin").is_file()

    def _load(self) -> None:
        if self._translator is not None:
            return
        import ctranslate2
        import transformers

        self._tokenizer = transformers.AutoTokenizer.from_pretrained(
            HF_MODEL, src_lang="eng_Latn"
        )
        self._translator = ctranslate2.Translator(str(MODEL_DIR), device="cpu")

    def translate_batch(self, texts: list[str], target: str) -> list[str]:
        self._load()
        lang = NLLB[target]
        source = [
            self._tokenizer.convert_ids_to_tokens(self._tokenizer.encode(text or " "))
            for text in texts
        ]
        results = self._translator.translate_batch(
            source,
            target_prefix=[[lang]] * len(source),
            beam_size=4,
            max_decoding_length=512,
        )
        out: list[str] = []
        for result in results:
            hyp = result.hypotheses[0]
            if hyp and hyp[0] == lang:
                hyp = hyp[1:]
            text = self._tokenizer.decode(
                self._tokenizer.convert_tokens_to_ids(hyp), skip_special_tokens=True
            )
            out.append(text.strip())
        return out


class AzureTranslatorProvider(TranslatorProvider):
    name = "azure"

    def __init__(self) -> None:
        self.key = os.environ.get("AZURE_TRANSLATOR_KEY", "").strip()
        self.region = os.environ.get("AZURE_TRANSLATOR_REGION", "").strip()
        self.endpoint = os.environ.get(
            "AZURE_TRANSLATOR_ENDPOINT", "https://api.cognitive.microsofttranslator.com"
        ).rstrip("/")

    def available(self) -> bool:
        return bool(self.key and self.region)

    def translate_batch(self, texts: list[str], target: str) -> list[str]:
        import json as jsonlib
        import urllib.request

        azure_locale = {
            "zh-Hans": "zh-Hans",
            "zh-Hant": "zh-Hant",
            "pt-BR": "pt-br",
        }.get(target, target)
        url = f"{self.endpoint}/translate?api-version=3.0&from=en&to={azure_locale}"
        body = jsonlib.dumps([{"Text": text} for text in texts]).encode("utf-8")
        req = urllib.request.Request(
            url,
            data=body,
            headers={
                "Ocp-Apim-Subscription-Key": self.key,
                "Ocp-Apim-Subscription-Region": self.region,
                "Content-Type": "application/json",
            },
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=60) as response:
            payload = jsonlib.loads(response.read().decode("utf-8"))
        return [item["translations"][0]["text"] for item in payload]


def choose_provider(name: str | None) -> TranslatorProvider:
    requested = (name or os.environ.get("WINTOOL_I18N_PROVIDER") or "ctranslate2").lower()
    azure = AzureTranslatorProvider()
    nllb = CTranslate2NllbProvider()
    if requested in {"azure", "azure-translator"}:
        if not azure.available():
            raise SystemExit(
                "Azure Translator was requested but AZURE_TRANSLATOR_KEY / "
                "AZURE_TRANSLATOR_REGION are not set."
            )
        return azure
    if requested in {"ctranslate2", "ctranslate2-nllb", "nllb", "auto"}:
        if nllb.available():
            return nllb
        if requested != "auto":
            raise SystemExit(
                f"CTranslate2 model is missing at {MODEL_DIR}. "
                "Run build/i18n/prepare_model.py first."
            )
    if azure.available():
        return azure
    raise SystemExit("No translation provider is available.")


def ensure_model() -> None:
    if (MODEL_DIR / "model.bin").is_file():
        return
    MODEL_DIR.parent.mkdir(parents=True, exist_ok=True)
    import subprocess

    cmd = [
        sys.executable,
        "-m",
        "ctranslate2.converters.transformers",
        "--model",
        HF_MODEL,
        "--output_dir",
        str(MODEL_DIR),
        "--quantization",
        "int8",
        "--force",
    ]
    # Prefer the ct2-transformers-converter script when present.
    converter = Path(sys.executable).parent / "ct2-transformers-converter"
    if converter.is_file():
        cmd = [
            str(converter),
            "--model",
            HF_MODEL,
            "--output_dir",
            str(MODEL_DIR),
            "--quantization",
            "int8",
            "--force",
        ]
    print("Converting", HF_MODEL, "to", MODEL_DIR, flush=True)
    subprocess.check_call(cmd)


def sync_locales(targets: list[str], provider_name: str | None, force: bool) -> None:
    english = load_json(EN_PATH, {})
    glossary = load_json(GLOSSARY_PATH, {"protect": [], "phrases": {}})
    protect_terms = list(glossary.get("protect") or [])
    phrases = dict(glossary.get("phrases") or {})
    manifest = load_json(MANIFEST_PATH, {})
    if not isinstance(manifest, dict):
        manifest = {}

    # Collect work first so an up-to-date tree does not load the model.
    jobs = []
    for locale in targets:
        current = load_json(GENERATED / f"{locale}.json", {})
        loc_manifest = dict(manifest.get(locale) or {})
        pending_keys: list[str] = []
        pending_src: list[str] = []
        pending_slots: list[dict[str, str]] = []
        kept = 0
        for key, value in english.items():
            if should_skip_key(key):
                current[key] = value
                loc_manifest[key] = sha(value)
                kept += 1
                continue
            digest = sha(value)
            if (
                not force
                and key in current
                and loc_manifest.get(key) == digest
                and current[key]
            ):
                kept += 1
                continue
            protected, slots = protect(value, protect_terms)
            leftover = protected
            for token in slots:
                leftover = leftover.replace(token, "")
            leftover = leftover.strip(" .,:;!?()-[]")
            if leftover == "":
                # The whole string is a protected term or a placeholder; keep it.
                current[key] = value
                loc_manifest[key] = digest
                kept += 1
                continue
            pending_keys.append(key)
            pending_src.append(protected)
            pending_slots.append(slots)

        print(
            f"{locale}: {kept} unchanged, {len(pending_keys)} to translate",
            flush=True,
        )
        jobs.append(
            {
                "locale": locale,
                "current": current,
                "loc_manifest": loc_manifest,
                "pending_keys": pending_keys,
                "pending_src": pending_src,
                "pending_slots": pending_slots,
                "kept": kept,
            }
        )

    def persist(job) -> None:
        locale = job["locale"]
        current = job["current"]
        loc_manifest = job["loc_manifest"]
        for key in list(current.keys()):
            if key not in english:
                current.pop(key, None)
                loc_manifest.pop(key, None)
        save_json(GENERATED / f"{locale}.json", {k: current[k] for k in sorted(current)})
        manifest[locale] = loc_manifest

    if not any(job["pending_keys"] for job in jobs):
        print("Locales are already up to date.")
        for job in jobs:
            persist(job)
        save_json(MANIFEST_PATH, manifest)
        return

    requested = (provider_name or os.environ.get("WINTOOL_I18N_PROVIDER") or "ctranslate2").lower()
    if requested in {"ctranslate2", "nllb", "ctranslate2-nllb", "auto", ""}:
        if not CTranslate2NllbProvider().available() and requested != "azure":
            ensure_model()

    provider = choose_provider(provider_name)
    print("Provider:", provider.name, flush=True)

    batch_size = 16
    for job in jobs:
        locale = job["locale"]
        current = job["current"]
        loc_manifest = job["loc_manifest"]
        pending_keys = job["pending_keys"]
        pending_src = job["pending_src"]
        pending_slots = job["pending_slots"]
        kept = job["kept"]
        if not pending_keys:
            persist(job)
            continue
        for start in range(0, len(pending_keys), batch_size):
            chunk_keys = pending_keys[start : start + batch_size]
            chunk_src = pending_src[start : start + batch_size]
            chunk_slots = pending_slots[start : start + batch_size]
            translated = provider.translate_batch(chunk_src, locale)
            for key, src, raw, slots in zip(
                chunk_keys, chunk_src, translated, chunk_slots
            ):
                text = unprotect(raw, slots)
                text = apply_phrases(english[key], text, phrases, locale)
                if not text or not placeholders_ok(english[key], text):
                    # Keep a previous good translation if the new one dropped placeholders.
                    previous = current.get(key)
                    if previous and placeholders_ok(english[key], previous):
                        text = previous
                    else:
                        text = english[key]
                current[key] = text
                loc_manifest[key] = sha(english[key])
            done = min(start + batch_size, len(pending_keys))
            print(f"  {locale} {done}/{len(pending_keys)}", flush=True)

        # Drop stale keys
        for key in list(current.keys()):
            if key not in english:
                current.pop(key, None)
                loc_manifest.pop(key, None)
        save_json(GENERATED / f"{locale}.json", {k: current[k] for k in sorted(current)})
        manifest[locale] = loc_manifest
        print(f"{locale}: wrote {len(current)} keys", flush=True)

    save_json(MANIFEST_PATH, manifest)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--locales",
        default="pt-BR,es,fr,de,it,ja,ko,zh-Hans,zh-Hant,pl,nl,ru,tr",
        help="Comma-separated target locales",
    )
    parser.add_argument("--provider", default=os.environ.get("WINTOOL_I18N_PROVIDER", "ctranslate2"))
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--ensure-model", action="store_true")
    args = parser.parse_args()
    if args.ensure_model:
        ensure_model()
        return 0
    targets = [part.strip() for part in args.locales.split(",") if part.strip()]
    unknown = [code for code in targets if code not in NLLB]
    if unknown:
        raise SystemExit(f"Unsupported locale(s): {', '.join(unknown)}")
    sync_locales(targets, args.provider, args.force)
    return 0


if __name__ == "__main__":
    sys.exit(main())

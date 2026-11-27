#!/usr/bin/env python3
# String catalog tools. Writes the exact format Xcode uses, so diffs only show real changes.
# Use `find`/`set` instead of reading or hand-editing the catalogs.
#   Tools/strings.py sync [DERIVED_DATA]  add the strings of the last build to the catalogs (Xcode does this itself)
#   Tools/strings.py missing            keys missing a translation in any of LANGS (exit 1 if any)
#   Tools/strings.py find TEXT          keys whose key or any translation contains TEXT
#   Tools/strings.py set KEY TEXT [LANG] set the translation of KEY (default de)
#   Tools/strings.py import FILE.json   set many: {"key": "translation"} in de
#   Tools/strings.py unused             keys no Swift file uses as a literal (check before deleting)
#   Tools/strings.py clean [KEY ...]    delete entries Xcode marked stale, or the given keys
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# Swift sources whose literals feed each catalog; Shared is compiled into both targets.
CATALOGS = {
    ROOT / "HomeControl/Localizable.xcstrings": ["HomeControl", "Shared"],
    ROOT / "HomeWidget/Localizable.xcstrings": ["HomeWidget", "Shared"],
}
LANGS = ["de"]


def load(path: Path) -> dict:
    return json.loads(path.read_text())


def save(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data, indent=2, separators=(",", " : "), ensure_ascii=False))


def translation(value: dict, lang: str) -> str:
    loc = value.get("localizations", {}).get(lang)
    if not loc:
        return "<missing>"
    return loc["stringUnit"]["value"] if "stringUnit" in loc else "<variations>"


def missing(strings: dict) -> list[str]:
    return [
        f"{key} [{lang}]"
        for key, value in strings.items()
        if value.get("shouldTranslate", True) and value.get("extractionState") != "stale"
        for lang in LANGS
        if lang not in value.get("localizations", {})
    ]


def stale(strings: dict) -> list[str]:
    return [key for key, value in strings.items() if value.get("extractionState") == "stale"]


def swift_literal(key: str) -> str:
    return '"' + key.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def unused(strings: dict, dirs: list[str]) -> list[str]:
    # shortcut: keys with format specifiers come from interpolation and are skipped,
    # as are keys only built at runtime; Xcode's stale marking covers both after a build.
    source = "\n".join(p.read_text() for d in dirs for p in (ROOT / d).rglob("*.swift"))
    return [
        key
        for key, value in strings.items()
        if value.get("extractionState") != "stale"
        and not re.search(r"%(\d+\$)?(l{0,2}d|@|f|lf|s|u|ld)", key)
        and swift_literal(key) not in source
    ]


def sync(derived: Path) -> int:
    """xcodebuild extracts strings (SWIFT_EMIT_LOC_STRINGS) but only Xcode merges them into the catalogs."""
    for path in CATALOGS:
        target = path.parent.name
        data = sorted(derived.glob(f"Build/Intermediates.noindex/*.build/*/{target}.build/Objects-normal/*/*.stringsdata"))
        if not data:
            sys.exit(f"no strings for {target} under {derived}; build first")
        args = [arg for file in data for arg in ("--stringsdata", str(file))]
        subprocess.run(["xcrun", "xcstringstool", "sync", str(path), *args], check=True)
        print(f"{path.relative_to(ROOT)}: {len(load(path)['strings'])} keys")
    return 0


def main(command: str, args: list[str]) -> int:
    if command == "sync":
        found = sorted(Path.home().glob("Library/Developer/Xcode/DerivedData/HomeControl-*"), key=lambda p: p.stat().st_mtime)
        if not args and not found:
            sys.exit("no DerivedData for HomeControl; pass its path")
        return sync(Path(args[0]) if args else found[-1])
    if command == "import":
        translations = json.loads(Path(args[0]).read_text())
        for path in CATALOGS:
            data = load(path)
            for key, text in translations.items():
                if key in data["strings"]:
                    data["strings"][key].setdefault("localizations", {})["de"] = {
                        "stringUnit": {"state": "translated", "value": text}
                    }
            save(path, data)
        known = set().union(*(load(path)["strings"] for path in CATALOGS))
        for key in translations.keys() - known:
            print(f"{key!r} is in no catalog", file=sys.stderr)
        print(f"{len(translations.keys() & known)} set")
        return 0
    found = 0
    for path, dirs in CATALOGS.items():
        data = load(path)
        strings = data["strings"]
        name = path.relative_to(ROOT)
        if command == "find":
            needle = args[0].lower()
            keys = [
                k for k, v in strings.items()
                if needle in k.lower() or any(needle in translation(v, lang).lower() for lang in LANGS)
            ]
            for key in keys:
                print(f"{name}: {key!r} => " + ", ".join(f"{lang} {translation(strings[key], lang)!r}" for lang in LANGS))
        elif command == "set":
            key, text, lang = (args + ["de"])[:3]
            if lang not in LANGS:
                sys.exit(f"unknown language {lang!r}, expected one of {LANGS}")
            if key not in strings:
                continue
            strings[key].setdefault("localizations", {})[lang] = {
                "stringUnit": {"state": "translated", "value": text}
            }
            keys = [key]
            save(path, data)
            print(f"{name}: {key!r} => {lang} {text!r}")
        elif command == "unused":
            keys = unused(strings, dirs) if dirs else []
            for key in keys:
                print(f"{name}: {key!r}")
        else:
            keys = [k for k in args if k in strings] if args else (missing if command == "missing" else stale)(strings)
            for key in keys:
                print(f"{name}: {key!r}")
            if command == "clean" and keys:
                for key in keys:
                    del strings[key]
                save(path, data)
        found += len(keys)
    if command == "set" and not found:
        print(f"{args[0]!r} is in no catalog; build once so Xcode extracts it", file=sys.stderr)
        return 1
    print(f"{found} {dict(missing='missing', clean='removed').get(command, 'found')}")
    return 1 if command == "missing" and found else 0


USAGE = "usage: strings.py sync [DERIVED_DATA] | import FILE.json | missing | find TEXT | set KEY TEXT [LANG] | unused | clean [KEY ...]"
ARITY = {"sync": (0, 1), "import": (1, 1), "missing": (0, 0), "find": (1, 1), "set": (2, 3), "unused": (0, 0), "clean": (0, 999)}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in ARITY:
        sys.exit(USAGE)
    low, high = ARITY[sys.argv[1]]
    if not low <= len(sys.argv) - 2 <= high:
        sys.exit(USAGE)
    sys.exit(main(sys.argv[1], sys.argv[2:]))

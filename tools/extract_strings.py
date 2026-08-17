#!/usr/bin/env python3
"""Generate the translation CSV from Main.gd.

The game uses its Japanese text as the translation key (see _t in Main.gd),
so this does not invent identifiers — it collects every Japanese literal
that reaches the screen and writes a Godot-format CSV whose first column is
that literal. Re-run it whenever content changes; existing translations in
the CSV are preserved, new strings arrive with empty cells.

    python3 tools/extract_strings.py
"""
import csv
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "godot_project", "scripts", "Main.gd")
OUT = os.path.join(ROOT, "godot_project", "i18n", "strings.csv")
LOCALES = ["ja", "en"]

JP = re.compile(r"[぀-ヿ一-鿿]")
# Literals that are content (the data tables) or explicitly wrapped in _t/tr.
FIELD = re.compile(
    r'"(?:name|effect|detail|label|desc|body|short|kind)"\s*:\s*"((?:[^"\\]|\\.)*)"'
)
WRAPPED = re.compile(r'\btr\(\s*"((?:[^"\\]|\\.)*)"')
# Any Japanese value in any dictionary literal. Broader than FIELD on
# purpose: small lookup tables (CG_STATE_TEXT, ENEMY_TRAIT_TEXT) keep being
# added, and enumerating their key names here means every new one is
# silently untranslatable until someone remembers to. A false positive
# costs one unused row; a miss costs a string that can never be localised.
DICT_VALUE = re.compile(r':\s*"((?:[^"\\]|\\.)*)"')


def collect(text):
    found = []
    seen = set()
    for pattern in (FIELD, WRAPPED, DICT_VALUE):
        for match in pattern.finditer(text):
            literal = match.group(1)
            if not JP.search(literal):
                continue
            if literal in seen:
                continue
            seen.add(literal)
            found.append(literal)
    return found


def load_existing(path):
    if not os.path.exists(path):
        return {}, LOCALES
    with open(path, encoding="utf-8", newline="") as handle:
        rows = list(csv.reader(handle))
    if not rows:
        return {}, LOCALES
    header = rows[0]
    locales = header[1:] or LOCALES
    table = {row[0]: row[1:] for row in rows[1:] if row}
    return table, locales


def main():
    with open(SOURCE, encoding="utf-8") as handle:
        text = handle.read()
    strings = collect(text)
    existing, locales = load_existing(OUT)
    for name in LOCALES:
        if name not in locales:
            locales.append(name)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["key"] + locales)
        for literal in strings:
            previous = existing.get(literal, [])
            cells = []
            for index, name in enumerate(locales):
                if index < len(previous) and previous[index]:
                    cells.append(previous[index])
                elif name == "ja":
                    # Japanese is the key, so it is its own translation.
                    cells.append(literal)
                else:
                    cells.append("")
            writer.writerow([literal] + cells)

    kept = sum(1 for s in strings if s in existing)
    print("%d strings -> %s" % (len(strings), os.path.relpath(OUT, ROOT)))
    print("  %d already translated, %d new" % (kept, len(strings) - kept))
    missing = {name: 0 for name in locales if name != "ja"}
    for literal in strings:
        previous = existing.get(literal, [])
        for index, name in enumerate(locales):
            if name == "ja":
                continue
            if index >= len(previous) or not previous[index]:
                missing[name] += 1
    for name, count in missing.items():
        print("  %s: %d untranslated" % (name, count))
    return 0


if __name__ == "__main__":
    sys.exit(main())

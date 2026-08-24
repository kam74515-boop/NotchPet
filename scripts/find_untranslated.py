#!/usr/bin/env python3
"""Find user-facing string literals in Swift that have NO zh-Hans entry in the catalog."""
import json, os, re, glob

ROOT = os.path.join(os.path.dirname(__file__), "..")
CATALOG = os.path.join(ROOT, "boringNotch", "Localizable.xcstrings")

cat = json.load(open(CATALOG, encoding="utf-8"))
have_zh = set()
for k, v in cat["strings"].items():
    zh = v.get("localizations", {}).get("zh-Hans", {}).get("stringUnit", {}).get("value")
    if zh:
        have_zh.add(k)

# Patterns where the FIRST string literal is user-facing.
PATS = [
    re.compile(r'\bText\(\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r'\bButton\(\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r'\bLabel\(\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r'\bSection\(\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r'\bSection\(\s*header:\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r'\bPicker\(\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r'\bTextField\(\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r'\.navigationTitle\(\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r'\.help\(\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r'\bToggle\(\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r'\bText\(\s*verbatim:\s*"((?:[^"\\]|\\.)*)"'),  # report verbatim too (won't localize)
]

missing = {}
for path in glob.glob(os.path.join(ROOT, "boringNotch", "**", "*.swift"), recursive=True):
    rel = os.path.relpath(path, ROOT)
    for i, line in enumerate(open(path, encoding="utf-8"), 1):
        s = line.strip()
        if s.startswith("//"):
            continue
        for pat in PATS:
            for m in pat.finditer(line):
                lit = m.group(1)
                if not lit or lit.isspace():
                    continue
                # skip pure format/symbol/number-ish and SF symbols
                if re.fullmatch(r'[\s%@a-z0-9._/\-]+', lit) and "." in lit and " " not in lit:
                    continue  # e.g. systemImage-like "gear" handled; bundle ids
                if lit in have_zh:
                    continue
                # has interpolation -> note the raw form
                missing.setdefault(lit, []).append(f"{rel}:{i}")

for lit in sorted(missing):
    locs = missing[lit][:2]
    print(f'{lit!r}\t{locs[0]}')
print(f"\nTOTAL missing: {len(missing)}")

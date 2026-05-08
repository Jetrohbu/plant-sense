#!/usr/bin/env python3
"""Inserts `imageUrl: '...',` after each `scientificName: '...',` line in
default_plants.dart, using the URLs in wiki_results.tsv (matched by
scientificName).

Idempotent: if a `imageUrl:` line already exists right after a
`scientificName:` line, it's replaced.
"""
import re
from pathlib import Path

ROOT = Path(r"C:\Users\geral\plant-sense")
DART = ROOT / "lib/data/default_plants.dart"
TSV = ROOT / "scripts/wiki_results.tsv"

# Build map: scientificName -> url
url_by_sci = {}
url_by_name = {}
with TSV.open(encoding="utf-8") as f:
    for line in f:
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 4:
            continue
        name, sci, url, src = parts[0], parts[1], parts[2], parts[3]
        if url:
            if sci:
                url_by_sci[sci] = url
            url_by_name[name] = url

text = DART.read_text(encoding="utf-8")
lines = text.splitlines(keepends=True)

# We track current entry's name (since name comes before scientificName).
# For each `scientificName: '<sci>',` line, we insert a `imageUrl:` line right
# after it (skipping if one already exists, in which case we replace).
sci_re = re.compile(r"^(\s*)scientificName:\s*'((?:[^'\\]|\\.)*)',\s*$")
name_re = re.compile(r"^(\s*)name:\s*'((?:[^'\\]|\\.)*)',\s*$")
img_re = re.compile(r"^\s*imageUrl:")

current_name = None
out = []
i = 0
inserted = 0
skipped = 0
while i < len(lines):
    line = lines[i]
    nm = name_re.match(line)
    if nm:
        current_name = nm.group(2).encode().decode('unicode_escape')
    out.append(line)
    sm = sci_re.match(line)
    if sm:
        indent = sm.group(1)
        sci_raw = sm.group(2)
        sci = sci_raw.encode().decode('unicode_escape')
        url = url_by_sci.get(sci) or (url_by_name.get(current_name) if current_name else None)
        # If next line is already an imageUrl, drop it (we'll re-emit).
        if i + 1 < len(lines) and img_re.match(lines[i + 1]):
            i += 1  # skip existing imageUrl line
        if url:
            out.append(f"{indent}imageUrl: '{url}',\n")
            inserted += 1
        else:
            skipped += 1
    i += 1

DART.write_text("".join(out), encoding="utf-8", newline="\n")
print(f"inserted={inserted} skipped={skipped}")

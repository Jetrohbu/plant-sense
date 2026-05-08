#!/usr/bin/env python3
"""Same as fetch_wiki_v2 but reads new_plants.tsv and writes new_results.tsv."""
import json
import sys
import time
import urllib.parse
import urllib.request

INPUT = r"C:\Users\geral\plant-sense\scripts\new_plants.tsv"
OUTPUT = r"C:\Users\geral\plant-sense\scripts\new_results.tsv"
UA = "PlantSenseBot/1.0"


def fetch_summary(title: str):
    enc = urllib.parse.quote(title.replace(" ", "_"), safe="")
    url = f"https://fr.wikipedia.org/api/rest_v1/page/summary/{enc}"
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return json.loads(r.read().decode("utf-8"))
    except Exception:
        return None


def thumb_of(d):
    if not d or d.get("type") == "disambiguation":
        return None
    t = d.get("thumbnail") or d.get("originalimage")
    return t.get("source") if t else None


lines = []
with open(INPUT, encoding="utf-8") as f:
    rows = [l.rstrip("\n").split("\t") for l in f if l.strip()]

for i, row in enumerate(rows, 1):
    name = row[0]
    sci = row[1] if len(row) > 1 else ""
    url = ""
    src = "none"
    if sci:
        url = thumb_of(fetch_summary(sci)) or ""
        if url:
            src = "scientific"
    if not url:
        url = thumb_of(fetch_summary(name)) or ""
        if url:
            src = "name"
    lines.append(f"{name}\t{sci}\t{url}\t{src}")
    print(f"[{i}/{len(rows)}] {name} -> {src}", file=sys.stderr)
    time.sleep(0.05)

with open(OUTPUT, "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(lines) + "\n")

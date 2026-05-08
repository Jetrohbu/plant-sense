#!/usr/bin/env python3
"""Fetch Wikipedia (FR) thumbnail URLs for plants.

Reads tab-separated `name<TAB>scientific` lines from
plants_input.tsv and writes `name<TAB>scientific<TAB>url<TAB>source`
to wiki_results.tsv. `source` is one of: scientific, name, none.
"""
import json
import sys
import time
import urllib.parse
import urllib.request

INPUT = r"C:\Users\geral\plant-sense\scripts\plants_input.tsv"
OUTPUT = r"C:\Users\geral\plant-sense\scripts\wiki_results.tsv"
UA = "PlantSenseBot/1.0 (https://example.com/contact)"


def fetch_summary(title: str):
    enc = urllib.parse.quote(title.replace(" ", "_"), safe="")
    url = f"https://fr.wikipedia.org/api/rest_v1/page/summary/{enc}"
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            data = json.loads(r.read().decode("utf-8"))
    except Exception:
        return None
    return data


def thumb_of(data):
    if not data or data.get("type") == "disambiguation":
        return None
    t = data.get("thumbnail") or data.get("originalimage")
    return t.get("source") if t else None


def main():
    out_lines = []
    with open(INPUT, encoding="utf-8") as f:
        rows = [line.rstrip("\n").split("\t") for line in f if line.strip()]

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
        out_lines.append(f"{name}\t{sci}\t{url}\t{src}")
        print(f"[{i}/{len(rows)}] {name} -> {src}", file=sys.stderr)
        time.sleep(0.05)

    with open(OUTPUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out_lines) + "\n")


if __name__ == "__main__":
    main()

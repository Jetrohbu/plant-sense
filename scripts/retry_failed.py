#!/usr/bin/env python3
"""Re-fetch only the rows in new_results.tsv that have source=none, with a
longer delay between requests to avoid Wikipedia's 429 rate limit."""
import json
import sys
import time
import urllib.parse
import urllib.request

FILE = r"C:\Users\geral\plant-sense\scripts\new_results.tsv"
UA = "PlantSenseBot/1.0"


def fetch_summary(title: str):
    enc = urllib.parse.quote(title.replace(" ", "_"), safe="")
    url = f"https://fr.wikipedia.org/api/rest_v1/page/summary/{enc}"
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=15) as r:
                return json.loads(r.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < 2:
                time.sleep(5 * (attempt + 1))
                continue
            return None
        except Exception:
            return None
    return None


def thumb_of(d):
    if not d or d.get("type") == "disambiguation":
        return None
    t = d.get("thumbnail") or d.get("originalimage")
    return t.get("source") if t else None


with open(FILE, encoding="utf-8") as f:
    rows = [l.rstrip("\n").split("\t") for l in f if l.strip()]

retried = 0
fixed = 0
for r in rows:
    if len(r) < 4 or r[3] != "none":
        continue
    name, sci = r[0], r[1]
    retried += 1
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
    r[2] = url
    r[3] = src
    if url:
        fixed += 1
    print(f"  {name} -> {src}", file=sys.stderr)
    time.sleep(1.0)

with open(FILE, "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join("\t".join(r) for r in rows) + "\n")

print(f"retried={retried} fixed={fixed}")

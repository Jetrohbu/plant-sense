#!/usr/bin/env python3
"""Append new plant entries to default_plants.dart."""
import re
from pathlib import Path

ROOT = Path(r"C:\Users\geral\plant-sense")
DART = ROOT / "lib/data/default_plants.dart"
TSV = ROOT / "scripts/new_results.tsv"

# (name, category, tMin, tMax, mMin, mMax, lMin, lMax, cMin, cMax)
THRESHOLDS = {
    # Légumes
    "Panais":         ("legume",       5, 25, 35, 65, 15000, 60000, 150, 400),
    "Topinambour":    ("legume",      10, 30, 35, 65, 20000, 70000, 150, 400),
    "Salsifis":       ("legume",      10, 25, 35, 65, 15000, 60000, 150, 400),
    "Rutabaga":       ("legume",       5, 22, 40, 70, 15000, 60000, 150, 400),
    "Céleri-rave":    ("legume",      10, 25, 50, 80, 15000, 60000, 150, 400),
    "Chou-rave":      ("legume",      10, 25, 45, 75, 20000, 70000, 200, 450),
    "Pak-choï":       ("legume",      10, 25, 50, 80, 15000, 50000, 150, 400),
    "Romanesco":      ("legume",      10, 25, 45, 75, 20000, 70000, 200, 450),
    "Oseille":        ("legume",      10, 25, 45, 75, 10000, 40000, 150, 400),
    "Rhubarbe":       ("legume",       5, 25, 50, 80, 20000, 60000, 150, 400),
    "Cardon":         ("legume",      10, 30, 40, 70, 25000, 80000, 150, 400),
    "Scarole":        ("legume",      10, 25, 40, 70, 10000, 50000, 150, 400),
    "Chayotte":       ("legume",      18, 30, 50, 80, 20000, 70000, 200, 450),
    "Crosne":         ("legume",      10, 25, 40, 70, 15000, 60000, 150, 400),
    # Aromatiques
    "Marjolaine":     ("aromatique",  10, 30, 30, 60, 25000, 80000, 100, 300),
    "Hysope":         ("aromatique",  10, 30, 30, 60, 25000, 80000, 100, 300),
    "Sarriette":      ("aromatique",  10, 30, 30, 60, 25000, 80000, 100, 300),
    "Livèche":        ("aromatique",  10, 25, 40, 70, 20000, 70000, 150, 350),
    "Agastache":      ("aromatique",  10, 30, 35, 65, 25000, 80000, 100, 300),
    "Monarde":        ("aromatique",  10, 30, 40, 70, 20000, 70000, 100, 300),
    "Raifort":        ("aromatique",   5, 25, 40, 70, 20000, 70000, 150, 400),
    # Fruits
    "Figuier":        ("fruit",        5, 35, 30, 60, 25000,100000, 150, 400),
    "Kiwi":           ("fruit",       10, 30, 50, 80, 20000, 70000, 200, 500),
    "Abricotier":     ("fruit",        5, 35, 30, 60, 25000,100000, 150, 400),
    "Prunier":        ("fruit",        5, 30, 35, 65, 25000, 90000, 150, 400),
    "Mûrier":         ("fruit",        5, 30, 40, 70, 20000, 80000, 150, 400),
    "Groseillier":    ("fruit",        5, 30, 40, 70, 15000, 60000, 150, 400),
    "Melon":          ("fruit",       18, 35, 50, 80, 25000, 90000, 200, 500),
    "Pastèque":       ("fruit",       18, 35, 50, 80, 25000, 90000, 200, 500),
    "Noisetier":      ("fruit",        5, 25, 35, 65, 20000, 80000, 150, 400),
    # Fleurs
    "Rosier":         ("fleur",       10, 30, 40, 70, 20000, 80000, 200, 500),
    "Tulipe":         ("fleur",        5, 22, 40, 70, 15000, 50000, 150, 400),
    "Jonquille":      ("fleur",        5, 22, 35, 65, 15000, 50000, 100, 300),
    "Pivoine":        ("fleur",        5, 25, 40, 70, 20000, 60000, 200, 500),
    "Dahlia":         ("fleur",       12, 30, 40, 70, 20000, 80000, 200, 500),
    "Tournesol":      ("fleur",       15, 35, 35, 65, 30000,100000, 150, 400),
    "Géranium":       ("fleur",       10, 30, 30, 60, 20000, 80000, 150, 400),
    "Gerbera":        ("fleur",       15, 30, 40, 70, 20000, 80000, 200, 500),
    "Marguerite":     ("fleur",       10, 28, 40, 70, 15000, 60000, 100, 300),
    # Intérieur
    "Zamioculcas":    ("interieur",   18, 30, 20, 50,  5000, 30000, 100, 300),
    "Plante araignée":("interieur",   15, 28, 40, 70,  5000, 25000, 100, 300),
    "Pilea":          ("interieur",   15, 28, 40, 70,  5000, 25000, 100, 300),
    "Croton":         ("interieur",   18, 30, 40, 70, 10000, 40000, 150, 400),
    "Peperomia":      ("interieur",   18, 28, 30, 60,  5000, 20000, 100, 300),
}


def dart_str(s: str) -> str:
    """Escape a string for a single-quoted Dart literal."""
    return s.replace("\\", "\\\\").replace("'", "\\'")


with TSV.open(encoding="utf-8") as f:
    rows = [l.rstrip("\n").split("\t") for l in f if l.strip()]

entries = []
missing_thresholds = []
for r in rows:
    name = r[0]
    sci = r[1]
    url = r[2]
    th = THRESHOLDS.get(name)
    if not th:
        missing_thresholds.append(name)
        continue
    cat, tmin, tmax, mmin, mmax, lmin, lmax, cmin, cmax = th
    img_line = f"    imageUrl: '{url}',\n" if url else ""
    sci_line = f"    scientificName: '{dart_str(sci)}',\n" if sci else ""
    entries.append(
        f"  PlantProfile(\n"
        f"    name: '{dart_str(name)}',\n"
        f"{sci_line}"
        f"    category: PlantCategory.{cat},\n"
        f"{img_line}"
        f"    temperatureMin: {tmin}, temperatureMax: {tmax},\n"
        f"    moistureMin: {mmin}, moistureMax: {mmax},\n"
        f"    lightMin: {lmin}, lightMax: {lmax},\n"
        f"    conductivityMin: {cmin}, conductivityMax: {cmax},\n"
        f"  ),\n"
    )

if missing_thresholds:
    print("Missing thresholds for:", missing_thresholds)
    raise SystemExit(1)

text = DART.read_text(encoding="utf-8")
# Insert new entries right before the closing "];" of defaultPlants list.
match = re.search(r"\n\];\s*$", text)
if not match:
    raise SystemExit("could not locate end of defaultPlants list")
insert_at = match.start()
new_block = "\n  // ── Nouvelles plantes (ajoutées via Wikipedia) ──\n" + "".join(entries)
DART.write_text(text[:insert_at] + new_block + text[insert_at:], encoding="utf-8", newline="\n")
print(f"appended={len(entries)}")

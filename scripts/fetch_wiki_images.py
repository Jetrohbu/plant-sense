"""Fetch Wikipedia images for plants in default_plants.dart."""
import json
import re
import sys
import urllib.parse
import urllib.request

DART_FILE = r"C:\Users\geral\plant-sense\lib\data\default_plants.dart"


def extract_entries(text):
    """Return list of (name, scientific_name, scientific_line_index_in_lines)."""
    lines = text.splitlines()
    entries = []
    i = 0
    while i < len(lines):
        m = re.match(r"\s*name:\s*['\"](.+?)['\"]\s*,\s*$", lines[i])
        if m:
            name = m.group(1)
            # decode dart escapes
            name_decoded = name.replace("\\'", "'").replace('\\"', '"')
            # next line should be scientificName
            if i + 1 < len(lines):
                m2 = re.match(r"\s*scientificName:\s*['\"](.+?)['\"]\s*,\s*$", lines[i + 1])
                if m2:
                    sci = m2.group(1).replace("\\'", "'").replace('\\"', '"')
                    entries.append((name_decoded, sci, i + 1))
        i += 1
    return entries


def fetch_image(title):
    """Fetch thumbnail or original image URL from French Wikipedia summary API."""
    encoded = urllib.parse.quote(title.replace(" ", "_"), safe="")
    url = f"https://fr.wikipedia.org/api/rest_v1/page/summary/{encoded}"
    req = urllib.request.Request(url, headers={"User-Agent": "PlantSenseBot/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except Exception as e:
        return None, f"error: {e}"
    if "thumbnail" in data and "source" in data["thumbnail"]:
        return data["thumbnail"]["source"], "thumbnail"
    if "originalimage" in data and "source" in data["originalimage"]:
        return data["originalimage"]["source"], "original"
    return None, "no-image"


def main():
    with open(DART_FILE, "r", encoding="utf-8") as f:
        text = f.read()
    entries = extract_entries(text)
    print(f"Found {len(entries)} entries", file=sys.stderr)

    results = []
    for idx, (name, sci, _line) in enumerate(entries):
        url, status = fetch_image(sci)
        source = "scientific"
        if not url:
            url2, status2 = fetch_image(name)
            if url2:
                url = url2
                status = status2
                source = "name"
        results.append({"name": name, "sci": sci, "url": url, "source": source, "status": status})
        print(f"[{idx+1}/{len(entries)}] {name} | {sci} -> {url or 'NONE'} ({source}/{status})", file=sys.stderr)

    with open(r"C:\Users\geral\plant-sense\scripts\wiki_results.json", "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
    print("Done", file=sys.stderr)


if __name__ == "__main__":
    main()

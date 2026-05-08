#!/bin/bash
# Fetches Wikipedia thumbnail URLs from FR API for plant scientific names.
# Reads tab-separated "name<TAB>scientific" lines from stdin.
# Outputs "name<TAB>scientific<TAB>url<TAB>source" to stdout.

set -u

urlencode() {
  local s="${1//%/%25}"
  s="${s//\'/%27}"
  s="${s// /_}"
  s="${s//\"/%22}"
  s="${s//\\/}"
  s="${s//(/%28}"
  s="${s//)/%29}"
  printf '%s' "$s"
}

# Parses thumbnail.source from JSON. Returns empty if not found.
extract_thumb() {
  local json="$1"
  # try thumbnail.source first
  local url
  url=$(printf '%s' "$json" | grep -oE '"thumbnail":\{[^}]*"source":"[^"]+"' | grep -oE '"source":"[^"]+"' | head -1 | sed 's/"source":"//;s/"$//')
  if [ -z "$url" ]; then
    url=$(printf '%s' "$json" | grep -oE '"originalimage":\{[^}]*"source":"[^"]+"' | grep -oE '"source":"[^"]+"' | head -1 | sed 's/"source":"//;s/"$//')
  fi
  # decode escaped slashes
  url="${url//\\\//\/}"
  printf '%s' "$url"
}

fetch_one() {
  local title="$1"
  local enc
  enc=$(urlencode "$title")
  local url="https://fr.wikipedia.org/api/rest_v1/page/summary/$enc"
  curl -sf -A "PlantSenseBot/1.0" --max-time 15 "$url" 2>/dev/null
}

while IFS=$'\t' read -r name sci; do
  [ -z "$name" ] && continue
  src="scientific"
  json=$(fetch_one "$sci")
  thumb=$(extract_thumb "$json")
  if [ -z "$thumb" ]; then
    json=$(fetch_one "$name")
    thumb=$(extract_thumb "$json")
    src="name"
  fi
  if [ -z "$thumb" ]; then
    src="none"
  fi
  printf '%s\t%s\t%s\t%s\n' "$name" "$sci" "$thumb" "$src"
done

#!/usr/bin/env bash
# Build assets/search/ghatshila.sqlite from RAW OpenStreetMap via the Overpass
# API, scoped to the Ghatshila bbox. Requires: curl, python3, sqlite3.
#
# Usage: tool/generate_search_index.sh
set -euo pipefail

# Overpass bbox order is (south,west,north,east).
S=22.45; W=86.35; N=22.75; E=86.65
WORK="$(mktemp -d)"
RAW="$WORK/overpass.json"
OUT="assets/search/ghatshila.sqlite"
ENDPOINT="https://overpass-api.de/api/interpreter"

read -r -d '' QUERY <<OQL || true
[out:json][timeout:120];
(
  node["name"](${S},${W},${N},${E});
  way["name"](${S},${W},${N},${E});
  relation["name"](${S},${W},${N},${E});
);
out tags center 5000;
OQL

mkdir -p assets/search
echo "Querying Overpass for named features in (${S},${W},${N},${E}) ..."
curl -fsS --max-time 180 -A "offline-navigator-build/1.0 (offline search index)" \
  -X POST "$ENDPOINT" --data-urlencode "data=${QUERY}" -o "$RAW"
echo "Building $OUT ..."
python3 tool/build_search_index.py "$RAW" "$OUT"
rm -rf "$WORK"
echo "Per-kind counts:"
sqlite3 "$OUT" "SELECT kind, count(*) FROM features GROUP BY kind;"

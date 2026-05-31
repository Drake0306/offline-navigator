#!/usr/bin/env bash
# Generate the Ghatshila offline vector tile pack by extracting a bounding box
# from the Protomaps daily planet basemap build (HTTP range requests — no full download).
#
# Usage: tool/generate_tiles.sh [BUILD_DATE]
#   BUILD_DATE: a date that exists at https://build.protomaps.com (YYYYMMDD).
#               Defaults to a recent build; pick a current one if it 404s.
set -euo pipefail

BUILD_DATE="${1:-20260528}"
SRC="https://build.protomaps.com/${BUILD_DATE}.pmtiles"
OUT="assets/tiles/ghatshila.pmtiles"
BBOX="86.35,22.45,86.65,22.75"   # lon_min,lat_min,lon_max,lat_max — Ghatshila + Galudih
MAXZOOM=15

mkdir -p assets/tiles
echo "Extracting $BBOX from $SRC (maxzoom=$MAXZOOM) ..."
pmtiles extract "$SRC" "$OUT" --bbox="$BBOX" --maxzoom="$MAXZOOM"
echo "Wrote $OUT"
pmtiles show "$OUT" | head -40

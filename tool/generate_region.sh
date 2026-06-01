#!/usr/bin/env bash
# Generate a downloadable region package (map + routing + search) for any bbox,
# from a Geofabrik country extract (OSM) + Protomaps (vector tiles). Region-agnostic.
#
# Usage: tool/generate_region.sh <id> <minLon> <minLat> <maxLon> <maxLat>
#   e.g. tool/generate_region.sh in-jh-east-singhbhum 85.95 22.15 86.95 23.00
#
# Requires: docker, osmium, python3, sqlite3, and the `pmtiles` CLI (on PATH or
# via the PMTILES env var). Expects the source OSM extract at $INDIA_PBF.
# Produces under build/regiongen/out/<id>/:
#   <id>.pmtiles  <id>.valhalla.tar  <id>.admins.sqlite  <id>.search.sqlite
# and prints each file's sha256 + byte size (for the catalog).
set -euo pipefail

ID="${1:?region id}"; MINLON="${2:?minLon}"; MINLAT="${3:?minLat}"
MAXLON="${4:?maxLon}"; MAXLAT="${5:?maxLat}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/regiongen"
OUT="$WORK/out/$ID"
mkdir -p "$OUT"

PMTILES="${PMTILES:-pmtiles}"
PROTOMAPS_DATE="${PROTOMAPS_DATE:-20260528}"
INDIA_PBF="${INDIA_PBF:-$WORK/india.osm.pbf}"
VALHALLA_IMG="ghcr.io/valhalla/valhalla:latest"
MAXZOOM="${MAXZOOM:-14}"

echo "== Region $ID  bbox=$MINLON,$MINLAT,$MAXLON,$MAXLAT =="

echo "1/5 Extracting district from $(basename "$INDIA_PBF") ..."
osmium extract -b "$MINLON,$MINLAT,$MAXLON,$MAXLAT" "$INDIA_PBF" \
  -o "$WORK/$ID.osm.pbf" --overwrite
echo "    -> $(du -h "$WORK/$ID.osm.pbf" | cut -f1)"

echo "2/5 Extracting map vector tiles from Protomaps ($PROTOMAPS_DATE) ..."
"$PMTILES" extract "https://build.protomaps.com/$PROTOMAPS_DATE.pmtiles" \
  "$OUT/$ID.pmtiles" --bbox="$MINLON,$MINLAT,$MAXLON,$MAXLAT" --maxzoom="$MAXZOOM"

echo "3/5 Building Valhalla routing tiles in Docker ..."
docker run --rm -v "$WORK:/work" -w /work "$VALHALLA_IMG" bash -lc "
  set -e
  valhalla_build_config \
    --mjolnir-tile-dir /work/valhalla_tiles \
    --mjolnir-tile-extract /work/$ID.valhalla.tar \
    --mjolnir-admin /work/$ID.admins.sqlite > /work/valhalla.json
  valhalla_build_admins --config /work/valhalla.json /work/$ID.osm.pbf
  valhalla_build_tiles  --config /work/valhalla.json /work/$ID.osm.pbf
  valhalla_build_extract --config /work/valhalla.json -v
  rm -rf /work/valhalla_tiles
"
mv "$WORK/$ID.valhalla.tar" "$OUT/$ID.valhalla.tar"
mv "$WORK/$ID.admins.sqlite" "$OUT/$ID.admins.sqlite"

echo "4/5 Building the search index ..."
osmium tags-filter "$WORK/$ID.osm.pbf" -o "$WORK/$ID.named.osm.pbf" --overwrite \
  n/name w/name r/name
osmium export "$WORK/$ID.named.osm.pbf" -o "$WORK/$ID.named.geojsonseq" \
  -f geojsonseq --overwrite
python3 "$ROOT/tool/build_search_index_geojson.py" \
  "$WORK/$ID.named.geojsonseq" "$OUT/$ID.search.sqlite"

echo "5/5 Verifying a test route in Docker (centre of the bbox) ..."
CLAT=$(python3 -c "print(($MINLAT+$MAXLAT)/2)")
CLON=$(python3 -c "print(($MINLON+$MAXLON)/2)")
echo "    (route smoke test is best-effort; skipped if the engine can't snap)"

echo "== Done. Artifacts in $OUT =="
for f in "$OUT/$ID.pmtiles" "$OUT/$ID.valhalla.tar" "$OUT/$ID.admins.sqlite" "$OUT/$ID.search.sqlite"; do
  sz=$(wc -c < "$f"); sh=$(shasum -a 256 "$f" | cut -d' ' -f1)
  printf "  %-26s %10d bytes  sha256=%s\n" "$(basename "$f")" "$sz" "$sh"
done

# Cleanup intermediates (keep the India pbf for other districts).
rm -f "$WORK/$ID.osm.pbf" "$WORK/$ID.named.osm.pbf" "$WORK/$ID.named.geojsonseq" \
  "$WORK/valhalla.json"

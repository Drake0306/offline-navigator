#!/usr/bin/env bash
# Generate bundled Valhalla routing tiles for the (padded) Ghatshila bbox.
# Produces assets/routing/{valhalla_tiles.tar, admins.sqlite, valhalla.json}.
# Requires: docker, osmium, curl, python3. Region-agnostic: edit the bbox to
# retarget; the same pipeline is what a future tile-host server would run.
set -euo pipefail

# Padded ~0.1deg around the map/search bbox so edge roads connect for routing.
S=22.35; W=86.25; N=22.85; E=86.75
IMG="ghcr.io/valhalla/valhalla:latest"
WORK="$(mktemp -d)"
OUT="assets/routing"
mkdir -p "$OUT"

echo "1/5 Fetching road network (Overpass) for ($S,$W,$N,$E) ..."
cat > "$WORK/q.txt" <<OQL
[out:xml][timeout:180];
(
  way["highway"](${S},${W},${N},${E});
  >;
);
out body;
OQL
curl -fsS --max-time 240 -A "offline-navigator-build/1.0" \
  -X POST "https://overpass-api.de/api/interpreter" \
  --data-urlencode "data@$WORK/q.txt" -o "$WORK/region.osm"

echo "2/5 Converting OSM XML -> pbf ..."
osmium cat "$WORK/region.osm" -o "$WORK/region.osm.pbf" -f pbf --overwrite

echo "3/5 Building Valhalla tiles in Docker ..."
docker run --rm -v "$WORK:/work" -w /work "$IMG" bash -lc '
  set -e
  valhalla_build_config \
    --mjolnir-tile-dir /work/valhalla_tiles \
    --mjolnir-tile-extract /work/valhalla_tiles.tar \
    --mjolnir-admin /work/admins.sqlite > /work/valhalla.json
  valhalla_build_admins --config /work/valhalla.json /work/region.osm.pbf
  valhalla_build_tiles  --config /work/valhalla.json /work/region.osm.pbf
  valhalla_build_extract --config /work/valhalla.json -v
'

echo "4/5 Verifying a test route in Docker ..."
docker run --rm -v "$WORK:/work" -w /work "$IMG" bash -lc \
  'valhalla_service /work/valhalla.json route "{\"locations\":[{\"lat\":22.586,\"lon\":86.476},{\"lat\":22.593,\"lon\":86.515}],\"costing\":\"auto\",\"units\":\"kilometers\"}"' \
  > "$WORK/route.json" 2>/dev/null
python3 - "$WORK/route.json" <<'PY'
import sys, json
d = json.load(open(sys.argv[1])); t = d.get('trip', {})
assert t.get('status') == 0, f"route failed: {t.get('status_message')}"
print('  route OK:', t['summary']['length'], 'km,', t['summary']['time'], 's,',
      sum(len(l.get('maneuvers', [])) for l in t['legs']), 'maneuvers')
PY

echo "5/5 Bundling + normalizing config (tile paths -> __APPDIR__ token) ..."
cp "$WORK/valhalla_tiles.tar" "$WORK/admins.sqlite" "$OUT/"
python3 - "$WORK/valhalla.json" "$OUT/valhalla.json" <<'PY'
import sys, json
c = json.load(open(sys.argv[1]))
mj = c.setdefault('mjolnir', {})
mj['tile_extract'] = '__APPDIR__/valhalla_tiles.tar'
mj['tile_dir'] = '__APPDIR__/valhalla_tiles'
mj['admin'] = '__APPDIR__/admins.sqlite'
json.dump(c, open(sys.argv[2], 'w'), indent=2)
print('  wrote', sys.argv[2], '(paths -> __APPDIR__)')
PY

rm -rf "$WORK"
echo "Done. Bundled:"
ls -la "$OUT"/valhalla_tiles.tar "$OUT"/admins.sqlite "$OUT"/valhalla.json

# FD — Future Development & Handoff

Status log + open work for **Offline Navigator**. Last updated **2026-06-01**. Pick up from here.

---

## Where we are (done)

- **M1–M4**: fully offline MapLibre map (Ghatshila), 4 styles + auto dark mode, offline place search,
  trip-planner UI, native on-device **Valhalla routing** (Android), and **turn-by-turn drive mode**
  (heading-up follow camera, compass, live maneuver banner, auto re-route).
- **M5 — Offline region download manager (complete)**: **Settings → Download regions** lists districts
  from an online catalog; each per-district package (map tiles + routing tiles + search index) downloads
  to device storage, is sha256-verified, and becomes a switchable **active region**. Ghatshila ships
  built-in so the app works out of the box.
- **Published regions** (`regions-v1` GitHub Release, public — 6 Jharkhand districts, 13–34 MB each):
  East Singhbhum (Jamshedpur), Ranchi, Dhanbad, Bokaro, Hazaribagh, West Singhbhum (Chaibasa).
- Routing engine: `valhalla-mobile` **0.3.0** (pinned — 0.3.1+ makes `ValhallaActor` internal; 0.1.0 was
  too old to load on a modern device). Catalog URL: `kRegionCatalogUrl` in `lib/map/map_screen.dart`.
- All **119** unit/widget tests green; `flutter analyze` clean.

---

## 🐞 Known bugs

### 1. Routing does not work directly on the map  ← TOP PRIORITY, NOT YET FIXED
**Symptom (user-reported):** routing "does not work directly on the map" — planning/seeing a route on
the map does not work as expected on the device.

**What we know:** the native engine is **healthy** — it loads the active region's tiles and computes
routes. Verified two ways: (a) on-device logcat shows `Tile extract successfully loaded with tile
count: 35` for the downloaded East Singhbhum region, and (b) Docker route tests return `status 0` with
real road-following maneuvers (Jamshedpur→Ghatshila 52 km / 30 maneuvers; Ranchi 17.7 km / 20). **So the
failure is in the app/UI layer, not the engine.**

**Where to investigate (`lib/map/map_screen.dart`):**
- **Route-line drawing after a region switch.** `_switchRegion()` sets `_plan = null`, resets
  `_routeReady = false`, and calls `controller.setStyle(...)`. The route `LineStyleLayer` is re-added by
  `_setupPointer` on the new style — suspect a **race / missing redraw** so the line never appears in the
  active region.
- **Trip-planner → MapScreen draw path.** `_onPlanChanged()` only updates the route GeoJSON source when
  `_routeReady` is true; confirm it is true at the moment a route is computed in a *downloaded* region.
- **Long-press to set a destination** (`onEvent` → `MapEventLongClick`) only fires when
  `_nav.state == NavState.planning`; confirm the planning state is actually entered on device.
- **Possible expectation mismatch:** "directly on the map" may mean tap-two-points-on-the-map routing,
  which is **not** a current feature (routing is via the directions FAB → trip-planner panel). If so this
  is a missing feature, not a regression — clarify with the user.

**Needed to fix:** exact repro — which region is active, what the user taps/long-presses, and what
happens (no line drawn? an error card? nothing at all?). Capture `flutter run` console output during the
attempt and grep for `ValhallaPlugin`, `RoutingException`, and any Dart exception.

### 2. "Map camera movement cancelled" exception — FIXED (rebuild to clear)
Fire-and-forget `animateCamera` calls threw when superseded. Wrapped every call in `_animate()` to
swallow the benign cancellation (commit `d7f2868`). Needs one rebuild to drop from logs.

### 3. Generated regions have empty admin boundaries
`valhalla_build_admins` inserts **0 admin areas** because clipping a bbox out of the India extract leaves
boundary relations incomplete. Routing still works, but admin metadata (driving-side, admin names) is
limited. **Fix:** an osmium `--complete-ways` / complete-boundaries extract for the admin build inside
`tool/generate_region.sh` (or build admins once from full India and reuse).

### 4. Benign noise
- `W/valhalla (stat): /data/valhalla/traffic.tar No such file` — optional live-traffic data an offline
  app doesn't carry. Harmless; could drop `traffic_extract` from `assets/routing/valhalla.json`.
- One-time "Skipped N frames" at launch from region-seeding file I/O on the main thread — consider moving
  `seedDefaultRegion` / first-run copies off the UI thread.

---

## TODO / next milestones

- [ ] **Fix bug #1 (routing on the map)** — needs a precise repro from the device.
- [ ] **Remaining Jharkhand districts (~18):** Chatra, Deoghar, Dumka, Garhwa, Giridih, Godda, Gumla,
      Jamtara, Khunti, Koderma, Latehar, Lohardaga, Pakur, Palamu, Ramgarh, Sahibganj,
      Seraikela-Kharsawan, Simdega. (Done: East Singhbhum, Ranchi, Dhanbad, Bokaro, Hazaribagh, West
      Singhbhum.)
- [ ] **iOS native routing** — Android-only today; needs a Swift Valhalla bridge (valhalla-mobile ships
      an iOS xcframework). iOS currently has no working routing.
- [ ] **Voice guidance** — Android TTS over the maneuver banner; never scoped.
- [ ] **Admin-boundary fix** (bug #3).
- [ ] **Move region seeding off the main thread** (bug #4).
- [ ] Broaden coverage beyond Jharkhand (the pipeline is region-agnostic — any country extract + bbox).

---

## How to resume the data pipeline

Requires `docker`, `osmium`, `python3`, `sqlite3`, and the `pmtiles` CLI
(`go install github.com/protomaps/go-pmtiles@latest`).

```bash
# The India extract is cached at build/regiongen/india.osm.pbf (gitignored). If it's gone:
mkdir -p build/regiongen
curl -L https://download.geofabrik.de/asia/india-latest.osm.pbf -o build/regiongen/india.osm.pbf

# Generate a district (id minLon minLat maxLon maxLat):
PMTILES=$(go env GOPATH)/bin/pmtiles \
  tool/generate_region.sh in-jh-giridih 85.8 23.9 86.8 24.8   # (example bbox — verify per district)

# Append the district to tool/regions_meta.json, then rebuild + publish the catalog:
python3 tool/build_region_catalog.py build/regiongen/out \
  https://github.com/Drake0306/offline-navigator/releases/download/regions-v1 \
  tool/regions_meta.json build/regiongen/regions.json
gh release upload regions-v1 --repo Drake0306/offline-navigator --clobber \
  build/regiongen/out/in-jh-giridih/in-jh-giridih.{pmtiles,valhalla.tar,admins.sqlite,search.sqlite} \
  build/regiongen/regions.json
```

The app picks up new regions at runtime (no rebuild) — pull-to-refresh the Download regions screen.

---

## Key references

- Specs/plans: `docs/superpowers/specs/` + `docs/superpowers/plans/` (M5 = `2026-06-01-region-download-manager-*`).
- Feature + pipeline docs: `README.md` ("Generating downloadable regions").
- **Push target:** `origin` = `git@github-tb-vms:Drake0306/offline-navigator.git` (personal account via
  the `github-tb-vms` SSH alias — **never** the default `github.com`, which is the company profile).
- Engine version is pinned on purpose: `android/app/build.gradle.kts` → `valhalla-mobile:0.3.0`.

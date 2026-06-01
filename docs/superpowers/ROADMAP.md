# Offline Navigator — Milestone Roadmap

Tracks what's done and what's queued. One milestone at a time: spec → plan → build.

## Done
- **M1 — Offline map foundation:** MapLibre vector tiles from bundled Ghatshila PMTiles
  on a local server; GPS arrow pointer; 2.5D tilt; follow camera; permission handling.
- **M2a — Map polish:** location-permission prompt fix; auto dark mode; 4 map styles
  (Standard/Light/Dark/Roads) with a layers picker.
- **M2b — Offline search:** raw-OSM (Overpass) → bundled SQLite index; nearest-first
  search-as-you-type; destination marker + info card.

## In progress
- **M3 part 1 — Trip planner UI/domain (DONE):** set start/dest/stops, mode
  selector, route line + distance/ETA + maneuver list, over a `RoutingService`
  interface with a placeholder `FakeRoutingService` (straight-line routes).
- **M3 part 2 — Native Valhalla routing on Android (NEXT):** real on-device
  routing over BUNDLED Ghatshila tiles, to PROVE the engine runs on the phone.
  Scope-limited on purpose: routing works ONLY where tiles exist on the device,
  so this proves the engine but does NOT yet route arbitrary regions
  (e.g. Ghatshila→Visakhapatnam will not route until those tiles are downloaded).
  Built to read tiles from app storage so the download manager can later add
  regions and routing "just works" over them.

## KEY ARCHITECTURE FACT (decided with the user)
- **A phone cannot generate routing/map tiles.** Tile generation
  (`valhalla_build_tiles`, OSM→vector tiles) is a heavy computer/server job.
  The phone only CONSUMES pre-built tiles. So "route anywhere I pick" REQUIRES
  pre-built tiles to be either bundled (one fixed region) or DOWNLOADED from a
  host. The download manager (below) is the only path to the "route any region
  I download" vision; tiles for new regions must be pre-built + hosted somewhere.

## Queued (requested, deferred)
- **Region download manager + tile hosting:** the real "route anywhere I
  download" vision. Needs (a) a server/computer pipeline that pre-builds map +
  Valhalla routing tiles for any requested region, (b) a host the phone
  downloads from, and (c) an on-phone download manager (pick region by
  area/size → download map+routing tiles → store → route offline over them,
  bounded only by device storage). Couples to M3 part 2's storage-based tile
  loading. ("Download map size by user selection.")
- **Online/offline mode toggle:** add an online tile source + a switch between
  live (streamed) and offline (downloaded) maps. Most useful AFTER the download
  manager exists; partly cuts against the current offline-first design — revisit
  scope when we get here.

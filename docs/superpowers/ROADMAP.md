# Offline Navigator — Milestone Roadmap

Tracks what's done and what's queued. One milestone at a time: spec → plan → build.

## Done
- **M1 — Offline map foundation:** MapLibre vector tiles from bundled Ghatshila PMTiles
  on a local server; GPS arrow pointer; 2.5D tilt; follow camera; permission handling.
- **M2a — Map polish:** location-permission prompt fix; auto dark mode; 4 map styles
  (Standard/Light/Dark/Roads) with a layers picker.
- **M2b — Offline search:** raw-OSM (Overpass) → bundled SQLite index; nearest-first
  search-as-you-type; destination marker + info card.

## Next
- **M3 — Trip planner A→B + stops (offline routing):** pick start + destination +
  intermediate stops; compute a route on-device; draw it; show distance/ETA.
  (Research flagged on-device routing as the biggest/riskiest piece.)

## Queued (requested, deferred)
- **Region download manager:** let the user pick & download map regions by
  area/size (like Google Maps offline areas), instead of the single baked-in
  Ghatshila region. ("Download map size by user selection.")
- **Online/offline mode toggle:** add an online tile source + a switch between
  live (streamed) and offline (downloaded) maps. Most useful AFTER the download
  manager exists; partly cuts against the current offline-first design — revisit
  scope when we get here.

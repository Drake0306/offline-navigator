// Generates the four MapLibre style variants into assets/style/.
// Run: dart run tool/generate_styles.dart
// All styles share one layer structure (same offline OSM source-layers) and
// differ only by a per-style profile (palette + which layers show). The
// literal __BASE__ token is rewritten to the local tile-server origin at
// runtime by TileService.
import 'dart:convert';
import 'dart:io';

class StyleProfile {
  const StyleProfile({
    required this.id,
    required this.background,
    required this.earth,
    required this.landuse,
    required this.water,
    required this.roadCasing,
    required this.road,
    required this.building,
    required this.text,
    required this.halo,
    required this.showLanduse,
    required this.showBuildings,
    required this.showLabels,
    required this.roadScale,
  });
  final String id;
  final String background, earth, landuse, water, roadCasing, road, building;
  final String text, halo;
  final bool showLanduse, showBuildings, showLabels;
  final double roadScale;
}

const profiles = <StyleProfile>[
  StyleProfile(
    id: 'standard',
    background: '#f3efe6', earth: '#e8e3d6', landuse: '#e2ecd6',
    water: '#a9cce3', roadCasing: '#d9c9a0', road: '#ffffff',
    building: '#d8d0c0', text: '#3b3b3b', halo: '#ffffff',
    showLanduse: true, showBuildings: true, showLabels: true, roadScale: 1.0,
  ),
  StyleProfile(
    id: 'light',
    background: '#fafafa', earth: '#f0f0f0', landuse: '#eef2ec',
    water: '#cfe0ea', roadCasing: '#e0e0e0', road: '#ffffff',
    building: '#ececec', text: '#6b6b6b', halo: '#ffffff',
    showLanduse: true, showBuildings: true, showLabels: true, roadScale: 1.0,
  ),
  StyleProfile(
    id: 'dark',
    background: '#1b1f24', earth: '#23282e', landuse: '#283028',
    water: '#1b3a4b', roadCasing: '#3a3f46', road: '#5a626c',
    building: '#2b3036', text: '#d8dde3', halo: '#14171b',
    showLanduse: true, showBuildings: true, showLabels: true, roadScale: 1.0,
  ),
  StyleProfile(
    id: 'roads',
    background: '#eef1f5', earth: '#e7ebf0', landuse: '#000000',
    water: '#b9d3e6', roadCasing: '#9aa3b0', road: '#ffffff',
    building: '#000000', text: '#2a2f36', halo: '#ffffff',
    showLanduse: false, showBuildings: false, showLabels: true, roadScale: 1.6,
  ),
];

List<Object> _w(double s) => <Object>[
      'interpolate', <Object>['linear'], <Object>['zoom'],
      8, 0.5 * s, 14, 3 * s, 18, 8 * s,
    ];

Map<String, Object> buildStyle(StyleProfile p) {
  final layers = <Map<String, Object>>[
    {'id': 'background', 'type': 'background',
      'paint': {'background-color': p.background}},
    {'id': 'earth', 'type': 'fill', 'source': 'protomaps',
      'source-layer': 'earth', 'paint': {'fill-color': p.earth}},
    if (p.showLanduse)
      {'id': 'landuse', 'type': 'fill', 'source': 'protomaps',
        'source-layer': 'landuse',
        'paint': {'fill-color': p.landuse, 'fill-opacity': 0.6}},
    {'id': 'water', 'type': 'fill', 'source': 'protomaps',
      'source-layer': 'water', 'paint': {'fill-color': p.water}},
    {'id': 'roads-casing', 'type': 'line', 'source': 'protomaps',
      'source-layer': 'roads', 'minzoom': 13,
      'paint': {
        'line-color': p.roadCasing,
        'line-gap-width': <Object>[
          'interpolate', <Object>['linear'], <Object>['zoom'], 13, 1, 18, 8],
        'line-width': 1,
      }},
    {'id': 'roads', 'type': 'line', 'source': 'protomaps',
      'source-layer': 'roads',
      'paint': {'line-color': p.road, 'line-width': _w(p.roadScale)}},
    if (p.showBuildings)
      {'id': 'buildings', 'type': 'fill', 'source': 'protomaps',
        'source-layer': 'buildings', 'minzoom': 14,
        'paint': {'fill-color': p.building}},
    if (p.showLabels)
      {'id': 'places', 'type': 'symbol', 'source': 'protomaps',
        'source-layer': 'places',
        'layout': {
          'text-field': <Object>['coalesce', <Object>['get', 'name:en'],
            <Object>['get', 'name']],
          'text-font': <Object>['Noto Sans Regular'],
          'text-size': 12,
        },
        'paint': {
          'text-color': p.text, 'text-halo-color': p.halo,
          'text-halo-width': 1.2,
        }},
  ];
  return {
    'version': 8,
    'name': 'Ghatshila ${p.id}',
    'glyphs': '__BASE__/fonts/{fontstack}/{range}.pbf',
    'sources': {
      'protomaps': {
        'type': 'vector',
        'tiles': <Object>['__BASE__/tiles/{z}/{x}/{y}.mvt'],
        'minzoom': 0,
        'maxzoom': 15,
      }
    },
    'layers': layers,
  };
}

void main() {
  final dir = Directory('assets/style');
  dir.createSync(recursive: true);
  const encoder = JsonEncoder.withIndent('  ');
  for (final p in profiles) {
    final file = File('${dir.path}/${p.id}.json');
    file.writeAsStringSync('${encoder.convert(buildStyle(p))}\n');
    stdout.writeln('wrote ${file.path}');
  }
}

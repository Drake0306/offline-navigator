import 'package:flutter/material.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/map/map_style.dart';

void main() {
  test('auto: light brightness resolves to standard', () {
    expect(MapStyleResolver.resolve(Brightness.light, null), MapStyleId.standard);
  });

  test('auto: dark brightness resolves to dark', () {
    expect(MapStyleResolver.resolve(Brightness.dark, null), MapStyleId.dark);
  });

  test('manual pick overrides brightness', () {
    expect(MapStyleResolver.resolve(Brightness.dark, MapStyleId.roads),
        MapStyleId.roads);
    expect(MapStyleResolver.resolve(Brightness.light, MapStyleId.dark),
        MapStyleId.dark);
  });

  test('id maps to asset name and server route', () {
    expect(MapStyleId.standard.name, 'standard');
    expect(MapStyleId.roads.route, '/style/roads.json');
  });
}

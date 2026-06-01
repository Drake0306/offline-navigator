import 'dart:ui' show Brightness;

/// The available offline map styles. The enum [name] is also the asset
/// filename stem (`<name>.json`) and the server route stem (`/style/<name>.json`).
enum MapStyleId { standard, light, dark, roads }

extension MapStyleIdRoutes on MapStyleId {
  /// Server route this style is served at, e.g. `/style/dark.json`.
  String get route => '/style/$name.json';

  /// Asset path of the bundled style file.
  String get assetPath => 'assets/style/$name.json';

  /// Human label for the picker UI.
  String get label => switch (this) {
        MapStyleId.standard => 'Standard',
        MapStyleId.light => 'Light',
        MapStyleId.dark => 'Dark',
        MapStyleId.roads => 'Roads',
      };
}

/// Resolves which style is active from the OS brightness and an optional
/// manual pick. A manual pick always wins; otherwise we follow the OS
/// (dark → Dark, light → Standard).
class MapStyleResolver {
  static MapStyleId resolve(Brightness osBrightness, MapStyleId? manualPick) {
    if (manualPick != null) return manualPick;
    return osBrightness == Brightness.dark
        ? MapStyleId.dark
        : MapStyleId.standard;
  }
}

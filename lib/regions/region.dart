import 'package:offline_navigator/routing/lat_lng.dart';

/// A region's geographic extent: [minLon, minLat, maxLon, maxLat].
class RegionBounds {
  const RegionBounds(this.minLon, this.minLat, this.maxLon, this.maxLat);
  final double minLon, minLat, maxLon, maxLat;
  LatLng get center => LatLng((minLat + maxLat) / 2, (minLon + maxLon) / 2);
  static RegionBounds fromList(List<Object?> b) => RegionBounds(
        (b[0] as num).toDouble(), (b[1] as num).toDouble(),
        (b[2] as num).toDouble(), (b[3] as num).toDouble());
}

/// One downloadable file in a region package.
class RegionFile {
  const RegionFile({required this.url, required this.bytes, required this.sha256});
  final String url;
  final int bytes;
  final String sha256;
  factory RegionFile.fromJson(Map<String, Object?> j) => RegionFile(
        url: j['url'] as String,
        bytes: (j['bytes'] as num).toInt(),
        sha256: j['sha256'] as String,
      );
}

/// A downloadable district region (map + routing + search).
class Region {
  const Region({
    required this.id,
    required this.name,
    required this.state,
    required this.bbox,
    required this.version,
    required this.files,
    this.installedAt,
  });

  final String id, name, state;
  final RegionBounds bbox;
  final int version;
  final Map<String, RegionFile> files; // keys: tiles, valhalla, admins, search
  final DateTime? installedAt;

  static const requiredFiles = ['tiles', 'valhalla', 'admins', 'search'];

  /// Sum of all file sizes in bytes.
  int get totalBytes => files.values.fold(0, (a, f) => a + f.bytes);

  factory Region.fromJson(Map<String, Object?> j) {
    final filesJson = j['files'];
    if (filesJson is! Map) throw const FormatException('region: missing files');
    final files = <String, RegionFile>{
      for (final e in filesJson.entries)
        e.key as String: RegionFile.fromJson(e.value as Map<String, Object?>),
    };
    for (final k in requiredFiles) {
      if (!files.containsKey(k)) throw FormatException('region: missing file "$k"');
    }
    return Region(
      id: j['id'] as String,
      name: j['name'] as String,
      state: (j['state'] as String?) ?? '',
      bbox: RegionBounds.fromList(j['bbox'] as List<Object?>),
      version: (j['version'] as num).toInt(),
      files: files,
      installedAt: (j['installedAt'] as String?) != null
          ? DateTime.parse(j['installedAt'] as String)
          : null,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'state': state,
        'bbox': [bbox.minLon, bbox.minLat, bbox.maxLon, bbox.maxLat],
        'version': version,
        'files': {
          for (final e in files.entries)
            e.key: {'url': e.value.url, 'bytes': e.value.bytes, 'sha256': e.value.sha256}
        },
        if (installedAt != null) 'installedAt': installedAt!.toIso8601String(),
      };

  Region copyWith({DateTime? installedAt}) => Region(
        id: id, name: name, state: state, bbox: bbox, version: version,
        files: files, installedAt: installedAt ?? this.installedAt);
}

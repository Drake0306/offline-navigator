import 'dart:math' as math;

/// A single offline-search hit. Immutable. [distanceM] is filled once an origin
/// is known (GPS fix or map center).
class SearchResult {
  const SearchResult({
    required this.name,
    required this.kind,
    required this.lat,
    required this.lng,
    this.nameEn,
    this.distanceM,
  });

  final String name;
  final String? nameEn;
  final String kind; // 'place' | 'poi' | 'road' | 'water'
  final double lat;
  final double lng;
  final double? distanceM;

  SearchResult withDistanceFrom(double originLat, double originLng) =>
      SearchResult(
        name: name,
        nameEn: nameEn,
        kind: kind,
        lat: lat,
        lng: lng,
        distanceM: distanceMeters(originLat, originLng, lat, lng),
      );

  /// Great-circle distance in metres (haversine).
  static double distanceMeters(
      double lat1, double lon1, double lat2, double lon2) {
    const earth = 6371000.0; // metres
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return earth * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double deg) => deg * math.pi / 180.0;
}

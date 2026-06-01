/// A geographic point in the routing domain. Kept independent of maplibre so
/// the domain layer has no UI dependency.
class LatLng {
  const LatLng(this.lat, this.lng);
  final double lat;
  final double lng;

  @override
  bool operator ==(Object other) =>
      other is LatLng && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);

  @override
  String toString() => 'LatLng($lat, $lng)';
}

/// "450 m" below 1 km, else "1.2 km".
String formatDistance(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}

/// "12 min", or "1 h 5 min" once it crosses an hour. Rounds up to the minute.
String formatDuration(Duration d) {
  final totalMin = (d.inSeconds / 60).ceil();
  if (totalMin < 60) return '$totalMin min';
  final h = totalMin ~/ 60;
  final m = totalMin % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

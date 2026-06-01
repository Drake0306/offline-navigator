import 'package:offline_navigator/routing/lat_lng.dart';
import 'package:offline_navigator/routing/travel_mode.dart';

/// A point in a trip (start, stop, or destination) with an optional label.
class TripPoint {
  const TripPoint(this.point, this.label);
  final LatLng point;
  final String? label;
}

/// Immutable trip definition: start, ordered stops, destination, and mode.
/// All mutating methods return a new instance.
class TripState {
  const TripState({
    this.start,
    this.destination,
    this.stops = const [],
    required this.mode,
  });

  final TripPoint? start;
  final TripPoint? destination;
  final List<TripPoint> stops;
  final TravelMode mode;

  bool get isRoutable => start != null && destination != null;

  /// start → stops (in order) → destination, skipping any nulls.
  List<TripPoint> get orderedPoints => [
        if (start != null) start!,
        ...stops,
        if (destination != null) destination!,
      ];

  List<LatLng> get latLngs => [for (final p in orderedPoints) p.point];

  TripState _copy({
    TripPoint? start,
    TripPoint? destination,
    List<TripPoint>? stops,
    TravelMode? mode,
    bool clearStart = false,
    bool clearDestination = false,
  }) =>
      TripState(
        start: clearStart ? null : (start ?? this.start),
        destination: clearDestination ? null : (destination ?? this.destination),
        stops: stops ?? this.stops,
        mode: mode ?? this.mode,
      );

  TripState withStart(TripPoint? p) =>
      p == null ? _copy(clearStart: true) : _copy(start: p);
  TripState withDestination(TripPoint? p) =>
      p == null ? _copy(clearDestination: true) : _copy(destination: p);
  TripState withMode(TravelMode m) => _copy(mode: m);

  TripState addStop(TripPoint p) => _copy(stops: [...stops, p]);
  TripState removeStopAt(int index) =>
      _copy(stops: [...stops]..removeAt(index));

  /// Move the stop from [oldIndex] to [newIndex] using Flutter's
  /// ReorderableList index convention (newIndex is the slot AFTER removal).
  TripState reorderStops(int oldIndex, int newIndex) {
    final next = [...stops];
    final item = next.removeAt(oldIndex);
    final insertAt = newIndex > oldIndex ? newIndex - 1 : newIndex;
    next.insert(insertAt, item);
    return _copy(stops: next);
  }

  TripState clear() => TripState(mode: mode);
}

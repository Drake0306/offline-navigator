import 'package:flutter/foundation.dart';
import 'package:offline_navigator/routing/lat_lng.dart';
import 'package:offline_navigator/routing/live_progress.dart';
import 'package:offline_navigator/routing/route_plan.dart';

/// The screen's high-level mode.
enum NavState { idle, planning, navigating }

/// Drives the navigation state machine. Holds the active route being driven and
/// the current maneuver index, advanced from live positions. A [ChangeNotifier]
/// so the UI rebuilds on transitions.
class NavController extends ChangeNotifier {
  NavState _state = NavState.idle;
  RoutePlan? _activePlan;
  int _currentManeuverIndex = 0;

  NavState get state => _state;
  RoutePlan? get activePlan => _activePlan;
  int get currentManeuverIndex => _currentManeuverIndex;

  /// Enter trip-planning mode.
  void planning() {
    _state = NavState.planning;
    notifyListeners();
  }

  /// Begin driving [plan].
  void startNavigation(RoutePlan plan) {
    _activePlan = plan;
    _currentManeuverIndex = 0;
    _state = NavState.navigating;
    notifyListeners();
  }

  /// Update the current maneuver from a live [position]. No-op unless navigating.
  void advanceTo(LatLng position) {
    final plan = _activePlan;
    if (_state != NavState.navigating || plan == null) return;
    final locs = [for (final m in plan.maneuvers) m.location];
    if (locs.isEmpty) return;
    final idx = nearestManeuverIndex(position, locs);
    if (idx != _currentManeuverIndex) {
      _currentManeuverIndex = idx;
      notifyListeners();
    }
  }

  /// Replace the active plan after a re-route (stays navigating).
  void replacePlan(RoutePlan plan) {
    _activePlan = plan;
    _currentManeuverIndex = 0;
    notifyListeners();
  }

  /// Leave driving, back to planning (route stays available in the UI).
  void exit() {
    _activePlan = null;
    _currentManeuverIndex = 0;
    _state = NavState.planning;
    notifyListeners();
  }

  /// Reset to idle (no trip).
  void clear() {
    _activePlan = null;
    _currentManeuverIndex = 0;
    _state = NavState.idle;
    notifyListeners();
  }
}

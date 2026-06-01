import 'package:flutter/material.dart';
import 'package:offline_navigator/routing/route_format.dart';
import 'package:offline_navigator/routing/route_plan.dart';
import 'package:offline_navigator/routing/routing_service.dart';
import 'package:offline_navigator/routing/travel_mode.dart';
import 'package:offline_navigator/routing/trip_state.dart';

/// Bottom panel that drives trip planning. Computes a route via [service]
/// whenever [trip] changes and renders distance/ETA + maneuvers, or an error.
class TripPlannerPanel extends StatefulWidget {
  const TripPlannerPanel({
    super.key,
    required this.service,
    required this.trip,
    required this.onModeChanged,
    required this.onRemoveStop,
    required this.onClear,
    required this.onPlanChanged,
    required this.onStart,
  });

  final RoutingService service;
  final TripState trip;
  final ValueChanged<TravelMode> onModeChanged;
  final ValueChanged<int> onRemoveStop;
  final VoidCallback onClear;

  /// Reports the latest computed plan (or null on error/none) to the parent so
  /// it can draw the route line.
  final ValueChanged<RoutePlan?> onPlanChanged;

  /// Called when the user taps Start to begin turn-by-turn navigation.
  final VoidCallback onStart;

  @override
  State<TripPlannerPanel> createState() => _TripPlannerPanelState();
}

class _TripPlannerPanelState extends State<TripPlannerPanel> {
  RoutePlan? _plan;
  String? _error;
  bool _loading = false;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  @override
  void didUpdateWidget(TripPlannerPanel old) {
    super.didUpdateWidget(old);
    if (old.trip != widget.trip) _recompute();
  }

  Future<void> _recompute() async {
    if (!widget.trip.isRoutable) {
      setState(() {
        _plan = null;
        _error = null;
        _loading = false;
      });
      widget.onPlanChanged(null);
      return;
    }
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.service.ensureReady();
      final plan =
          await widget.service.route(widget.trip.latLngs, widget.trip.mode);
      if (!mounted || seq != _seq) return;
      setState(() {
        _plan = plan;
        _loading = false;
      });
      widget.onPlanChanged(plan);
    } on RoutingException catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _plan = null;
        _error = e.message;
        _loading = false;
      });
      widget.onPlanChanged(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('tripPanel'),
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Mode selector + clear button.
              Row(
                children: [
                  for (final m in TravelMode.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        key: Key('mode-${m.name}'),
                        label: Text(m.label),
                        selected: widget.trip.mode == m,
                        onSelected: (_) => widget.onModeChanged(m),
                      ),
                    ),
                  const Spacer(),
                  IconButton(
                    key: const Key('clearTrip'),
                    icon: const Icon(Icons.close),
                    onPressed: widget.onClear,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Ordered stops list with delete buttons.
              if (widget.trip.stops.isNotEmpty)
                Column(
                  children: [
                    for (var i = 0; i < widget.trip.stops.length; i++)
                      ListTile(
                        key: Key('stop-$i'),
                        dense: true,
                        leading: const Icon(Icons.place, size: 18),
                        title:
                            Text(widget.trip.stops[i].label ?? 'Stop ${i + 1}'),
                        trailing: IconButton(
                          key: Key('removeStop-$i'),
                          icon: const Icon(Icons.remove_circle_outline,
                              size: 18),
                          onPressed: () => widget.onRemoveStop(i),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 4),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Padding(
                  key: const Key('tripError'),
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    const Icon(Icons.error_outline),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_routeErrorText(_error!))),
                    TextButton(onPressed: _recompute, child: const Text('Retry')),
                  ]),
                )
              else if (_plan != null) ...[
                Text(
                  '${formatDistance(_plan!.distanceMeters)} · ${formatDuration(_plan!.duration)}',
                  key: const Key('tripSummary'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (var i = 0; i < _plan!.maneuvers.length; i++)
                        ListTile(
                          key: Key('maneuver-$i'),
                          dense: true,
                          leading: Icon(_iconFor(_plan!.maneuvers[i].type)),
                          title: Text(_plan!.maneuvers[i].instruction),
                          trailing: Text(formatDistance(
                              _plan!.maneuvers[i].distanceMeters)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('startNavButton'),
                    onPressed: widget.onStart,
                    icon: const Icon(Icons.navigation),
                    label: const Text('Start'),
                  ),
                ),
              ] else
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Set a destination to plan a trip.'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _routeErrorText(String msg) =>
      msg.toLowerCase().contains('outside')
          ? 'Destination is outside the downloaded map area.'
          : 'Routing unavailable: $msg';

  IconData _iconFor(ManeuverType t) => switch (t) {
        ManeuverType.start => Icons.my_location,
        ManeuverType.destination => Icons.flag,
        ManeuverType.left ||
        ManeuverType.slightLeft ||
        ManeuverType.sharpLeft =>
          Icons.turn_left,
        ManeuverType.right ||
        ManeuverType.slightRight ||
        ManeuverType.sharpRight =>
          Icons.turn_right,
        ManeuverType.roundabout => Icons.roundabout_left,
        _ => Icons.straight,
      };
}

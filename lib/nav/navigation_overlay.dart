import 'package:flutter/material.dart';
import 'package:offline_navigator/routing/route_format.dart';
import 'package:offline_navigator/routing/route_plan.dart';

/// Drive-mode overlay: a top maneuver banner and a bottom status bar with End.
/// Pure presentation — given the active plan, the current maneuver index, the
/// remaining distance/duration, and a status string; reports End via [onEnd].
class NavigationOverlay extends StatelessWidget {
  const NavigationOverlay({
    super.key,
    required this.plan,
    required this.currentManeuverIndex,
    required this.remainingMeters,
    required this.remaining,
    required this.statusText,
    required this.onEnd,
    required this.onRecenter,
  });

  final RoutePlan plan;
  final int currentManeuverIndex;
  final double remainingMeters;
  final Duration remaining;
  final String? statusText; // e.g. "Recalculating…", "You have arrived"
  final VoidCallback onEnd;
  final VoidCallback onRecenter;

  Maneuver? get _current =>
      (currentManeuverIndex >= 0 && currentManeuverIndex < plan.maneuvers.length)
          ? plan.maneuvers[currentManeuverIndex]
          : null;
  Maneuver? get _next =>
      (currentManeuverIndex + 1 < plan.maneuvers.length)
          ? plan.maneuvers[currentManeuverIndex + 1]
          : null;

  @override
  Widget build(BuildContext context) {
    final cur = _current;
    return Stack(
      children: [
        // Top maneuver banner.
        Positioned(
          left: 8, right: 8, top: 8,
          child: Material(
            key: const Key('maneuverBanner'),
            color: const Color(0xFF1B2540),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Icon(_iconFor(cur?.type), color: Colors.white, size: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(cur?.instruction ?? statusText ?? 'Proceed',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 18,
                              fontWeight: FontWeight.w600)),
                      if (_next != null)
                        Text('then ${_next!.instruction}',
                            style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
                Text(formatDistance(cur?.distanceMeters ?? 0),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
        // Bottom status bar.
        Positioned(
          left: 8, right: 8, bottom: 8,
          child: Material(
            key: const Key('navStatusBar'),
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            elevation: 6,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                Text('${formatDuration(remaining)} · ${formatDistance(remainingMeters)}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  key: const Key('navRecenter'),
                  icon: const Icon(Icons.my_location),
                  onPressed: onRecenter,
                ),
                FilledButton(
                  key: const Key('navEnd'),
                  onPressed: onEnd,
                  child: const Text('End'),
                ),
              ]),
            ),
          ),
        ),
        if (statusText != null && _current != null)
          Positioned(
            left: 8, right: 8, top: 92,
            child: Material(
              key: const Key('navStatusFlash'),
              color: const Color(0xFFFDF1DC),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(statusText!),
              ),
            ),
          ),
      ],
    );
  }

  IconData _iconFor(ManeuverType? t) => switch (t) {
        ManeuverType.start => Icons.navigation,
        ManeuverType.destination => Icons.flag,
        ManeuverType.left || ManeuverType.slightLeft || ManeuverType.sharpLeft =>
          Icons.turn_left,
        ManeuverType.right || ManeuverType.slightRight || ManeuverType.sharpRight =>
          Icons.turn_right,
        ManeuverType.roundabout => Icons.roundabout_left,
        _ => Icons.straight,
      };
}

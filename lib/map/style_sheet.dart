import 'package:flutter/material.dart';
import 'package:offline_navigator/map/map_style.dart';

/// Result of the style picker. [auto] true means "follow OS brightness";
/// otherwise [id] is the manual pick.
typedef StyleChoice = ({bool auto, MapStyleId? id});

/// Shows the style picker as a bottom sheet. Returns null if dismissed.
Future<StyleChoice?> showStyleSheet(
  BuildContext context, {
  required MapStyleId active,
  required bool isAuto,
}) {
  return showModalBottomSheet<StyleChoice>(
    context: context,
    builder: (ctx) => StyleSheet(active: active, isAuto: isAuto),
  );
}

class StyleSheet extends StatelessWidget {
  const StyleSheet({super.key, required this.active, required this.isAuto});

  final MapStyleId active;
  final bool isAuto;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Map style', style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            for (final id in MapStyleId.values)
              ListTile(
                key: Key('style-${id.name}'),
                leading: Icon(id == active ? Icons.check_circle
                    : Icons.circle_outlined),
                title: Text(id.label),
                onTap: () => Navigator.pop<StyleChoice>(
                    context, (auto: false, id: id)),
              ),
            const Divider(height: 1),
            ListTile(
              key: const Key('style-auto'),
              leading: Icon(isAuto ? Icons.brightness_auto
                  : Icons.brightness_auto_outlined),
              title: const Text('Auto (follow system)'),
              subtitle: isAuto ? const Text('Active') : null,
              onTap: () => Navigator.pop<StyleChoice>(
                  context, (auto: true, id: null)),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

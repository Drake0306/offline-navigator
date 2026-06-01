import 'package:flutter/material.dart';
import 'package:offline_navigator/regions/region_controller.dart';
import 'package:offline_navigator/regions/region_manager_screen.dart';

/// App settings. Currently the home for the offline region download manager.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.regions});

  final RegionController regions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            key: const Key('downloadRegionsTile'),
            leading: const Icon(Icons.download_for_offline_outlined),
            title: const Text('Download regions'),
            subtitle: const Text('Add offline maps for more districts'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RegionManagerScreen(controller: regions),
              ),
            ),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

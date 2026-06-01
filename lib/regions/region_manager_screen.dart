import 'package:flutter/material.dart';
import 'package:offline_navigator/regions/region.dart';
import 'package:offline_navigator/regions/region_controller.dart';

/// Settings → Download regions: lists installed + catalog regions with
/// download/cancel/activate/delete controls and live progress.
class RegionManagerScreen extends StatefulWidget {
  const RegionManagerScreen({super.key, required this.controller});
  final RegionController controller;

  @override
  State<RegionManagerScreen> createState() => _RegionManagerScreenState();
}

class _RegionManagerScreenState extends State<RegionManagerScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.loadInstalled();
    widget.controller.refreshCatalog();
  }

  String _size(int bytes) {
    if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
    if (bytes >= 1 << 10) return '${(bytes / (1 << 10)).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Download regions'),
        actions: [
          IconButton(
            key: const Key('refreshRegions'),
            icon: const Icon(Icons.refresh),
            onPressed: c.refreshCatalog,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final installedIds = c.installed.map((r) => r.id).toSet();
          final rows = <Region>[
            ...c.installed,
            ...c.available.where((r) => !installedIds.contains(r.id)),
          ];
          return Column(
            children: [
              if (c.error != null)
                Container(
                  key: const Key('regionError'),
                  width: double.infinity,
                  color: const Color(0xFFFDE7E7),
                  padding: const EdgeInsets.all(12),
                  child: Text(c.error!),
                ),
              Expanded(
                child: rows.isEmpty
                    ? const Center(child: Text('No regions available yet.'))
                    : ListView(
                        children: [
                          for (final r in rows)
                            _row(c, r, installedIds.contains(r.id)),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(RegionController c, Region r, bool installed) {
    final active = c.activeRegionId == r.id;
    final downloading = c.isDownloading(r.id);
    return ListTile(
      key: Key('regionRow-${r.id}'),
      title: Text(r.name),
      subtitle: downloading
          ? LinearProgressIndicator(
              key: Key('regionProgress-${r.id}'), value: c.progress[r.id])
          : Text('${r.state} · ${_size(r.totalBytes)}'),
      trailing: _trailing(c, r, installed, active, downloading),
    );
  }

  Widget _trailing(RegionController c, Region r, bool installed, bool active,
      bool downloading) {
    if (downloading) {
      return TextButton(
        key: Key('cancelRegion-${r.id}'),
        onPressed: () => c.cancel(r.id),
        child: const Text('Cancel'),
      );
    }
    if (!installed) {
      return FilledButton(
        key: Key('downloadRegion-${r.id}'),
        onPressed: () => c.download(r.id),
        child: const Text('Download'),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (active)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Chip(label: Text('Active')),
          )
        else
          TextButton(
            key: Key('activateRegion-${r.id}'),
            onPressed: () => c.setActive(r.id),
            child: const Text('Use'),
          ),
        IconButton(
          key: Key('deleteRegion-${r.id}'),
          icon: const Icon(Icons.delete_outline),
          onPressed: () => c.delete(r.id),
        ),
      ],
    );
  }
}

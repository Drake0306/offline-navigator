import 'package:flutter/foundation.dart';
import 'package:offline_navigator/regions/region.dart';
import 'package:offline_navigator/regions/region_catalog.dart';
import 'package:offline_navigator/regions/region_downloader.dart';
import 'package:offline_navigator/regions/region_store.dart';

/// App-wide region state: the online catalog ([available]), [installed] regions,
/// the [activeRegionId], and in-flight download [progress]. A [ChangeNotifier]
/// so the UI rebuilds on every transition.
class RegionController extends ChangeNotifier {
  RegionController({
    required RegionStore store,
    required RegionDownloader downloader,
    required Future<List<Region>> Function() catalogSource,
    this.defaultRegionId = 'ghatshila',
  })  : _store = store,
        _downloader = downloader,
        _catalogSource = catalogSource;

  final RegionStore _store;
  final RegionDownloader _downloader;
  final Future<List<Region>> Function() _catalogSource;
  final String defaultRegionId;

  List<Region> _available = const [];
  List<Region> _installed = const [];
  String? _activeRegionId;
  final Map<String, double> _progress = {};
  final Map<String, CancelToken> _cancels = {};
  String? _error;

  List<Region> get available => _available;
  List<Region> get installed => _installed;
  String? get activeRegionId => _activeRegionId;
  Map<String, double> get progress => Map.unmodifiable(_progress);
  String? get error => _error;
  bool isInstalled(String id) => _installed.any((r) => r.id == id);
  bool isDownloading(String id) => _progress.containsKey(id);

  Future<void> loadInstalled() async {
    _installed = await _store.installedRegions();
    _activeRegionId = await _store.activeRegionId();
    notifyListeners();
  }

  Future<void> refreshCatalog() async {
    try {
      _available = await _catalogSource();
      _error = null;
    } on RegionCatalogException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Could not load the region catalog — check your connection.';
    }
    notifyListeners();
  }

  Future<void> download(String id) async {
    if (_progress.containsKey(id)) return; // already downloading
    final region = _available.firstWhere((r) => r.id == id,
        orElse: () => throw StateError('unknown region: $id'));
    final cancel = CancelToken();
    _cancels[id] = cancel;
    _progress[id] = 0;
    _error = null;
    notifyListeners();
    try {
      await _downloader.download(region, _store,
          cancel: cancel, onProgress: (f) {
        _progress[id] = f;
        notifyListeners();
      });
      _installed = await _store.installedRegions();
    } on RegionDownloadCancelled {
      // user-canceled: no error surfaced
    } catch (e) {
      _error = 'Download failed: $e';
    } finally {
      _progress.remove(id);
      _cancels.remove(id);
      notifyListeners();
    }
  }

  void cancel(String id) => _cancels[id]?.cancel();

  Future<void> setActive(String id) async {
    await _store.setActive(id);
    _activeRegionId = id;
    notifyListeners();
  }

  Future<void> delete(String id) async {
    await _store.delete(id);
    _installed = await _store.installedRegions();
    _activeRegionId = await _store.activeRegionId();
    if (_activeRegionId == null && isInstalled(defaultRegionId)) {
      await setActive(defaultRegionId); // notifies
    } else {
      notifyListeners();
    }
  }
}

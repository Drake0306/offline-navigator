import 'dart:async';
import 'package:flutter/material.dart';
import 'package:offline_navigator/search/search_result.dart';

/// Abstraction so the screen can be tested without a real DB.
abstract class SearchQuerier {
  Future<List<SearchResult>> query(String text,
      {required double originLat, required double originLng, int limit});
}

/// Full-screen offline search. Debounces input, shows live results, and pops
/// the chosen [SearchResult] (or null if cancelled).
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.querier,
    required this.originLat,
    required this.originLng,
  });

  final SearchQuerier querier;
  final double originLat;
  final double originLng;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  int _seq = 0; // drop stale in-flight results
  List<SearchResult> _results = const [];
  bool _error = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () => _run(text));
  }

  Future<void> _run(String text) async {
    final seq = ++_seq;
    try {
      final r = await widget.querier.query(
        text,
        originLat: widget.originLat,
        originLng: widget.originLng,
        limit: 30,
      );
      if (!mounted || seq != _seq) return; // a newer query superseded this one
      setState(() {
        _results = r;
        _error = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() => _error = true);
    }
  }

  String _distanceLabel(double? m) {
    if (m == null) return '';
    if (m < 1000) return '${m.round()} m';
    return '${(m / 1000).toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          key: const Key('searchField'),
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search places, POIs, roads…',
            border: InputBorder.none,
          ),
          onChanged: _onChanged,
        ),
      ),
      body: _error
          ? const Center(
              key: Key('searchError'),
              child: Text('Search unavailable.'),
            )
          : ListView.builder(
              itemCount: _results.length,
              itemBuilder: (ctx, i) {
                final r = _results[i];
                return ListTile(
                  key: Key('result-$i'),
                  leading: Icon(_iconFor(r.kind)),
                  title: Text(r.name),
                  subtitle: Text(r.kind),
                  trailing: Text(_distanceLabel(r.distanceM)),
                  onTap: () => Navigator.pop<SearchResult>(context, r),
                );
              },
            ),
    );
  }

  IconData _iconFor(String kind) => switch (kind) {
        'place' => Icons.location_city,
        'poi' => Icons.place,
        'road' => Icons.alt_route,
        'water' => Icons.water,
        _ => Icons.location_on,
      };
}

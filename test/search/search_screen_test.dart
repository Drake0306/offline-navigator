import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/search/search_result.dart';
import 'package:offline_navigator/search/search_screen.dart';

class _FakeQuerier implements SearchQuerier {
  _FakeQuerier(this.results, {this.fail = false});
  final List<SearchResult> results;
  final bool fail;
  @override
  Future<List<SearchResult>> query(String text,
      {required double originLat, required double originLng, int limit = 30}) async {
    if (fail) throw Exception('boom');
    if (text.trim().isEmpty) return const [];
    return results;
  }
}

void main() {
  testWidgets('typing shows results and tapping pops the chosen one',
      (tester) async {
    const hit = SearchResult(
        name: 'Ghatshila', kind: 'place', lat: 22.586, lng: 86.476, distanceM: 0);
    SearchResult? popped;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () async {
            popped = await Navigator.push<SearchResult>(
              ctx,
              MaterialPageRoute(
                builder: (_) => SearchScreen(
                  querier: _FakeQuerier(const [hit]),
                  originLat: 22.586,
                  originLng: 86.476,
                ),
              ),
            );
          },
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('searchField')), 'ghat');
    await tester.pump(const Duration(milliseconds: 250)); // debounce
    await tester.pump(); // rebuild with results

    expect(find.text('Ghatshila'), findsOneWidget);
    await tester.tap(find.byKey(const Key('result-0')));
    await tester.pumpAndSettle();
    expect(popped?.name, 'Ghatshila');
  });

  testWidgets('error state renders when the querier throws', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SearchScreen(
        querier: _FakeQuerier(const [], fail: true),
        originLat: 0,
        originLng: 0,
      ),
    ));
    await tester.enterText(find.byKey(const Key('searchField')), 'x');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(find.byKey(const Key('searchError')), findsOneWidget);
  });
}

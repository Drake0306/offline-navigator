import 'package:flutter_test/flutter_test.dart';
import 'package:offline_navigator/search/text_normalize.dart';

void main() {
  test('lowercases and trims/collapses whitespace', () {
    expect(normalizeSearch('  Ghatshila  Town '), 'ghatshila town');
  });

  test('strips diacritics', () {
    expect(normalizeSearch('Galudīh'), 'galudih');
    expect(normalizeSearch('Café'), 'cafe');
  });

  test('empty/whitespace → empty', () {
    expect(normalizeSearch(''), '');
    expect(normalizeSearch('   '), '');
  });

  test('non-latin script is preserved (lowercased/trimmed only)', () {
    // Devanagari has no case; normalization should keep the characters.
    expect(normalizeSearch(' घाटशिला '), 'घाटशिला');
  });
}

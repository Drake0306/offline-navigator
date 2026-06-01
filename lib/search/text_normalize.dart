import 'dart:core';

/// Normalizes text for offline search matching. MUST stay in sync with the
/// build-time `normalize()` in tool/extract_features.py: NFKD-decompose, drop
/// combining marks (diacritics), lowercase, collapse whitespace, trim.
///
/// Dart's String has no built-in NFKD, so we strip the common Latin combining
/// diacritical marks (U+0300–U+036F) after lowercasing. Scripts without case
/// or combining marks (e.g. Devanagari) pass through unchanged except for
/// whitespace/casing — matching the Python side for the names we index.
String normalizeSearch(String input) {
  if (input.trim().isEmpty) return '';
  final lowered = input.toLowerCase();
  // Remove combining diacritical marks (U+0300–U+036F).
  final stripped = lowered.replaceAll(RegExp('[̀-ͯ]'), '');
  // Also fold the most common precomposed Latin accents that don't decompose
  // via the regex above (é, ï, etc. are single code points in Dart strings).
  final folded = _foldLatin(stripped);
  return folded.replaceAll(RegExp(r'\s+'), ' ').trim();
}

const _latinFolds = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ō': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u',
  'ñ': 'n', 'ç': 'c',
};

String _foldLatin(String s) {
  final sb = StringBuffer();
  for (final ch in s.split('')) {
    sb.write(_latinFolds[ch] ?? ch);
  }
  return sb.toString();
}

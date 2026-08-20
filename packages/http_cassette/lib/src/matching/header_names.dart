import '../model/http_syntax.dart';

/// Validates, lower-cases, deduplicates and sorts HTTP header [names].
Set<String> canonicaliseHeaderNames(
  Iterable<String> names, {
  required String invalidMessage,
}) {
  final canonicalNames = <String>{};
  for (final name in names) {
    if (!isHttpToken(name)) {
      throw ArgumentError(invalidMessage);
    }
    canonicalNames.add(name.toLowerCase());
  }

  final sorted = canonicalNames.toList()..sort();
  return Set<String>.unmodifiable(sorted);
}

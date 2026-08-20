/// The value-free result of comparing two canonical bodies as exact bytes.
final class ExactBodyComparisonResult {
  const ExactBodyComparisonResult._({
    required this.matches,
    required this.expectedLength,
    required this.actualLength,
    required this.firstDifferenceOffset,
  });

  /// Whether both bodies contain exactly the same bytes.
  final bool matches;

  /// The expected body length in bytes.
  final int expectedLength;

  /// The actual body length in bytes.
  final int actualLength;

  /// The zero-based offset of the first difference, or `null` when matched.
  ///
  /// When one body is an exact prefix of the other, this is the length of the
  /// shorter body.
  final int? firstDifferenceOffset;

  /// Whether the expected body contains zero bytes.
  bool get expectedIsEmpty => expectedLength == 0;

  /// Whether the actual body contains zero bytes.
  bool get actualIsEmpty => actualLength == 0;
}

/// Compares [expected] and [actual] without retaining or exposing their bytes.
ExactBodyComparisonResult compareExactBodies(
  List<int> expected,
  List<int> actual,
) {
  final sharedLength =
      expected.length < actual.length ? expected.length : actual.length;
  for (var offset = 0; offset < sharedLength; offset += 1) {
    if (expected[offset] != actual[offset]) {
      return ExactBodyComparisonResult._(
        matches: false,
        expectedLength: expected.length,
        actualLength: actual.length,
        firstDifferenceOffset: offset,
      );
    }
  }

  final matches = expected.length == actual.length;
  return ExactBodyComparisonResult._(
    matches: matches,
    expectedLength: expected.length,
    actualLength: actual.length,
    firstDifferenceOffset: matches ? null : sharedLength,
  );
}

import '../model/headers.dart';
import 'difference.dart';
import 'exclusions.dart';
import 'header_names.dart';

/// Immutable values for the explicitly selected request headers.
final class NormalisedSelectedHeaders {
  /// Selects and normalises [selectedNames] from [headers].
  ///
  /// Names are case-insensitive and must use the HTTP token grammar. An absent
  /// selected field is retained so it remains distinct from an empty value.
  factory NormalisedSelectedHeaders.fromHeaders(
    CassetteHeaders headers, {
    Set<String> selectedNames = const <String>{},
    MatchingExclusions exclusions = MatchingExclusions.none,
  }) {
    final sortedNames = canonicaliseHeaderNames(
      selectedNames,
      invalidMessage: 'Selected header name must use the token grammar.',
    ).where((name) => !exclusions.headers.contains(name));
    return NormalisedSelectedHeaders._(
      List<NormalisedSelectedHeader>.unmodifiable(
        sortedNames.map((name) {
          final values = headers.values(name);
          return NormalisedSelectedHeader._(
            name: name,
            values: values == null
                ? null
                : List<String>.unmodifiable(
                    values.map(_trimOptionalWhitespace),
                  ),
          );
        }),
      ),
    );
  }

  const NormalisedSelectedHeaders._(this.fields);

  /// Selected fields in deterministic name order.
  final List<NormalisedSelectedHeader> fields;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NormalisedSelectedHeaders &&
          _nullableListsEqual(fields, other.fields);

  @override
  int get hashCode => Object.hashAll(fields);
}

/// Compares selected headers without retaining field values in differences.
BoundedMatchDifferences compareSelectedHeaders(
  NormalisedSelectedHeaders expected,
  NormalisedSelectedHeaders actual, {
  int maximumRetained = MatchDifferenceCollector.defaultMaximumRetained,
}) {
  if (expected.fields.length != actual.fields.length) {
    throw StateError(
      'Selected header comparison requires the same canonical fields.',
    );
  }
  final collector = MatchDifferenceCollector(maximumRetained: maximumRetained);
  for (var index = 0; index < expected.fields.length; index += 1) {
    final expectedField = expected.fields[index];
    final actualField = actual.fields[index];
    if (expectedField.name != actualField.name) {
      throw StateError(
        'Selected header comparison requires the same canonical fields.',
      );
    }
    final expectedValues = expectedField.values;
    final actualValues = actualField.values;
    if (expectedValues == null && actualValues != null) {
      collector.add(
        MatchDifference(
          kind: MatchDifferenceKind.extra,
          location: expectedField.name,
        ),
      );
      continue;
    }
    if (expectedValues != null && actualValues == null) {
      collector.add(
        MatchDifference(
          kind: MatchDifferenceKind.missing,
          location: expectedField.name,
        ),
      );
      continue;
    }
    if (expectedValues == null || actualValues == null) {
      continue;
    }
    if (expectedValues.length != actualValues.length) {
      collector.add(
        MatchDifference(
          kind: MatchDifferenceKind.differentMultiplicity,
          location: expectedField.name,
        ),
      );
    } else if (!_nullableListsEqual(expectedValues, actualValues) &&
        _containEquivalentStrings(expectedValues, actualValues)) {
      collector.add(
        MatchDifference(
          kind: MatchDifferenceKind.differentOrder,
          location: expectedField.name,
        ),
      );
      continue;
    }

    final sharedLength = expectedValues.length < actualValues.length
        ? expectedValues.length
        : actualValues.length;
    for (var valueIndex = 0; valueIndex < sharedLength; valueIndex += 1) {
      if (expectedValues[valueIndex] != actualValues[valueIndex]) {
        collector.add(
          MatchDifference(
            kind: MatchDifferenceKind.differentValue,
            location: '${expectedField.name}[$valueIndex]',
          ),
        );
      }
    }
    for (var valueIndex = sharedLength;
        valueIndex < expectedValues.length;
        valueIndex += 1) {
      collector.add(
        MatchDifference(
          kind: MatchDifferenceKind.missing,
          location: '${expectedField.name}[$valueIndex]',
        ),
      );
    }
    for (var valueIndex = sharedLength;
        valueIndex < actualValues.length;
        valueIndex += 1) {
      collector.add(
        MatchDifference(
          kind: MatchDifferenceKind.extra,
          location: '${expectedField.name}[$valueIndex]',
        ),
      );
    }
  }
  return collector.build();
}

/// One selected header field and its ordered normalised values.
final class NormalisedSelectedHeader {
  const NormalisedSelectedHeader._({
    required this.name,
    required this.values,
  });

  /// The lower-case canonical field name.
  final String name;

  /// Ordered values, or `null` when the selected field was absent.
  final List<String>? values;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NormalisedSelectedHeader &&
          name == other.name &&
          _nullableListsEqual(values, other.values);

  @override
  int get hashCode => Object.hash(
        name,
        values == null,
        Object.hashAll(values ?? <String>[]),
      );
}

String _trimOptionalWhitespace(String value) {
  var start = 0;
  while (
      start < value.length && _isOptionalWhitespace(value.codeUnitAt(start))) {
    start += 1;
  }

  var end = value.length;
  while (end > start && _isOptionalWhitespace(value.codeUnitAt(end - 1))) {
    end -= 1;
  }
  return value.substring(start, end);
}

bool _isOptionalWhitespace(int codeUnit) =>
    codeUnit == 0x20 || codeUnit == 0x09;

bool _nullableListsEqual<T>(List<T>? first, List<T>? second) {
  if (identical(first, second)) {
    return true;
  }
  if (first == null || second == null || first.length != second.length) {
    return false;
  }
  for (var index = 0; index < first.length; index += 1) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}

bool _containEquivalentStrings(List<String> expected, List<String> actual) {
  final unmatched = List<String>.of(actual);
  for (final value in expected) {
    final index = unmatched.indexOf(value);
    if (index == -1) {
      return false;
    }
    unmatched.removeAt(index);
  }
  return unmatched.isEmpty;
}

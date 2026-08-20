import '../model/headers.dart';
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

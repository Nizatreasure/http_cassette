import 'dart:convert';

import '../json/strict_json.dart';
import '../json/value.dart';
import '../model/headers.dart';
import '../model/http_syntax.dart';
import 'exclusions.dart';

export '../json/value.dart' show ParsedJsonNumber;

/// The result of classifying and parsing a canonical body as JSON.
enum JsonBodyStatus {
  /// The content type does not identify JSON.
  notJsonMediaType,

  /// The body is not valid UTF-8.
  invalidUtf8,

  /// The body is not one complete valid JSON value.
  malformedJson,

  /// An object contains the same decoded member name more than once.
  duplicateObjectMember,

  /// The body contains one complete valid JSON value.
  valid,
}

/// An immutable JSON body classification result.
final class JsonBodyParseResult {
  const JsonBodyParseResult._({required this.status, this.value});

  /// The classification or parsing status.
  final JsonBodyStatus status;

  /// The deeply immutable parsed value when [status] is [JsonBodyStatus.valid].
  ///
  /// This may itself be `null` for a valid JSON `null` root.
  final Object? value;
}

/// The kind of structural difference between two parsed JSON values.
enum JsonDifferenceKind {
  /// An expected object member or array position is absent.
  missing,

  /// An unexpected object member or array position is present.
  extra,

  /// Two values have different JSON types.
  differentType,

  /// Two scalar values have different values.
  differentValue,

  /// An array contains equivalent values in a different order.
  differentOrder,

  /// Two arrays have different lengths.
  differentLength,
}

/// A value-free structural JSON difference at an RFC 6901 location.
final class JsonDifference {
  const JsonDifference({required this.pointer, required this.kind});

  /// The RFC 6901 JSON Pointer, or the empty string for the root value.
  final String pointer;

  /// The category of difference at [pointer].
  final JsonDifferenceKind kind;
}

/// The immutable result of structurally comparing two parsed JSON values.
final class JsonComparisonResult {
  JsonComparisonResult(Iterable<JsonDifference> differences)
      : differences = List<JsonDifference>.unmodifiable(differences);

  /// Deterministically ordered structural differences.
  final List<JsonDifference> differences;

  /// Whether the two values are structurally equivalent.
  bool get matches => differences.isEmpty;
}

/// Compares values produced by [parseJsonBody] without exposing scalar values.
JsonComparisonResult compareJsonValues(
  Object? expected,
  Object? actual, {
  MatchingExclusions exclusions = MatchingExclusions.none,
}) {
  final differences = <JsonDifference>[];
  _compareJsonValue(expected, actual, '', exclusions, differences);
  return JsonComparisonResult(differences);
}

/// Classifies and strictly parses [body] using [headers].
///
/// Invalid JSON is returned as a status so later matching can fall back to
/// exact bytes. Duplicate object member names are detected at every depth.
JsonBodyParseResult parseJsonBody(
  CassetteHeaders headers,
  List<int> body,
) {
  if (!_hasJsonMediaType(headers)) {
    return const JsonBodyParseResult._(
      status: JsonBodyStatus.notJsonMediaType,
    );
  }

  late final String source;
  try {
    source = utf8.decode(body, allowMalformed: false);
  } on FormatException {
    return const JsonBodyParseResult._(status: JsonBodyStatus.invalidUtf8);
  }

  try {
    return JsonBodyParseResult._(
      status: JsonBodyStatus.valid,
      value: parseStrictJson(source),
    );
  } on StrictJsonFormatException catch (error) {
    return JsonBodyParseResult._(
      status: error.kind == StrictJsonFailureKind.duplicateObjectMember
          ? JsonBodyStatus.duplicateObjectMember
          : JsonBodyStatus.malformedJson,
    );
  }
}

bool _hasJsonMediaType(CassetteHeaders headers) {
  if (headers.contains('content-encoding')) {
    return false;
  }
  final values = headers.values('content-type');
  if (values == null || values.length != 1) {
    return false;
  }

  final mediaType = values.single.split(';').first.trim();
  final slash = mediaType.indexOf('/');
  if (slash <= 0 || slash == mediaType.length - 1) {
    return false;
  }
  final type = mediaType.substring(0, slash);
  final subtype = mediaType.substring(slash + 1);
  if (!isHttpToken(type) || !isHttpToken(subtype)) {
    return false;
  }

  final lowerType = type.toLowerCase();
  final lowerSubtype = subtype.toLowerCase();
  return (lowerType == 'application' && lowerSubtype == 'json') ||
      (lowerSubtype.length > 5 && lowerSubtype.endsWith('+json'));
}

void _compareJsonValue(
  Object? expected,
  Object? actual,
  String pointer,
  MatchingExclusions exclusions,
  List<JsonDifference> differences,
) {
  if (exclusions.jsonPointers.contains(pointer)) {
    return;
  }
  if (_jsonType(expected) != _jsonType(actual)) {
    differences.add(
      JsonDifference(pointer: pointer, kind: JsonDifferenceKind.differentType),
    );
    return;
  }

  if (expected is Map<String, Object?> && actual is Map<String, Object?>) {
    _compareJsonObjects(expected, actual, pointer, exclusions, differences);
  } else if (expected is List<Object?> && actual is List<Object?>) {
    _compareJsonArrays(expected, actual, pointer, exclusions, differences);
  } else if (!_jsonScalarsEqual(expected, actual)) {
    differences.add(
      JsonDifference(pointer: pointer, kind: JsonDifferenceKind.differentValue),
    );
  }
}

void _compareJsonObjects(
  Map<String, Object?> expected,
  Map<String, Object?> actual,
  String pointer,
  MatchingExclusions exclusions,
  List<JsonDifference> differences,
) {
  final names = <String>{...expected.keys, ...actual.keys}.toList()..sort();
  for (final name in names) {
    final memberPointer = '$pointer/${_escapeJsonPointerToken(name)}';
    if (!expected.containsKey(name)) {
      differences.add(
        JsonDifference(
          pointer: memberPointer,
          kind: JsonDifferenceKind.extra,
        ),
      );
    } else if (!actual.containsKey(name)) {
      differences.add(
        JsonDifference(
          pointer: memberPointer,
          kind: JsonDifferenceKind.missing,
        ),
      );
    } else {
      _compareJsonValue(
        expected[name],
        actual[name],
        memberPointer,
        exclusions,
        differences,
      );
    }
  }
}

void _compareJsonArrays(
  List<Object?> expected,
  List<Object?> actual,
  String pointer,
  MatchingExclusions exclusions,
  List<JsonDifference> differences,
) {
  if (expected.length != actual.length) {
    differences.add(
      JsonDifference(
          pointer: pointer, kind: JsonDifferenceKind.differentLength),
    );
  } else if (!_hasExcludedDescendant(pointer, exclusions) &&
      !_jsonListsEqual(expected, actual) &&
      _containEquivalentJsonValues(expected, actual)) {
    differences.add(
      JsonDifference(pointer: pointer, kind: JsonDifferenceKind.differentOrder),
    );
    return;
  }

  final sharedLength =
      expected.length < actual.length ? expected.length : actual.length;
  for (var index = 0; index < sharedLength; index += 1) {
    _compareJsonValue(
      expected[index],
      actual[index],
      '$pointer/$index',
      exclusions,
      differences,
    );
  }
  for (var index = sharedLength; index < expected.length; index += 1) {
    differences.add(
      JsonDifference(
        pointer: '$pointer/$index',
        kind: JsonDifferenceKind.missing,
      ),
    );
  }
  for (var index = sharedLength; index < actual.length; index += 1) {
    differences.add(
      JsonDifference(
        pointer: '$pointer/$index',
        kind: JsonDifferenceKind.extra,
      ),
    );
  }
}

bool _containEquivalentJsonValues(
  List<Object?> expected,
  List<Object?> actual,
) {
  final unmatched = List<Object?>.of(actual);
  for (final expectedValue in expected) {
    final index = unmatched.indexWhere(
      (actualValue) => _jsonValuesEqual(expectedValue, actualValue),
    );
    if (index == -1) {
      return false;
    }
    unmatched.removeAt(index);
  }
  return unmatched.isEmpty;
}

bool _jsonListsEqual(List<Object?> expected, List<Object?> actual) {
  if (expected.length != actual.length) {
    return false;
  }
  for (var index = 0; index < expected.length; index += 1) {
    if (!_jsonValuesEqual(expected[index], actual[index])) {
      return false;
    }
  }
  return true;
}

bool _jsonValuesEqual(Object? expected, Object? actual) {
  final differences = <JsonDifference>[];
  _compareJsonValue(
    expected,
    actual,
    '',
    MatchingExclusions.none,
    differences,
  );
  return differences.isEmpty;
}

bool _hasExcludedDescendant(
  String pointer,
  MatchingExclusions exclusions,
) {
  final prefix = '$pointer/';
  return exclusions.jsonPointers.any((excluded) => excluded.startsWith(prefix));
}

bool _jsonScalarsEqual(Object? expected, Object? actual) {
  if (expected is ParsedJsonNumber && actual is ParsedJsonNumber) {
    return _normaliseJsonNumber(expected.source) ==
        _normaliseJsonNumber(actual.source);
  }
  return expected == actual;
}

_JsonType _jsonType(Object? value) => switch (value) {
      Map<String, Object?>() => _JsonType.object,
      List<Object?>() => _JsonType.array,
      String() => _JsonType.string,
      bool() => _JsonType.boolean,
      ParsedJsonNumber() => _JsonType.number,
      null => _JsonType.nullValue,
      _ =>
        throw ArgumentError.value(value, 'value', 'Not a parsed JSON value.'),
    };

String _normaliseJsonNumber(String source) {
  var unsigned = source;
  var negative = false;
  if (unsigned.startsWith('-')) {
    negative = true;
    unsigned = unsigned.substring(1);
  }

  final exponentMarker = unsigned.indexOf(RegExp('[eE]'));
  final significand =
      exponentMarker == -1 ? unsigned : unsigned.substring(0, exponentMarker);
  var exponent = exponentMarker == -1
      ? BigInt.zero
      : BigInt.parse(unsigned.substring(exponentMarker + 1));
  final point = significand.indexOf('.');
  var digits = point == -1
      ? significand
      : significand.substring(0, point) + significand.substring(point + 1);
  if (point != -1) {
    exponent -= BigInt.from(significand.length - point - 1);
  }

  digits = digits.replaceFirst(RegExp('^0+'), '');
  if (digits.isEmpty) {
    return '0';
  }
  while (digits.endsWith('0')) {
    digits = digits.substring(0, digits.length - 1);
    exponent += BigInt.one;
  }
  return '${negative ? '-' : ''}$digits@$exponent';
}

String _escapeJsonPointerToken(String token) =>
    token.replaceAll('~', '~0').replaceAll('/', '~1');

enum _JsonType { object, array, string, boolean, number, nullValue }

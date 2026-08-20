import 'dart:convert';

import '../model/headers.dart';
import '../model/http_syntax.dart';

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

/// A validated JSON number retained without binary floating-point conversion.
final class ParsedJsonNumber {
  const ParsedJsonNumber._(this.source);

  /// The original valid JSON number spelling.
  final String source;
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
JsonComparisonResult compareJsonValues(Object? expected, Object? actual) {
  final differences = <JsonDifference>[];
  _compareJsonValue(expected, actual, '', differences);
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
      value: _StrictJsonParser(source).parse(),
    );
  } on _DuplicateObjectMember {
    return const JsonBodyParseResult._(
      status: JsonBodyStatus.duplicateObjectMember,
    );
  } on FormatException {
    return const JsonBodyParseResult._(status: JsonBodyStatus.malformedJson);
  }
}

bool _hasJsonMediaType(CassetteHeaders headers) {
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

final class _StrictJsonParser {
  _StrictJsonParser(this._source);

  final String _source;
  var _index = 0;

  Object? parse() {
    _skipWhitespace();
    final value = _parseValue();
    _skipWhitespace();
    if (_index != _source.length) {
      throw const FormatException('Unexpected content after JSON value.');
    }
    return value;
  }

  Object? _parseValue() {
    if (_index >= _source.length) {
      throw const FormatException('Expected a JSON value.');
    }

    return switch (_source.codeUnitAt(_index)) {
      0x7b => _parseObject(),
      0x5b => _parseArray(),
      0x22 => _parseString(),
      0x74 => _parseLiteral('true', true),
      0x66 => _parseLiteral('false', false),
      0x6e => _parseLiteral('null', null),
      _ => _parseNumber(),
    };
  }

  Map<String, Object?> _parseObject() {
    _index += 1;
    _skipWhitespace();
    final values = <String, Object?>{};
    if (_consume(0x7d)) {
      return Map<String, Object?>.unmodifiable(values);
    }

    while (true) {
      if (_index >= _source.length || _source.codeUnitAt(_index) != 0x22) {
        throw const FormatException('Expected a JSON object member name.');
      }
      final name = _parseString();
      if (values.containsKey(name)) {
        throw const _DuplicateObjectMember();
      }

      _skipWhitespace();
      _expect(0x3a);
      _skipWhitespace();
      values[name] = _parseValue();
      _skipWhitespace();
      if (_consume(0x7d)) {
        return Map<String, Object?>.unmodifiable(values);
      }
      _expect(0x2c);
      _skipWhitespace();
    }
  }

  List<Object?> _parseArray() {
    _index += 1;
    _skipWhitespace();
    final values = <Object?>[];
    if (_consume(0x5d)) {
      return List<Object?>.unmodifiable(values);
    }

    while (true) {
      values.add(_parseValue());
      _skipWhitespace();
      if (_consume(0x5d)) {
        return List<Object?>.unmodifiable(values);
      }
      _expect(0x2c);
      _skipWhitespace();
    }
  }

  String _parseString() {
    final start = _index;
    _index += 1;
    var escaped = false;
    while (_index < _source.length) {
      final codeUnit = _source.codeUnitAt(_index);
      _index += 1;
      if (escaped) {
        escaped = false;
      } else if (codeUnit == 0x5c) {
        escaped = true;
      } else if (codeUnit == 0x22) {
        final decoded = jsonDecode(_source.substring(start, _index));
        if (decoded is! String) {
          throw const FormatException('Expected a JSON string.');
        }
        return decoded;
      }
    }
    throw const FormatException('Unterminated JSON string.');
  }

  Object? _parseLiteral(String spelling, Object? value) {
    if (!_source.startsWith(spelling, _index)) {
      throw const FormatException('Invalid JSON literal.');
    }
    _index += spelling.length;
    return value;
  }

  ParsedJsonNumber _parseNumber() {
    final start = _index;
    while (_index < _source.length &&
        !_isValueDelimiter(_source.codeUnitAt(_index))) {
      _index += 1;
    }
    if (start == _index) {
      throw const FormatException('Expected a JSON number.');
    }
    final source = _source.substring(start, _index);
    if (!_isValidJsonNumber(source)) {
      throw const FormatException('Expected a JSON number.');
    }
    return ParsedJsonNumber._(source);
  }

  void _skipWhitespace() {
    while (_index < _source.length &&
        _isJsonWhitespace(_source.codeUnitAt(_index))) {
      _index += 1;
    }
  }

  bool _consume(int expected) {
    if (_index < _source.length && _source.codeUnitAt(_index) == expected) {
      _index += 1;
      return true;
    }
    return false;
  }

  void _expect(int expected) {
    if (!_consume(expected)) {
      throw const FormatException('Unexpected JSON token.');
    }
  }
}

final class _DuplicateObjectMember implements Exception {
  const _DuplicateObjectMember();
}

bool _isValueDelimiter(int codeUnit) =>
    codeUnit == 0x2c ||
    codeUnit == 0x5d ||
    codeUnit == 0x7d ||
    _isJsonWhitespace(codeUnit);

bool _isJsonWhitespace(int codeUnit) =>
    codeUnit == 0x20 ||
    codeUnit == 0x09 ||
    codeUnit == 0x0a ||
    codeUnit == 0x0d;

bool _isValidJsonNumber(String source) {
  var index = 0;
  if (source.codeUnitAt(index) == 0x2d) {
    index += 1;
    if (index == source.length) {
      return false;
    }
  }

  if (source.codeUnitAt(index) == 0x30) {
    index += 1;
    if (index < source.length && _isDigit(source.codeUnitAt(index))) {
      return false;
    }
  } else {
    if (!_isNonZeroDigit(source.codeUnitAt(index))) {
      return false;
    }
    index += 1;
    while (index < source.length && _isDigit(source.codeUnitAt(index))) {
      index += 1;
    }
  }

  if (index < source.length && source.codeUnitAt(index) == 0x2e) {
    index += 1;
    if (index == source.length || !_isDigit(source.codeUnitAt(index))) {
      return false;
    }
    while (index < source.length && _isDigit(source.codeUnitAt(index))) {
      index += 1;
    }
  }

  if (index < source.length &&
      (source.codeUnitAt(index) == 0x65 || source.codeUnitAt(index) == 0x45)) {
    index += 1;
    if (index < source.length &&
        (source.codeUnitAt(index) == 0x2b ||
            source.codeUnitAt(index) == 0x2d)) {
      index += 1;
    }
    if (index == source.length || !_isDigit(source.codeUnitAt(index))) {
      return false;
    }
    while (index < source.length && _isDigit(source.codeUnitAt(index))) {
      index += 1;
    }
  }

  return index == source.length;
}

void _compareJsonValue(
  Object? expected,
  Object? actual,
  String pointer,
  List<JsonDifference> differences,
) {
  if (_jsonType(expected) != _jsonType(actual)) {
    differences.add(
      JsonDifference(pointer: pointer, kind: JsonDifferenceKind.differentType),
    );
    return;
  }

  if (expected is Map<String, Object?> && actual is Map<String, Object?>) {
    _compareJsonObjects(expected, actual, pointer, differences);
  } else if (expected is List<Object?> && actual is List<Object?>) {
    _compareJsonArrays(expected, actual, pointer, differences);
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
        differences,
      );
    }
  }
}

void _compareJsonArrays(
  List<Object?> expected,
  List<Object?> actual,
  String pointer,
  List<JsonDifference> differences,
) {
  if (expected.length != actual.length) {
    differences.add(
      JsonDifference(
          pointer: pointer, kind: JsonDifferenceKind.differentLength),
    );
  } else if (!_jsonListsEqual(expected, actual) &&
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
  _compareJsonValue(expected, actual, '', differences);
  return differences.isEmpty;
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

bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

bool _isNonZeroDigit(int codeUnit) => codeUnit >= 0x31 && codeUnit <= 0x39;

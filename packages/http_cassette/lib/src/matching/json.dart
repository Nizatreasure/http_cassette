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

bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

bool _isNonZeroDigit(int codeUnit) => codeUnit >= 0x31 && codeUnit <= 0x39;

import 'dart:convert';

import 'value.dart';

/// The safe category of a strict JSON syntax failure.
enum StrictJsonFailureKind {
  /// The source is not one complete valid JSON value.
  malformed,

  /// An object repeats the same decoded member name.
  duplicateObjectMember,
}

/// A value-free strict JSON failure with a bounded source position.
final class StrictJsonFormatException implements Exception {
  const StrictJsonFormatException({
    required this.kind,
    required this.line,
    required this.column,
  });

  /// The safe failure category.
  final StrictJsonFailureKind kind;

  /// The one-based source line containing the failure.
  final int line;

  /// The one-based UTF-16 code-unit column containing the failure.
  final int column;

  @override
  String toString() => 'StrictJsonFormatException('
      '${kind.name} at line $line, column $column)';
}

/// Parses one strict JSON [source] without losing number spelling or map order.
///
/// Returned arrays and objects are deeply immutable. Failures never retain or
/// quote source text.
Object? parseStrictJson(String source) => _StrictJsonParser(source).parse();

final class _StrictJsonParser {
  _StrictJsonParser(this._source);

  final String _source;
  var _index = 0;

  Object? parse() {
    try {
      _skipWhitespace();
      final value = _parseValue();
      _skipWhitespace();
      if (_index != _source.length) {
        _fail();
      }
      return value;
    } on StrictJsonFormatException {
      rethrow;
    } on FormatException {
      _fail();
    }
  }

  Object? _parseValue() {
    if (_index >= _source.length) {
      _fail();
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
        _fail();
      }
      final memberIndex = _index;
      final name = _parseString();
      if (values.containsKey(name)) {
        _index = memberIndex;
        _fail(StrictJsonFailureKind.duplicateObjectMember);
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
        if (decoded is String) {
          return decoded;
        }
        _fail();
      }
    }
    _fail();
  }

  Object? _parseLiteral(String spelling, Object? value) {
    if (!_source.startsWith(spelling, _index)) {
      _fail();
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
      _fail();
    }
    final source = _source.substring(start, _index);
    if (!_isValidJsonNumber(source)) {
      _index = start;
      _fail();
    }
    return ParsedJsonNumber.internal(source);
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
      _fail();
    }
  }

  Never _fail([
    StrictJsonFailureKind kind = StrictJsonFailureKind.malformed,
  ]) {
    var line = 1;
    var column = 1;
    for (var index = 0; index < _index && index < _source.length; index += 1) {
      if (_source.codeUnitAt(index) == 0x0a) {
        line += 1;
        column = 1;
      } else {
        column += 1;
      }
    }
    throw StrictJsonFormatException(kind: kind, line: line, column: column);
  }
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
    if (index == source.length) return false;
  }
  if (source.codeUnitAt(index) == 0x30) {
    index += 1;
    if (index < source.length && _isDigit(source.codeUnitAt(index))) {
      return false;
    }
  } else {
    if (!_isNonZeroDigit(source.codeUnitAt(index))) return false;
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

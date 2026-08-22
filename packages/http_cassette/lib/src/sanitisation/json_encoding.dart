import 'dart:convert';
import 'dart:typed_data';

import '../matching/json.dart';

/// Deterministically encodes one strictly parsed JSON value as UTF-8 bytes.
Uint8List encodeSanitisedJsonValue(Object? value) {
  final output = StringBuffer();
  _writeJsonValue(output, value);
  return Uint8List.fromList(utf8.encode(output.toString()))
      .asUnmodifiableView();
}

void _writeJsonValue(StringBuffer output, Object? value) {
  switch (value) {
    case Map<String, Object?>():
      _writeJsonObject(output, value);
    case List<Object?>():
      _writeJsonArray(output, value);
    case String():
      output.write(jsonEncode(value));
    case bool():
      output.write(value ? 'true' : 'false');
    case ParsedJsonNumber():
      output.write(value.source);
    case null:
      output.write('null');
    default:
      throw ArgumentError.value(value, 'value', 'Not a parsed JSON value.');
  }
}

void _writeJsonObject(
  StringBuffer output,
  Map<String, Object?> value,
) {
  final names = value.keys.toList()..sort();
  output.write('{');
  for (var index = 0; index < names.length; index += 1) {
    if (index > 0) {
      output.write(',');
    }
    final name = names[index];
    output
      ..write(jsonEncode(name))
      ..write(':');
    _writeJsonValue(output, value[name]);
  }
  output.write('}');
}

void _writeJsonArray(StringBuffer output, List<Object?> value) {
  output.write('[');
  for (var index = 0; index < value.length; index += 1) {
    if (index > 0) {
      output.write(',');
    }
    _writeJsonValue(output, value[index]);
  }
  output.write(']');
}

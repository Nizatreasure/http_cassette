import 'dart:convert';
import 'dart:typed_data';

import '../matching/json.dart';
import 'cassette.dart';
import 'schema_projection.dart';

/// Encodes [cassette] as deterministic, pretty-printed V1 JSON.
///
/// Output uses two-space indentation, LF line endings and one final line feed.
/// The returned bytes are immutable.
Uint8List encodeCassetteV1(Cassette cassette) {
  final output = StringBuffer();
  _writeValue(output, projectCassetteSchemaV1(cassette), 0);
  output.write('\n');
  return Uint8List.fromList(utf8.encode(output.toString()))
      .asUnmodifiableView();
}

void _writeValue(StringBuffer output, Object? value, int indentation) {
  switch (value) {
    case Map<String, Object?>():
      _writeObject(output, value, indentation);
    case List<Object?>():
      _writeArray(output, value, indentation);
    case String():
      output.write(jsonEncode(value));
    case bool():
      output.write(value ? 'true' : 'false');
    case int():
      output.write(value);
    case ParsedJsonNumber():
      output.write(value.source);
    case null:
      output.write('null');
    default:
      throw ArgumentError.value(value, 'value', 'Not a V1 schema value.');
  }
}

void _writeObject(
  StringBuffer output,
  Map<String, Object?> value,
  int indentation,
) {
  if (value.isEmpty) {
    output.write('{}');
    return;
  }

  output.write('{\n');
  final entries = value.entries.toList(growable: false);
  for (var index = 0; index < entries.length; index += 1) {
    final entry = entries[index];
    _writeIndentation(output, indentation + 2);
    output
      ..write(jsonEncode(entry.key))
      ..write(': ');
    _writeValue(output, entry.value, indentation + 2);
    if (index < entries.length - 1) {
      output.write(',');
    }
    output.write('\n');
  }
  _writeIndentation(output, indentation);
  output.write('}');
}

void _writeArray(
  StringBuffer output,
  List<Object?> value,
  int indentation,
) {
  if (value.isEmpty) {
    output.write('[]');
    return;
  }

  output.write('[\n');
  for (var index = 0; index < value.length; index += 1) {
    _writeIndentation(output, indentation + 2);
    _writeValue(output, value[index], indentation + 2);
    if (index < value.length - 1) {
      output.write(',');
    }
    output.write('\n');
  }
  _writeIndentation(output, indentation);
  output.write(']');
}

void _writeIndentation(StringBuffer output, int indentation) {
  output.write(' ' * indentation);
}

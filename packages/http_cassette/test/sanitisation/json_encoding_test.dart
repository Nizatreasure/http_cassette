import 'dart:convert';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/matching/json.dart';
import 'package:http_cassette/src/sanitisation/json_encoding.dart';
import 'package:test/test.dart';

void main() {
  group('encodeSanitisedJsonValue', () {
    test('sorts object names recursively and preserves array order', () {
      final first = _parse(
        '{"z":{"second":2,"first":1},"a":[{"z":3,"a":4},5]}',
      );
      final second = _parse(
        '{"a":[{"a":4,"z":3},5],"z":{"first":1,"second":2}}',
      );

      final firstBytes = encodeSanitisedJsonValue(first);
      final secondBytes = encodeSanitisedJsonValue(second);

      expect(firstBytes, secondBytes);
      expect(
        utf8.decode(firstBytes),
        '{"a":[{"a":4,"z":3},5],"z":{"first":1,"second":2}}',
      );
    });

    test('preserves parsed JSON number spellings without double conversion',
        () {
      final value =
          _parse('[0,-0,1.0,1e0,-2E+3,123456789012345678901234567890]');

      final encoded = encodeSanitisedJsonValue(value);

      expect(
        utf8.decode(encoded),
        '[0,-0,1.0,1e0,-2E+3,123456789012345678901234567890]',
      );
    });

    test('encodes strings, booleans, null and empty structures', () {
      final value = _parse(
        '{"text":"line\\nquote\\"slash\\\\","true":true,"false":false,"null":null,"array":[],"object":{}}',
      );

      final encoded = encodeSanitisedJsonValue(value);
      final reparsed = _parse(utf8.decode(encoded));

      expect(compareJsonValues(value, reparsed).matches, isTrue);
    });

    test('returns immutable bytes', () {
      final encoded = encodeSanitisedJsonValue(_parse('{"value":1}'));

      expect(() => encoded[0] = 0, throwsUnsupportedError);
    });

    test('rejects values outside the strict parsed representation', () {
      for (final value in <Object>[
        1,
        1.5,
        <String, Object>{'value': 1}
      ]) {
        expect(
          () => encodeSanitisedJsonValue(value),
          throwsArgumentError,
          reason: '$value',
        );
      }
    });
  });
}

Object? _parse(String source) {
  final result = parseJsonBody(
    CassetteHeaders(<String, Iterable<String>>{
      'content-type': <String>['application/json'],
    }),
    utf8.encode(source),
  );
  expect(result.status, JsonBodyStatus.valid);
  return result.value;
}

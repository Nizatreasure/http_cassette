import 'package:http_cassette/src/cassette/decoder.dart';
import 'package:http_cassette/src/json/strict_json.dart';
import 'package:http_cassette/src/matching/exclusions.dart';
import 'package:http_cassette/src/model/headers.dart';
import 'package:test/test.dart';

void main() {
  group('decodeCassetteHeadersV1', () {
    test('decodes lexical names and ordered repeated values', () {
      final headers = _decodeHeaders(
        '{"accept":["application/json"],"x-trace":["one","two"]}',
      );

      expect(headers.names, <String>['accept', 'x-trace']);
      expect(headers.values('x-trace'), <String>['one', 'two']);
    });

    test('accepts an empty header object', () {
      expect(_decodeHeaders('{}').names, isEmpty);
    });

    test('requires lexical canonical lower-case names', () {
      _expectInvalid(
        () => _decodeHeaders('{"x-z":["last"],"accept":["first"]}'),
        '/headers',
      );
      _expectInvalid(
        () => _decodeHeaders('{"Accept":["application/json"]}'),
        '/headers/Accept',
      );
      _expectInvalid(
        () => _decodeHeaders('{"bad name":["value"]}'),
        '/headers/bad name',
      );
    });

    test('requires a non-empty string array for every field', () {
      _expectInvalid(() => _decodeHeaders('{"accept":[]}'), '/headers/accept');
      _expectInvalid(
        () => _decodeHeaders('{"accept":"application/json"}'),
        '/headers/accept',
      );
      _expectInvalid(
        () => _decodeHeaders('{"accept":[false]}'),
        '/headers/accept/0',
      );
    });

    test('rejects invalid field values without retaining them', () {
      const value = 'private\u0000value';
      final error = _capture(
        () => decodeCassetteHeadersV1(
          <String, Object?>{
            'x-secret': <Object?>[value],
          },
          location: '/headers',
        ),
      );

      expect(error.location, '/headers/x-secret/0');
      expect(error.toString(), isNot(contains('private')));
    });
  });

  group('decodeMatchingExclusionsV1', () {
    test('decodes the exact canonical exclusion shape', () {
      final exclusions = _decodeExclusions(
        '{"uriUserInformation":true,"body":true,'
        '"headers":["authorization","x-secret"],'
        '"queryParameters":["request_id","token"],'
        '"jsonPointers":["/a~1b","/secret"]}',
      );

      expect(exclusions.uriUserInformation, isTrue);
      expect(exclusions.body, isTrue);
      expect(exclusions.headers, <String>{'authorization', 'x-secret'});
      expect(exclusions.queryParameters, <String>{'request_id', 'token'});
      expect(exclusions.jsonPointers, <String>{'/a~1b', '/secret'});
    });

    test('requires exact fields in exact order and boolean flags', () {
      _expectInvalid(
        () => _decodeExclusions(
          '{"body":false,"uriUserInformation":false,'
          '"headers":[],"queryParameters":[],"jsonPointers":[]}',
        ),
        '/matchingExclusions',
      );
      _expectInvalid(
        () => _decodeExclusions(
          '{"uriUserInformation":null,"body":false,'
          '"headers":[],"queryParameters":[],"jsonPointers":[]}',
        ),
        '/matchingExclusions/uriUserInformation',
      );
    });

    test('requires sorted unique string arrays', () {
      for (final headers in <String>[
        '["x-z","accept"]',
        '["accept","accept"]',
        '[false]',
      ]) {
        _expectInvalid(
          () => _decodeExclusions(
            '{"uriUserInformation":false,"body":false,'
            '"headers":$headers,"queryParameters":[],"jsonPointers":[]}',
          ),
          headers == '[false]'
              ? '/matchingExclusions/headers/0'
              : '/matchingExclusions/headers',
        );
      }
    });

    test('requires canonical names and valid RFC 6901 pointers', () {
      _expectInvalid(
        () => _decodeExclusions(
          '{"uriUserInformation":false,"body":false,'
          '"headers":["Accept"],"queryParameters":[],"jsonPointers":[]}',
        ),
        '/matchingExclusions/headers/0',
      );
      _expectInvalid(
        () => _decodeExclusions(
          '{"uriUserInformation":false,"body":false,'
          '"headers":[],"queryParameters":["request%5fid"],'
          '"jsonPointers":[]}',
        ),
        '/matchingExclusions/queryParameters/0',
      );
      _expectInvalid(
        () => _decodeExclusions(
          '{"uriUserInformation":false,"body":false,'
          '"headers":[],"queryParameters":["bad%"],"jsonPointers":[]}',
        ),
        '/matchingExclusions/queryParameters/0',
      );
      _expectInvalid(
        () => _decodeExclusions(
          '{"uriUserInformation":false,"body":false,'
          '"headers":[],"queryParameters":[],"jsonPointers":["bad"]}',
        ),
        '/matchingExclusions/jsonPointers/0',
      );
    });
  });
}

CassetteHeaders _decodeHeaders(String source) => decodeCassetteHeadersV1(
      parseStrictJson(source),
      location: '/headers',
    );

MatchingExclusions _decodeExclusions(String source) =>
    decodeMatchingExclusionsV1(
      parseStrictJson(source),
      location: '/matchingExclusions',
    );

void _expectInvalid(void Function() operation, String location) {
  final error = _capture(operation);
  expect(error.kind, CassetteDecodeFailureKind.invalidStructure);
  expect(error.location, location);
}

CassetteDecodeException _capture(void Function() operation) {
  try {
    operation();
  } on CassetteDecodeException catch (error) {
    return error;
  }
  fail('Expected a CassetteDecodeException.');
}

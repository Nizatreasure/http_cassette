import 'dart:convert';
import 'dart:io';

import 'package:http_cassette/src/cassette/body_codec.dart';
import 'package:http_cassette/src/cassette/decoder.dart';
import 'package:http_cassette/src/json/strict_json.dart';
import 'package:http_cassette/src/json/value.dart';
import 'package:test/test.dart';

void main() {
  group('decodePersistedBodyV1', () {
    test('decodes every canonical body representation', () {
      expect(_decode('{"encoding":"empty"}'), isA<PersistedEmptyBody>());

      final jsonBody = _decode(
        '{"encoding":"json","content":{"a":true,"z":1e+02}}',
      ) as PersistedJsonBody;
      final json = jsonBody.content! as Map<String, Object?>;
      expect(json.keys, <String>['a', 'z']);
      expect((json['z']! as ParsedJsonNumber).source, '1e+02');

      final text = _decode(
        '{"encoding":"text","content":"hello\\n"}',
      ) as PersistedTextBody;
      expect(text.content, 'hello\n');

      final binary = _decode(
        '{"encoding":"base64","content":"AAECAw=="}',
      );
      expect(binary.reconstruct(), <int>[0, 1, 2, 3]);

      final plain = utf8.encode('{"value":true}');
      final gzipBody = _decode(
        '{"encoding":"gzipBase64",'
        '"content":"${base64Encode(gzip.encode(plain))}"}',
      ) as PersistedGzipBase64Body;
      expect(gzipBody.reconstruct(), plain);
    });

    test('requires exact fields in exact order', () {
      _expectInvalid('{}', '/body/encoding');
      for (final source in <String>[
        '{"content":"value","encoding":"text"}',
        '{"encoding":"empty","content":null}',
        '{"encoding":"text","content":"value","unknown":false}',
      ]) {
        _expectInvalid(source, '/body');
      }
    });

    test('rejects unknown encodings without retaining their value', () {
      const encoding = 'private-encoding';
      final error = _capture(
        () => _decode('{"encoding":"$encoding"}'),
      );

      expect(error.location, '/body/encoding');
      expect(error.toString(), isNot(contains(encoding)));
    });

    test('requires content of the correct JSON type', () {
      for (final source in <String>[
        '{"encoding":"text","content":false}',
        '{"encoding":"base64","content":null}',
      ]) {
        _expectInvalid(source, '/body/content');
      }
    });

    test('rejects empty text and Base64 in favour of empty encoding', () {
      _expectInvalid('{"encoding":"text","content":""}', '/body/content');
      _expectInvalid(
        '{"encoding":"base64","content":""}',
        '/body/content',
      );
    });

    test('rejects non-canonical or malformed Base64', () {
      for (final content in <String>['AA', 'AAECAw', 'AAEC Aw==', '****']) {
        _expectInvalid(
          '{"encoding":"base64","content":"$content"}',
          '/body/content',
        );
      }
    });

    test('rejects malformed or oversized gzip storage safely', () {
      _expectInvalid(
        '{"encoding":"gzipBase64","content":"AAECAw=="}',
        '/body/content',
      );

      final content = base64Encode(gzip.encode(utf8.encode('too large')));
      final error = _capture(
        () => decodePersistedBodyV1(
          parseStrictJson(
            '{"encoding":"gzipBase64","content":"$content"}',
          ),
          location: '/body',
          maximumReconstructedBytes: 3,
        ),
      );

      expect(error.kind, CassetteDecodeFailureKind.bodyTooLarge);
      expect(error.location, '/body/content');
      expect(error.maximumBytes, 3);
    });

    test('requires lexical object order throughout JSON content', () {
      _expectInvalid(
        '{"encoding":"json","content":{"z":1,"a":2}}',
        '/body/content',
      );
      _expectInvalid(
        '{"encoding":"json","content":{"nested":{"z":1,"a":2}}}',
        '/body/content/nested',
      );
    });

    test('reports invalid text and JSON Unicode without its value', () {
      final invalid = String.fromCharCode(0xd800);

      for (final value in <Object?>[
        <String, Object?>{'encoding': 'text', 'content': invalid},
        <String, Object?>{'encoding': 'json', 'content': invalid},
      ]) {
        final error = _capture(
          () => decodePersistedBodyV1(value, location: '/body'),
        );
        expect(error.location, '/body/content');
        expect(error.toString(), isNot(contains(invalid)));
      }
    });
  });
}

PersistedBody _decode(String source) => decodePersistedBodyV1(
      parseStrictJson(source),
      location: '/body',
    );

void _expectInvalid(String source, String location) {
  final error = _capture(() => _decode(source));
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

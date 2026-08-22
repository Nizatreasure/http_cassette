import 'dart:convert';
import 'dart:io';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/cassette.dart';
import 'package:http_cassette/src/cassette/decoder.dart';
import 'package:http_cassette/src/cassette/encoder.dart';
import 'package:test/test.dart';

void main() {
  group('decodeCassetteV1', () {
    test('decodes an empty immutable cassette', () {
      final cassette = _decode(
        '{"schemaVersion":1,"interactions":[]}',
      );

      expect(cassette.schemaVersion, 1);
      expect(cassette.interactions, isEmpty);
      expect(cassette.interactions.clear, throwsUnsupportedError);
    });

    test('decodes the complete golden cassette in arrival order', () {
      final fixture = _goldenFixture().readAsBytesSync();
      final cassette = decodeCassetteV1(fixture);

      expect(cassette.interactions, hasLength(2));
      expect(
        cassette.interactions.map((interaction) => interaction.index),
        <int>[0, 1],
      );
      expect(cassette.interactions.first.request.method, 'POST');
      expect(
        cassette.interactions.first.matchingExclusions.headers,
        <String>{'authorization'},
      );
      expect(
        cassette.interactions.first.outcome,
        isA<CassetteResponseOutcome>(),
      );
      expect(
        cassette.interactions.last.outcome,
        isA<CassetteTransportFailure>(),
      );
    });

    test('re-encodes a decoded canonical cassette byte for byte', () {
      final fixture = _goldenFixture().readAsBytesSync();

      expect(encodeCassetteV1(decodeCassetteV1(fixture)), fixture);
    });

    test('requires exact interaction fields in exact order', () {
      _expectInteractionFailure(
        '{"request":${_request()},"index":0,"outcome":${_outcome()}}',
        '/interactions/0',
      );
      _expectInteractionFailure(
        '{"index":0,"request":${_request()},"outcome":${_outcome()},'
            '"unknown":false}',
        '/interactions/0',
      );
      _expectInteractionFailure('false', '/interactions/0');
    });

    test('requires indices to equal their zero-based array positions', () {
      for (final index in <String>['-1', '1', '0.0', '9999999999999999999']) {
        _expectInteractionFailure(
          '{"index":$index,"request":${_request()},'
              '"outcome":${_outcome()}}',
          '/interactions/0/index',
        );
      }

      final source = '{"schemaVersion":1,"interactions":['
          '{"index":0,"request":${_request()},"outcome":${_outcome()}},'
          '{"index":2,"request":${_request()},"outcome":${_outcome()}}]}';
      _expectFailure(source, '/interactions/1/index');
    });

    test('preserves nested structural failure locations', () {
      final interaction = '{"index":0,"request":${_request(method: 'get')},'
          '"outcome":${_outcome()}}';

      _expectInteractionFailure(
        interaction,
        '/interactions/0/request/method',
      );
    });
  });
}

String _request({String method = 'GET'}) =>
    '{"method":"$method","uri":"https://example.test/","headers":{},'
    '"body":{"encoding":"empty"},"matchingExclusions":{'
    '"uriUserInformation":false,"body":false,"headers":[],'
    '"queryParameters":[],"jsonPointers":[]}}';

String _outcome() => '{"type":"response","statusCode":204,"headers":{},'
    '"body":{"encoding":"empty"}}';

void _expectInteractionFailure(String interaction, String location) {
  _expectFailure(
    '{"schemaVersion":1,"interactions":[$interaction]}',
    location,
  );
}

void _expectFailure(String source, String location) {
  final error = _capture(() => _decode(source));
  expect(error.kind, CassetteDecodeFailureKind.invalidStructure);
  expect(error.location, location);
}

Cassette _decode(String source) => decodeCassetteV1(utf8.encode(source));

CassetteDecodeException _capture(void Function() operation) {
  try {
    operation();
  } on CassetteDecodeException catch (error) {
    return error;
  }
  fail('Expected a CassetteDecodeException.');
}

File _goldenFixture() {
  for (final path in <String>[
    'test/fixtures/cassette_v1.json',
    'packages/http_cassette/test/fixtures/cassette_v1.json',
  ]) {
    final file = File(path);
    if (file.existsSync()) {
      return file;
    }
  }
  throw StateError('The V1 cassette golden fixture is missing.');
}

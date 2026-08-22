import 'dart:convert';
import 'dart:io';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/cassette.dart';
import 'package:http_cassette/src/cassette/encoder.dart';
import 'package:http_cassette/src/cassette/interaction.dart';
import 'package:test/test.dart';

void main() {
  group('encodeCassetteV1', () {
    test('encodes an empty cassette with canonical whitespace', () {
      expect(
        utf8.decode(encodeCassetteV1(Cassette())),
        '{\n'
        '  "schemaVersion": 1,\n'
        '  "interactions": []\n'
        '}\n',
      );
    });

    test('matches the reviewed complete V1 golden fixture', () {
      final encoded = encodeCassetteV1(_completeCassette());
      final expected = _goldenFixture().readAsBytesSync();

      expect(encoded, expected);
      expect(encoded.last, 0x0a);
      expect(encoded, isNot(contains(0x0d)));
    });

    test('is byte-for-byte deterministic and returns immutable bytes', () {
      final cassette = _completeCassette();
      final first = encodeCassetteV1(cassette);
      final second = encodeCassetteV1(cassette);

      expect(first, second);
      expect(() => first[0] = 0, throwsUnsupportedError);
    });
  });
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

Cassette _completeCassette() => Cassette(
      interactions: <CassetteInteraction>[
        CassetteInteraction(
          index: 0,
          request: CassetteRequest(
            method: 'POST',
            uri: Uri.parse(
              'HTTPS://EXAMPLE.TEST:443/items?tag=first&page=2&tag=second#part',
            ),
            headers: CassetteHeaders(<String, Iterable<String>>{
              'X-Trace': <String>['one', 'two'],
              'Content-Type': <String>['application/json'],
            }),
            body: utf8.encode(r'{"z":1e+02,"a":"line\n\"quoted\" £"}'),
          ),
          matchingExclusions: MatchingExclusions(
            headers: <String>['authorization'],
            queryParameters: <String>['token'],
            jsonPointers: <String>['/z'],
          ),
          outcome: CassetteResponseOutcome(
            CassetteResponse(
              statusCode: 201,
              reasonPhrase: 'Created',
              headers: CassetteHeaders(<String, Iterable<String>>{
                'Content-Type': <String>['text/plain; charset=utf-8'],
              }),
              body: utf8.encode('saved'),
            ),
          ),
        ),
        CassetteInteraction(
          index: 1,
          request: CassetteRequest(
            method: 'GET',
            uri: Uri.parse('https://example.test/failure'),
          ),
          outcome: CassetteTransportFailure(
            category: TransportFailureCategory.timeout,
            message: 'The operation timed out.',
          ),
        ),
      ],
    );

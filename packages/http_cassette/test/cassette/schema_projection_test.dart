import 'dart:convert';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/cassette.dart';
import 'package:http_cassette/src/cassette/interaction.dart';
import 'package:http_cassette/src/cassette/schema_projection.dart';
import 'package:test/test.dart';

void main() {
  group('projectCassetteToV1Schema', () {
    test('projects an empty cassette in root field order', () {
      final projected = projectCassetteToV1Schema(Cassette());

      expect(projected.keys, <String>['schemaVersion', 'interactions']);
      expect(projected, <String, Object?>{
        'schemaVersion': 1,
        'interactions': <Object?>[],
      });
      expect(
        () => projected['schemaVersion'] = 2,
        throwsUnsupportedError,
      );
    });

    test('projects a prepared request in exact field order', () {
      final projected = _projectInteraction(
        request: CassetteRequest(
          method: 'POST',
          uri: Uri.parse(
            'HTTPS://EXAMPLE.TEST:443/items?tag=first&page=2&tag=second#part',
          ),
          headers: CassetteHeaders(<String, Iterable<String>>{
            'X-Trace': <String>['one', 'two'],
            'Content-Type': <String>['application/json'],
            'ETag': <String>['"old"'],
            'Content-Length': <String>['999'],
          }),
          body: utf8.encode('{ "z": 2, "a": true }'),
        ),
        matchingExclusions: MatchingExclusions(
          headers: <String>['x-secret'],
          queryParameters: <String>['token'],
          jsonPointers: <String>['/secret'],
          uriUserInformation: true,
          body: true,
        ),
      );
      final request = projected['request']! as Map<String, Object?>;

      expect(request.keys, <String>[
        'method',
        'uri',
        'headers',
        'body',
        'matchingExclusions',
      ]);
      expect(
        request['uri'],
        'https://example.test/items?page=2&tag=first&tag=second',
      );
      expect(
        request['headers'],
        <String, Object?>{
          'content-length': <String>['16'],
          'content-type': <String>['application/json'],
          'x-trace': <String>['one', 'two'],
        },
      );
      expect(
        (request['body']! as Map<String, Object?>).keys,
        <String>['encoding', 'content'],
      );
      expect(request['body'], <String, Object?>{
        'encoding': 'json',
        'content': <String, Object?>{'a': true, 'z': isNotNull},
      });
      expect(request['matchingExclusions'], <String, Object?>{
        'uriUserInformation': true,
        'body': true,
        'headers': <String>['content-length', 'etag', 'x-secret'],
        'queryParameters': <String>['token'],
        'jsonPointers': <String>['/secret'],
      });
    });

    test('projects a prepared response and optional reason phrase', () {
      final projected = _projectInteraction(
        outcome: CassetteResponseOutcome(
          CassetteResponse(
            statusCode: 201,
            reasonPhrase: 'Created',
            headers: CassetteHeaders(<String, Iterable<String>>{
              'Content-Length': <String>['12'],
              'Digest': <String>['sha-256=old'],
            }),
            body: utf8.encode('hello'),
          ),
        ),
      );
      final outcome = projected['outcome']! as Map<String, Object?>;

      expect(outcome.keys, <String>[
        'type',
        'statusCode',
        'reasonPhrase',
        'headers',
        'body',
      ]);
      expect(outcome, <String, Object?>{
        'type': 'response',
        'statusCode': 201,
        'reasonPhrase': 'Created',
        'headers': <String, Object?>{
          'content-length': <String>['5'],
        },
        'body': <String, Object?>{
          'encoding': 'text',
          'content': 'hello',
        },
      });
    });

    test('omits an absent response reason phrase', () {
      final projected = _projectInteraction();
      final outcome = projected['outcome']! as Map<String, Object?>;

      expect(outcome.keys, <String>['type', 'statusCode', 'headers', 'body']);
    });

    test('projects a transport failure in exact field order', () {
      final projected = _projectInteraction(
        outcome: CassetteTransportFailure(
          category: TransportFailureCategory.timeout,
          message: 'The operation timed out.',
        ),
      );
      final outcome = projected['outcome']! as Map<String, Object?>;

      expect(outcome.keys, <String>['type', 'category', 'message']);
      expect(outcome, <String, Object?>{
        'type': 'transportFailure',
        'category': 'timeout',
        'message': 'The operation timed out.',
      });
    });

    test('returns immutable nested schema collections', () {
      final projected = _projectInteraction(
        request: CassetteRequest(
          method: 'GET',
          uri: Uri.parse('https://example.test/'),
          headers: CassetteHeaders(<String, Iterable<String>>{
            'Accept': <String>['text/plain'],
          }),
        ),
      );
      final request = projected['request']! as Map<String, Object?>;
      final headers = request['headers']! as Map<String, Object?>;
      final values = headers['accept']! as List<String>;

      expect(() => request['method'] = 'POST', throwsUnsupportedError);
      expect(
          () => headers['other'] = <String>['value'], throwsUnsupportedError);
      expect(() => values.add('other'), throwsUnsupportedError);
    });
  });
}

Map<String, Object?> _projectInteraction({
  CassetteRequest? request,
  CassetteOutcome? outcome,
  MatchingExclusions matchingExclusions = MatchingExclusions.none,
}) {
  final cassette = Cassette(
    interactions: <CassetteInteraction>[
      CassetteInteraction(
        index: 0,
        request: request ??
            CassetteRequest(
              method: 'GET',
              uri: Uri.parse('https://example.test/'),
            ),
        outcome: outcome ??
            CassetteResponseOutcome(CassetteResponse(statusCode: 200)),
        matchingExclusions: matchingExclusions,
      ),
    ],
  );
  final interactions =
      projectCassetteToV1Schema(cassette)['interactions']! as List<Object?>;
  return interactions.single as Map<String, Object?>;
}

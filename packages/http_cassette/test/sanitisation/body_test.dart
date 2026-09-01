import 'dart:convert';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/matching/json.dart';
import 'package:http_cassette/src/sanitisation/body.dart';
import 'package:test/test.dart';

void main() {
  group('sanitiseJsonBody', () {
    test('leaves an empty JSON-labelled body unchanged', () {
      final result = sanitiseJsonBody(
        _headers('application/json'),
        const <int>[],
        SanitisationConfiguration(),
      );

      expect(result.body, isEmpty);
      expect(result.sanitisedPointers, isEmpty);
      expect(() => result.body.add(0), throwsUnsupportedError);
    });

    test('sanitises valid JSON and returns exact matching exclusions', () {
      final result = sanitiseJsonBody(
        _headers('application/problem+json; charset=utf-8'),
        utf8.encode(
          '{"z":"retained","credentials":{"code":"secret"},"token":"synthetic-secret"}',
        ),
        SanitisationConfiguration(
          additionalJsonPointers: <String>{'/credentials/code'},
        ),
      );

      expect(
        utf8.decode(result.body),
        '{"credentials":{"code":"[REDACTED]"},"token":"[REDACTED]","z":"retained"}',
      );
      expect(
        result.sanitisedPointers,
        <String>{'/credentials/code', '/token'},
      );
    });

    test('preserves exact valid JSON bytes when no value is selected', () {
      final source = utf8.encode('{ "keep" : 1e0 }\n');

      final result = sanitiseJsonBody(
        _headers('application/json'),
        source,
        SanitisationConfiguration(),
      );

      expect(result.body, source);
      expect(result.sanitisedPointers, isEmpty);
      expect(() => result.body[0] = 0, throwsUnsupportedError);
    });

    test('leaves non-JSON body bytes unchanged and uninspected', () {
      final source = utf8.encode('token=synthetic-secret');

      final result = sanitiseJsonBody(
        _headers('application/x-www-form-urlencoded'),
        source,
        SanitisationConfiguration(),
      );

      expect(result.body, source);
      expect(result.sanitisedPointers, isEmpty);
    });

    test('leaves content-encoded claimed JSON opaque and unchanged', () {
      final cases = <List<int>>[
        <int>[0x1f, 0x8b, 0x08, 0xff],
        utf8.encode('{"token":"still-encoded"}'),
      ];

      for (final source in cases) {
        final result = sanitiseJsonBody(
          CassetteHeaders(<String, Iterable<String>>{
            'content-type': <String>['application/json'],
            'content-encoding': <String>['gzip'],
          }),
          source,
          SanitisationConfiguration(),
        );

        expect(result.body, source);
        expect(result.sanitisedPointers, isEmpty);
        expect(() => result.body.add(0), throwsUnsupportedError);
      }
    });

    test('fails safely for every invalid claimed-JSON classification', () {
      const sentinel = 'synthetic-secret-sentinel';
      final cases = <JsonBodyStatus, List<int>>{
        JsonBodyStatus.invalidUtf8: <int>[0xff],
        JsonBodyStatus.malformedJson: utf8.encode('{"token":"$sentinel"'),
        JsonBodyStatus.duplicateObjectMember:
            utf8.encode('{"token":"$sentinel","token":"another"}'),
      };

      for (final MapEntry(:key, :value) in cases.entries) {
        late JsonBodySanitisationException failure;
        expect(
          () => sanitiseJsonBody(
            _headers('application/json'),
            value,
            SanitisationConfiguration(),
          ),
          throwsA(
            isA<JsonBodySanitisationException>().having(
              (exception) {
                failure = exception;
                return exception.status;
              },
              'status',
              key,
            ),
          ),
        );
        expect(failure.toString(), isNot(contains(sentinel)));
      }
    });

    test('unsafe no-built-ins configuration leaves invalid JSON unchanged', () {
      final source = utf8.encode('{"token":"synthetic-secret"');

      final result = sanitiseJsonBody(
        _headers('application/json'),
        source,
        SanitisationConfiguration.unsafeWithoutBuiltIns(),
      );

      expect(result.body, source);
      expect(result.sanitisedPointers, isEmpty);
    });
  });
}

CassetteHeaders _headers(String contentType) =>
    CassetteHeaders(<String, Iterable<String>>{
      'content-type': <String>[contentType],
    });

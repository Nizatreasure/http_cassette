import 'dart:convert';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/sanitisation/pipeline.dart';
import 'package:test/test.dart';

void main() {
  group('sanitiseCustomRequest', () {
    test('runs in registration order and accumulates exclusions', () {
      final calls = <String>[];
      final configuration = SanitisationConfiguration(
        requestSanitisers: <RequestSanitiser>[
          _RequestSanitiser((request) {
            calls.add('query');
            return SanitisedRequest(
              request: _copyRequest(
                request,
                uri: Uri.parse('https://example.test/?token=[REDACTED]'),
              ),
              exclusions: MatchingExclusions(
                queryParameters: <String>{'token'},
              ),
            );
          }),
          _RequestSanitiser((request) {
            calls.add('body');
            expect(request.uri.query, 'token=%5BREDACTED%5D');
            return SanitisedRequest(
              request: _copyRequest(request, body: utf8.encode('[SAFE]')),
              exclusions: MatchingExclusions(body: true),
            );
          }),
        ],
      );

      final result = sanitiseCustomRequest(
        _request(uri: 'https://example.test/?token=secret', body: 'secret'),
        configuration,
      );

      expect(calls, <String>['query', 'body']);
      expect(result.request.uri.query, 'token=%5BREDACTED%5D');
      expect(utf8.decode(result.request.body), '[SAFE]');
      expect(result.exclusions.queryParameters, <String>{'token'});
      expect(result.exclusions.body, isTrue);
    });

    test('returns the original request when no sanitisers are registered', () {
      final request = _request();

      final result = sanitiseCustomRequest(
        request,
        SanitisationConfiguration(),
      );

      expect(result.request, same(request));
      expect(result.exclusions, same(MatchingExclusions.none));
    });

    test('allows an unchanged request without exclusions', () {
      final request = _request();
      final configuration = SanitisationConfiguration(
        requestSanitisers: <RequestSanitiser>[
          _RequestSanitiser(
            (request) => SanitisedRequest(
              request: request,
              exclusions: MatchingExclusions.none,
            ),
          ),
        ],
      );

      final result = sanitiseCustomRequest(request, configuration);

      expect(result.request, same(request));
      expect(result.exclusions.headers, isEmpty);
      expect(result.exclusions.queryParameters, isEmpty);
      expect(result.exclusions.jsonPointers, isEmpty);
      expect(result.exclusions.uriUserInformation, isFalse);
      expect(result.exclusions.body, isFalse);
    });

    test('rejects a changed value without its matching exclusion', () {
      final configuration = SanitisationConfiguration(
        requestSanitisers: <RequestSanitiser>[
          _RequestSanitiser(
            (request) => SanitisedRequest(
              request: _copyRequest(
                request,
                uri: Uri.parse('https://example.test/?token=[REDACTED]'),
              ),
              exclusions: MatchingExclusions.none,
            ),
          ),
        ],
      );

      expect(
        () => sanitiseCustomRequest(
          _request(uri: 'https://example.test/?token=secret'),
          configuration,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('index 0'),
          ),
        ),
      );
    });

    test('rejects changes that cannot be excluded', () {
      final configuration = SanitisationConfiguration(
        requestSanitisers: <RequestSanitiser>[
          _RequestSanitiser(
            (request) => SanitisedRequest(
              request: _copyRequest(
                request,
                uri: Uri.parse('https://example.test/changed'),
              ),
              exclusions: MatchingExclusions(body: true),
            ),
          ),
        ],
      );

      expect(
        () => sanitiseCustomRequest(_request(), configuration),
        throwsStateError,
      );
    });

    test('stops when a sanitiser throws', () {
      var laterCalled = false;
      final configuration = SanitisationConfiguration(
        requestSanitisers: <RequestSanitiser>[
          _RequestSanitiser((request) => throw const _SyntheticFailure()),
          _RequestSanitiser((request) {
            laterCalled = true;
            return SanitisedRequest(
              request: request,
              exclusions: MatchingExclusions.none,
            );
          }),
        ],
      );

      expect(
        () => sanitiseCustomRequest(_request(), configuration),
        throwsA(isA<_SyntheticFailure>()),
      );
      expect(laterCalled, isFalse);
    });
  });
}

final class _RequestSanitiser implements RequestSanitiser {
  const _RequestSanitiser(this._sanitise);

  final SanitisedRequest Function(CassetteRequest request) _sanitise;

  @override
  SanitisedRequest sanitise(CassetteRequest request) => _sanitise(request);
}

final class _SyntheticFailure implements Exception {
  const _SyntheticFailure();
}

CassetteRequest _request({
  String uri = 'https://example.test/',
  String body = '',
}) =>
    CassetteRequest(
      method: 'POST',
      uri: Uri.parse(uri),
      body: utf8.encode(body),
    );

CassetteRequest _copyRequest(
  CassetteRequest request, {
  Uri? uri,
  List<int>? body,
}) =>
    CassetteRequest(
      method: request.method,
      uri: uri ?? request.uri,
      headers: request.headers,
      body: body ?? request.body,
    );

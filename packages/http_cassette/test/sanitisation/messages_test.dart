import 'dart:convert';
import 'dart:io';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/matching/json.dart';
import 'package:http_cassette/src/matching/request_matcher.dart';
import 'package:http_cassette/src/sanitisation/body.dart';
import 'package:http_cassette/src/sanitisation/content_decoding.dart';
import 'package:http_cassette/src/sanitisation/content_recompression.dart';
import 'package:http_cassette/src/sanitisation/messages.dart';
import 'package:test/test.dart';

void main() {
  group('sanitiseBuiltInRequest', () {
    test('composes every request field and matching exclusion', () {
      final request = CassetteRequest(
        method: 'POST',
        uri: Uri.parse(
          'https://user:password@example.test/path?TOKEN=synthetic-query&keep=value',
        ),
        headers: CassetteHeaders(<String, Iterable<String>>{
          'authorization': <String>['synthetic-header'],
          'content-type': <String>['application/json'],
        }),
        body: utf8.encode(
          '{"credentials":{"code":"synthetic-code"},"token":"synthetic-body","keep":true}',
        ),
      );
      final configuration = SanitisationConfiguration(
        additionalJsonPointers: <String>{'/credentials/code'},
      );

      final result = sanitiseBuiltInRequest(request, configuration);

      expect(
        result.request.uri.toString(),
        'https://%5BREDACTED%5D@example.test/path?TOKEN=%5BREDACTED%5D&keep=value',
      );
      expect(
        result.request.headers.values('authorization'),
        <String>['[REDACTED]'],
      );
      expect(
        utf8.decode(result.request.body),
        '{"credentials":{"code":"[REDACTED]"},"keep":true,"token":"[REDACTED]"}',
      );
      expect(result.exclusions.uriUserInformation, isTrue);
      expect(result.exclusions.headers, <String>{'authorization'});
      expect(result.exclusions.queryParameters, <String>{'TOKEN'});
      expect(
        result.exclusions.jsonPointers,
        <String>{'/credentials/code', '/token'},
      );
    });

    test('produced exclusions match incoming unsanitised values', () {
      final recorded = CassetteRequest(
        method: 'POST',
        uri: Uri.parse('https://first:secret@example.test/?TOKEN=first'),
        headers: CassetteHeaders(<String, Iterable<String>>{
          'authorization': <String>['first'],
          'content-type': <String>['application/json'],
        }),
        body: utf8.encode('{"token":"first","keep":true}'),
      );
      final incoming = CassetteRequest(
        method: 'POST',
        uri: Uri.parse('https://second:secret@example.test/?TOKEN=second'),
        headers: CassetteHeaders(<String, Iterable<String>>{
          'authorization': <String>['second'],
          'content-type': <String>['application/json'],
        }),
        body: utf8.encode('{"token":"second","keep":true}'),
      );
      final sanitised = sanitiseBuiltInRequest(
        recorded,
        SanitisationConfiguration(),
      );
      final matcher = DefaultRequestMatcher(
        configuration: MatchingConfiguration(
          includedHeaders: <String>{'authorization'},
        ),
      );

      final comparison = matcher.compare(
        sanitised.request,
        incoming,
        exclusions: sanitised.exclusions,
      );

      expect(comparison.matches, isTrue);
    });

    test('uses the original content type before sanitising headers', () {
      final request = CassetteRequest(
        method: 'POST',
        uri: Uri.parse('https://example.test/'),
        headers: CassetteHeaders(<String, Iterable<String>>{
          'content-type': <String>['application/json'],
        }),
        body: utf8.encode('{"token":"synthetic-secret"}'),
      );
      final configuration = SanitisationConfiguration(
        additionalHeaders: <String>{'content-type'},
      );

      final result = sanitiseBuiltInRequest(request, configuration);

      expect(
        result.request.headers.values('content-type'),
        <String>['[REDACTED]'],
      );
      expect(utf8.decode(result.request.body), '{"token":"[REDACTED]"}');
      expect(result.exclusions.headers, <String>{'content-type'});
      expect(result.exclusions.jsonPointers, <String>{'/token'});
    });

    test('returns the original request when nothing changes', () {
      final request = CassetteRequest(
        method: 'GET',
        uri: Uri.parse('https://example.test/?keep=value'),
        body: utf8.encode('opaque'),
      );

      final result = sanitiseBuiltInRequest(
        request,
        SanitisationConfiguration(),
      );

      expect(result.request, same(request));
      expect(result.exclusions.headers, isEmpty);
      expect(result.exclusions.queryParameters, isEmpty);
      expect(result.exclusions.jsonPointers, isEmpty);
      expect(result.exclusions.uriUserInformation, isFalse);
    });

    test('propagates invalid claimed-JSON failure without a result', () {
      final request = CassetteRequest(
        method: 'POST',
        uri: Uri.parse('https://example.test/'),
        headers: CassetteHeaders(<String, Iterable<String>>{
          'authorization': <String>['synthetic-header'],
          'content-type': <String>['application/json'],
        }),
        body: utf8.encode('{"token":"synthetic-secret"'),
      );

      expect(
        () => sanitiseBuiltInRequest(
          request,
          SanitisationConfiguration(),
        ),
        throwsA(isA<JsonBodySanitisationException>()),
      );
      expect(
        request.headers.values('authorization'),
        <String>['synthetic-header'],
      );
    });
  });

  group('sanitiseBuiltInResponse', () {
    test('sanitises response headers and JSON without request exclusions', () {
      final response = CassetteResponse(
        statusCode: 401,
        reasonPhrase: 'Unauthorised',
        headers: CassetteHeaders(<String, Iterable<String>>{
          'set-cookie': <String>['first=secret', 'second=secret'],
          'content-type': <String>['application/json'],
        }),
        body: utf8.encode('{"token":"synthetic-secret","keep":false}'),
      );

      final result = sanitiseBuiltInResponse(
        response,
        SanitisationConfiguration(),
        maximumTransformedBodyBytes: BodyLimits.defaultResponseBytes,
      );

      expect(result.statusCode, 401);
      expect(result.reasonPhrase, 'Unauthorised');
      expect(
        result.headers.values('set-cookie'),
        <String>['[REDACTED]', '[REDACTED]'],
      );
      expect(
        utf8.decode(result.body),
        '{"keep":false,"token":"[REDACTED]"}',
      );
    });

    test('returns the original response when nothing changes', () {
      final response = CassetteResponse(
        statusCode: 204,
        headers: CassetteHeaders(<String, Iterable<String>>{
          'content-type': <String>['text/plain'],
        }),
      );

      final result = sanitiseBuiltInResponse(
        response,
        SanitisationConfiguration(),
        maximumTransformedBodyBytes: BodyLimits.defaultResponseBytes,
      );

      expect(result, same(response));
    });

    test('decodes and sanitises configured gzip JSON as plain content', () {
      final encoded = gzip.encode(
        utf8.encode('{"token":"synthetic-secret","keep":true}'),
      );
      final response = CassetteResponse(
        statusCode: 200,
        headers: CassetteHeaders(<String, Iterable<String>>{
          'content-type': <String>['application/json'],
          'content-encoding': <String>[' GZip '],
        }),
        body: encoded,
      );

      final result = sanitiseBuiltInResponse(
        response,
        SanitisationConfiguration(
          encodedJsonResponses: EncodedJsonResponseHandling.decodeAndStorePlain,
        ),
        maximumTransformedBodyBytes: BodyLimits.defaultResponseBytes,
      );

      expect(result.headers.contains('content-encoding'), isFalse);
      expect(utf8.decode(result.body), '{"keep":true,"token":"[REDACTED]"}');
      expect(response.body, encoded);
      expect(response.headers.values('content-encoding'), <String>[' GZip ']);
    });

    test('keeps gzip JSON opaque under the default handling', () {
      final encoded = gzip.encode(utf8.encode('{"token":"secret"}'));
      final response = CassetteResponse(
        statusCode: 200,
        headers: CassetteHeaders(<String, Iterable<String>>{
          'content-type': <String>['application/json'],
          'content-encoding': <String>['gzip'],
        }),
        body: encoded,
      );

      final result = sanitiseBuiltInResponse(
        response,
        SanitisationConfiguration(),
        maximumTransformedBodyBytes: BodyLimits.defaultResponseBytes,
      );

      expect(result, same(response));
    });

    test('decodes, sanitises, and recompresses configured gzip JSON', () {
      final response = CassetteResponse(
        statusCode: 200,
        headers: CassetteHeaders(<String, Iterable<String>>{
          'content-type': <String>['application/json'],
          'content-encoding': <String>[' GZip '],
        }),
        body: gzip.encode(
          utf8.encode('{"token":"synthetic-secret","keep":true}'),
        ),
      );

      final result = sanitiseBuiltInResponse(
        response,
        SanitisationConfiguration(
          encodedJsonResponses: EncodedJsonResponseHandling.decodeAndRecompress,
        ),
        maximumTransformedBodyBytes: BodyLimits.defaultResponseBytes,
      );

      expect(result.headers.values('content-encoding'), <String>['gzip']);
      expect(
        utf8.decode(gzip.decode(result.body)),
        '{"keep":true,"token":"[REDACTED]"}',
      );
    });

    test('rejects recompressed content exceeding the response limit', () {
      final response = CassetteResponse(
        statusCode: 200,
        headers: CassetteHeaders(<String, Iterable<String>>{
          'content-type': <String>['application/json'],
          'content-encoding': <String>['gzip'],
        }),
        body: gzip.encode(utf8.encode('{}')),
      );

      expect(
        () => sanitiseBuiltInResponse(
          response,
          SanitisationConfiguration(
            encodedJsonResponses:
                EncodedJsonResponseHandling.decodeAndRecompress,
          ),
          maximumTransformedBodyBytes: 2,
        ),
        throwsA(
          isA<ContentRecompressionException>()
              .having(
                (failure) => failure.kind,
                'kind',
                ContentRecompressionFailureKind.recompressedBodyTooLarge,
              )
              .having((failure) => failure.maximumBytes, 'limit', 2),
        ),
      );
    });

    test('rejects gzip content exceeding the decoded response limit', () {
      final response = CassetteResponse(
        statusCode: 200,
        headers: CassetteHeaders(<String, Iterable<String>>{
          'content-type': <String>['application/json'],
          'content-encoding': <String>['gzip'],
        }),
        body: gzip.encode(utf8.encode('{"keep":"too large"}')),
      );

      expect(
        () => sanitiseBuiltInResponse(
          response,
          SanitisationConfiguration(
            encodedJsonResponses:
                EncodedJsonResponseHandling.decodeAndStorePlain,
          ),
          maximumTransformedBodyBytes: 4,
        ),
        throwsA(
          isA<ContentDecodingException>()
              .having(
                (failure) => failure.kind,
                'kind',
                ContentDecodingFailureKind.decodedBodyTooLarge,
              )
              .having((failure) => failure.maximumBytes, 'limit', 4),
        ),
      );
    });

    test('keeps non-JSON and unsupported or ambiguous codings opaque', () {
      final cases = <CassetteResponse>[
        CassetteResponse(
          statusCode: 200,
          headers: CassetteHeaders(<String, Iterable<String>>{
            'content-type': <String>['text/plain'],
            'content-encoding': <String>['gzip'],
          }),
          body: gzip.encode(utf8.encode('plain text')),
        ),
        CassetteResponse(
          statusCode: 200,
          headers: CassetteHeaders(<String, Iterable<String>>{
            'content-type': <String>['application/json'],
            'content-encoding': <String>['deflate'],
          }),
          body: const <int>[1, 2, 3],
        ),
        CassetteResponse(
          statusCode: 200,
          headers: CassetteHeaders(<String, Iterable<String>>{
            'content-type': <String>['application/json'],
            'content-encoding': <String>['gzip', 'identity'],
          }),
          body: const <int>[1, 2, 3],
        ),
      ];

      for (final response in cases) {
        final result = sanitiseBuiltInResponse(
          response,
          SanitisationConfiguration(
            encodedJsonResponses:
                EncodedJsonResponseHandling.decodeAndStorePlain,
          ),
          maximumTransformedBodyBytes: BodyLimits.defaultResponseBytes,
        );

        expect(result, same(response));
      }
    });

    test('rejects invalid gzip and invalid decoded JSON safely', () {
      final headers = CassetteHeaders(<String, Iterable<String>>{
        'content-type': <String>['application/json'],
        'content-encoding': <String>['gzip'],
      });
      final configuration = SanitisationConfiguration(
        encodedJsonResponses: EncodedJsonResponseHandling.decodeAndStorePlain,
      );

      expect(
        () => sanitiseBuiltInResponse(
          CassetteResponse(
            statusCode: 200,
            headers: headers,
            body: const <int>[1, 2, 3],
          ),
          configuration,
          maximumTransformedBodyBytes: BodyLimits.defaultResponseBytes,
        ),
        throwsA(
          isA<ContentDecodingException>().having(
            (failure) => failure.kind,
            'kind',
            ContentDecodingFailureKind.invalidContent,
          ),
        ),
      );
      expect(
        () => sanitiseBuiltInResponse(
          CassetteResponse(
            statusCode: 200,
            headers: headers,
            body: gzip.encode(utf8.encode('{"token":')),
          ),
          configuration,
          maximumTransformedBodyBytes: BodyLimits.defaultResponseBytes,
        ),
        throwsA(
          isA<JsonBodySanitisationException>().having(
            (failure) => failure.status,
            'status',
            JsonBodyStatus.malformedJson,
          ),
        ),
      );
    });
  });
}

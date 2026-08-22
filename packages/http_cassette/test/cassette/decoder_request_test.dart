import 'package:http_cassette/src/cassette/decoder.dart';
import 'package:http_cassette/src/json/strict_json.dart';
import 'package:test/test.dart';

void main() {
  group('decodeCassetteRequestV1', () {
    test('reconstructs a complete canonical request and exclusions', () {
      final decoded = _decode(
        method: 'POST',
        uri: 'https://example.test/items?page=2&tag=first&tag=second',
        headers: '{"content-length":["16"],'
            '"content-type":["application/json"]}',
        body: '{"encoding":"json","content":{"a":true,"z":2}}',
        exclusions: '{"uriUserInformation":false,"body":false,'
            '"headers":["authorization"],"queryParameters":["token"],'
            '"jsonPointers":["/z"]}',
      );

      expect(decoded.request.method, 'POST');
      expect(decoded.request.uri.toString(), contains('example.test/items'));
      expect(decoded.request.body, hasLength(16));
      expect(decoded.matchingExclusions.headers, <String>{'authorization'});
      expect(decoded.matchingExclusions.queryParameters, <String>{'token'});
      expect(decoded.matchingExclusions.jsonPointers, <String>{'/z'});
    });

    test('requires exact request fields in exact order', () {
      _expectInvalid(
        '{"uri":"https://example.test/","method":"GET",'
            '"headers":{},"body":{"encoding":"empty"},'
            '"matchingExclusions":${_noExclusions()}}',
        '/request',
      );
      _expectInvalid(
        '{"method":"GET","uri":"https://example.test/",'
            '"headers":{},"body":{"encoding":"empty"},'
            '"matchingExclusions":${_noExclusions()},"unknown":false}',
        '/request',
      );
    });

    test('requires a canonical upper-case HTTP method', () {
      for (final method in <String>['get', 'Get', 'NOT VALID']) {
        final error = _capture(() => _decode(method: method));
        expect(error.location, '/request/method');
      }
    });

    test('requires an absolute canonical persisted URI', () {
      for (final uri in <String>[
        '/relative',
        'HTTPS://EXAMPLE.TEST:443',
        'https://example.test/path#fragment',
        'https://example.test/?z=2&a=1',
      ]) {
        final error = _capture(() => _decode(uri: uri));
        expect(error.location, '/request/uri');
      }
    });

    test('requires the body representation selected by core precedence', () {
      _expectRequestFailure(
        headers: '{}',
        body: '{"encoding":"json","content":{}}',
        location: '/request/body',
      );
      _expectRequestFailure(
        headers: '{"content-type":["application/json"]}',
        body: '{"encoding":"text","content":"{}"}',
        location: '/request/body',
      );
      _expectRequestFailure(
        headers: '{}',
        body: '{"encoding":"base64","content":"aGVsbG8="}',
        location: '/request/body',
      );
    });

    test('accepts opaque Base64 when content encoding remains present', () {
      final decoded = _decode(
        headers: '{"content-encoding":["gzip"]}',
        body: '{"encoding":"base64","content":"aGVsbG8="}',
      );

      expect(decoded.request.body, <int>[104, 101, 108, 108, 111]);
    });

    test('requires payload-derived headers to match reconstructed bytes', () {
      for (final headers in <String>[
        '{"content-length":["99"]}',
        '{"digest":["sha-256=private"]}',
        '{"etag":["private"]}',
        '{"content-encoding":["gzip"]}',
      ]) {
        _expectRequestFailure(
          headers: headers,
          body: '{"encoding":"text","content":"hello"}',
          location: headers.contains('content-encoding')
              ? '/request/body'
              : '/request/headers',
        );
      }
    });
  });
}

DecodedCassetteRequestV1 _decode({
  String method = 'GET',
  String uri = 'https://example.test/',
  String headers = '{}',
  String body = '{"encoding":"empty"}',
  String? exclusions,
}) =>
    decodeCassetteRequestV1(
      parseStrictJson(
        '{"method":"$method","uri":"$uri","headers":$headers,'
        '"body":$body,"matchingExclusions":${exclusions ?? _noExclusions()}}',
      ),
      location: '/request',
    );

String _noExclusions() => '{"uriUserInformation":false,"body":false,'
    '"headers":[],"queryParameters":[],"jsonPointers":[]}';

void _expectRequestFailure({
  required String headers,
  required String body,
  required String location,
}) {
  final error = _capture(() => _decode(headers: headers, body: body));
  expect(error.kind, CassetteDecodeFailureKind.invalidStructure);
  expect(error.location, location);
  expect(error.toString(), isNot(contains('private')));
}

void _expectInvalid(String source, String location) {
  final error = _capture(
    () => decodeCassetteRequestV1(
      parseStrictJson(source),
      location: '/request',
    ),
  );
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

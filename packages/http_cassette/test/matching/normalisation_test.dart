import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/matching/normalisation.dart';
import 'package:test/test.dart';

void main() {
  group('NormalisedRequestTarget', () {
    test('normalises method, scheme and host case', () {
      final target = _target('get', 'HTTP://EXAMPLE.TEST/resource');

      expect(target.method, 'GET');
      expect(target.scheme, 'http');
      expect(target.host, 'example.test');
    });

    test('treats omitted and default ports as equivalent', () {
      expect(
        _target('GET', 'http://example.test/resource'),
        _target('GET', 'http://example.test:80/resource'),
      );
      expect(
        _target('GET', 'https://example.test/resource'),
        _target('GET', 'https://example.test:443/resource'),
      );
    });

    test('retains non-default and unknown-scheme explicit ports', () {
      expect(_target('GET', 'http://example.test:8080/').port, 8080);
      expect(_target('GET', 'custom://example.test:1234/').port, 1234);
      expect(_target('GET', 'custom://example.test/').port, isNull);
      expect(
        _target('GET', 'http://example.test:8080/'),
        isNot(_target('GET', 'http://example.test:8081/')),
      );
    });

    test('treats an empty path as a root path', () {
      expect(
        _target('GET', 'https://example.test'),
        _target('GET', 'https://example.test/'),
      );
    });

    test('preserves path separators and trailing slashes', () {
      expect(
        _target('GET', 'https://example.test/a//b').path,
        '/a//b',
      );
      expect(
        _target('GET', 'https://example.test/a/b/'),
        isNot(_target('GET', 'https://example.test/a/b')),
      );
    });

    test('normalises escapes without decoding reserved characters', () {
      expect(
        _target('GET', 'https://example.test/%7euser/%2f').path,
        '/~user/%2F',
      );
      expect(
        _target('GET', 'https://example.test/a%2Fb'),
        isNot(_target('GET', 'https://example.test/a/b')),
      );
    });

    test('accepts Dart URI dot-segment normalisation', () {
      expect(
        _target('GET', 'https://example.test/a/b/../c'),
        _target('GET', 'https://example.test/a/c'),
      );
    });

    test('excludes fragments and query data from this projection', () {
      expect(
        _target('GET', 'https://example.test/path?a=1#first'),
        _target('GET', 'https://example.test/path?b=2#second'),
      );
    });

    test('matches URI user information unless its value is excluded', () {
      final first = _target(
        'GET',
        'https://first:secret@example.test/path',
      );
      final second = _target(
        'GET',
        'https://second:other@example.test/path',
      );

      expect(first, isNot(second));
      final exclusions = MatchingExclusions(uriUserInformation: true);
      expect(
        _target(
          'GET',
          'https://first:secret@example.test/path',
          exclusions: exclusions,
        ),
        _target(
          'GET',
          'https://second:other@example.test/path',
          exclusions: exclusions,
        ),
      );
    });

    test('accepts canonical ASCII internationalised hosts', () {
      expect(
        _target('GET', 'https://XN--MNICH-KVA.EXAMPLE/').host,
        'xn--mnich-kva.example',
      );
    });

    test('rejects non-ASCII hosts without echoing them', () {
      const unsafeHost = 'MÜNICH.example';

      expect(
        () => _target('GET', 'https://$unsafeHost/'),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.toString(),
            'message',
            isNot(contains(unsafeHost)),
          ),
        ),
      );
    });

    test('distinguishes methods and path case', () {
      expect(
        _target('GET', 'https://example.test/path'),
        isNot(_target('POST', 'https://example.test/path')),
      );
      expect(
        _target('GET', 'https://example.test/Path'),
        isNot(_target('GET', 'https://example.test/path')),
      );
    });
  });
}

NormalisedRequestTarget _target(
  String method,
  String uri, {
  MatchingExclusions exclusions = MatchingExclusions.none,
}) =>
    NormalisedRequestTarget.fromRequest(
      CassetteRequest(method: method, uri: Uri.parse(uri)),
      exclusions: exclusions,
    );

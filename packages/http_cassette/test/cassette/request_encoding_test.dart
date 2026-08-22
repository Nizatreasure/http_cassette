import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/request_encoding.dart';
import 'package:test/test.dart';

void main() {
  group('canonicalisePersistedRequestUri', () {
    test('normalises origin, default port, path and fragment', () {
      expect(
        _canonical('HTTPS://EXAMPLE.TEST:443#fragment'),
        'https://example.test/',
      );
      expect(
        _canonical('http://example.test:8080/path'),
        'http://example.test:8080/path',
      );
    });

    test('normalises percent escapes without decoding reserved characters', () {
      expect(
        _canonical('https://example.test/%7euser/a%2fb?%6eame=%7e%2f'),
        'https://example.test/~user/a%2Fb?name=~%2F',
      );
    });

    test('sorts query names and preserves occurrence order and equals state',
        () {
      expect(
        _canonical(
          'https://example.test/?tag=first&flag&page=2&tag=second&empty=',
        ),
        'https://example.test/?empty=&flag&page=2&tag=first&tag=second',
      );
    });

    test('preserves a literal plus and encoded space distinctly', () {
      expect(
        _canonical('https://example.test/?value=a+b&space=a%20b'),
        'https://example.test/?space=a%20b&value=a+b',
      );
    });

    test('retains normalised sanitised user information', () {
      expect(
        _canonical('https://%5bredacted%5d@example.test/path'),
        'https://%5Bredacted%5D@example.test/path',
      );
    });

    test('brackets an IPv6 host', () {
      expect(
        _canonical('https://[2001:db8::1]:8443/path'),
        'https://[2001:db8::1]:8443/path',
      );
    });

    test('rejects a non-canonical internationalised host safely', () {
      const unsafeHost = 'MÜNICH.example';

      expect(
        () => _canonical('https://$unsafeHost/path'),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.toString(),
            'message',
            isNot(contains(unsafeHost)),
          ),
        ),
      );
    });
  });
}

String _canonical(String uri) => canonicalisePersistedRequestUri(
      CassetteRequest(method: 'GET', uri: Uri.parse(uri)),
    );

import 'package:http_cassette/http_cassette.dart';
import 'package:test/test.dart';

void main() {
  group('CassetteRequest', () {
    test('creates a canonical request', () {
      final headers = CassetteHeaders(<String, Iterable<String>>{
        'Content-Type': <String>['application/json'],
      });
      final request = CassetteRequest(
        method: 'post',
        uri: Uri.parse('https://api.example.test/orders?active=true'),
        headers: headers,
        body: <int>[1, 2, 3],
      );

      expect(request.method, 'POST');
      expect(request.uri,
          Uri.parse('https://api.example.test/orders?active=true'));
      expect(request.headers, same(headers));
      expect(request.body, <int>[1, 2, 3]);
    });

    test('provides empty header and body defaults', () {
      final request = CassetteRequest(
        method: 'GET',
        uri: Uri.parse('custom://example.test/resource'),
      );

      expect(request.headers, const CassetteHeaders.empty());
      expect(request.body, isEmpty);
    });

    test('supports extension methods', () {
      final request = CassetteRequest(
        method: 'example-method',
        uri: Uri.parse('https://example.test/'),
      );

      expect(request.method, 'EXAMPLE-METHOD');
    });

    test('rejects invalid methods without echoing them', () {
      const unsafeMethod = 'GET\r\nx-secret: value';

      expect(
        () => CassetteRequest(
          method: unsafeMethod,
          uri: Uri.parse('https://example.test/'),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.toString(),
            'message',
            isNot(contains('x-secret')),
          ),
        ),
      );
    });

    test('rejects relative and hostless URIs without echoing them', () {
      for (final uri in <Uri>[
        Uri.parse('/relative'),
        Uri.parse('file:///private/path'),
      ]) {
        expect(
          () => CassetteRequest(method: 'GET', uri: uri),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.toString(),
              'message',
              isNot(contains(uri.toString())),
            ),
          ),
        );
      }
    });

    test('copies body input and does not expose mutable bytes', () {
      final source = <int>[1, 2, 3];
      final request = CassetteRequest(
        method: 'POST',
        uri: Uri.parse('https://example.test/'),
        body: source,
      );

      source[0] = 9;

      expect(request.body, <int>[1, 2, 3]);
      expect(() => request.body[0] = 9, throwsUnsupportedError);
      expect(
        () => request.body.buffer.asUint8List()[0] = 9,
        throwsUnsupportedError,
      );
    });

    test('rejects values outside the byte range', () {
      for (final byte in <int>[-1, 256]) {
        expect(
          () => CassetteRequest(
            method: 'POST',
            uri: Uri.parse('https://example.test/'),
            body: <int>[byte],
          ),
          throwsArgumentError,
        );
      }
    });

    test('uses structural equality and hash codes', () {
      final first = CassetteRequest(
        method: 'get',
        uri: Uri.parse('https://example.test/resource'),
        headers: CassetteHeaders(<String, Iterable<String>>{
          'Accept': <String>['application/json'],
        }),
        body: <int>[1, 2],
      );
      final second = CassetteRequest(
        method: 'GET',
        uri: Uri.parse('https://example.test/resource'),
        headers: CassetteHeaders(<String, Iterable<String>>{
          'accept': <String>['application/json'],
        }),
        body: <int>[1, 2],
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(
        first,
        isNot(
          CassetteRequest(
            method: 'GET',
            uri: Uri.parse('https://example.test/other'),
            headers: second.headers,
            body: <int>[1, 2],
          ),
        ),
      );
    });
  });

  group('CassetteResponse', () {
    test('creates a canonical response', () {
      final headers = CassetteHeaders(<String, Iterable<String>>{
        'Content-Type': <String>['application/json'],
      });
      final response = CassetteResponse(
        statusCode: 201,
        headers: headers,
        body: <int>[4, 5, 6],
        reasonPhrase: 'Created',
      );

      expect(response.statusCode, 201);
      expect(response.headers, same(headers));
      expect(response.body, <int>[4, 5, 6]);
      expect(response.reasonPhrase, 'Created');
    });

    test('accepts the complete V1 status range', () {
      expect(CassetteResponse(statusCode: 100).statusCode, 100);
      expect(CassetteResponse(statusCode: 599).statusCode, 599);
    });

    test('rejects out-of-range statuses', () {
      for (final statusCode in <int>[99, 600]) {
        expect(
          () => CassetteResponse(statusCode: statusCode),
          throwsArgumentError,
        );
      }
    });

    test('rejects invalid reason phrases without echoing them', () {
      for (final reasonPhrase in <String>['', 'secret\r\nvalue']) {
        expect(
          () => CassetteResponse(
            statusCode: 200,
            reasonPhrase: reasonPhrase,
          ),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.toString(),
              'message',
              isNot(contains('secret')),
            ),
          ),
        );
      }
    });

    test('copies body input and does not expose mutable bytes', () {
      final source = <int>[1, 2, 3];
      final response = CassetteResponse(statusCode: 200, body: source);

      source[0] = 9;

      expect(response.body, <int>[1, 2, 3]);
      expect(() => response.body[0] = 9, throwsUnsupportedError);
    });

    test('uses structural equality and hash codes', () {
      final first = CassetteResponse(
        statusCode: 200,
        headers: CassetteHeaders(<String, Iterable<String>>{
          'Content-Type': <String>['application/json'],
        }),
        body: <int>[1, 2],
        reasonPhrase: 'OK',
      );
      final second = CassetteResponse(
        statusCode: 200,
        headers: CassetteHeaders(<String, Iterable<String>>{
          'content-type': <String>['application/json'],
        }),
        body: <int>[1, 2],
        reasonPhrase: 'OK',
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first, isNot(CassetteResponse(statusCode: 204)));
    });
  });
}

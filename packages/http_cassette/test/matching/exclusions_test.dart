import 'package:http_cassette/src/matching/exclusions.dart';
import 'package:test/test.dart';

void main() {
  group('MatchingExclusions', () {
    test('canonicalises, deduplicates and sorts locations', () {
      final exclusions = MatchingExclusions(
        headers: <String>['X-Trace', 'accept', 'x-trace'],
        queryParameters: <String>['token', 'request%5fid'],
        jsonPointers: <String>['/z', '/a~1b/m~0n', '/z'],
        uriUserInformation: true,
      );

      expect(exclusions.headers, <String>{'accept', 'x-trace'});
      expect(exclusions.queryParameters, <String>{'request_id', 'token'});
      expect(exclusions.jsonPointers, <String>{'/a~1b/m~0n', '/z'});
      expect(exclusions.uriUserInformation, isTrue);
    });

    test('rejects invalid header names safely', () {
      expect(
        () => MatchingExclusions(headers: <String>{'not a header'}),
        throwsArgumentError,
      );
    });

    test('rejects malformed query-name escapes safely', () {
      expect(
        () => MatchingExclusions(queryParameters: <String>{'token%'}),
        throwsArgumentError,
      );
    });

    test('accepts the root and exact RFC 6901 pointers', () {
      final exclusions = MatchingExclusions(
        jsonPointers: <String>{'', '/', '/items/0', '/a~1b/m~0n'},
      );

      expect(
        exclusions.jsonPointers,
        <String>{'', '/', '/a~1b/m~0n', '/items/0'},
      );
    });

    test('rejects non-pointer and invalid escape syntax safely', () {
      for (final pointer in <String>['member', '/bad~', '/bad~2']) {
        expect(
          () => MatchingExclusions(jsonPointers: <String>{pointer}),
          throwsArgumentError,
          reason: pointer,
        );
      }
    });

    test('does not expose mutable sets', () {
      final exclusions = MatchingExclusions(headers: <String>{'accept'});

      expect(
        () => exclusions.headers.add('content-type'),
        throwsUnsupportedError,
      );
    });
  });
}

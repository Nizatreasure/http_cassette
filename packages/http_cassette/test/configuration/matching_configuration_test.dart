import 'package:http_cassette/http_cassette.dart';
import 'package:test/test.dart';

void main() {
  group('MatchingConfiguration', () {
    test('provides immutable empty defaults', () {
      final configuration = MatchingConfiguration();

      expect(configuration.includedHeaders, isEmpty);
      expect(configuration.ignoredQueryParameters, isEmpty);
      expect(configuration.ignoredJsonPointers, isEmpty);
      expect(
        () => configuration.includedHeaders.add('accept'),
        throwsUnsupportedError,
      );
    });

    test('validates, canonicalises and deduplicates configuration', () {
      final configuration = MatchingConfiguration(
        includedHeaders: <String>['X-Version', 'accept', 'x-version'],
        ignoredQueryParameters: <String>['request%5fid', 'token'],
        ignoredJsonPointers: <String>['/z', '/a~1b', '/z'],
      );

      expect(configuration.includedHeaders, <String>{'accept', 'x-version'});
      expect(
        configuration.ignoredQueryParameters,
        <String>{'request_id', 'token'},
      );
      expect(configuration.ignoredJsonPointers, <String>{'/a~1b', '/z'});
    });

    test('rejects invalid configuration before matching', () {
      expect(
        () => MatchingConfiguration(includedHeaders: <String>{'not valid'}),
        throwsArgumentError,
      );
      expect(
        () => MatchingConfiguration(ignoredQueryParameters: <String>{'bad%'}),
        throwsArgumentError,
      );
      expect(
        () => MatchingConfiguration(ignoredJsonPointers: <String>{'/bad~2'}),
        throwsArgumentError,
      );
    });

    test('has structural equality and deterministic hash codes', () {
      final first = MatchingConfiguration(
        includedHeaders: <String>{'accept'},
        ignoredJsonPointers: <String>{'/volatile'},
      );
      final second = MatchingConfiguration(
        ignoredJsonPointers: <String>{'/volatile'},
        includedHeaders: <String>{'ACCEPT'},
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });
  });
}

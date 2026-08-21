import 'package:http_cassette/http_cassette.dart';
import 'package:test/test.dart';

void main() {
  group('MatchingConfiguration', () {
    test('provides immutable empty defaults', () {
      final configuration = MatchingConfiguration();

      expect(configuration.includedHeaders, isEmpty);
      expect(configuration.ignoredQueryParameters, isEmpty);
      expect(configuration.ignoredJsonPointers, isEmpty);
      expect(configuration.customComponents, isEmpty);
      expect(
        () => configuration.includedHeaders.add('accept'),
        throwsUnsupportedError,
      );
    });

    test('preserves custom component registration order immutably', () {
      final first = _Component('first');
      final second = _Component('second');
      final source = <RequestMatcherComponent>[first, second];

      final configuration = MatchingConfiguration(customComponents: source);
      source.clear();

      expect(configuration.customComponents, <RequestMatcherComponent>[
        first,
        second,
      ]);
      expect(
        () => configuration.customComponents.add(_Component('third')),
        throwsUnsupportedError,
      );
    });

    test('rejects unsafe or duplicate custom component names', () {
      expect(
        () => MatchingConfiguration(
          customComponents: <RequestMatcherComponent>[
            _Component('unsafe\nname'),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => MatchingConfiguration(
          customComponents: <RequestMatcherComponent>[
            _Component('authority'),
            _Component('authority'),
          ],
        ),
        throwsArgumentError,
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
      final component = _Component('authority');
      final first = MatchingConfiguration(
        includedHeaders: <String>{'accept'},
        ignoredJsonPointers: <String>{'/volatile'},
        customComponents: <RequestMatcherComponent>[component],
      );
      final second = MatchingConfiguration(
        ignoredJsonPointers: <String>{'/volatile'},
        includedHeaders: <String>{'ACCEPT'},
        customComponents: <RequestMatcherComponent>[component],
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(
        first,
        isNot(
          MatchingConfiguration(
            includedHeaders: <String>{'accept'},
            ignoredJsonPointers: <String>{'/volatile'},
          ),
        ),
      );
    });
  });
}

final class _Component implements RequestMatcherComponent {
  const _Component(this.name);

  @override
  final String name;

  @override
  MatchComponentResult compare(
    CassetteRequest expected,
    CassetteRequest actual,
    MatchContext context,
  ) =>
      MatchComponentResult(matches: true);
}

import 'package:http_cassette/http_cassette.dart';
import 'package:test/test.dart';

void main() {
  group('MatchContext', () {
    test('validates and exposes only immutable canonical exclusions', () {
      final context = MatchContext(
        excludedHeaders: <String>['X-Secret'],
        excludedQueryParameters: <String>['request%5fid'],
        excludedJsonPointers: <String>['/secret'],
        uriUserInformationExcluded: true,
        bodyExcluded: true,
      );

      expect(context.excludedHeaders, <String>{'x-secret'});
      expect(context.excludedQueryParameters, <String>{'request_id'});
      expect(context.excludedJsonPointers, <String>{'/secret'});
      expect(context.uriUserInformationExcluded, isTrue);
      expect(context.bodyExcluded, isTrue);
      expect(
        () => context.excludedHeaders.add('another'),
        throwsUnsupportedError,
      );
      expect(
        () => MatchContext(excludedJsonPointers: <String>['invalid']),
        throwsArgumentError,
      );
    });
  });

  group('MatchComponentResult', () {
    test('creates a matching result without differences', () {
      final result = MatchComponentResult(matches: true);

      expect(result.matches, isTrue);
      expect(result.differences.isEmpty, isTrue);
    });

    test('bounds safe differences while preserving the complete count', () {
      final result = MatchComponentResult(
        matches: false,
        differences: List<MatchDifference>.generate(
          25,
          (index) => MatchDifference(
            kind: MatchDifferenceKind.customComponentDifference,
            location: 'field-$index',
          ),
        ),
      );

      expect(result.matches, isFalse);
      expect(result.differences.totalCount, 25);
      expect(result.differences.differences.length, 20);
      expect(result.differences.omittedCount, 5);
    });

    test('rejects inconsistent match state and differences', () {
      final difference = MatchDifference(
        kind: MatchDifferenceKind.customComponentDifference,
      );

      expect(
        () => MatchComponentResult(
          matches: true,
          differences: <MatchDifference>[difference],
        ),
        throwsArgumentError,
      );
      expect(
        () => MatchComponentResult(matches: false),
        throwsArgumentError,
      );
    });

    test('suppresses an unsafe custom location', () {
      final result = MatchComponentResult(
        matches: false,
        differences: <MatchDifference>[
          MatchDifference(
            kind: MatchDifferenceKind.customComponentDifference,
            location: 'unsafe\nvalue',
          ),
        ],
      );

      expect(result.differences.differences.single.location, isNull);
      expect(
        result.differences.differences.single.locationSuppressed,
        isTrue,
      );
    });
  });

  test('supports a third-party component using only the public library', () {
    final component = _AuthorityMatcher();
    final result = component.compare(
      _request('https://one.example.test/items'),
      _request('https://two.example.test/items'),
      MatchContext(),
    );

    expect(component.name, 'authority');
    expect(result.matches, isFalse);
    expect(
      result.differences.differences.single.kind,
      MatchDifferenceKind.customComponentDifference,
    );
  });
}

final class _AuthorityMatcher implements RequestMatcherComponent {
  @override
  String get name => 'authority';

  @override
  MatchComponentResult compare(
    CassetteRequest expected,
    CassetteRequest actual,
    MatchContext context,
  ) {
    final matches = expected.uri.authority == actual.uri.authority;
    return MatchComponentResult(
      matches: matches,
      differences: matches
          ? const <MatchDifference>[]
          : <MatchDifference>[
              MatchDifference(
                kind: MatchDifferenceKind.customComponentDifference,
                location: 'authority',
              ),
            ],
    );
  }
}

CassetteRequest _request(String uri) => CassetteRequest(
      method: 'GET',
      uri: Uri.parse(uri),
    );

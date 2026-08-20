import 'package:http_cassette/src/matching/difference.dart';
import 'package:test/test.dart';

void main() {
  group('MatchDifferenceCollector', () {
    test('retains a bounded prefix and counts omitted differences', () {
      final collector = MatchDifferenceCollector(maximumRetained: 2)
        ..add(MatchDifference(kind: MatchDifferenceKind.missing, location: 'a'))
        ..add(MatchDifference(kind: MatchDifferenceKind.extra, location: 'b'))
        ..add(
          MatchDifference(
            kind: MatchDifferenceKind.differentValue,
            location: 'c',
          ),
        );

      final result = collector.build();
      expect(result.totalCount, 3);
      expect(result.differences.map((difference) => difference.location),
          <String>['a', 'b']);
      expect(result.omittedCount, 1);
    });

    test('suppresses unsafe locations without dropping differences', () {
      final collector = MatchDifferenceCollector()
        ..add(
          MatchDifference(
            kind: MatchDifferenceKind.differentValue,
            location: 'unsafe\nlocation',
          ),
        );

      final difference = collector.build().differences.single;
      expect(difference.location, isNull);
      expect(difference.locationSuppressed, isTrue);
    });

    test('rejects a negative retention bound', () {
      expect(
        () => MatchDifferenceCollector(maximumRetained: -1),
        throwsArgumentError,
      );
    });
  });
}

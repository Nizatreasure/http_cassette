import '../matching/difference.dart';
import '../matching/json.dart';
import '../matching/request_matcher.dart';

/// One value-free difference with any structural location suppressed.
final class ReplayDifferenceFact {
  const ReplayDifferenceFact._({
    required this.kind,
    required this.locationSuppressed,
  });

  /// The difference category.
  final MatchDifferenceKind kind;

  /// Whether the source difference supplied or suppressed a location.
  final bool locationSuppressed;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReplayDifferenceFact &&
          kind == other.kind &&
          locationSuppressed == other.locationSuppressed;

  @override
  int get hashCode => Object.hash(kind, locationSuppressed);
}

/// A bounded immutable collection of location-suppressed differences.
final class ReplayDifferenceFacts {
  ReplayDifferenceFacts._(BoundedMatchDifferences source)
      : differences = List<ReplayDifferenceFact>.unmodifiable(
          source.differences.map(
            (difference) => ReplayDifferenceFact._(
              kind: difference.kind,
              locationSuppressed:
                  difference.location != null || difference.locationSuppressed,
            ),
          ),
        ),
        totalCount = source.totalCount;

  /// Retained value-free differences in their original deterministic order.
  final List<ReplayDifferenceFact> differences;

  /// The complete difference count used during candidate ranking.
  final int totalCount;

  /// The number of differences omitted by the source comparison bound.
  int get omittedCount => totalCount - differences.length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReplayDifferenceFacts &&
          totalCount == other.totalCount &&
          _listsEqual(differences, other.differences);

  @override
  int get hashCode => Object.hash(totalCount, Object.hashAll(differences));
}

/// Safe facts for one built-in matcher component.
final class ReplayBuiltInComponentFact {
  ReplayBuiltInComponentFact._(RequestMatchComponentResult source)
      : component = source.component,
        state = source.state,
        matches = source.matches,
        differences = ReplayDifferenceFacts._(source.differences);

  /// The built-in component in fixed comparison order.
  final RequestMatchComponent component;

  /// The component's comparison state.
  final RequestMatchComponentState state;

  /// Whether this component permitted the request to match.
  final bool matches;

  /// Its bounded location-suppressed differences.
  final ReplayDifferenceFacts differences;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReplayBuiltInComponentFact &&
          component == other.component &&
          state == other.state &&
          matches == other.matches &&
          differences == other.differences;

  @override
  int get hashCode => Object.hash(component, state, matches, differences);
}

/// Safe facts for one custom matcher component without retaining its name.
final class ReplayCustomComponentFact {
  ReplayCustomComponentFact._({
    required this.registrationIndex,
    required CustomComponentMatchResult source,
  })  : matches = source.result.matches,
        differences = ReplayDifferenceFacts._(source.result.differences);

  /// The component's zero-based deterministic registration index.
  final int registrationIndex;

  /// Whether this component permitted the request to match.
  final bool matches;

  /// Its bounded location-suppressed differences.
  final ReplayDifferenceFacts differences;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReplayCustomComponentFact &&
          registrationIndex == other.registrationIndex &&
          matches == other.matches &&
          differences == other.differences;

  @override
  int get hashCode => Object.hash(registrationIndex, matches, differences);
}

/// Value-free body-comparison facts for the closest candidate.
final class ReplayBodyComparisonFact {
  ReplayBodyComparisonFact._(RequestBodyMatchResult source)
      : kind = source.kind,
        expectedLength = source.exactComparison?.expectedLength,
        actualLength = source.exactComparison?.actualLength,
        firstDifferenceOffset = source.exactComparison?.firstDifferenceOffset,
        expectedJsonStatus = source.expectedJsonStatus,
        actualJsonStatus = source.actualJsonStatus;

  /// The body comparison strategy that was used.
  final RequestBodyComparisonKind kind;

  /// Expected byte length when exact comparison was used.
  final int? expectedLength;

  /// Actual byte length when exact comparison was used.
  final int? actualLength;

  /// First differing byte offset when exact comparison found a difference.
  final int? firstDifferenceOffset;

  /// Expected JSON classification when JSON parsing was attempted.
  final JsonBodyStatus? expectedJsonStatus;

  /// Actual JSON classification when JSON parsing was attempted.
  final JsonBodyStatus? actualJsonStatus;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReplayBodyComparisonFact &&
          kind == other.kind &&
          expectedLength == other.expectedLength &&
          actualLength == other.actualLength &&
          firstDifferenceOffset == other.firstDifferenceOffset &&
          expectedJsonStatus == other.expectedJsonStatus &&
          actualJsonStatus == other.actualJsonStatus;

  @override
  int get hashCode => Object.hash(
        kind,
        expectedLength,
        actualLength,
        firstDifferenceOffset,
        expectedJsonStatus,
        actualJsonStatus,
      );
}

/// Location-safe projection of the closest non-matching comparison.
final class ReplayNoMatchComparisonProjection {
  /// Projects [comparison] without retaining names, locations or HTTP values.
  factory ReplayNoMatchComparisonProjection.fromComparison(
    RequestMatchResult comparison,
  ) {
    if (comparison.matches) {
      throw ArgumentError('A no-match projection requires a mismatch.');
    }
    return ReplayNoMatchComparisonProjection._(
      builtInComponents: comparison.components.map(
        ReplayBuiltInComponentFact._,
      ),
      customComponents: comparison.customComponents.indexed.map(
        (entry) => ReplayCustomComponentFact._(
          registrationIndex: entry.$1,
          source: entry.$2,
        ),
      ),
      body: ReplayBodyComparisonFact._(comparison.body),
    );
  }

  ReplayNoMatchComparisonProjection._({
    required Iterable<ReplayBuiltInComponentFact> builtInComponents,
    required Iterable<ReplayCustomComponentFact> customComponents,
    required this.body,
  })  : builtInComponents =
            List<ReplayBuiltInComponentFact>.unmodifiable(builtInComponents),
        customComponents =
            List<ReplayCustomComponentFact>.unmodifiable(customComponents);

  /// Built-in facts in fixed matcher order.
  final List<ReplayBuiltInComponentFact> builtInComponents;

  /// Custom facts in registration order, identified only by index.
  final List<ReplayCustomComponentFact> customComponents;

  /// Safe value-free details about the body comparison strategy.
  final ReplayBodyComparisonFact body;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReplayNoMatchComparisonProjection &&
          _listsEqual(builtInComponents, other.builtInComponents) &&
          _listsEqual(customComponents, other.customComponents) &&
          body == other.body;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(builtInComponents),
        Object.hashAll(customComponents),
        body,
      );
}

bool _listsEqual<T>(List<T> first, List<T> second) {
  if (first.length != second.length) {
    return false;
  }
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}

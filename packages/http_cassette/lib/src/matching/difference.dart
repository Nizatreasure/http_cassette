import '../safety/safe_text.dart';

/// A value-free category of request difference.
enum MatchDifferenceKind {
  /// An expected structural item is absent from the incoming request.
  missing,

  /// The incoming request contains an unexpected structural item.
  extra,

  /// Both requests contain the item but its value differs.
  differentValue,

  /// Both requests contain the item with different data types.
  differentType,

  /// Equivalent items occur in a different significant order.
  differentOrder,

  /// An item occurs a different number of times.
  differentMultiplicity,

  /// A value cannot be compared because its representation is invalid.
  invalidRepresentation,

  /// A required comparison cannot be performed safely.
  unavailableComparison,

  /// A custom matcher component reported a domain-specific difference.
  customComponentDifference,
}

/// One safe, value-free request difference.
final class MatchDifference {
  /// Creates a difference with an optional safe structural [location].
  ///
  /// A location which is unsafe or longer than the diagnostic limit is
  /// suppressed rather than retained. Request values must never be supplied as
  /// locations.
  factory MatchDifference({
    required MatchDifferenceKind kind,
    String? location,
  }) {
    final safeLocation = _safeLocation(location);
    return MatchDifference._(
      kind: kind,
      location: safeLocation,
      locationSuppressed: location != null && safeLocation == null,
    );
  }

  const MatchDifference._({
    required this.kind,
    required this.location,
    required this.locationSuppressed,
  });

  /// The difference category.
  final MatchDifferenceKind kind;

  /// A safe bounded structural location, or `null` when absent or suppressed.
  final String? location;

  /// Whether an unsafe or overlong location was suppressed.
  final bool locationSuppressed;
}

/// A bounded list of retained differences with the complete observed count.
///
/// Matching and ranking use [totalCount], while diagnostics display only the
/// deterministic prefix in [differences].
final class BoundedMatchDifferences {
  BoundedMatchDifferences._({
    required Iterable<MatchDifference> differences,
    required this.totalCount,
  }) : differences = List<MatchDifference>.unmodifiable(differences);

  /// Retained differences in deterministic order.
  final List<MatchDifference> differences;

  /// The complete number of differences used for ranking.
  final int totalCount;

  /// The number counted but omitted from [differences].
  int get omittedCount => totalCount - differences.length;

  /// Whether the component has no differences.
  bool get isEmpty => totalCount == 0;
}

/// Counts every difference while retaining only a configured prefix.
final class MatchDifferenceCollector {
  /// Creates a collector retaining at most [maximumRetained] differences.
  MatchDifferenceCollector({this.maximumRetained = defaultMaximumRetained}) {
    if (maximumRetained < 0) {
      throw ArgumentError('Maximum retained differences must not be negative.');
    }
  }

  /// The default maximum of 20 retained differences.
  static const defaultMaximumRetained = 20;

  /// The maximum number of difference records retained.
  final int maximumRetained;

  final _differences = <MatchDifference>[];
  var _totalCount = 0;

  /// Counts [difference] and retains it while within the configured bound.
  void add(MatchDifference difference) {
    _totalCount += 1;
    if (_differences.length < maximumRetained) {
      _differences.add(difference);
    }
  }

  /// Returns an immutable snapshot of the collected differences.
  BoundedMatchDifferences build() => BoundedMatchDifferences._(
        differences: _differences,
        totalCount: _totalCount,
      );
}

String? _safeLocation(String? location) {
  if (location == null) {
    return null;
  }
  try {
    return validateSafeSingleLine(
      location,
      description: 'Match difference location',
      maximumLength: 256,
    );
  } on ArgumentError {
    return null;
  }
}

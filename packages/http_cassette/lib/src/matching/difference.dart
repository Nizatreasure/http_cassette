import '../safety/safe_text.dart';

/// A value-free category of request difference.
enum MatchDifferenceKind {
  missing,
  extra,
  differentValue,
  differentType,
  differentOrder,
  differentMultiplicity,
  invalidRepresentation,
  unavailableComparison,
}

/// One safe, value-free request difference.
final class MatchDifference {
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

/// A deterministic bounded prefix of component differences.
final class BoundedMatchDifferences {
  BoundedMatchDifferences._({
    required Iterable<MatchDifference> differences,
    required this.totalCount,
  }) : differences = List<MatchDifference>.unmodifiable(differences);

  /// Retained differences in deterministic order.
  final List<MatchDifference> differences;

  /// The complete number of differences used for ranking.
  final int totalCount;

  /// The number omitted from [differences].
  int get omittedCount => totalCount - differences.length;

  /// Whether the component has no differences.
  bool get isEmpty => totalCount == 0;
}

/// Collects a bounded prefix while counting every observed difference.
final class MatchDifferenceCollector {
  /// Creates a collector retaining at most [maximumRetained] differences.
  MatchDifferenceCollector({this.maximumRetained = defaultMaximumRetained}) {
    if (maximumRetained < 0) {
      throw ArgumentError('Maximum retained differences must not be negative.');
    }
  }

  /// The measured default retained difference count.
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

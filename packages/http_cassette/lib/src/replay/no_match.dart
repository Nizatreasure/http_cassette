import '../diagnostics/diagnostic.dart';
import '../matching/ranking.dart';
import '../matching/request_matcher.dart';

/// Immutable value-free facts from one verified no-match candidate ranking.
final class ReplayNoMatchDetails {
  /// Captures facts from [ranking] without recomputing request matching.
  factory ReplayNoMatchDetails.fromRanking(RequestCandidateRanking ranking) {
    final closest = ranking.closestCandidate;
    if (closest?.comparison.matches ?? false) {
      throw ArgumentError(
        'No-match details require a ranking without a matching candidate.',
      );
    }
    return ReplayNoMatchDetails._(
      consideredInteractionCount: ranking.consideredCount,
      closestRecordedIndex: closest?.recordedIndex,
      closestComparison: closest?.comparison,
    );
  }

  const ReplayNoMatchDetails._({
    required this.consideredInteractionCount,
    required this.closestRecordedIndex,
    required this.closestComparison,
  });

  /// The complete number of recorded interactions considered.
  final int consideredInteractionCount;

  /// The closest candidate's recorded index, or `null` for an empty cassette.
  final int? closestRecordedIndex;

  /// The closest candidate's original safe comparison, if one exists.
  ///
  /// This is the comparison already used for ranking; diagnostics must not
  /// recompute request semantics independently.
  final RequestMatchResult? closestComparison;

  /// Replay no-match failures always have real network access disabled.
  NetworkAccess get networkAccess => NetworkAccess.disabled;
}

import 'request_matcher.dart';

/// A recorded interaction paired with its existing request comparison.
final class RequestMatchCandidate {
  /// Creates a candidate at [recordedIndex].
  RequestMatchCandidate({
    required this.recordedIndex,
    required this.comparison,
  }) {
    if (recordedIndex < 0) {
      throw ArgumentError.value(
        recordedIndex,
        'recordedIndex',
        'Recorded interaction index must not be negative.',
      );
    }
  }

  /// The interaction's zero-based position in the cassette.
  final int recordedIndex;

  /// The comparison already used to determine matching eligibility.
  final RequestMatchResult comparison;
}

/// The deterministic outcome of ranking request match candidates.
final class RequestCandidateRanking {
  const RequestCandidateRanking._({
    required this.consideredCount,
    required this.closestCandidate,
  });

  /// The complete number of candidates considered.
  final int consideredCount;

  /// The closest candidate, or `null` when no candidates were supplied.
  final RequestMatchCandidate? closestCandidate;
}

/// Selects the closest candidate using the fixed V1 component precedence.
///
/// This function uses only the stored component difference counts. It does not
/// recompute request semantics or alter matching eligibility. Candidate
/// recorded indices must be unique.
RequestCandidateRanking rankRequestMatchCandidates(
  Iterable<RequestMatchCandidate> candidates,
) {
  RequestMatchCandidate? closest;
  final recordedIndices = <int>{};
  var consideredCount = 0;

  for (final candidate in candidates) {
    if (!recordedIndices.add(candidate.recordedIndex)) {
      throw ArgumentError(
        'Candidate recorded interaction indices must be unique.',
      );
    }
    consideredCount++;
    if (closest == null || _compareCandidates(candidate, closest) < 0) {
      closest = candidate;
    }
  }

  return RequestCandidateRanking._(
    consideredCount: consideredCount,
    closestCandidate: closest,
  );
}

int _compareCandidates(
  RequestMatchCandidate left,
  RequestMatchCandidate right,
) {
  for (final component in RequestMatchComponent.values) {
    final leftCount =
        left.comparison.components[component.index].differences.totalCount;
    final rightCount =
        right.comparison.components[component.index].differences.totalCount;
    final differenceComparison = leftCount.compareTo(rightCount);
    if (differenceComparison != 0) {
      return differenceComparison;
    }
  }

  final leftCustom = left.comparison.customComponents;
  final rightCustom = right.comparison.customComponents;
  if (leftCustom.length != rightCustom.length) {
    throw StateError('Candidate custom matcher components must be identical.');
  }
  for (var index = 0; index < leftCustom.length; index += 1) {
    if (leftCustom[index].name != rightCustom[index].name) {
      throw StateError(
        'Candidate custom matcher components must be identical.',
      );
    }
    final differenceComparison = leftCustom[index]
        .result
        .differences
        .totalCount
        .compareTo(rightCustom[index].result.differences.totalCount);
    if (differenceComparison != 0) {
      return differenceComparison;
    }
  }

  return left.recordedIndex.compareTo(right.recordedIndex);
}

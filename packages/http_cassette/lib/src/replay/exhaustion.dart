import '../diagnostics/diagnostic.dart';
import 'configuration.dart';
import 'selection.dart';

/// Immutable value-free facts about one exhausted replay matching group.
///
/// These facts combine with cassette identity and a safe request summary to
/// form a complete exhaustion diagnostic.
final class ReplayExhaustionDetails {
  /// Captures exhaustion facts from an actual exhausted [result] and [state].
  factory ReplayExhaustionDetails.fromSelection({
    required ReplaySelectionState state,
    required ReplaySelectionResult result,
  }) {
    if (result is! ReplayGroupExhausted ||
        !result.wasProducedBy(state) ||
        !state.isExhausted) {
      throw ArgumentError(
        'Exhaustion details require an actually exhausted selection state.',
      );
    }
    return ReplayExhaustionDetails._(
      replayPolicy: state.policy,
      matchingGroupSize: state.matchingInteractions.length,
      usedInteractionCount: state.consumedCount,
      recordedIndices: List<int>.unmodifiable(
        state.matchingInteractions.map((interaction) => interaction.index),
      ),
    );
  }

  const ReplayExhaustionDetails._({
    required this.replayPolicy,
    required this.matchingGroupSize,
    required this.usedInteractionCount,
    required this.recordedIndices,
  });

  /// The policy under which the matching group exhausted.
  final ReplayPolicy replayPolicy;

  /// The complete number of matching interactions.
  final int matchingGroupSize;

  /// The number of distinct matching interactions used.
  final int usedInteractionCount;

  /// Matching interaction indices in ascending recorded order.
  final List<int> recordedIndices;

  /// Replay exhaustion always occurs with real network access disabled.
  NetworkAccess get networkAccess => NetworkAccess.disabled;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReplayExhaustionDetails &&
          replayPolicy == other.replayPolicy &&
          matchingGroupSize == other.matchingGroupSize &&
          usedInteractionCount == other.usedInteractionCount &&
          _listsEqual(recordedIndices, other.recordedIndices);

  @override
  int get hashCode => Object.hash(
        replayPolicy,
        matchingGroupSize,
        usedInteractionCount,
        Object.hashAll(recordedIndices),
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

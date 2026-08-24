import '../cassette/cassette.dart';
import 'selection.dart';

/// The typed outcome of optional cassette-wide replay verification.
sealed class ReplayVerificationResult {
  const ReplayVerificationResult();
}

/// A replay-verification result indicating that verification was disabled.
final class ReplayVerificationSkipped extends ReplayVerificationResult {
  /// Creates a skipped-verification result.
  const ReplayVerificationSkipped();
}

/// A replay-verification result indicating that every interaction was used.
final class ReplayVerificationPassed extends ReplayVerificationResult {
  /// Creates a passed-verification result.
  const ReplayVerificationPassed();
}

/// A replay-verification result containing unused recorded indices.
final class ReplayUnusedInteractions extends ReplayVerificationResult {
  ReplayUnusedInteractions._({
    required this.totalInteractionCount,
    required List<int> unusedRecordedIndices,
  }) : unusedRecordedIndices = List<int>.unmodifiable(
          unusedRecordedIndices,
        );

  /// The complete number of interactions in the verified cassette.
  final int totalInteractionCount;

  /// The number of interactions used before verification.
  int get usedInteractionCount =>
      totalInteractionCount - unusedRecordedIndices.length;

  /// Unused interaction indices in ascending recorded order.
  final List<int> unusedRecordedIndices;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReplayUnusedInteractions &&
          totalInteractionCount == other.totalInteractionCount &&
          _listsEqual(
            unusedRecordedIndices,
            other.unusedRecordedIndices,
          );

  @override
  int get hashCode => Object.hash(
        totalInteractionCount,
        Object.hashAll(unusedRecordedIndices),
      );
}

/// Verifies cassette-wide usage when [requireAllInteractions] is true.
///
/// Usage from independent matching groups is combined by recorded index.
/// Disabled verification does not inspect [usageSnapshots].
ReplayVerificationResult verifyReplayUsage({
  required Cassette cassette,
  required Iterable<ReplayUsageSnapshot> usageSnapshots,
  bool requireAllInteractions = false,
}) {
  if (!requireAllInteractions) {
    return const ReplayVerificationSkipped();
  }

  final usedIndices = <int>{};
  for (final snapshot in usageSnapshots) {
    for (final index in snapshot.usedRecordedIndices) {
      if (index >= cassette.interactions.length) {
        throw StateError(
          'Replay usage contains an index outside the cassette.',
        );
      }
      usedIndices.add(index);
    }
  }

  final unusedIndices = <int>[];
  for (final interaction in cassette.interactions) {
    if (!usedIndices.contains(interaction.index)) {
      unusedIndices.add(interaction.index);
    }
  }
  if (unusedIndices.isEmpty) {
    return const ReplayVerificationPassed();
  }
  return ReplayUnusedInteractions._(
    totalInteractionCount: cassette.interactions.length,
    unusedRecordedIndices: unusedIndices,
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

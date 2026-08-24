import '../cassette/name.dart';
import '../diagnostics/diagnostic.dart';
import 'configuration.dart';
import 'verification.dart';

/// Safe structured information for failed unused-interaction verification.
final class ReplayUnusedInteractionsDiagnostic {
  /// Assembles a diagnostic from an actual unused [result].
  factory ReplayUnusedInteractionsDiagnostic.fromVerification({
    required CassetteName cassetteName,
    required ReplayPolicy replayPolicy,
    required ReplayVerificationResult result,
  }) {
    if (result is! ReplayUnusedInteractions) {
      throw ArgumentError(
        'An unused-interaction diagnostic requires failed verification.',
      );
    }
    return ReplayUnusedInteractionsDiagnostic._(
      cassetteName: cassetteName,
      replayPolicy: replayPolicy,
      result: result,
    );
  }

  ReplayUnusedInteractionsDiagnostic._({
    required this.cassetteName,
    required this.replayPolicy,
    required this.result,
  }) : envelope = CassetteDiagnostic(
          category: DiagnosticCategory.unusedInteractions,
          summary: 'Replay completed with unused interactions.',
          networkAccess: NetworkAccess.disabled,
        );

  /// The validated logical cassette identity, never a persistence path.
  final CassetteName cassetteName;

  /// The policy active for the replay session.
  final ReplayPolicy replayPolicy;

  /// The verified complete unused-interaction result.
  final ReplayUnusedInteractions result;

  /// The common diagnostic envelope with fixed verification semantics.
  final CassetteDiagnostic envelope;

  /// The complete number of interactions in the cassette.
  int get totalInteractionCount => result.totalInteractionCount;

  /// The number of interactions used during replay.
  int get usedInteractionCount => result.usedInteractionCount;

  /// Complete unused recorded indices in ascending order.
  List<int> get unusedRecordedIndices => result.unusedRecordedIndices;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReplayUnusedInteractionsDiagnostic &&
          cassetteName == other.cassetteName &&
          replayPolicy == other.replayPolicy &&
          result == other.result;

  @override
  int get hashCode => Object.hash(
        cassetteName,
        replayPolicy,
        totalInteractionCount,
        Object.hashAll(unusedRecordedIndices),
      );
}

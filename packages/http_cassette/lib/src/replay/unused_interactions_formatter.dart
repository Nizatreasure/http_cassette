import 'diagnostic_formatting.dart';
import 'unused_interactions_diagnostic.dart';

/// Deterministically formats safe unused-interaction diagnostics as plain text.
final class ReplayUnusedInteractionsDiagnosticFormatter {
  /// Creates the default unused-interaction formatter.
  const ReplayUnusedInteractionsDiagnosticFormatter();

  /// Formats [diagnostic] without logging or inspecting recorded interactions.
  String format(ReplayUnusedInteractionsDiagnostic diagnostic) {
    final verificationLine =
        'Verification: ${diagnostic.totalInteractionCount} interactions; '
        '${diagnostic.usedInteractionCount} used; '
        '${diagnostic.unusedRecordedIndices.length} unused';
    return <String>[
      'HTTP Cassette failure: ${diagnostic.envelope.summary}',
      'Category: ${diagnostic.envelope.category.name}',
      'Cassette: ${formatReplayDiagnosticCassetteName(diagnostic.cassetteName.value)}',
      verificationLine,
      'Replay policy: ${diagnostic.replayPolicy.name}',
      'Unused indices: ${formatReplayDiagnosticIndices(diagnostic.unusedRecordedIndices)}',
      'Network access: disabled; no real request was made',
    ].join('\n');
  }
}

/// Human-readable formatting for failed unused-interaction verification.
extension ReplayUnusedInteractionsDiagnosticFormatting
    on ReplayUnusedInteractionsDiagnostic {
  /// Formats this diagnostic with [formatter].
  String format([
    ReplayUnusedInteractionsDiagnosticFormatter formatter =
        const ReplayUnusedInteractionsDiagnosticFormatter(),
  ]) =>
      formatter.format(this);
}

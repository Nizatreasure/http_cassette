import 'diagnostic_formatting.dart';
import 'exhaustion_diagnostic.dart';

/// Deterministically formats safe replay exhaustion diagnostics as plain text.
final class ReplayExhaustionDiagnosticFormatter {
  /// Creates the default exhaustion formatter.
  const ReplayExhaustionDiagnosticFormatter();

  /// Formats [diagnostic] without logging or inspecting canonical HTTP values.
  String format(ReplayExhaustionDiagnostic diagnostic) {
    final request = diagnostic.context.request;
    final details = diagnostic.details;
    final method = _formatMethod(
      request.method,
      request.methodCharacterLength,
    );
    final requestLine =
        'Request: method=$method; arrival=${request.arrivalIndex}; '
        'body=${request.bodyByteLength} bytes';
    final groupLine = 'Matching group: ${details.matchingGroupSize} '
        'interactions; ${details.usedInteractionCount} used';
    return <String>[
      'HTTP Cassette failure: ${diagnostic.envelope.summary}',
      'Category: ${diagnostic.envelope.category.name}',
      'Cassette: ${formatReplayDiagnosticCassetteName(diagnostic.context.cassetteName.value)}',
      requestLine,
      groupLine,
      'Replay policy: ${details.replayPolicy.name}',
      'Recorded indices: ${formatReplayDiagnosticIndices(details.recordedIndices)}',
      'Network access: disabled; no real request was made',
    ].join('\n');
  }
}

/// Human-readable formatting for a replay exhaustion diagnostic.
extension ReplayExhaustionDiagnosticFormatting on ReplayExhaustionDiagnostic {
  /// Formats this diagnostic with [formatter].
  String format([
    ReplayExhaustionDiagnosticFormatter formatter =
        const ReplayExhaustionDiagnosticFormatter(),
  ]) =>
      formatter.format(this);
}

String _formatMethod(String? method, int characterLength) =>
    method ?? '<omitted; $characterLength characters>';

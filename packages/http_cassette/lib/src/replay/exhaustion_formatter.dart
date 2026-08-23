import 'exhaustion_diagnostic.dart';

/// Deterministically formats safe replay exhaustion diagnostics as plain text.
final class ReplayExhaustionDiagnosticFormatter {
  /// Creates the internal default exhaustion formatter.
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
      'Cassette: ${_formatCassetteName(diagnostic.context.cassetteName.value)}',
      requestLine,
      groupLine,
      'Replay policy: ${details.replayPolicy.name}',
      'Recorded indices: ${_formatIndices(details.recordedIndices)}',
      'Network access: disabled; no real request was made',
    ].join('\n');
  }
}

/// Internal human-readable formatting for a replay exhaustion diagnostic.
extension ReplayExhaustionDiagnosticFormatting on ReplayExhaustionDiagnostic {
  /// Formats this diagnostic with [formatter].
  String format([
    ReplayExhaustionDiagnosticFormatter formatter =
        const ReplayExhaustionDiagnosticFormatter(),
  ]) =>
      formatter.format(this);
}

String _formatCassetteName(String name) {
  if (name.length <= _maximumCassetteNameLength) {
    return name;
  }
  return '${name.substring(0, _maximumCassetteNameLength)}... '
      '(${name.length} characters)';
}

String _formatMethod(String? method, int characterLength) =>
    method ?? '<omitted; $characterLength characters>';

String _formatIndices(List<int> indices) {
  final displayedCount = indices.length < _maximumDisplayedIndices
      ? indices.length
      : _maximumDisplayedIndices;
  final output = indices.take(displayedCount).join(', ');
  final omittedCount = indices.length - displayedCount;
  if (omittedCount == 0) {
    return output;
  }
  return '$output ... ($omittedCount omitted)';
}

const _maximumCassetteNameLength = 128;
const _maximumDisplayedIndices = 16;

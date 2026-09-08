import 'diagnostic_formatting.dart';
import 'no_match_diagnostic.dart';
import 'no_match_projection.dart';

/// Deterministically formats safe replay no-match diagnostics as plain text.
final class ReplayNoMatchDiagnosticFormatter {
  /// Creates the default no-match formatter.
  const ReplayNoMatchDiagnosticFormatter();

  /// Formats [diagnostic] without logging or inspecting canonical HTTP values.
  String format(ReplayNoMatchDiagnostic diagnostic) {
    final request = diagnostic.context.request;
    final method = request.method ??
        '<omitted; ${request.methodCharacterLength} characters>';
    final requestLine =
        'Request: method=$method; arrival=${request.arrivalIndex}; '
        'body=${request.bodyByteLength} bytes';
    final lines = <String>[
      'HTTP Cassette failure: ${diagnostic.envelope.summary}',
      'Category: ${diagnostic.envelope.category.name}',
      'Cassette: ${formatReplayDiagnosticCassetteName(diagnostic.context.cassetteName.value)}',
      requestLine,
      'Interactions considered: ${diagnostic.consideredInteractionCount}',
    ];
    final closest = diagnostic.closestComparison;
    if (closest == null) {
      lines.add('Closest interaction: none; cassette contains no interactions');
    } else {
      lines
        ..add('Closest interaction: #${diagnostic.closestRecordedIndex}')
        ..add('Built-in components:');
      for (final component in closest.builtInComponents) {
        lines.add(
          '  ${component.component.name}: ${component.state.name}'
          '${_formatDifferences(component.differences)}',
        );
      }
      _addCustomComponents(lines, closest.customComponents);
      lines.add(_formatBody(closest.body));
    }
    final matcher = diagnostic.matcher;
    final matcherLine = 'Matcher: method + URI + non-empty body; '
        'selected headers=${matcher.selectedHeaderCount}; '
        'ignored query parameters=${matcher.ignoredQueryParameterCount}; '
        'ignored JSON locations=${matcher.ignoredJsonLocationCount}; '
        'custom components=${matcher.customComponentCount}';
    lines
      ..add(matcherLine)
      ..add('Replay policy: ${diagnostic.replayPolicy.name}')
      ..add('Network access: disabled; no real request was made');
    return lines.join('\n');
  }
}

/// Human-readable formatting for a replay no-match diagnostic.
extension ReplayNoMatchDiagnosticFormatting on ReplayNoMatchDiagnostic {
  /// Formats this diagnostic with [formatter].
  String format([
    ReplayNoMatchDiagnosticFormatter formatter =
        const ReplayNoMatchDiagnosticFormatter(),
  ]) =>
      formatter.format(this);
}

String _formatDifferences(ReplayDifferenceFacts facts) {
  if (facts.totalCount == 0) {
    return '';
  }
  final displayed = facts.differences.take(_maximumDisplayedDifferences).map(
        (difference) => difference.locationSuppressed
            ? '${difference.kind.name} (location suppressed)'
            : difference.kind.name,
      );
  final displayedText = displayed.join(', ');
  final displayedCount = facts.differences.length < _maximumDisplayedDifferences
      ? facts.differences.length
      : _maximumDisplayedDifferences;
  final omittedCount = facts.totalCount - displayedCount;
  if (displayedText.isEmpty) {
    return '; differences=${facts.totalCount} (details omitted)';
  }
  if (omittedCount == 0) {
    return '; differences=$displayedText';
  }
  return '; differences=$displayedText ... ($omittedCount omitted)';
}

void _addCustomComponents(
  List<String> lines,
  List<ReplayCustomComponentFact> components,
) {
  if (components.isEmpty) {
    return;
  }
  lines.add('Custom components:');
  for (final component in components.take(_maximumDisplayedCustomComponents)) {
    lines.add(
      '  [${component.registrationIndex}]: '
      '${component.matches ? 'matched' : 'different'}'
      '${_formatDifferences(component.differences)}',
    );
  }
  final omittedCount = components.length - _maximumDisplayedCustomComponents;
  if (omittedCount > 0) {
    lines.add('  ... ($omittedCount custom components omitted)');
  }
}

String _formatBody(ReplayBodyComparisonFact body) {
  final facts = <String>['strategy=${body.kind.name}'];
  if (body.expectedLength case final expectedLength?) {
    facts.add('expected bytes=$expectedLength');
  }
  if (body.actualLength case final actualLength?) {
    facts.add('actual bytes=$actualLength');
  }
  if (body.firstDifferenceOffset case final firstDifferenceOffset?) {
    facts.add('first difference=$firstDifferenceOffset');
  }
  if (body.expectedJsonStatus case final expectedJsonStatus?) {
    facts.add('expected JSON=${expectedJsonStatus.name}');
  }
  if (body.actualJsonStatus case final actualJsonStatus?) {
    facts.add('actual JSON=${actualJsonStatus.name}');
  }
  return 'Body comparison: ${facts.join('; ')}';
}

const _maximumDisplayedCustomComponents = 8;
const _maximumDisplayedDifferences = 8;

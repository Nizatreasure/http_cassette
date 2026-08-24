import '../diagnostics/diagnostic.dart';
import '../matching/request_matcher.dart';
import 'configuration.dart';
import 'diagnostic_context.dart';
import 'matcher_description.dart';
import 'no_match.dart';
import 'no_match_projection.dart';

/// Complete location-safe structured information for a replay no-match failure.
final class ReplayNoMatchDiagnostic {
  /// Assembles a diagnostic without retaining the original match comparison.
  factory ReplayNoMatchDiagnostic({
    required ReplayDiagnosticContext context,
    required ReplayPolicy replayPolicy,
    required ReplayMatcherDescription matcher,
    required ReplayNoMatchDetails details,
  }) {
    final comparison = details.closestComparison;
    final closest = comparison == null
        ? null
        : ReplayNoMatchComparisonProjection.fromComparison(comparison);
    if (closest != null) {
      if (closest.customComponents.length != matcher.customComponentCount) {
        throw ArgumentError(
          'Matcher description must agree with the closest comparison.',
        );
      }
      final selectedHeaders = closest
          .builtInComponents[RequestMatchComponent.selectedHeaders.index];
      final selectedHeadersConfigured =
          selectedHeaders.state != RequestMatchComponentState.notConfigured;
      if (selectedHeadersConfigured != (matcher.selectedHeaderCount != 0)) {
        throw ArgumentError(
          'Matcher description must agree with the closest comparison.',
        );
      }
    }
    return ReplayNoMatchDiagnostic._(
      context: context,
      replayPolicy: replayPolicy,
      matcher: matcher,
      consideredInteractionCount: details.consideredInteractionCount,
      closestRecordedIndex: details.closestRecordedIndex,
      closestComparison: closest,
    );
  }

  ReplayNoMatchDiagnostic._({
    required this.context,
    required this.replayPolicy,
    required this.matcher,
    required this.consideredInteractionCount,
    required this.closestRecordedIndex,
    required this.closestComparison,
  }) : envelope = CassetteDiagnostic(
          category: DiagnosticCategory.noMatchingInteraction,
          summary: 'No recorded interaction matched the request.',
          networkAccess: NetworkAccess.disabled,
        );

  /// The validated logical cassette and value-free request context.
  final ReplayDiagnosticContext context;

  /// The policy active for the replay session.
  final ReplayPolicy replayPolicy;

  /// The active matcher represented without configured identifiers.
  final ReplayMatcherDescription matcher;

  /// The complete number of recorded interactions considered.
  final int consideredInteractionCount;

  /// The closest candidate's recorded index, or `null` for an empty cassette.
  final int? closestRecordedIndex;

  /// Location-suppressed facts for the closest candidate, when one exists.
  final ReplayNoMatchComparisonProjection? closestComparison;

  /// The common diagnostic envelope with fixed no-match semantics.
  final CassetteDiagnostic envelope;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReplayNoMatchDiagnostic &&
          context == other.context &&
          replayPolicy == other.replayPolicy &&
          matcher == other.matcher &&
          consideredInteractionCount == other.consideredInteractionCount &&
          closestRecordedIndex == other.closestRecordedIndex &&
          closestComparison == other.closestComparison;

  @override
  int get hashCode => Object.hash(
        context,
        replayPolicy,
        matcher,
        consideredInteractionCount,
        closestRecordedIndex,
        closestComparison,
      );
}

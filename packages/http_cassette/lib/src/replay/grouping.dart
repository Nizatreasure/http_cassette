import '../cassette/cassette.dart';
import '../cassette/interaction.dart';
import '../matching/ranking.dart';
import '../matching/request_matcher.dart';
import '../model/http_message.dart';

/// One complete request-matching evaluation over a recorded cassette.
final class ReplayRequestEvaluation {
  /// Creates an immutable evaluation from [matchingInteractions] and
  /// [candidates].
  ReplayRequestEvaluation({
    required Iterable<CassetteInteraction> matchingInteractions,
    required Iterable<RequestMatchCandidate> candidates,
  })  : matchingInteractions =
            List<CassetteInteraction>.unmodifiable(matchingInteractions),
        candidates = List<RequestMatchCandidate>.unmodifiable(candidates);

  /// Every matching interaction in recorded-index order.
  final List<CassetteInteraction> matchingInteractions;

  /// Every recorded interaction paired with its single stored comparison.
  final List<RequestMatchCandidate> candidates;
}

/// Evaluates [incoming] against every interaction exactly once.
ReplayRequestEvaluation evaluateReplayRequest({
  required Cassette cassette,
  required CassetteRequest incoming,
  required DefaultRequestMatcher matcher,
}) {
  final matches = <CassetteInteraction>[];
  final candidates = <RequestMatchCandidate>[];
  for (final interaction in cassette.interactions) {
    final comparison = matcher.compare(
      interaction.request,
      incoming,
      exclusions: interaction.matchingExclusions,
    );
    candidates.add(
      RequestMatchCandidate(
        recordedIndex: interaction.index,
        comparison: comparison,
      ),
    );
    if (comparison.matches) {
      matches.add(interaction);
    }
  }
  return ReplayRequestEvaluation(
    matchingInteractions: matches,
    candidates: candidates,
  );
}

/// Builds the immutable recorded-index-ordered group matching [incoming].
///
/// Every interaction is compared independently with its persisted matching
/// exclusions. Identical interactions are retained and no selection or
/// consumption state is applied.
List<CassetteInteraction> buildReplayMatchingGroup({
  required Cassette cassette,
  required CassetteRequest incoming,
  required DefaultRequestMatcher matcher,
}) {
  return evaluateReplayRequest(
    cassette: cassette,
    incoming: incoming,
    matcher: matcher,
  ).matchingInteractions;
}

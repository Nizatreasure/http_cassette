import '../cassette/cassette.dart';
import '../cassette/interaction.dart';
import '../matching/request_matcher.dart';
import '../model/http_message.dart';

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
  final matches = <CassetteInteraction>[];
  for (final interaction in cassette.interactions) {
    final comparison = matcher.compare(
      interaction.request,
      incoming,
      exclusions: interaction.matchingExclusions,
    );
    if (comparison.matches) {
      matches.add(interaction);
    }
  }
  return List<CassetteInteraction>.unmodifiable(matches);
}

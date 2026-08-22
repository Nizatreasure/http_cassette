import '../configuration/matching_configuration.dart';
import '../matching/exclusions.dart';
import '../matching/request_matcher.dart';
import '../model/http_message.dart';
import 'configuration.dart';

/// Immutable output from ordered custom request sanitisation.
final class CustomRequestSanitisationResult {
  const CustomRequestSanitisationResult._({
    required this.request,
    required this.exclusions,
  });

  /// The request returned by the final custom sanitiser.
  final CassetteRequest request;

  /// The union of exclusions reported by every custom sanitiser.
  final MatchingExclusions exclusions;
}

/// Runs configured custom request sanitisers in registration order.
///
/// Each sanitiser receives the preceding sanitiser's request. A changed
/// request must match its input under the exclusions reported by that same
/// sanitiser, otherwise this function fails without returning a result.
CustomRequestSanitisationResult sanitiseCustomRequest(
  CassetteRequest request,
  SanitisationConfiguration configuration,
) {
  var current = request;
  var accumulatedExclusions = MatchingExclusions.none;

  for (var index = 0; index < configuration.requestSanitisers.length; index++) {
    final result = configuration.requestSanitisers[index].sanitise(current);
    _validateRequestChange(current, result.request, result.exclusions, index);
    current = result.request;
    accumulatedExclusions = accumulatedExclusions.mergedWith(
      result.exclusions,
    );
  }

  return CustomRequestSanitisationResult._(
    request: current,
    exclusions: accumulatedExclusions,
  );
}

void _validateRequestChange(
  CassetteRequest before,
  CassetteRequest after,
  MatchingExclusions exclusions,
  int sanitiserIndex,
) {
  final includedHeaders = <String>{
    ...before.headers.names,
    ...after.headers.names,
  };
  final matcher = DefaultRequestMatcher(
    configuration: MatchingConfiguration(includedHeaders: includedHeaders),
    maximumDifferencesPerComponent: 0,
  );
  if (!matcher.compare(before, after, exclusions: exclusions).matches) {
    throw StateError(
      'Custom request sanitiser at index $sanitiserIndex changed request data '
      'without complete matching exclusions.',
    );
  }
}

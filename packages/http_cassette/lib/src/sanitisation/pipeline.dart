import '../configuration/body_limits.dart';
import '../configuration/matching_configuration.dart';
import '../matching/exclusions.dart';
import '../matching/request_matcher.dart';
import '../model/http_message.dart';
import 'configuration.dart';
import 'messages.dart';

/// Immutable output from the complete request sanitisation pipeline.
final class RequestSanitisationResult {
  const RequestSanitisationResult._({
    required this.request,
    required this.exclusions,
  });

  /// The canonical request after custom and built-in sanitisation.
  final CassetteRequest request;

  /// The union of every custom and built-in matching exclusion.
  final MatchingExclusions exclusions;
}

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

/// Runs the complete custom-then-built-in request sanitisation pipeline.
RequestSanitisationResult sanitiseRequest(
  CassetteRequest request,
  SanitisationConfiguration configuration,
) {
  final custom = sanitiseCustomRequest(request, configuration);
  final builtIn = sanitiseBuiltInRequest(custom.request, configuration);
  return RequestSanitisationResult._(
    request: builtIn.request,
    exclusions: custom.exclusions.mergedWith(builtIn.exclusions),
  );
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

/// Runs configured custom response sanitisers in registration order.
///
/// Each sanitiser receives the preceding sanitiser's canonical response. If a
/// sanitiser throws, later sanitisers are not invoked.
CassetteResponse sanitiseCustomResponse(
  CassetteResponse response,
  SanitisationConfiguration configuration,
) {
  var current = response;
  for (final sanitiser in configuration.responseSanitisers) {
    current = sanitiser.sanitise(current);
  }
  return current;
}

/// Runs the complete custom-then-built-in response sanitisation pipeline.
CassetteResponse sanitiseResponse(
  CassetteResponse response,
  SanitisationConfiguration configuration, {
  int maximumTransformedBodyBytes = BodyLimits.defaultResponseBytes,
}) =>
    sanitiseBuiltInResponse(
      sanitiseCustomResponse(response, configuration),
      configuration,
      maximumTransformedBodyBytes: maximumTransformedBodyBytes,
    );

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

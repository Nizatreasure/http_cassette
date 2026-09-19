import '../cassette/interaction.dart';
import '../model/outcome.dart';
import '../sanitisation/configuration.dart';
import '../sanitisation/pipeline.dart';
import 'request_attempt.dart';

/// Sanitises one transient recording [result] into a persistable interaction.
///
/// The returned interaction contains no unsanitised request or response data.
CassetteInteraction sanitiseRecordingResult(
  RecordingRequestResult result,
  SanitisationConfiguration configuration, {
  required int maximumDecodedResponseBodyBytes,
}) {
  final request = sanitiseRequest(result.request, configuration);
  final outcome = switch (result.outcome) {
    CassetteResponseOutcome(:final response) => CassetteResponseOutcome(
        sanitiseResponse(
          response,
          configuration,
          maximumDecodedBodyBytes: maximumDecodedResponseBodyBytes,
        ),
      ),
    final CassetteTransportFailure failure => failure,
  };
  return CassetteInteraction(
    index: result.arrivalIndex,
    request: request.request,
    matchingExclusions: request.exclusions,
    outcome: outcome,
  );
}

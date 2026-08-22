import '../matching/exclusions.dart';
import '../model/http_message.dart';

/// A transport-neutral extension that sanitises one canonical request.
///
/// Implementations must return every changed match-relevant location through
/// [SanitisedRequest.exclusions]. They must be deterministic, avoid logging
/// their input and return valid canonical data.
abstract interface class RequestSanitiser {
  /// Returns a safe request and the locations whose values changed.
  SanitisedRequest sanitise(CassetteRequest request);
}

/// A transport-neutral extension that sanitises one canonical response.
///
/// Implementations must be deterministic, avoid logging their input and return
/// a valid canonical response.
abstract interface class ResponseSanitiser {
  /// Returns a safe canonical response.
  CassetteResponse sanitise(CassetteResponse response);
}

/// The immutable output of a custom [RequestSanitiser].
final class SanitisedRequest {
  /// Creates a custom sanitisation result.
  const SanitisedRequest({
    required this.request,
    required this.exclusions,
  });

  /// The valid canonical request returned by the sanitiser.
  final CassetteRequest request;

  /// Every match-relevant request location changed by the sanitiser.
  final MatchingExclusions exclusions;
}

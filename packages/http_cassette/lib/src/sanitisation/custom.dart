import '../matching/exclusions.dart';
import '../model/http_message.dart';

/// Replaces domain-specific sensitive data in one canonical request.
///
/// The sanitiser runs in registration order before built-in rules. It must be
/// deterministic, must not log or retain input values, and must report every
/// changed match-relevant location through [SanitisedRequest.exclusions]. The
/// pipeline rejects an incomplete exclusion report.
abstract interface class RequestSanitiser {
  /// Returns a safe request and every location whose match-relevant value
  /// changed.
  SanitisedRequest sanitise(CassetteRequest request);
}

/// Replaces domain-specific sensitive data in one canonical response.
///
/// The sanitiser runs in registration order before built-in rules. It must be
/// deterministic, must not log or retain input values, and must return a valid
/// canonical response.
abstract interface class ResponseSanitiser {
  /// Returns a safe canonical response.
  CassetteResponse sanitise(CassetteResponse response);
}

/// The immutable output of a custom [RequestSanitiser].
final class SanitisedRequest {
  /// Creates a result containing the safe [request] and its [exclusions].
  const SanitisedRequest({
    required this.request,
    required this.exclusions,
  });

  /// The valid canonical request returned by the sanitiser.
  final CassetteRequest request;

  /// Every match-relevant request location changed by the sanitiser.
  final MatchingExclusions exclusions;
}

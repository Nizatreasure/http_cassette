import '../safety/safe_text.dart';
import 'http_message.dart';

/// A transport-neutral category for a failed HTTP operation.
enum TransportFailureCategory {
  /// The remote host name could not be resolved.
  nameResolution,

  /// A connection could not be established or was interrupted.
  connection,

  /// A secure connection could not be established or maintained.
  secureConnection,

  /// The transport operation exceeded its time limit.
  timeout,

  /// The peer sent or received invalid protocol data.
  protocol,

  /// The failure does not fit another portable category.
  other,
}

/// The transport result recorded for an HTTP request.
///
/// An outcome is either an HTTP response or a portable transport failure.
/// Caller-initiated cancellation and cassette-system failures are not outcomes.
sealed class CassetteOutcome {
  const CassetteOutcome();
}

/// A successfully received HTTP response outcome.
final class CassetteResponseOutcome extends CassetteOutcome {
  /// Creates an outcome containing [response].
  const CassetteResponseOutcome(this.response);

  /// The canonical response received from the transport.
  final CassetteResponse response;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CassetteResponseOutcome && response == other.response;

  @override
  int get hashCode => response.hashCode;
}

/// A portable transport-failure outcome.
///
/// The [message] must be a trimmed, non-empty single line containing no more
/// than 256 Unicode code points. It must be written from safe, sanitised
/// context rather than copied from an arbitrary transport exception.
final class CassetteTransportFailure extends CassetteOutcome {
  /// Creates a validated transport failure.
  CassetteTransportFailure({
    required this.category,
    required String message,
  }) : message = validateSafeSingleLine(
          message,
          description: 'Transport failure message',
        );

  /// The portable kind of transport failure.
  final TransportFailureCategory category;

  /// A concise, safe description of the failure.
  final String message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CassetteTransportFailure &&
          category == other.category &&
          message == other.message;

  @override
  int get hashCode => Object.hash(category, message);
}

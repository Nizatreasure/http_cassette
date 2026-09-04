import 'package:http/http.dart' as http;
import 'package:http_cassette/http_cassette.dart';

/// Provides access to safe core failures carried by HTTP client exceptions.
extension HttpCassetteClientException on http.ClientException {
  /// The cassette-system failure carried by this exception, when present.
  ///
  /// Ordinary client failures, cancellation and replayed transport failures
  /// return `null`.
  CassetteException? get cassetteException => switch (this) {
        _CassetteSystemClientException(:final failure) => failure,
        _ => null,
      };

  /// The portable recorded transport failure carried during replay.
  ///
  /// Ordinary client failures, cancellation and cassette-system failures
  /// return `null`.
  CassetteTransportFailure? get cassetteTransportFailure => switch (this) {
        _CassetteTransportClientException(:final failure) => failure,
        _ => null,
      };
}

/// Wraps one safe cassette-system [failure] for `package:http` callers.
http.ClientException wrapCassetteExceptionForHttp(CassetteException failure) =>
    _CassetteSystemClientException(failure);

/// Wraps one portable replay [failure] for `package:http` callers.
http.ClientException wrapHttpTransportFailureForReplay(
  CassetteTransportFailure failure,
) =>
    _CassetteTransportClientException(failure);

final class _CassetteSystemClientException extends http.ClientException {
  _CassetteSystemClientException(this.failure) : super(failure.toString());

  final CassetteException failure;
}

final class _CassetteTransportClientException extends http.ClientException {
  _CassetteTransportClientException(this.failure) : super(failure.message);

  final CassetteTransportFailure failure;
}

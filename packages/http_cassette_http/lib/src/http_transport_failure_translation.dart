import 'package:http/http.dart' as http;
import 'package:http_cassette/http_cassette.dart';

import 'http_client_exception.dart';

/// Translates a recordable `http` [failure] to a portable outcome.
///
/// `ClientException` exposes no stable typed cause or failure category, so the
/// adapter uses the conservative portable fallback without inspecting its
/// message or URI. Caller cancellation is not a recordable outcome.
CassetteTransportFailure translateHttpTransportFailure(
  http.ClientException failure,
) {
  if (failure is http.RequestAbortedException) {
    throw ArgumentError(
      'Caller cancellation is not a recordable transport failure.',
    );
  }

  return CassetteTransportFailure(
    category: TransportFailureCategory.other,
    message: 'The HTTP transport failed.',
  );
}

/// Reconstructs a portable replay [failure] as an HTTP client exception.
///
/// The safe canonical message and exact portable failure remain available,
/// while the potentially sensitive request URI is deliberately omitted.
http.ClientException reconstructHttpTransportFailure(
  CassetteTransportFailure failure,
) =>
    wrapHttpTransportFailureForReplay(failure);

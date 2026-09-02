import 'package:http/http.dart' as http;
import 'package:http_cassette/http_cassette.dart';

/// Translates a recordable `package:http` [failure] to a portable outcome.
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

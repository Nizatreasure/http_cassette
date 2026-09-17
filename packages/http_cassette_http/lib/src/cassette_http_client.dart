import 'package:http/http.dart' as http;
import 'package:http_cassette/http_cassette.dart';

import 'http_byte_stream_buffer.dart';
import 'http_client_exception.dart';
import 'http_request_buffer.dart';
import 'http_request_translation.dart';
import 'http_response_translation.dart';
import 'http_transport_failure_translation.dart';

/// An `http` client connected to one shared [CassetteEngine].
///
/// While [engine] has no active session, requests pass directly to the inner
/// client without inspection or finalisation. Recording uses the inner client
/// only when the core authorises one real attempt. Replay never uses it.
///
/// Active requests and responses are completely buffered within the engine's
/// body limits. Place request-changing or per-attempt retry middleware outside
/// this client when each resulting request must be visible to the cassette.
/// Custom request-subclass state beyond the public [http.BaseRequest]
/// properties is not preserved on the active replacement request.
///
/// The wrapper owns its inner client. Calling [close] closes that client at
/// most once, including when it was supplied by the caller.
final class CassetteHttpClient extends http.BaseClient {
  /// Creates a cassette-aware HTTP client.
  ///
  /// When [inner] is omitted, a normal [http.Client] is created. A supplied
  /// client is still owned and closed by this wrapper.
  CassetteHttpClient(
    this.engine, {
    http.Client? inner,
  }) : _inner = inner ?? http.Client();

  /// The engine whose current session controls interception.
  final CassetteEngine engine;

  final http.Client _inner;
  var _isClosed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final interception = engine.beginInterception();
    if (!interception.isActive) {
      return _inner.send(request);
    }

    late final BufferedHttpRequest buffered;
    try {
      buffered = await bufferHttpRequest(
        request,
        maximumBytes: interception.bodyLimits!.requestBytes,
      );
    } on HttpByteStreamLimitExceeded {
      throw wrapCassetteExceptionForHttp(_requestBodyLimitException());
    } on HttpByteStreamBufferCancelled {
      throw http.RequestAbortedException(request.url);
    } on Object {
      throw wrapCassetteExceptionForHttp(_invalidRequestStreamException());
    }

    late final CassetteRequest canonicalRequest;
    try {
      canonicalRequest = canonicaliseHttpRequest(request, buffered.bytes);
    } on ArgumentError {
      throw wrapCassetteExceptionForHttp(_invalidRequestException());
    }

    http.StreamedResponse? liveResponse;
    http.ClientException? liveFailure;
    late final CassetteOutcome outcome;
    try {
      outcome = await interception.proceed(
        canonicalRequest,
        () async {
          try {
            final response = await _inner.send(buffered.replacementRequest);
            late final CapturedHttpResponse captured;
            try {
              captured = await captureHttpResponse(
                response,
                request: request,
                maximumBytes: interception.bodyLimits!.responseBytes,
                cancellation: buffered.cancellation?.whenCancelled,
              );
            } on HttpByteStreamLimitExceeded {
              throw _responseBodyLimitException();
            }
            liveResponse = captured.replacementResponse;
            return CassetteResponseOutcome(captured.canonicalResponse);
          } on http.RequestAbortedException {
            rethrow;
          } on http.ClientException catch (failure) {
            liveFailure = failure;
            return translateHttpTransportFailure(failure);
          }
        },
        cancellation: buffered.cancellation,
      );
    } on CassetteException catch (failure) {
      if (failure.diagnostic.category == DiagnosticCategory.cancelled) {
        throw http.RequestAbortedException(request.url);
      }
      if (liveResponse case final response?) {
        return response;
      }
      throw wrapCassetteExceptionForHttp(failure);
    } on Object {
      if (liveResponse case final response?) {
        return response;
      }
      rethrow;
    }

    return switch (outcome) {
      CassetteResponseOutcome(:final response) =>
        liveResponse ?? reconstructHttpResponse(response, request: request),
      final CassetteTransportFailure failure =>
        throw liveFailure ?? reconstructHttpTransportFailure(failure),
    };
  }

  @override
  void close() {
    if (_isClosed) {
      return;
    }
    _isClosed = true;
    _inner.close();
  }
}

CassetteException _requestBodyLimitException() => CassetteException(
      CassetteDiagnostic(
        category: DiagnosticCategory.bodyLimitExceeded,
        summary:
            'The HTTP request body exceeded its configured cassette limit.',
        networkAccess: NetworkAccess.notAttempted,
      ),
    );

CassetteException _responseBodyLimitException() => CassetteException(
      CassetteDiagnostic(
        category: DiagnosticCategory.bodyLimitExceeded,
        summary:
            'The HTTP response body exceeded its configured cassette limit.',
        networkAccess: NetworkAccess.attempted,
      ),
    );

CassetteException _invalidRequestException() => CassetteException(
      CassetteDiagnostic(
        category: DiagnosticCategory.invalidCanonicalRequest,
        summary: 'The client request could not form a canonical HTTP request.',
        networkAccess: NetworkAccess.notAttempted,
      ),
    );

CassetteException _invalidRequestStreamException() => CassetteException(
      CassetteDiagnostic(
        category: DiagnosticCategory.adapterContractViolation,
        summary: 'The client request stream could not be captured.',
        networkAccess: NetworkAccess.notAttempted,
      ),
    );

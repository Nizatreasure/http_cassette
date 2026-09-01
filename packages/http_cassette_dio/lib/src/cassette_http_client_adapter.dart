import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http_cassette/http_cassette.dart';

import 'dio_byte_stream_buffer.dart';
import 'dio_cassette_exception.dart';
import 'dio_request_body_buffer.dart';
import 'dio_request_translation.dart';

/// Connects Dio's final transport boundary to a shared [CassetteEngine].
///
/// Requests pass through unchanged while [engine] is inactive. Active request
/// execution is not implemented yet, so active requests fail before [inner]
/// can access the network.
final class CassetteHttpClientAdapter implements HttpClientAdapter {
  /// Creates a cassette adapter that owns [inner] for Dio's lifetime.
  CassetteHttpClientAdapter({
    required this.engine,
    required this.inner,
  });

  /// The engine whose current session controls interception.
  final CassetteEngine engine;

  /// The Dio adapter used for authorised real HTTP attempts.
  final HttpClientAdapter inner;

  var _isClosed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final interception = engine.beginInterception();
    if (!interception.isActive) {
      return inner.fetch(options, requestStream, cancelFuture);
    }

    final cancellationError = options.cancelToken?.cancelError;
    if (cancellationError != null) {
      throw cancellationError;
    }

    final maximumBytes = interception.bodyLimits!.requestBytes;
    if (_declaredContentLength(options) case final declaredLength?
        when requestStream != null && declaredLength > maximumBytes) {
      throw _requestBodyLimitException(options);
    }

    late final BufferedDioRequestBody bufferedBody;
    try {
      bufferedBody = await bufferDioRequestBody(
        requestStream,
        maximumBytes: maximumBytes,
        cancellation: cancelFuture,
      );
    } on DioByteStreamLimitExceeded {
      throw _requestBodyLimitException(options);
    } on DioByteStreamBufferCancelled catch (_, stackTrace) {
      throw DioException.requestCancelled(
        requestOptions: options,
        reason: options.cancelToken?.cancelError,
        stackTrace: stackTrace,
      );
    }

    canonicaliseDioRequest(options, bufferedBody.bytes);
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.unknown,
      message: 'Active HTTP Cassette Dio execution is not available yet.',
    );
  }

  @override
  void close({bool force = false}) {
    if (_isClosed) {
      return;
    }
    _isClosed = true;
    inner.close(force: force);
  }
}

int? _declaredContentLength(RequestOptions options) {
  final value = options.headers[Headers.contentLengthHeader];
  return switch (value) {
    final int length when length >= 0 => length,
    final String text => int.tryParse(text),
    _ => null,
  };
}

DioException _requestBodyLimitException(RequestOptions options) {
  final error = CassetteException(
    CassetteDiagnostic(
      category: DiagnosticCategory.bodyLimitExceeded,
      summary: 'The HTTP request body exceeded its configured cassette limit.',
      networkAccess: NetworkAccess.notAttempted,
    ),
  );
  return wrapCassetteExceptionForDio(
    error,
    requestOptions: options,
  );
}

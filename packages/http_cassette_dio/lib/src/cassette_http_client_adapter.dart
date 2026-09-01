import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http_cassette/http_cassette.dart';

import 'dio_byte_stream_buffer.dart';
import 'dio_cancellation.dart';
import 'dio_cassette_exception.dart';
import 'dio_request_body_buffer.dart';
import 'dio_request_translation.dart';
import 'dio_response_translation.dart';
import 'dio_transport_failure_translation.dart';

/// Connects Dio's final transport boundary to a shared [CassetteEngine].
///
/// Requests pass through unchanged while [engine] is inactive. Recording uses
/// [inner] only when the core authorises one real attempt. Replay never uses
/// [inner].
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

    final cancellation = createDioCassetteCancellation(options, cancelFuture);
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
        cancellation: cancellation?.whenCancelled,
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

    late final CassetteRequest request;
    try {
      request = canonicaliseDioRequest(options, bufferedBody.bytes);
    } on ArgumentError catch (_, stackTrace) {
      throw wrapCassetteExceptionForDio(
        _invalidRequestException(),
        requestOptions: options,
        stackTrace: stackTrace,
      );
    }

    ResponseBody? liveResponse;
    DioException? liveFailure;
    late final CassetteOutcome outcome;
    try {
      outcome = await interception.proceed(
        request,
        () async {
          try {
            final response = await inner.fetch(
              options,
              bufferedBody.replacementStream,
              cancelFuture,
            );
            late final CapturedDioResponse captured;
            try {
              captured = await captureDioResponse(
                response,
                maximumBytes: interception.bodyLimits!.responseBytes,
                cancellation: cancellation?.whenCancelled,
              );
            } on DioByteStreamLimitExceeded {
              throw _responseBodyLimitException();
            }
            liveResponse = captured.replacementResponse;
            return CassetteResponseOutcome(captured.canonicalResponse);
          } on DioException catch (failure) {
            if (failure.type == DioExceptionType.cancel ||
                failure.type == DioExceptionType.badResponse) {
              rethrow;
            }
            liveFailure = failure;
            return translateDioTransportFailure(failure);
          }
        },
        cancellation: cancellation,
      );
    } on CassetteException catch (failure, stackTrace) {
      if (failure.diagnostic.category == DiagnosticCategory.cancelled) {
        throw options.cancelToken?.cancelError ??
            DioException.requestCancelled(
              requestOptions: options,
              reason: null,
              stackTrace: stackTrace,
            );
      }
      throw wrapCassetteExceptionForDio(
        failure,
        requestOptions: options,
        stackTrace: stackTrace,
      );
    }

    return switch (outcome) {
      CassetteResponseOutcome(:final response) =>
        liveResponse ?? reconstructDioResponse(response),
      final CassetteTransportFailure failure =>
        throw liveFailure ?? reconstructDioTransportFailure(failure, options),
    };
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
        summary: 'Dio request data could not form a canonical HTTP request.',
        networkAccess: NetworkAccess.notAttempted,
      ),
    );

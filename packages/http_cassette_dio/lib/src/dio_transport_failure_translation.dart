import 'package:dio/dio.dart';
import 'package:http_cassette/http_cassette.dart';

/// Translates a recordable `dio` transport [failure] into a portable outcome.
///
/// Caller cancellation and status-based `badResponse` failures are not
/// transport failures and must be handled before calling this function.
CassetteTransportFailure translateDioTransportFailure(DioException failure) {
  final type = failure.type;
  if (type == DioExceptionType.cancel) {
    throw ArgumentError(
      'Caller cancellation is not a recordable transport failure.',
    );
  }
  if (type == DioExceptionType.badResponse) {
    throw ArgumentError(
      'A rejected HTTP status is a response, not a transport failure.',
    );
  }

  if (type.name.endsWith('Timeout')) {
    return CassetteTransportFailure(
      category: TransportFailureCategory.timeout,
      message: 'The HTTP transport operation timed out.',
    );
  }

  return switch (type) {
    DioExceptionType.badCertificate => CassetteTransportFailure(
        category: TransportFailureCategory.secureConnection,
        message: 'The secure HTTP connection failed.',
      ),
    DioExceptionType.connectionError => CassetteTransportFailure(
        category: TransportFailureCategory.connection,
        message: 'The HTTP connection failed.',
      ),
    _ => CassetteTransportFailure(
        category: TransportFailureCategory.other,
        message: 'The HTTP transport failed.',
      ),
  };
}

/// Reconstructs a portable replay [failure] as the closest `dio` exception.
DioException reconstructDioTransportFailure(
  CassetteTransportFailure failure,
  RequestOptions requestOptions,
) {
  final type = switch (failure.category) {
    TransportFailureCategory.nameResolution ||
    TransportFailureCategory.connection =>
      DioExceptionType.connectionError,
    TransportFailureCategory.secureConnection =>
      DioExceptionType.badCertificate,
    TransportFailureCategory.timeout => DioExceptionType.connectionTimeout,
    TransportFailureCategory.protocol ||
    TransportFailureCategory.other =>
      DioExceptionType.unknown,
  };

  return DioException(
    requestOptions: requestOptions,
    type: type,
    error: failure,
    message: failure.message,
  );
}

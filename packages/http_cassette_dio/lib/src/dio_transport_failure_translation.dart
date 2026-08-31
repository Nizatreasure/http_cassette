import 'package:dio/dio.dart';
import 'package:http_cassette/http_cassette.dart';

/// Translates a recordable Dio transport [failure] into a portable outcome.
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

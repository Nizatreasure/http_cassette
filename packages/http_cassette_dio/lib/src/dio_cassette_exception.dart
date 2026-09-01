import 'package:dio/dio.dart';
import 'package:http_cassette/http_cassette.dart';

/// Provides access to a structured HTTP Cassette system failure.
extension HttpCassetteDioException on DioException {
  /// The safe core cassette failure carried by this exception, when present.
  ///
  /// Ordinary Dio failures and replayed transport failures return `null`.
  CassetteException? get cassetteException => switch (error) {
        final CassetteException failure => failure,
        _ => null,
      };
}

/// Wraps one safe cassette-system [failure] for Dio's error pipeline.
DioException wrapCassetteExceptionForDio(
  CassetteException failure, {
  required RequestOptions requestOptions,
  StackTrace? stackTrace,
}) =>
    DioException(
      requestOptions: requestOptions,
      type: DioExceptionType.unknown,
      error: failure,
      stackTrace: stackTrace,
      message: failure.toString(),
    );

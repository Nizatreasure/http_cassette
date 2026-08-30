import 'package:dio/dio.dart';
import 'package:http_cassette/http_cassette.dart';

/// Connects Dio request interception to a shared [CassetteEngine].
///
/// Requests pass through unchanged while the engine is inactive. Active
/// recording and replay translation is not implemented yet, so active requests
/// fail before Dio can access the network.
final class CassetteDioInterceptor extends Interceptor {
  /// Creates an interceptor backed by [engine].
  CassetteDioInterceptor(this.engine);

  /// The engine whose current session controls interception.
  final CassetteEngine engine;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final interception = engine.beginInterception();
    if (!interception.isActive) {
      handler.next(options);
      return;
    }

    handler.reject(
      DioException(
        requestOptions: options,
        type: DioExceptionType.unknown,
        message: 'Active HTTP Cassette Dio interception is not available yet.',
      ),
    );
  }
}

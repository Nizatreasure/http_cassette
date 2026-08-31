import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http_cassette/http_cassette.dart';

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
  ) {
    final interception = engine.beginInterception();
    if (!interception.isActive) {
      return inner.fetch(options, requestStream, cancelFuture);
    }

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

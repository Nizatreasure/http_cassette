import 'package:dio/dio.dart';
import 'package:http_cassette/http_cassette.dart';

import 'cassette_http_client_adapter.dart';

/// Installs HTTP Cassette at Dio's final transport boundary.
extension HttpCassetteDioInstallation on Dio {
  /// Wraps the currently configured [Dio.httpClientAdapter] with [engine].
  ///
  /// Configure a custom underlying adapter before calling this method.
  /// Installing HTTP Cassette more than once on the same Dio instance throws a
  /// [StateError]. Assigning another adapter afterwards replaces this
  /// integration.
  void installHttpCassette(CassetteEngine engine) {
    final currentAdapter = httpClientAdapter;
    if (currentAdapter is CassetteHttpClientAdapter) {
      throw StateError(
          'HTTP Cassette is already installed on this Dio client.');
    }
    httpClientAdapter = CassetteHttpClientAdapter(
      engine: engine,
      inner: currentAdapter,
    );
  }
}

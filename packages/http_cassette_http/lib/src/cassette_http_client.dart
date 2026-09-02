import 'package:http/http.dart' as http;
import 'package:http_cassette/http_cassette.dart';

/// A `package:http` client connected to one shared [CassetteEngine].
///
/// While [engine] has no active session, requests pass directly to the inner
/// client without inspection or finalisation. Active recording and replay are
/// not available until their request and response translation is implemented.
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
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final interception = engine.beginInterception();
    if (!interception.isActive) {
      return _inner.send(request);
    }

    throw StateError(
      'Active package:http cassette execution is not implemented yet.',
    );
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

import 'package:http/http.dart' as http;
import 'package:http_cassette/http_cassette.dart';

/// Adapts an `http` abort trigger to the core cancellation contract.
final class HttpCassetteCancellation implements CassetteCancellation {
  HttpCassetteCancellation._(this.abortTrigger) {
    _whenCancelled = abortTrigger.then<void>(
      (_) {
        _isCancelled = true;
      },
      onError: (Object _, StackTrace __) {
        throw const HttpAbortTriggerFailure();
      },
    );
  }

  /// The exact trigger supplied by the original abortable request.
  final Future<void> abortTrigger;

  var _isCancelled = false;
  late final Future<void> _whenCancelled;

  @override
  bool get isCancelled => _isCancelled;

  @override
  Future<void> get whenCancelled => _whenCancelled;
}

/// Creates a core cancellation view for an abortable HTTP [request].
///
/// Ordinary requests and abortable requests without a trigger return `null`.
HttpCassetteCancellation? createHttpCassetteCancellation(
  http.BaseRequest request,
) {
  if (request case http.Abortable(:final abortTrigger?)) {
    return HttpCassetteCancellation._(abortTrigger);
  }
  return null;
}

/// Signals that an abort trigger broke the `http` contract.
///
/// Abort triggers must complete normally. This value-free signal prevents an
/// error carried by a custom trigger from crossing the adapter boundary.
final class HttpAbortTriggerFailure implements Exception {
  /// Creates a safe value-free signal.
  const HttpAbortTriggerFailure();
}

import 'package:dio/dio.dart';
import 'package:http_cassette/http_cassette.dart';

/// Adapts Dio's monotonic cancellation state to the core contract.
final class DioCassetteCancellation implements CassetteCancellation {
  DioCassetteCancellation._({
    required bool isCancelled,
    required Future<void> cancellation,
  }) : _isCancelled = isCancelled {
    _whenCancelled = isCancelled
        ? Future<void>.value()
        : cancellation.then<void>((_) {
            _isCancelled = true;
          });
  }

  var _isCancelled = false;
  late final Future<void> _whenCancelled;

  @override
  bool get isCancelled => _isCancelled;

  @override
  Future<void> get whenCancelled => _whenCancelled;
}

/// Creates a core cancellation view when Dio supplied cancellation state.
DioCassetteCancellation? createDioCassetteCancellation(
  RequestOptions options,
  Future<void>? cancelFuture,
) {
  final token = options.cancelToken;
  if (token == null && cancelFuture == null) {
    return null;
  }

  final cancellation = cancelFuture ?? token!.whenCancel.then<void>((_) {});
  return DioCassetteCancellation._(
    isCancelled: token?.isCancelled ?? false,
    cancellation: cancellation,
  );
}

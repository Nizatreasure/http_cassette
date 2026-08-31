import 'dart:async';
import 'dart:typed_data';

/// The completed bytes and equivalent replacement stream for one Dio body.
typedef BufferedDioRequestBody = ({
  Uint8List bytes,
  Stream<Uint8List>? replacementStream,
});

/// Buffers [stream] once without retaining more than [maximumBytes].
///
/// A null stream produces an empty body and null replacement. A non-null stream
/// always produces a non-null replacement with the same complete byte sequence.
/// [DioRequestBodyLimitExceeded] and [DioRequestBodyBufferCancelled] are safe
/// internal control failures for the transport adapter to map.
Future<BufferedDioRequestBody> bufferDioRequestBody(
  Stream<Uint8List>? stream, {
  required int maximumBytes,
  Future<void>? cancellation,
}) async {
  if (stream == null) {
    return (
      bytes: Uint8List(0),
      replacementStream: null,
    );
  }

  final builder = BytesBuilder();
  final completion = Completer<Uint8List>();
  late final StreamSubscription<Uint8List> subscription;
  var settled = false;
  var subscriptionIsReady = false;
  Object? pendingError;
  StackTrace? pendingStackTrace;

  Future<void> completeFailure(Object error, StackTrace stackTrace) async {
    await subscription.cancel();
    completion.completeError(error, stackTrace);
  }

  void fail(Object error, [StackTrace? stackTrace]) {
    if (settled) {
      return;
    }
    settled = true;
    final resolvedStackTrace = stackTrace ?? StackTrace.current;
    if (subscriptionIsReady) {
      unawaited(completeFailure(error, resolvedStackTrace));
      return;
    }
    pendingError = error;
    pendingStackTrace = resolvedStackTrace;
  }

  subscription = stream.listen(
    (chunk) {
      if (settled) {
        return;
      }
      if (chunk.length > maximumBytes - builder.length) {
        fail(const DioRequestBodyLimitExceeded());
        return;
      }
      builder.add(chunk);
    },
    onError: (Object error, StackTrace stackTrace) {
      fail(error, stackTrace);
    },
    onDone: () {
      if (settled) {
        return;
      }
      settled = true;
      completion.complete(builder.takeBytes());
    },
    cancelOnError: true,
  );

  subscriptionIsReady = true;
  if (pendingError case final error?) {
    unawaited(completeFailure(error, pendingStackTrace!));
  }
  final cancellationFuture = cancellation;
  if (cancellationFuture != null) {
    unawaited(
      cancellationFuture.then((_) {
        fail(const DioRequestBodyBufferCancelled());
      }),
    );
  }

  final bytes = await completion.future;
  return (
    bytes: bytes,
    replacementStream: Stream<Uint8List>.fromIterable(
      bytes.isEmpty ? const <Uint8List>[] : <Uint8List>[bytes],
    ),
  );
}

/// Signals that a Dio request body exceeded its active cassette limit.
final class DioRequestBodyLimitExceeded implements Exception {
  /// Creates the value-free internal signal.
  const DioRequestBodyLimitExceeded();
}

/// Signals cancellation while an active Dio request body was being buffered.
final class DioRequestBodyBufferCancelled implements Exception {
  /// Creates the value-free internal signal.
  const DioRequestBodyBufferCancelled();
}

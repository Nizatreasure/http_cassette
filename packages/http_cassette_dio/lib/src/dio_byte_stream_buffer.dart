import 'dart:async';
import 'dart:typed_data';

/// Buffers one Dio byte [stream] without retaining more than [maximumBytes].
///
/// [DioByteStreamLimitExceeded] and [DioByteStreamBufferCancelled] are safe
/// internal control failures for the transport adapter to map.
Future<Uint8List> bufferDioByteStream(
  Stream<Uint8List> stream, {
  required int maximumBytes,
  Future<void>? cancellation,
}) async {
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
        fail(const DioByteStreamLimitExceeded());
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
        fail(const DioByteStreamBufferCancelled());
      }),
    );
  }

  return completion.future;
}

/// Creates one single-subscription stream with the complete [bytes] sequence.
Stream<Uint8List> createDioByteStream(Uint8List bytes) =>
    Stream<Uint8List>.fromIterable(
      bytes.isEmpty ? const <Uint8List>[] : <Uint8List>[bytes],
    );

/// Signals that a Dio byte stream exceeded its active cassette limit.
final class DioByteStreamLimitExceeded implements Exception {
  /// Creates the value-free internal signal.
  const DioByteStreamLimitExceeded();
}

/// Signals cancellation while an active Dio byte stream was being buffered.
final class DioByteStreamBufferCancelled implements Exception {
  /// Creates the value-free internal signal.
  const DioByteStreamBufferCancelled();
}

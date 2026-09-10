import 'dart:async';
import 'dart:typed_data';

/// Buffers one `http` byte [stream] within [maximumBytes].
///
/// Limit and cancellation failures use value-free signals. A source stream
/// failure is preserved for the adapter to classify.
Future<Uint8List> bufferHttpByteStream(
  Stream<List<int>> stream, {
  required int maximumBytes,
  Future<void>? cancellation,
}) async {
  if (maximumBytes <= 0) {
    throw ArgumentError.value(
      maximumBytes,
      'maximumBytes',
      'Maximum byte count must be positive.',
    );
  }

  final builder = BytesBuilder();
  final completion = Completer<Uint8List>();
  late final StreamSubscription<List<int>> subscription;
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
        fail(const HttpByteStreamLimitExceeded());
        return;
      }
      if (_containsInvalidByte(chunk)) {
        fail(const HttpByteStreamInvalidByte());
        return;
      }
      try {
        builder.add(chunk);
      } on Object catch (error, stackTrace) {
        fail(error, stackTrace);
      }
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
  if (cancellation case final cancellationFuture?) {
    unawaited(
      cancellationFuture.then<void>(
        (_) {
          fail(const HttpByteStreamBufferCancelled());
        },
        onError: (Object error, StackTrace stackTrace) {
          fail(error, stackTrace);
        },
      ),
    );
  }

  return completion.future;
}

bool _containsInvalidByte(List<int> chunk) {
  for (final byte in chunk) {
    if (byte < 0 || byte > 255) {
      return true;
    }
  }
  return false;
}

/// Signals that an HTTP byte stream exceeded its active cassette limit.
final class HttpByteStreamLimitExceeded implements Exception {
  /// Creates a value-free limit signal.
  const HttpByteStreamLimitExceeded();
}

/// Signals cancellation while an active HTTP byte stream was being buffered.
final class HttpByteStreamBufferCancelled implements Exception {
  /// Creates a value-free cancellation signal.
  const HttpByteStreamBufferCancelled();
}

/// Signals that a custom HTTP stream emitted a value outside one byte.
final class HttpByteStreamInvalidByte implements Exception {
  /// Creates a value-free invalid-byte signal.
  const HttpByteStreamInvalidByte();
}

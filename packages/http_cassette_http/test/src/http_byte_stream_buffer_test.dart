import 'dart:async';

import 'package:http_cassette_http/src/http_byte_stream_buffer.dart';
import 'package:test/test.dart';

void main() {
  test('consumes one chunked stream once and accepts the exact limit',
      () async {
    var listenCount = 0;
    final source = Stream<List<int>>.multi((controller) {
      listenCount += 1;
      controller
        ..add(<int>[1])
        ..add(<int>[2, 3]);
      unawaited(controller.close());
    }, isBroadcast: false);

    final bytes = await bufferHttpByteStream(source, maximumBytes: 3);

    expect(listenCount, 1);
    expect(bytes, <int>[1, 2, 3]);
  });

  test('returns zero bytes for an empty stream', () async {
    final bytes = await bufferHttpByteStream(
      const Stream<List<int>>.empty(),
      maximumBytes: 1,
    );

    expect(bytes, isEmpty);
  });

  test('stops after measured bytes exceed the limit', () async {
    var wasCancelled = false;
    final controller = StreamController<List<int>>(
      onCancel: () {
        wasCancelled = true;
      },
    );
    addTearDown(controller.close);
    final buffering = bufferHttpByteStream(
      controller.stream,
      maximumBytes: 2,
    );

    controller
      ..add(<int>[1, 2])
      ..add(<int>[3]);

    await expectLater(buffering, throwsA(isA<HttpByteStreamLimitExceeded>()));
    expect(wasCancelled, isTrue);
  });

  test('stops when cancellation completes', () async {
    var wasCancelled = false;
    final controller = StreamController<List<int>>(
      onCancel: () {
        wasCancelled = true;
      },
    );
    addTearDown(controller.close);
    final cancellation = Completer<void>();
    final buffering = bufferHttpByteStream(
      controller.stream,
      maximumBytes: 2,
      cancellation: cancellation.future,
    );

    cancellation.complete();

    await expectLater(
      buffering,
      throwsA(isA<HttpByteStreamBufferCancelled>()),
    );
    expect(wasCancelled, isTrue);
  });

  test('preserves a source stream failure', () async {
    final failure = StateError('stream failed');

    await expectLater(
      bufferHttpByteStream(
        Stream<List<int>>.error(failure),
        maximumBytes: 2,
      ),
      throwsA(same(failure)),
    );
  });

  test('rejects a non-positive maximum before listening', () async {
    var wasListened = false;
    final source = Stream<List<int>>.multi((controller) {
      wasListened = true;
      unawaited(controller.close());
    });

    await expectLater(
      bufferHttpByteStream(source, maximumBytes: 0),
      throwsArgumentError,
    );
    expect(wasListened, isFalse);
  });

  test('surfaces an invalid byte chunk for later safe mapping', () async {
    await expectLater(
      bufferHttpByteStream(
        Stream<List<int>>.value(<int>[256]),
        maximumBytes: 1,
      ),
      throwsA(isA<HttpByteStreamInvalidByte>()),
    );
  });
}

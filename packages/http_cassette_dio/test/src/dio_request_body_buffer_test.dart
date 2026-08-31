import 'dart:async';
import 'dart:typed_data';

import 'package:http_cassette_dio/src/dio_request_body_buffer.dart';
import 'package:test/test.dart';

void main() {
  test('preserves a null body stream', () async {
    final result = await bufferDioRequestBody(
      null,
      maximumBytes: 1,
    );

    expect(result.bytes, isEmpty);
    expect(result.replacementStream, isNull);
  });

  test('preserves a non-null empty body stream', () async {
    final result = await bufferDioRequestBody(
      const Stream<Uint8List>.empty(),
      maximumBytes: 1,
    );

    expect(result.bytes, isEmpty);
    expect(result.replacementStream, isNotNull);
    expect(await result.replacementStream!.toList(), isEmpty);
  });

  test('consumes once and accepts the exact limit', () async {
    var listenCount = 0;
    final source = Stream<Uint8List>.multi((controller) {
      listenCount += 1;
      controller
        ..add(Uint8List.fromList(<int>[1]))
        ..add(Uint8List.fromList(<int>[2, 3]));
      unawaited(controller.close());
    }, isBroadcast: false);

    final result = await bufferDioRequestBody(
      source,
      maximumBytes: 3,
    );

    expect(listenCount, 1);
    expect(result.bytes, <int>[1, 2, 3]);
    expect(
      await result.replacementStream!.expand((chunk) => chunk).toList(),
      <int>[1, 2, 3],
    );
  });

  test('stops after measured bytes exceed the limit', () async {
    var wasCancelled = false;
    final controller = StreamController<Uint8List>(
      onCancel: () {
        wasCancelled = true;
      },
    );
    addTearDown(controller.close);
    final buffering = bufferDioRequestBody(
      controller.stream,
      maximumBytes: 2,
    );

    controller
      ..add(Uint8List.fromList(<int>[1, 2]))
      ..add(Uint8List.fromList(<int>[3]));

    await expectLater(buffering, throwsA(isA<DioRequestBodyLimitExceeded>()));
    expect(wasCancelled, isTrue);
  });

  test('stops when cancellation completes', () async {
    var wasCancelled = false;
    final controller = StreamController<Uint8List>(
      onCancel: () {
        wasCancelled = true;
      },
    );
    addTearDown(controller.close);
    final cancellation = Completer<void>();
    final buffering = bufferDioRequestBody(
      controller.stream,
      maximumBytes: 2,
      cancellation: cancellation.future,
    );

    cancellation.complete();

    await expectLater(
      buffering,
      throwsA(isA<DioRequestBodyBufferCancelled>()),
    );
    expect(wasCancelled, isTrue);
  });

  test('preserves a source stream failure', () async {
    final failure = StateError('stream failed');
    final source = Stream<Uint8List>.error(failure);

    await expectLater(
      bufferDioRequestBody(source, maximumBytes: 2),
      throwsA(same(failure)),
    );
  });
}

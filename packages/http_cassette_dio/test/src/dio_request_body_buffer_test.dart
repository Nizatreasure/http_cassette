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
}

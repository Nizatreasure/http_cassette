import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http_cassette_http/src/http_byte_stream_buffer.dart';
import 'package:http_cassette_http/src/http_request_buffer.dart';
import 'package:test/test.dart';

void main() {
  final uri = Uri.parse('https://example.test/items');

  test('finalises once and rebuilds exact bytes and standard metadata',
      () async {
    final request = _CountingRequest('POST', uri, <List<int>>[
      <int>[1],
      <int>[2, 3],
    ])
      ..headers['x-before'] = 'present'
      ..contentLength = 3
      ..persistentConnection = false
      ..followRedirects = false
      ..maxRedirects = 2;

    final buffered = await bufferHttpRequest(request, maximumBytes: 3);
    final replacement = buffered.replacementRequest;

    expect(request.finalizeCount, 1);
    expect(request.listenCount, 1);
    expect(request.finalized, isTrue);
    expect(buffered.bytes, <int>[1, 2, 3]);
    expect(replacement.method, 'POST');
    expect(replacement.url, uri);
    expect(replacement.headers, <String, String>{
      'x-before': 'present',
      'x-finalized': 'present',
    });
    expect(replacement.contentLength, 3);
    expect(replacement.persistentConnection, isFalse);
    expect(replacement.followRedirects, isFalse);
    expect(replacement.maxRedirects, 2);
    expect(await replacement.finalize().toBytes(), <int>[1, 2, 3]);
  });

  test('preserves unknown content length without inventing one', () async {
    final request = _CountingRequest('POST', uri, <List<int>>[
      <int>[1, 2],
    ]);

    final buffered = await bufferHttpRequest(request, maximumBytes: 2);

    expect(request.contentLength, isNull);
    expect(buffered.replacementRequest.contentLength, isNull);
  });

  test('rejects an oversized declared length before finalisation', () async {
    final request = _CountingRequest('POST', uri, const <List<int>>[])
      ..contentLength = 3;

    await expectLater(
      bufferHttpRequest(request, maximumBytes: 2),
      throwsA(isA<HttpByteStreamLimitExceeded>()),
    );

    expect(request.finalizeCount, 0);
    expect(request.listenCount, 0);
    expect(request.finalized, isFalse);
  });

  test('preserves multipart final bytes and generated content type', () async {
    final request = http.MultipartRequest('POST', uri)
      ..fields['name'] = 'value';

    final buffered = await bufferHttpRequest(
      request,
      maximumBytes: request.contentLength,
    );
    final replacement = buffered.replacementRequest;

    expect(
      replacement.headers['content-type'],
      startsWith('multipart/form-data; boundary='),
    );
    expect(await replacement.finalize().toBytes(), buffered.bytes);
  });

  test('preserves the exact abort trigger on the replacement', () async {
    final trigger = Completer<void>();
    final request = http.AbortableStreamedRequest(
      'POST',
      uri,
      abortTrigger: trigger.future,
    );
    request.sink.add(<int>[1, 2]);
    unawaited(request.sink.close());

    final buffered = await bufferHttpRequest(request, maximumBytes: 2);
    final replacement = buffered.replacementRequest;

    expect(buffered.cancellation, isNotNull);
    expect(replacement, isA<http.Abortable>());
    expect(
      (replacement as http.Abortable).abortTrigger,
      same(trigger.future),
    );
    expect(await replacement.finalize().toBytes(), <int>[1, 2]);
  });
}

final class _CountingRequest extends http.BaseRequest {
  _CountingRequest(super.method, super.url, this.chunks);

  final List<List<int>> chunks;
  var finalizeCount = 0;
  var listenCount = 0;

  @override
  http.ByteStream finalize() {
    finalizeCount += 1;
    headers['x-finalized'] = 'present';
    super.finalize();
    return http.ByteStream(
      Stream<List<int>>.multi((controller) {
        listenCount += 1;
        for (final chunk in chunks) {
          controller.add(chunk);
        }
        unawaited(controller.close());
      }, isBroadcast: false),
    );
  }
}

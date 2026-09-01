import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette_dio/http_cassette_dio.dart';

Future<void> main() async {
  final engine = CassetteEngine(store: MemoryCassetteStore());
  final transport = _ExampleAdapter();
  final dio = Dio()..httpClientAdapter = transport;
  dio.installHttpCassette(engine);

  final recording = await engine.startRecording('example/greeting');
  final live = await dio.get<String>('https://example.test/greeting');
  await recording.close();

  final replay = await engine.startReplay('example/greeting');
  final recorded = await dio.get<String>('https://example.test/greeting');
  await replay.close();

  if (live.data != 'Hello' || recorded.data != 'Hello') {
    throw StateError('The example response was not preserved.');
  }
  if (transport.fetchCount != 1) {
    throw StateError('Replay unexpectedly reached the transport.');
  }

  dio.close();
}

final class _ExampleAdapter implements HttpClientAdapter {
  var fetchCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    fetchCount += 1;
    return ResponseBody.fromString(
      'Hello',
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/plain'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

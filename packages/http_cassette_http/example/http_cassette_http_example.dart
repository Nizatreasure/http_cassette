import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette_http/http_cassette_http.dart';

Future<void> main() async {
  final engine = CassetteEngine(store: MemoryCassetteStore());
  final transport = _ExampleClient();
  final client = CassetteHttpClient(engine, inner: transport);

  final recording = await engine.startRecording('example/status');
  final live = await client.get(Uri.parse('https://example.test/status'));
  await recording.close();

  final replay = await engine.startReplay('example/status');
  final recorded = await client.get(Uri.parse('https://example.test/status'));
  await replay.close();

  if (live.body != 'Available' || recorded.body != 'Available') {
    throw StateError('The HTTP response was not preserved.');
  }
  if (transport.sendCount != 1) {
    throw StateError('Replay unexpectedly reached the wrapped client.');
  }

  client.close();
  if (transport.closeCount != 1) {
    throw StateError('The wrapped client was not closed exactly once.');
  }
}

final class _ExampleClient extends http.BaseClient {
  var sendCount = 0;
  var closeCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sendCount += 1;
    return http.StreamedResponse(
      Stream<List<int>>.value('Available'.codeUnits),
      200,
      request: request,
      headers: <String, String>{'content-type': 'text/plain'},
    );
  }

  @override
  void close() {
    closeCount += 1;
  }
}

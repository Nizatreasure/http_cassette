import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_cassette/file.dart';
import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette_http/http_cassette_http.dart';
import 'package:test/test.dart';

import '../support/synthetic_http_transport.dart';

void main() {
  test('does not persist a cancelled file-backed recording request', () async {
    final root = await Directory.systemTemp.createTemp(
      'http_cassette_cancellation_end_to_end_',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final store = FileCassetteStore(root);
    final engine = CassetteEngine(store: store);
    final transport = SyntheticHttpTransport('unexpected response');
    final client = CassetteHttpClient(engine, inner: transport);
    addTearDown(client.close);
    final name = CassetteName('workflows/cancellation');
    final abortTrigger = Completer<void>()..complete();
    final request = http.AbortableStreamedRequest(
      'GET',
      Uri.parse('https://example.test/workflows/cancellation'),
      abortTrigger: abortTrigger.future,
    );
    unawaited(request.sink.close());

    final recording = await engine.startRecording(name.value);
    await expectLater(
      client.send(request),
      throwsA(isA<http.RequestAbortedException>()),
    );
    await recording.discard();

    expect(await store.exists(name), isFalse);
    expect(transport.sendCount, 0);
    expect(engine.isActive, isFalse);
  });
}

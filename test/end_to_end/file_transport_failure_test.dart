import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_cassette/file.dart';
import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette_http/http_cassette_http.dart';
import 'package:test/test.dart';

import '../support/synthetic_http_transport.dart';

void main() {
  test('persists and replays a safe file-backed transport failure', () async {
    final root = await Directory.systemTemp.createTemp(
      'http_cassette_failure_end_to_end_',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final store = FileCassetteStore(root);
    final engine = CassetteEngine(store: store);
    final transport = SyntheticHttpTransport('unused response');
    final client = CassetteHttpClient(engine, inner: transport);
    addTearDown(client.close);
    final uri = Uri.parse('https://example.test/workflows/failure');
    const privateMessage = 'private live transport detail';
    final liveFailure = http.ClientException(privateMessage, uri);
    transport.failure = liveFailure;

    final recording = await engine.startRecording('workflows/failure');
    await expectLater(client.get(uri), throwsA(same(liveFailure)));
    await recording.close();

    final snapshot = await store.read(CassetteName('workflows/failure'));
    final encodedCassette = utf8.decode(snapshot.bytes);
    expect(encodedCassette, contains('"type": "transportFailure"'));
    expect(encodedCassette, isNot(contains(privateMessage)));
    expect(transport.sendCount, 1);

    transport.failure = null;
    final replay = await engine.startReplay('workflows/failure');
    http.ClientException? replayedFailure;
    try {
      await client.get(uri);
    } on http.ClientException catch (failure) {
      replayedFailure = failure;
    }
    await replay.close();

    expect(replayedFailure, isNotNull);
    expect(replayedFailure, isNot(same(liveFailure)));
    expect(replayedFailure?.message, 'The HTTP transport failed.');
    expect(
      replayedFailure?.cassetteTransportFailure?.category,
      TransportFailureCategory.other,
    );
    expect(replayedFailure?.cassetteException, isNull);
    expect(transport.sendCount, 1);
  });
}

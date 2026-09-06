import 'dart:convert';
import 'dart:io';

import 'package:http_cassette/file.dart';
import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette_http/http_cassette_http.dart';
import 'package:test/test.dart';

import '../support/synthetic_http_transport.dart';

void main() {
  test('appends to a file-backed cassette and replays both interactions',
      () async {
    final root = await Directory.systemTemp.createTemp(
      'http_cassette_append_end_to_end_',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final store = FileCassetteStore(root);
    final engine = CassetteEngine(store: store);
    final transport = SyntheticHttpTransport('initial response');
    final client = CassetteHttpClient(engine, inner: transport);
    addTearDown(client.close);
    final firstUri = Uri.parse(
      'https://example.test/workflows/append/first',
    );
    final secondUri = Uri.parse(
      'https://example.test/workflows/append/second',
    );
    final name = CassetteName('workflows/append');

    final initial = await engine.startRecording(name.value);
    expect((await client.get(firstUri)).body, 'initial response');
    await initial.close();

    transport.responseBody = 'appended response';
    final append = await engine.startRecording(
      name.value,
      options: const RecordingOptions(
        existingCassette: ExistingCassette.append,
      ),
    );
    expect((await client.get(secondUri)).body, 'appended response');
    await append.close();

    final snapshot = await store.read(name);
    final document = jsonDecode(utf8.decode(snapshot.bytes)) as Map;
    final interactions = document['interactions'] as List;
    expect(
      interactions.map((interaction) => (interaction as Map)['index']),
      <int>[0, 1],
    );
    expect(transport.sendCount, 2);

    transport.responseBody = 'unexpected transport response';
    final replay = await engine.startReplay(name.value);
    final firstReplay = await client.get(firstUri);
    final secondReplay = await client.get(secondUri);
    await replay.close();

    expect(firstReplay.body, 'initial response');
    expect(secondReplay.body, 'appended response');
    expect(transport.sendCount, 2);
  });
}

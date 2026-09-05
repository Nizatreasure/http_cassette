import 'dart:io';

import 'package:http_cassette/file.dart';
import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette_http/http_cassette_http.dart';
import 'package:test/test.dart';

import '../support/synthetic_http_transport.dart';

void main() {
  test('explicitly replaces a file-backed cassette before replay', () async {
    final root = await Directory.systemTemp.createTemp(
      'http_cassette_replace_end_to_end_',
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
    final uri = Uri.parse('https://example.test/workflows/replace');
    final name = CassetteName('workflows/replace');

    final initial = await engine.startRecording(name.value);
    expect((await client.get(uri)).body, 'initial response');
    await initial.close();
    final initialSnapshot = await store.read(name);

    transport.responseBody = 'replacement response';
    final replacement = await engine.startRecording(
      name.value,
      options: const RecordingOptions(
        existingCassette: ExistingCassette.replace,
      ),
    );
    expect((await client.get(uri)).body, 'replacement response');
    await replacement.close();
    final replacementSnapshot = await store.read(name);

    expect(replacementSnapshot.bytes, isNot(equals(initialSnapshot.bytes)));
    expect(transport.sendCount, 2);

    transport.responseBody = 'unexpected transport response';
    final replay = await engine.startReplay(name.value);
    final replayed = await client.get(uri);
    await replay.close();

    expect(replayed.body, 'replacement response');
    expect(transport.sendCount, 2);
  });
}

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_cassette/file.dart';
import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette_http/http_cassette_http.dart';
import 'package:test/test.dart';

import '../support/synthetic_http_transport.dart';

void main() {
  test('reports strict file-backed replay exhaustion without transport access',
      () async {
    final root = await Directory.systemTemp.createTemp(
      'http_cassette_exhaustion_end_to_end_',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final store = FileCassetteStore(root);
    final engine = CassetteEngine(store: store);
    final transport = SyntheticHttpTransport('recorded response');
    final client = CassetteHttpClient(engine, inner: transport);
    addTearDown(client.close);
    final uri = Uri.parse('https://example.test/workflows/exhaustion');

    final recording = await engine.startRecording('workflows/exhaustion');
    expect((await client.get(uri)).body, 'recorded response');
    await recording.close();
    expect(transport.sendCount, 1);

    final replay = await engine.startReplay('workflows/exhaustion');
    expect((await client.get(uri)).body, 'recorded response');
    http.ClientException? caught;
    try {
      await client.get(uri);
    } on http.ClientException catch (failure) {
      caught = failure;
    }
    await replay.close();

    expect(caught, isNotNull);
    expect(
      caught?.cassetteException?.diagnostic.category,
      DiagnosticCategory.interactionsExhausted,
    );
    expect(
      caught?.cassetteException?.diagnostic.networkAccess,
      NetworkAccess.disabled,
    );
    expect(transport.sendCount, 1);
  });
}

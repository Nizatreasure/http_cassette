import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_cassette/file.dart';
import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette_http/http_cassette_http.dart';
import 'package:test/test.dart';

import '../support/synthetic_http_transport.dart';

void main() {
  test('reports a file-backed replay mismatch without transport access',
      () async {
    final root = await Directory.systemTemp.createTemp(
      'http_cassette_mismatch_end_to_end_',
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
    final recordedUri = Uri.parse(
      'https://example.test/workflows/mismatch/recorded',
    );
    final unmatchedUri = Uri.parse(
      'https://example.test/workflows/mismatch/unmatched',
    );

    final recording = await engine.startRecording('workflows/mismatch');
    expect((await client.get(recordedUri)).body, 'recorded response');
    await recording.close();
    expect(transport.sendCount, 1);

    final replay = await engine.startReplay('workflows/mismatch');
    http.ClientException? caught;
    try {
      await client.get(unmatchedUri);
    } on http.ClientException catch (failure) {
      caught = failure;
    }
    await replay.close();

    expect(caught, isNotNull);
    expect(
      caught?.cassetteException?.diagnostic.category,
      DiagnosticCategory.noMatchingInteraction,
    );
    expect(
      caught?.cassetteException?.diagnostic.networkAccess,
      NetworkAccess.disabled,
    );
    expect(transport.sendCount, 1);
  });
}

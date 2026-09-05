import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_cassette/file.dart';
import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette_http/http_cassette_http.dart';
import 'package:test/test.dart';

void main() {
  test('creates and replays a file-backed cassette without replay transport',
      () async {
    final root = await Directory.systemTemp.createTemp(
      'http_cassette_end_to_end_',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final store = FileCassetteStore(root);
    final engine = CassetteEngine(store: store);
    final transport = _SyntheticTransport('recorded response');
    final client = CassetteHttpClient(engine, inner: transport);
    addTearDown(client.close);
    final uri = Uri.parse('https://example.test/workflows/create');
    final name = CassetteName('workflows/create-replay');

    final recording = await engine.startRecording(name.value);
    final live = await client.get(uri);
    await recording.close();

    final cassetteFile = File.fromUri(
      root.uri.resolve('workflows/create-replay.json'),
    );
    final snapshot = await store.read(name);
    expect(live.statusCode, 201);
    expect(live.body, 'recorded response');
    expect(await cassetteFile.exists(), isTrue);
    expect(snapshot.bytes, isNotEmpty);
    expect(transport.sendCount, 1);

    transport.responseBody = 'unexpected transport response';
    final replay = await engine.startReplay(name.value);
    final replayed = await client.get(uri);
    await replay.close();

    expect(replayed.statusCode, 201);
    expect(replayed.body, 'recorded response');
    expect(transport.sendCount, 1);
  });
}

final class _SyntheticTransport extends http.BaseClient {
  _SyntheticTransport(this.responseBody);

  String responseBody;
  var sendCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sendCount += 1;
    return http.StreamedResponse(
      Stream<List<int>>.value(responseBody.codeUnits),
      201,
      request: request,
      reasonPhrase: 'Created',
      headers: const <String, String>{'content-type': 'text/plain'},
    );
  }
}

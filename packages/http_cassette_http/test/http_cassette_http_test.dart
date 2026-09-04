import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette_http/http_cassette_http.dart';
import 'package:test/test.dart';

void main() {
  late CassetteEngine engine;
  late _StubClient inner;
  late CassetteHttpClient client;

  setUp(() {
    engine = CassetteEngine(store: MemoryCassetteStore());
    inner = _StubClient();
    client = CassetteHttpClient(engine, inner: inner);
  });

  tearDown(() => client.close());

  test('exposes the shared engine', () {
    expect(client.engine, same(engine));
  });

  test('passes the exact inactive request and response through', () async {
    final request = http.Request(
      'GET',
      Uri.parse('https://example.test/items'),
    );

    final response = await client.send(request);

    expect(inner.sendCount, 1);
    expect(inner.request, same(request));
    expect(response, same(inner.lastResponse));
    expect(request.finalized, isFalse);
  });

  test('passes an inactive client failure through unchanged', () async {
    final request = http.Request(
      'GET',
      Uri.parse('https://example.test/failure'),
    );
    final failure = http.ClientException('transport failed', request.url);
    inner.failure = failure;

    await expectLater(client.send(request), throwsA(same(failure)));

    expect(inner.sendCount, 1);
    expect(inner.request, same(request));
    expect(request.finalized, isFalse);
  });

  test('records one live response and replays without inner-client access',
      () async {
    inner.responseBody = <int>[1, 2, 3];
    final recording = await engine.startRecording('active-response');

    final live = await client.send(
      http.Request('GET', Uri.parse('https://example.test/items')),
    );
    expect(await live.stream.toBytes(), <int>[1, 2, 3]);
    await recording.close();

    expect(inner.sendCount, 1);

    inner.responseBody = <int>[9];
    final replay = await engine.startReplay('active-response');
    addTearDown(replay.discard);
    final replayed = await client.send(
      http.Request('GET', Uri.parse('https://example.test/items')),
    );

    expect(await replayed.stream.toBytes(), <int>[1, 2, 3]);
    expect(inner.sendCount, 1);
  });

  test('records a live client failure and reconstructs it on replay', () async {
    final requestUri = Uri.parse('https://example.test/failure');
    final liveFailure =
        http.ClientException('private live failure', requestUri);
    inner.failure = liveFailure;
    final recording = await engine.startRecording('active-failure');

    await expectLater(
      client.send(http.Request('GET', requestUri)),
      throwsA(same(liveFailure)),
    );
    await recording.close();

    expect(inner.sendCount, 1);

    inner.failure = null;
    final replay = await engine.startReplay('active-failure');
    addTearDown(replay.discard);
    http.ClientException? replayedFailure;
    try {
      await client.send(http.Request('GET', requestUri));
    } on http.ClientException catch (failure) {
      replayedFailure = failure;
    }

    expect(replayedFailure, isNotNull);
    expect(replayedFailure, isNot(same(liveFailure)));
    expect(replayedFailure?.message, 'The HTTP transport failed.');
    expect(
      replayedFailure?.cassetteTransportFailure?.category,
      TransportFailureCategory.other,
    );
    expect(replayedFailure?.cassetteException, isNull);
    expect(inner.sendCount, 1);
  });

  test('reports a replay mismatch without inner-client access', () async {
    final recording = await engine.startRecording('no-match');
    await client.send(
      http.Request('GET', Uri.parse('https://example.test/recorded')),
    );
    await recording.close();
    final replay = await engine.startReplay('no-match');
    addTearDown(replay.discard);
    http.ClientException? caught;

    try {
      await client.send(
        http.Request('GET', Uri.parse('https://example.test/different')),
      );
    } on http.ClientException catch (failure) {
      caught = failure;
    }

    expect(
      caught?.cassetteException?.diagnostic.category,
      DiagnosticCategory.noMatchingInteraction,
    );
    expect(
      caught?.cassetteException?.diagnostic.networkAccess,
      NetworkAccess.disabled,
    );
    expect(inner.sendCount, 1);
  });

  test('closes the inner client at most once', () {
    client.close();
    client.close();

    expect(inner.closeCount, 1);
  });
}

final class _StubClient extends http.BaseClient {
  http.StreamedResponse get response => http.StreamedResponse(
        Stream<List<int>>.value(responseBody),
        200,
      );
  List<int> responseBody = const <int>[];
  http.StreamedResponse? lastResponse;
  Object? failure;
  var sendCount = 0;
  http.BaseRequest? request;
  var closeCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sendCount += 1;
    this.request = request;
    final error = failure;
    if (error != null) {
      throw error;
    }
    final result = response;
    lastResponse = result;
    return result;
  }

  @override
  void close() {
    closeCount += 1;
  }
}

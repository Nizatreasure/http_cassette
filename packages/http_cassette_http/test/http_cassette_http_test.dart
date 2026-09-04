import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette_http/http_cassette_http.dart';
import 'package:test/test.dart';

void main() {
  late CassetteEngine engine;
  late _StubClient inner;
  late CassetteHttpClient client;
  late MemoryCassetteStore store;

  setUp(() {
    store = MemoryCassetteStore();
    engine = CassetteEngine(store: store);
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

  test('pre-aborted replay consumes nothing and never reaches the inner client',
      () async {
    final uri = Uri.parse('https://example.test/replay');
    inner.responseBody = <int>[1, 2, 3];
    final recording = await engine.startRecording('cancelled-replay');
    await client.send(http.Request('GET', uri));
    await recording.close();
    final replay = await engine.startReplay('cancelled-replay');
    addTearDown(replay.discard);
    final trigger = Completer<void>()..complete();
    final cancelled = http.AbortableStreamedRequest(
      'GET',
      uri,
      abortTrigger: trigger.future,
    );
    unawaited(cancelled.sink.close());

    await expectLater(
      client.send(cancelled),
      throwsA(isA<http.RequestAbortedException>()),
    );

    final replayed = await client.send(http.Request('GET', uri));
    expect(await replayed.stream.toBytes(), <int>[1, 2, 3]);
    expect(inner.sendCount, 1);
  });

  test('cancels request buffering before an inner-client call', () async {
    final trigger = Completer<void>();
    final request = http.AbortableStreamedRequest(
      'POST',
      Uri.parse('https://example.test/upload'),
      abortTrigger: trigger.future,
    );
    final recording = await engine.startRecording('cancelled-buffering');
    final sending = client.send(request);

    await Future<void>.delayed(Duration.zero);
    trigger.complete();

    await expectLater(
      sending,
      throwsA(isA<http.RequestAbortedException>()),
    );
    unawaited(request.sink.close());
    await recording.discard();

    expect(inner.sendCount, 0);
    expect(
      await store.exists(CassetteName('cancelled-buffering')),
      isFalse,
    );
  });

  test('discards a late response after cancellation wins recording', () async {
    final responseStarted = Completer<void>();
    final responseController = StreamController<List<int>>(
      onListen: responseStarted.complete,
    );
    addTearDown(responseController.close);
    inner.responseOverride = http.StreamedResponse(
      responseController.stream,
      200,
    );
    final trigger = Completer<void>();
    final request = http.AbortableStreamedRequest(
      'GET',
      Uri.parse('https://example.test/slow'),
      abortTrigger: trigger.future,
    );
    unawaited(request.sink.close());
    final recording = await engine.startRecording('cancelled-response');
    final sending = client.send(request);

    await responseStarted.future;
    trigger.complete();

    await expectLater(
      sending,
      throwsA(isA<http.RequestAbortedException>()),
    );
    responseController.add(<int>[1, 2, 3]);
    await Future<void>.delayed(Duration.zero);
    await recording.discard();

    expect(inner.sendCount, 1);
    expect(
      await store.exists(CassetteName('cancelled-response')),
      isFalse,
    );
  });

  test('records and replays a completed server-error response', () async {
    inner.responseOverride = http.StreamedResponse(
      Stream<List<int>>.value('server failed'.codeUnits),
      500,
      headers: <String, String>{'content-type': 'text/plain'},
      reasonPhrase: 'Internal Server Error',
    );
    final uri = Uri.parse('https://example.test/error-status');
    final recording = await engine.startRecording('error-status');

    final live = await client.send(http.Request('GET', uri));
    expect(live.statusCode, 500);
    expect(live.reasonPhrase, 'Internal Server Error');
    expect(await live.stream.bytesToString(), 'server failed');
    await recording.close();

    final replay = await engine.startReplay('error-status');
    addTearDown(replay.discard);
    final replayed = await client.send(http.Request('GET', uri));

    expect(replayed.statusCode, 500);
    expect(replayed.reasonPhrase, 'Internal Server Error');
    expect(await replayed.stream.bytesToString(), 'server failed');
    expect(inner.sendCount, 1);
  });

  test('replays canonical redirect data without live-only metadata', () async {
    final requestUri = Uri.parse('https://example.test/redirect');
    final finalUri = Uri.parse('https://example.test/final');
    inner.responseOverride = _UrlStreamedResponse(
      Stream<List<int>>.value('redirect body'.codeUnits),
      302,
      url: finalUri,
      headers: <String, String>{
        'content-type': 'text/plain',
        'location': finalUri.toString(),
      },
      isRedirect: true,
      persistentConnection: false,
      reasonPhrase: 'Found',
    );
    final recording = await engine.startRecording('direct-redirect');

    final live = await client.send(http.Request('GET', requestUri));
    expect(live.statusCode, 302);
    expect(live.isRedirect, isTrue);
    expect(live.persistentConnection, isFalse);
    expect((live as http.BaseResponseWithUrl).url, finalUri);
    expect(await live.stream.bytesToString(), 'redirect body');
    await recording.close();

    final replay = await engine.startReplay('direct-redirect');
    addTearDown(replay.discard);
    final replayed = await client.send(http.Request('GET', requestUri));

    expect(replayed.statusCode, 302);
    expect(replayed.reasonPhrase, 'Found');
    expect(replayed.headers['location'], finalUri.toString());
    expect(await replayed.stream.bytesToString(), 'redirect body');
    expect(replayed.isRedirect, isFalse);
    expect(replayed.persistentConnection, isTrue);
    expect(replayed, isNot(isA<http.BaseResponseWithUrl>()));
    expect(inner.sendCount, 1);
  });

  test('records a bodyless JSON-labelled GET request', () async {
    inner.responseOverride = http.StreamedResponse(
      Stream<List<int>>.value(
        '{"@odata.context":"https://example.test/metadata","value":[]}'
            .codeUnits,
      ),
      200,
      headers: <String, String>{'content-type': 'application/json'},
    );
    final uri = Uri.parse('https://example.test/policies');
    final request = http.Request('GET', uri)
      ..headers['content-type'] = 'application/json';
    final recording = await engine.startRecording('empty-json-get-http');

    final live = await client.send(request);
    await recording.close();

    expect(await live.stream.bytesToString(), contains('@odata.context'));
    expect(inner.request?.contentLength, 0);

    final replay = await engine.startReplay('empty-json-get-http');
    addTearDown(replay.discard);
    final replayedRequest = http.Request('GET', uri)
      ..headers['content-type'] = 'application/json';
    final replayed = await client.send(replayedRequest);

    expect(await replayed.stream.bytesToString(), contains('@odata.context'));
    expect(inner.sendCount, 1);
  });

  test('closes the inner client at most once', () {
    client.close();
    client.close();

    expect(inner.closeCount, 1);
  });
}

final class _UrlStreamedResponse extends http.StreamedResponse
    implements http.BaseResponseWithUrl {
  _UrlStreamedResponse(
    super.stream,
    super.statusCode, {
    required this.url,
    super.headers,
    super.isRedirect,
    super.persistentConnection,
    super.reasonPhrase,
  });

  @override
  final Uri url;
}

final class _StubClient extends http.BaseClient {
  http.StreamedResponse get response => http.StreamedResponse(
        Stream<List<int>>.value(responseBody),
        200,
      );
  List<int> responseBody = const <int>[];
  http.StreamedResponse? responseOverride;
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
    final result = responseOverride ?? response;
    lastResponse = result;
    return result;
  }

  @override
  void close() {
    closeCount += 1;
  }
}

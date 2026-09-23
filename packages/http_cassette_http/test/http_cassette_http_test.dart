import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

  test('passes through a disabled replay command to the inner client',
      () async {
    final disabledStore = MemoryCassetteStore();
    final disabledEngine = CassetteEngine(
      store: disabledStore,
      activationPolicy: CassetteActivationPolicy.disabledWithPassThrough,
    );
    final disabledInner = _StubClient()
      ..responseBody = 'production response'.codeUnits;
    final disabledClient = CassetteHttpClient(
      disabledEngine,
      inner: disabledInner,
    );
    addTearDown(disabledClient.close);

    final response = await disabledEngine.replay<String>(
      'disabled/replay',
      () async => (await disabledClient.get(
        Uri.parse('https://example.test/production'),
      ))
          .body,
    );

    expect(response, 'production response');
    expect(disabledInner.sendCount, 1);
    expect(disabledEngine.isActive, isFalse);
    expect(
      await disabledStore.exists(CassetteName('disabled/replay')),
      isFalse,
    );
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

  test('records gzip JSON as plain content and replays without inner access',
      () async {
    await _verifyGzipResponseLifecycle(
      handling: GzipJsonResponseHandling.sanitiseAndStorePlain,
      expectedPersistedEncoding: 'json',
      expectedReplayIsGzip: false,
    );
  });

  test('recompresses sanitised gzip JSON and replays without inner access',
      () async {
    await _verifyGzipResponseLifecycle(
      handling: GzipJsonResponseHandling.sanitiseAndStoreCompressed,
      expectedPersistedEncoding: 'base64',
      expectedReplayIsGzip: true,
    );
  });

  for (final testCase in <({
    GzipJsonResponseHandling handling,
    String description,
    String encoding,
    bool sanitised,
  })>[
    (
      handling: GzipJsonResponseHandling.storeWithoutSanitisation,
      description: 'stores client-decoded gzip JSON without sanitisation',
      encoding: 'gzipBase64',
      sanitised: false,
    ),
    (
      handling: GzipJsonResponseHandling.sanitiseAndStorePlain,
      description: 'stores client-decoded gzip JSON as sanitised plain JSON',
      encoding: 'json',
      sanitised: true,
    ),
    (
      handling: GzipJsonResponseHandling.sanitiseAndStoreCompressed,
      description: 'compresses client-decoded sanitised JSON only for storage',
      encoding: 'gzipBase64',
      sanitised: true,
    ),
  ]) {
    test('${testCase.description} and replays without inner access', () async {
      await _verifyGzipResponseLifecycle(
        handling: testCase.handling,
        expectedPersistedEncoding: testCase.encoding,
        expectedReplayIsGzip: false,
        capturedBodyIsDecompressed: true,
        expectedSanitised: testCase.sanitised,
      );
    });
  }

  for (final failureKind in <String>['malformed', 'decoded-too-large']) {
    test('returns live gzip response when $failureKind processing fails',
        () async {
      await _verifyGzipResponseFailure(failureKind);
    });
  }

  test('returns a captured response when later sanitisation fails', () async {
    const malformedJson = '{"token":"secret"';
    inner.responseOverride = http.StreamedResponse(
      Stream<List<int>>.value(malformedJson.codeUnits),
      200,
      headers: <String, String>{'content-type': 'application/json'},
    );
    final recording = await engine.startRecording('sanitisation-failure');

    final response = await client.send(
      http.Request('GET', Uri.parse('https://example.test/items')),
    );

    expect(await response.stream.bytesToString(), malformedJson);
    await expectLater(
      recording.close(),
      throwsA(
        isA<CassetteException>().having(
          (failure) => failure.diagnostic.category,
          'category',
          DiagnosticCategory.recordingRequestFailed,
        ),
      ),
    );
    expect(
      await store.exists(CassetteName('sanitisation-failure')),
      isFalse,
    );
    expect(engine.isActive, isFalse);
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

  test('rejects a declared oversized request before inner-client access',
      () async {
    final limitedStore = MemoryCassetteStore();
    final limitedEngine = CassetteEngine(
      store: limitedStore,
      configuration: CassetteConfiguration(
        bodyLimits: BodyLimits(requestBytes: 2),
      ),
    );
    final limitedInner = _StubClient();
    final limitedClient = CassetteHttpClient(
      limitedEngine,
      inner: limitedInner,
    );
    addTearDown(limitedClient.close);
    final recording = await limitedEngine.startRecording('declared-limit');
    final request = http.StreamedRequest(
      'POST',
      Uri.parse('https://example.test/upload'),
    )..contentLength = 3;
    http.ClientException? caught;

    try {
      await limitedClient.send(request);
    } on http.ClientException catch (failure) {
      caught = failure;
    }
    await recording.discard();

    expect(request.finalized, isFalse);
    expect(limitedInner.sendCount, 0);
    expect(
      caught?.cassetteException?.diagnostic.category,
      DiagnosticCategory.bodyLimitExceeded,
    );
    expect(
      caught?.cassetteException?.diagnostic.networkAccess,
      NetworkAccess.notAttempted,
    );
    expect(
      await limitedStore.exists(CassetteName('declared-limit')),
      isFalse,
    );
  });

  test('rejects a measured oversized request before inner-client access',
      () async {
    final limitedStore = MemoryCassetteStore();
    final limitedEngine = CassetteEngine(
      store: limitedStore,
      configuration: CassetteConfiguration(
        bodyLimits: BodyLimits(requestBytes: 2),
      ),
    );
    final limitedInner = _StubClient();
    final limitedClient = CassetteHttpClient(
      limitedEngine,
      inner: limitedInner,
    );
    addTearDown(limitedClient.close);
    final recording = await limitedEngine.startRecording('measured-limit');
    final request = http.StreamedRequest(
      'POST',
      Uri.parse('https://example.test/upload'),
    );
    request.sink.add(<int>[1, 2, 3]);
    unawaited(request.sink.close());
    http.ClientException? caught;

    try {
      await limitedClient.send(request);
    } on http.ClientException catch (failure) {
      caught = failure;
    }
    await recording.discard();

    expect(limitedInner.sendCount, 0);
    expect(
      caught?.cassetteException?.diagnostic.category,
      DiagnosticCategory.bodyLimitExceeded,
    );
    expect(
      caught?.cassetteException?.diagnostic.networkAccess,
      NetworkAccess.notAttempted,
    );
    expect(
      await limitedStore.exists(CassetteName('measured-limit')),
      isFalse,
    );
  });

  test('rejects an oversized response after one inner-client attempt',
      () async {
    final limitedStore = MemoryCassetteStore();
    final limitedEngine = CassetteEngine(
      store: limitedStore,
      configuration: CassetteConfiguration(
        bodyLimits: BodyLimits(responseBytes: 2),
      ),
    );
    final limitedInner = _StubClient()..responseBody = <int>[1, 2, 3];
    final limitedClient = CassetteHttpClient(
      limitedEngine,
      inner: limitedInner,
    );
    addTearDown(limitedClient.close);
    final recording = await limitedEngine.startRecording('response-limit');
    http.ClientException? caught;

    try {
      await limitedClient.send(
        http.Request('GET', Uri.parse('https://example.test/items')),
      );
    } on http.ClientException catch (failure) {
      caught = failure;
    }
    await recording.discard();

    expect(limitedInner.sendCount, 1);
    expect(
      caught?.cassetteException?.diagnostic.category,
      DiagnosticCategory.bodyLimitExceeded,
    );
    expect(
      caught?.cassetteException?.diagnostic.networkAccess,
      NetworkAccess.attempted,
    );
    expect(
      await limitedStore.exists(CassetteName('response-limit')),
      isFalse,
    );
  });

  test('records and replays empty request and response streams', () async {
    inner.responseOverride = http.StreamedResponse(
      const Stream<List<int>>.empty(),
      204,
    );
    final uri = Uri.parse('https://example.test/empty');
    final request = http.StreamedRequest('POST', uri);
    unawaited(request.sink.close());
    final recording = await engine.startRecording('empty-streams');

    final live = await client.send(request);
    expect(await live.stream.toBytes(), isEmpty);
    await recording.close();

    final replay = await engine.startReplay('empty-streams');
    addTearDown(replay.discard);
    final replayRequest = http.StreamedRequest('POST', uri);
    unawaited(replayRequest.sink.close());
    final replayed = await client.send(replayRequest);

    expect(replayed.statusCode, 204);
    expect(await replayed.stream.toBytes(), isEmpty);
    expect(inner.sendCount, 1);
  });

  test('maps an invalid abort trigger without retaining its value', () async {
    const secret = 'private abort trigger detail';
    final trigger = Completer<void>();
    final request = http.AbortableStreamedRequest(
      'GET',
      Uri.parse('https://example.test/invalid-abort'),
      abortTrigger: trigger.future,
    );
    unawaited(request.sink.close());
    final recording = await engine.startRecording('invalid-abort');
    trigger.completeError(StateError(secret));
    http.ClientException? caught;

    try {
      await client.send(request);
    } on http.ClientException catch (failure) {
      caught = failure;
    }
    await recording.discard();

    expect(inner.sendCount, 0);
    expect(
      caught?.cassetteException?.diagnostic.category,
      DiagnosticCategory.adapterContractViolation,
    );
    expect(caught.toString(), isNot(contains(secret)));
    expect(await store.exists(CassetteName('invalid-abort')), isFalse);
  });

  test('maps an unmapped inner-client error without retaining its value',
      () async {
    const secret = 'private custom client error';
    inner.failure = StateError(secret);
    final recording = await engine.startRecording('unmapped-client');
    http.ClientException? caught;

    try {
      await client.send(
        http.Request('GET', Uri.parse('https://example.test/unmapped')),
      );
    } on http.ClientException catch (failure) {
      caught = failure;
    }
    await recording.discard();

    expect(inner.sendCount, 1);
    expect(
      caught?.cassetteException?.diagnostic.category,
      DiagnosticCategory.adapterContractViolation,
    );
    expect(
      caught?.cassetteException?.diagnostic.networkAccess,
      NetworkAccess.attempted,
    );
    expect(caught.toString(), isNot(contains(secret)));
    expect(await store.exists(CassetteName('unmapped-client')), isFalse);
  });

  test('maps a failing response stream without retaining its value', () async {
    const secret = 'private response stream error';
    inner.responseOverride = http.StreamedResponse(
      Stream<List<int>>.error(StateError(secret)),
      200,
    );
    final recording = await engine.startRecording('failing-response-stream');
    http.ClientException? caught;

    try {
      await client.send(
        http.Request('GET', Uri.parse('https://example.test/stream-failure')),
      );
    } on http.ClientException catch (failure) {
      caught = failure;
    }
    await recording.discard();

    expect(inner.sendCount, 1);
    expect(
      caught?.cassetteException?.diagnostic.category,
      DiagnosticCategory.adapterContractViolation,
    );
    expect(caught.toString(), isNot(contains(secret)));
    expect(
      await store.exists(CassetteName('failing-response-stream')),
      isFalse,
    );
  });

  test('closes the inner client at most once', () {
    client.close();
    client.close();

    expect(inner.closeCount, 1);
  });
}

Future<void> _verifyGzipResponseLifecycle({
  required GzipJsonResponseHandling handling,
  required String expectedPersistedEncoding,
  required bool expectedReplayIsGzip,
  bool capturedBodyIsDecompressed = false,
  bool expectedSanitised = true,
}) async {
  final store = MemoryCassetteStore();
  final engine = CassetteEngine(
    store: store,
    configuration: CassetteConfiguration(
      sanitisation: SanitisationConfiguration(
        gzipJsonResponses: handling,
      ),
    ),
  );
  final plainBytes = utf8.encode('{"token":"synthetic-secret","keep":true}');
  final originalBytes =
      capturedBodyIsDecompressed ? plainBytes : gzip.encode(plainBytes);
  final inner = _StubClient()
    ..responseOverride = http.StreamedResponse(
      Stream<List<int>>.value(originalBytes),
      200,
      headers: <String, String>{
        'content-type': 'application/json',
        'content-encoding': 'gzip',
      },
    );
  final client = CassetteHttpClient(engine, inner: inner);
  addTearDown(client.close);
  final uri = Uri.parse('https://example.test/gzip');

  final recording = await engine.startRecording('gzip-response');
  final live = await client.send(http.Request('GET', uri));
  final liveBytes = await live.stream.toBytes();

  expect(liveBytes, originalBytes);
  expect(live.headers['content-encoding'], 'gzip');
  expect(inner.sendCount, 1);
  await recording.close();

  final snapshot = await store.read(CassetteName('gzip-response'));
  final cassette =
      jsonDecode(utf8.decode(snapshot.bytes)) as Map<String, Object?>;
  final interaction = (cassette['interactions']! as List<Object?>).single
      as Map<String, Object?>;
  final storedOutcome = interaction['outcome']! as Map<String, Object?>;
  final storedBody = storedOutcome['body']! as Map<String, Object?>;
  expect(storedBody['encoding'], expectedPersistedEncoding);

  inner.responseOverride = http.StreamedResponse(
    Stream<List<int>>.value(utf8.encode('unexpected network response')),
    200,
  );
  final replay = await engine.startReplay('gzip-response');
  addTearDown(replay.discard);
  final replayed = await client.send(http.Request('GET', uri));
  final replayedBytes = await replayed.stream.toBytes();

  expect(inner.sendCount, 1);
  expect(replayed.headers['content-encoding'], 'gzip');
  final replayedPlainBytes =
      expectedReplayIsGzip ? gzip.decode(replayedBytes) : replayedBytes;
  expect(
    utf8.decode(replayedPlainBytes),
    expectedSanitised
        ? '{"keep":true,"token":"[REDACTED]"}'
        : '{"token":"synthetic-secret","keep":true}',
  );
}

Future<void> _verifyGzipResponseFailure(String failureKind) async {
  const maximumResponseBytes = 128;
  final isDecodedSizeFailure = failureKind == 'decoded-too-large';
  final responseBytes = isDecodedSizeFailure
      ? gzip.encode(
          utf8.encode(
            '{"keep":"${List<String>.filled(4096, 'a').join()}"}',
          ),
        )
      : <int>[1, 2, 3];
  expect(responseBytes.length, lessThan(maximumResponseBytes));
  final store = MemoryCassetteStore();
  final engine = CassetteEngine(
    store: store,
    configuration: CassetteConfiguration(
      bodyLimits: BodyLimits(responseBytes: maximumResponseBytes),
      sanitisation: SanitisationConfiguration(
        gzipJsonResponses: isDecodedSizeFailure
            ? GzipJsonResponseHandling.sanitiseAndStoreCompressed
            : GzipJsonResponseHandling.sanitiseAndStorePlain,
      ),
    ),
  );
  final inner = _StubClient()
    ..responseOverride = http.StreamedResponse(
      Stream<List<int>>.value(responseBytes),
      200,
      headers: <String, String>{
        'content-type': 'application/json',
        'content-encoding': 'gzip',
      },
    );
  final client = CassetteHttpClient(engine, inner: inner);
  addTearDown(client.close);
  final cassetteName = 'gzip-$failureKind';
  final recording = await engine.startRecording(cassetteName);

  final live = await client.send(
    http.Request('GET', Uri.parse('https://example.test/gzip-failure')),
  );
  final liveBytes = await live.stream.toBytes();

  expect(liveBytes, responseBytes);
  expect(live.headers['content-encoding'], 'gzip');
  expect(inner.sendCount, 1);
  await expectLater(
    recording.close(),
    throwsA(
      isA<CassetteException>().having(
        (failure) => failure.diagnostic.category,
        'category',
        DiagnosticCategory.recordingRequestFailed,
      ),
    ),
  );
  expect(await store.exists(CassetteName(cassetteName)), isFalse);
  expect(engine.isActive, isFalse);

  final recovery = await engine.startRecording('recovery-$failureKind');
  await recovery.discard();
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

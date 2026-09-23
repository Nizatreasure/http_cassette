import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette_dio/http_cassette_dio.dart';
import 'package:test/test.dart';

void main() {
  late CassetteEngine engine;
  late Dio dio;
  late _StubHttpClientAdapter inner;
  late MemoryCassetteStore store;

  setUp(() {
    store = MemoryCassetteStore();
    engine = CassetteEngine(store: store);
    inner = _StubHttpClientAdapter();
    dio = Dio()..httpClientAdapter = inner;
    dio.installHttpCassette(engine);
  });

  tearDown(() {
    dio.close(force: true);
  });

  test('wraps the currently configured adapter with the shared engine', () {
    final installed = dio.httpClientAdapter;

    expect(installed, isA<CassetteHttpClientAdapter>());
    expect((installed as CassetteHttpClientAdapter).engine, same(engine));
    expect(installed.inner, same(inner));
  });

  test('rejects installation more than once', () {
    expect(
      () => dio.installHttpCassette(engine),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'HTTP Cassette is already installed on this Dio client.',
        ),
      ),
    );
  });

  test('delegates exact inactive fetch arguments and response', () async {
    final adapter = dio.httpClientAdapter;
    final options = RequestOptions(path: 'https://example.test/items');
    final stream = Stream<Uint8List>.value(Uint8List.fromList(<int>[1, 2]));
    final cancelFuture = Completer<void>().future;

    final response = await adapter.fetch(options, stream, cancelFuture);

    expect(inner.fetchCount, 1);
    expect(inner.requestOptions, same(options));
    expect(inner.requestStream, same(stream));
    expect(inner.cancelFuture, same(cancelFuture));
    expect(response, same(inner.response));
  });

  test('passes an inactive Dio request and response through', () async {
    final body = <String, Object?>{'message': 'hello'};
    inner.response = ResponseBody.fromString(
      'response body',
      201,
      headers: {
        Headers.contentTypeHeader: ['text/plain'],
      },
    );

    final response = await dio.post<String>(
      'https://example.test/items',
      data: body,
    );

    expect(inner.fetchCount, 1);
    expect(inner.requestOptions?.data, same(body));
    expect(response.statusCode, 201);
    expect(response.data, 'response body');
  });

  test('passes an inactive transport failure through unchanged', () async {
    inner.failureMessage = 'transport failed';
    DioException? caught;

    try {
      await dio.get<void>('https://example.test/failure');
    } on DioException catch (error) {
      caught = error;
    }

    expect(inner.fetchCount, 1);
    expect(caught, same(inner.failure));
  });

  test('passes through a disabled replay command to the wrapped adapter',
      () async {
    final disabledStore = MemoryCassetteStore();
    final disabledEngine = CassetteEngine(
      store: disabledStore,
      activationPolicy: CassetteActivationPolicy.disabledWithPassThrough,
    );
    final disabledInner = _StubHttpClientAdapter()
      ..response = ResponseBody.fromString('production response', 200);
    final disabledDio = Dio()..httpClientAdapter = disabledInner;
    addTearDown(() => disabledDio.close(force: true));
    disabledDio.installHttpCassette(disabledEngine);

    final response = await disabledEngine.replay<String>(
      'disabled/replay',
      () async => (await disabledDio.get<String>(
        'https://example.test/production',
      ))
          .data!,
    );

    expect(response, 'production response');
    expect(disabledInner.fetchCount, 1);
    expect(disabledEngine.isActive, isFalse);
    expect(
      await disabledStore.exists(CassetteName('disabled/replay')),
      isFalse,
    );
  });

  test('records one live response and replays it without network access',
      () async {
    inner.response = ResponseBody.fromString(
      'recorded response',
      201,
      statusMessage: 'Created',
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/plain'],
        'x-trace': <String>['first', 'second'],
      },
    );
    final recording = await engine.startRecording('active-response');

    final live = await dio.get<String>('https://example.test/active');
    await recording.close();

    expect(live.statusCode, 201);
    expect(live.statusMessage, 'Created');
    expect(live.data, 'recorded response');
    expect(live.headers['x-trace'], <String>['first', 'second']);
    expect(inner.fetchCount, 1);

    inner.response = ResponseBody.fromString('network response', 200);
    final replay = await engine.startReplay('active-response');
    addTearDown(replay.discard);

    final replayed = await dio.get<String>('https://example.test/active');

    expect(replayed.statusCode, 201);
    expect(replayed.statusMessage, 'Created');
    expect(replayed.data, 'recorded response');
    expect(replayed.headers['x-trace'], <String>['first', 'second']);
    expect(inner.fetchCount, 1);
  });

  test('records gzip JSON as plain content and replays without transport',
      () async {
    await _verifyGzipResponseLifecycle(
      handling: GzipJsonResponseHandling.sanitiseAndStorePlain,
      expectedPersistedEncoding: 'json',
      expectedReplayIsGzip: false,
    );
  });

  test('recompresses sanitised gzip JSON and replays without transport',
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
    test('${testCase.description} and replays without transport', () async {
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
    inner.response = ResponseBody.fromString(
      malformedJson,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
    final recording = await engine.startRecording('sanitisation-failure');

    final response = await dio.httpClientAdapter.fetch(
      RequestOptions(path: 'https://example.test/items'),
      null,
      null,
    );

    expect(
      await response.stream.expand((chunk) => chunk).toList(),
      malformedJson.codeUnits,
    );
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

  test('records a bodyless JSON-labelled GET request', () async {
    inner.response = ResponseBody.fromString(
      '{"@odata.context":"https://example.test/metadata","value":[]}',
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
    final recording = await engine.startRecording('empty-json-get');

    final live = await dio.get<Map<String, Object?>>(
      'https://example.test/policies',
      options: Options(contentType: Headers.jsonContentType),
    );
    await recording.close();

    expect(live.data?['value'], isEmpty);
    expect(inner.fetchCount, 1);

    final replay = await engine.startReplay('empty-json-get');
    addTearDown(replay.discard);

    final replayed = await dio.get<Map<String, Object?>>(
      'https://example.test/policies',
      options: Options(contentType: Headers.jsonContentType),
    );

    expect(replayed.data, live.data);
    expect(inner.fetchCount, 1);
  });

  test('records and replays a status rejected later by Dio', () async {
    inner.response = ResponseBody.fromString(
      'server failed',
      500,
      statusMessage: 'Internal Server Error',
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/plain'],
      },
    );
    final recording = await engine.startRecording('error-status');
    DioException? liveFailure;

    try {
      await dio.get<String>('https://example.test/error-status');
    } on DioException catch (failure) {
      liveFailure = failure;
    }
    await recording.close();

    expect(liveFailure?.type, DioExceptionType.badResponse);
    expect(liveFailure?.response?.statusCode, 500);
    expect(liveFailure?.response?.statusMessage, 'Internal Server Error');
    expect(liveFailure?.response?.data, 'server failed');
    expect(inner.fetchCount, 1);

    inner.response = ResponseBody.fromString('network response', 200);
    final replay = await engine.startReplay('error-status');
    addTearDown(replay.discard);
    DioException? replayedFailure;

    try {
      await dio.get<String>('https://example.test/error-status');
    } on DioException catch (failure) {
      replayedFailure = failure;
    }

    expect(replayedFailure?.type, DioExceptionType.badResponse);
    expect(replayedFailure?.response?.statusCode, 500);
    expect(replayedFailure?.response?.statusMessage, 'Internal Server Error');
    expect(replayedFailure?.response?.data, 'server failed');
    expect(replayedFailure?.cassetteException, isNull);
    expect(inner.fetchCount, 1);
  });

  test('records and replays a directly observed redirect response', () async {
    final redirects = <RedirectRecord>[
      RedirectRecord(
        301,
        'GET',
        Uri.parse('https://example.test/redirected'),
      ),
    ];
    inner.response = ResponseBody.fromString(
      'redirect body',
      302,
      statusMessage: 'Found',
      isRedirect: true,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/plain'],
        'location': <String>[
          'https://example.test/destination',
        ],
      },
    )..redirects = redirects;
    final recording = await engine.startRecording('direct-redirect');
    DioException? liveFailure;

    try {
      await dio.get<String>('https://example.test/redirect');
    } on DioException catch (failure) {
      liveFailure = failure;
    }
    await recording.close();

    expect(liveFailure?.type, DioExceptionType.badResponse);
    expect(liveFailure?.response?.statusCode, 302);
    expect(liveFailure?.response?.isRedirect, isTrue);
    expect(liveFailure?.response?.redirects, same(redirects));
    expect(inner.fetchCount, 1);

    final replay = await engine.startReplay('direct-redirect');
    addTearDown(replay.discard);
    DioException? replayedFailure;

    try {
      await dio.get<String>('https://example.test/redirect');
    } on DioException catch (failure) {
      replayedFailure = failure;
    }

    final replayed = replayedFailure?.response;
    expect(replayedFailure?.type, DioExceptionType.badResponse);
    expect(replayed?.statusCode, 302);
    expect(replayed?.statusMessage, 'Found');
    expect(replayed?.data, 'redirect body');
    expect(
      replayed?.headers.value('location'),
      'https://example.test/destination',
    );
    expect(replayed?.isRedirect, isFalse);
    expect(replayed?.redirects, isEmpty);
    expect(inner.fetchCount, 1);
  });

  test('records a live transport failure and reconstructs it on replay',
      () async {
    inner.failureMessage = 'machine-specific live failure';
    final recording = await engine.startRecording('active-failure');
    DioException? liveFailure;

    try {
      await dio.get<void>('https://example.test/failure');
    } on DioException catch (failure) {
      liveFailure = failure;
    }
    await recording.close();

    expect(liveFailure, same(inner.failure));
    expect(inner.fetchCount, 1);

    final replay = await engine.startReplay('active-failure');
    addTearDown(replay.discard);
    DioException? replayedFailure;

    try {
      await dio.get<void>('https://example.test/failure');
    } on DioException catch (failure) {
      replayedFailure = failure;
    }

    expect(replayedFailure, isNotNull);
    expect(replayedFailure, isNot(same(liveFailure)));
    expect(replayedFailure?.type, DioExceptionType.unknown);
    expect(replayedFailure?.message, 'The HTTP transport failed.');
    expect(replayedFailure?.error, isA<CassetteTransportFailure>());
    expect(replayedFailure?.cassetteException, isNull);
    expect(inner.fetchCount, 1);
  });

  test('reports a replay mismatch without network access', () async {
    final recording = await engine.startRecording('no-match');
    await dio.get<void>('https://example.test/recorded');
    await recording.close();
    final replay = await engine.startReplay('no-match');
    addTearDown(replay.discard);
    DioException? caught;

    try {
      await dio.get<void>('https://example.test/different');
    } on DioException catch (failure) {
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
    expect(inner.fetchCount, 1);
  });

  test('rejects a declared oversized active body before listening', () async {
    final limitedEngine = CassetteEngine(
      store: MemoryCassetteStore(),
      configuration: CassetteConfiguration(
        bodyLimits: BodyLimits(requestBytes: 2),
      ),
    );
    final limitedInner = _StubHttpClientAdapter();
    final adapter = CassetteHttpClientAdapter(
      engine: limitedEngine,
      inner: limitedInner,
    );
    final session = await limitedEngine.startRecording('limited');
    addTearDown(session.discard);
    var listenCount = 0;
    final stream = Stream<Uint8List>.multi((controller) {
      listenCount += 1;
      controller.add(Uint8List.fromList(<int>[1, 2, 3]));
      unawaited(controller.close());
    }, isBroadcast: false);
    final options = RequestOptions(
      path: 'https://example.test/upload',
      headers: <String, Object?>{Headers.contentLengthHeader: '3'},
    );

    DioException? caught;
    try {
      await adapter.fetch(options, stream, null);
    } on DioException catch (error) {
      caught = error;
    }

    expect(listenCount, 0);
    expect(limitedInner.fetchCount, 0);
    expect(caught?.error, isA<CassetteException>());
    expect(caught?.cassetteException, same(caught?.error));
    expect(
      (caught?.error as CassetteException).diagnostic.category,
      DiagnosticCategory.bodyLimitExceeded,
    );
    expect(
      (caught?.error as CassetteException).diagnostic.networkAccess,
      NetworkAccess.notAttempted,
    );
  });

  test('rejects a measured oversized active body before network access',
      () async {
    final limitedEngine = CassetteEngine(
      store: MemoryCassetteStore(),
      configuration: CassetteConfiguration(
        bodyLimits: BodyLimits(requestBytes: 2),
      ),
    );
    final limitedInner = _StubHttpClientAdapter();
    final adapter = CassetteHttpClientAdapter(
      engine: limitedEngine,
      inner: limitedInner,
    );
    final session = await limitedEngine.startRecording('measured');
    addTearDown(session.discard);
    final options = RequestOptions(path: 'https://example.test/upload');
    final stream = Stream<Uint8List>.value(
      Uint8List.fromList(<int>[1, 2, 3]),
    );

    DioException? caught;
    try {
      await adapter.fetch(options, stream, null);
    } on DioException catch (error) {
      caught = error;
    }

    expect(limitedInner.fetchCount, 0);
    expect(caught?.error, isA<CassetteException>());
    expect(
      (caught?.error as CassetteException).diagnostic.category,
      DiagnosticCategory.bodyLimitExceeded,
    );
  });

  test('cancels active buffering before network access', () async {
    final session = await engine.startRecording('cancelled');
    addTearDown(session.discard);
    var sourceWasCancelled = false;
    final source = StreamController<Uint8List>(
      onCancel: () {
        sourceWasCancelled = true;
      },
    );
    addTearDown(source.close);
    final cancellation = Completer<void>();
    final options = RequestOptions(path: 'https://example.test/upload');
    final fetching = dio.httpClientAdapter.fetch(
      options,
      source.stream,
      cancellation.future,
    );

    cancellation.complete();

    await expectLater(
      fetching,
      throwsA(
        isA<DioException>().having(
          (error) => error.type,
          'type',
          DioExceptionType.cancel,
        ),
      ),
    );
    expect(sourceWasCancelled, isTrue);
    expect(inner.fetchCount, 0);
  });

  test('does not retain a recording when cancellation wins the live race',
      () async {
    final response = Completer<ResponseBody>();
    final fetchStarted = Completer<void>();
    inner
      ..responseFuture = response.future
      ..fetchStarted = fetchStarted;
    final session = await engine.startRecording('cancelled-attempt');
    addTearDown(session.discard);
    final token = CancelToken();
    final options = RequestOptions(
      path: 'https://example.test/slow',
      cancelToken: token,
    );
    final fetching = dio.httpClientAdapter.fetch(
      options,
      null,
      token.whenCancel,
    );

    await fetchStarted.future;
    expect(inner.cancelFuture, same(token.whenCancel));

    token.cancel('caller stopped the request');

    await expectLater(fetching, throwsA(same(token.cancelError)));

    response.complete(ResponseBody.fromString('late response', 200));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await session.discard();

    expect(
      await store.exists(CassetteName('cancelled-attempt')),
      isFalse,
    );
  });

  test('pre-cancelled replay consumes nothing and never reaches network',
      () async {
    inner.response = ResponseBody.fromString('recorded', 200);
    final recording = await engine.startRecording('cancelled-replay');
    await dio.get<String>('https://example.test/replay');
    await recording.close();
    final replay = await engine.startReplay('cancelled-replay');
    addTearDown(replay.discard);
    final token = CancelToken()..cancel('already cancelled');
    final cancelledOptions = RequestOptions(
      path: 'https://example.test/replay',
      cancelToken: token,
    );

    await expectLater(
      dio.httpClientAdapter.fetch(
        cancelledOptions,
        null,
        token.whenCancel,
      ),
      throwsA(same(token.cancelError)),
    );

    final replayed = await dio.httpClientAdapter.fetch(
      RequestOptions(path: 'https://example.test/replay'),
      null,
      null,
    );

    expect(await replayed.stream.expand((chunk) => chunk).toList(),
        'recorded'.codeUnits);
    expect(inner.fetchCount, 1);
  });

  test('consumes an active request stream once and delegates its replacement',
      () async {
    final session = await engine.startRecording('streamed');
    addTearDown(session.discard);
    var listenCount = 0;
    final stream = Stream<Uint8List>.multi((controller) {
      listenCount += 1;
      controller.add(Uint8List.fromList(<int>[1, 2]));
      unawaited(controller.close());
    }, isBroadcast: false);
    final options = RequestOptions(path: 'https://example.test/upload');

    final response = await dio.httpClientAdapter.fetch(options, stream, null);

    expect(listenCount, 1);
    expect(response.statusCode, 200);
    expect(inner.fetchCount, 1);
    expect(
      await inner.requestStream!.expand((chunk) => chunk).toList(),
      <int>[1, 2],
    );
  });

  test('rejects an oversized live response after one network attempt',
      () async {
    final limitedEngine = CassetteEngine(
      store: MemoryCassetteStore(),
      configuration: CassetteConfiguration(
        bodyLimits: BodyLimits(responseBytes: 2),
      ),
    );
    final limitedInner = _StubHttpClientAdapter()
      ..response = ResponseBody.fromBytes(<int>[1, 2, 3], 200);
    final adapter = CassetteHttpClientAdapter(
      engine: limitedEngine,
      inner: limitedInner,
    );
    final session = await limitedEngine.startRecording('response-limit');
    addTearDown(session.discard);
    final options = RequestOptions(path: 'https://example.test/items');
    DioException? caught;

    try {
      await adapter.fetch(options, null, null);
    } on DioException catch (failure) {
      caught = failure;
    }

    expect(limitedInner.fetchCount, 1);
    expect(
      caught?.cassetteException?.diagnostic.category,
      DiagnosticCategory.bodyLimitExceeded,
    );
    expect(
      caught?.cassetteException?.diagnostic.networkAccess,
      NetworkAccess.attempted,
    );
  });

  test('maps an unmapped adapter error without retaining its value', () async {
    const secret = 'private adapter path and credentials';
    inner.thrownFailure = StateError(secret);
    final session = await engine.startRecording('unmapped-adapter');
    addTearDown(session.discard);
    DioException? caught;

    try {
      await dio.httpClientAdapter.fetch(
        RequestOptions(path: 'https://example.test/unmapped'),
        null,
        null,
      );
    } on DioException catch (failure) {
      caught = failure;
    }

    expect(
      caught?.cassetteException?.diagnostic.category,
      DiagnosticCategory.adapterContractViolation,
    );
    expect(
      caught?.cassetteException?.diagnostic.networkAccess,
      NetworkAccess.attempted,
    );
    expect(caught?.error, isNot(isA<StateError>()));
    expect(caught.toString(), isNot(contains(secret)));
    expect(await store.exists(CassetteName('unmapped-adapter')), isFalse);
  });

  test('maps a failing response stream without retaining its value', () async {
    const secret = 'private response stream detail';
    inner.response = ResponseBody(
      Stream<Uint8List>.error(StateError(secret)),
      200,
    );
    final session = await engine.startRecording('failing-response-stream');
    addTearDown(session.discard);
    DioException? caught;

    try {
      await dio.httpClientAdapter.fetch(
        RequestOptions(path: 'https://example.test/stream-failure'),
        null,
        null,
      );
    } on DioException catch (failure) {
      caught = failure;
    }

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

  test('rejects badResponse thrown from the transport boundary', () async {
    final transportOptions = RequestOptions(
      path: 'https://example.test/invalid-boundary',
    );
    inner.thrownFailure = DioException.badResponse(
      statusCode: 500,
      requestOptions: transportOptions,
      response: Response<void>(
        requestOptions: transportOptions,
        statusCode: 500,
      ),
    );
    final session = await engine.startRecording('invalid-bad-response');
    addTearDown(session.discard);
    DioException? caught;

    try {
      await dio.httpClientAdapter.fetch(
        RequestOptions(path: 'https://example.test/invalid-boundary'),
        null,
        null,
      );
    } on DioException catch (failure) {
      caught = failure;
    }

    expect(
      caught?.cassetteException?.diagnostic.category,
      DiagnosticCategory.adapterContractViolation,
    );
    expect(caught?.type, DioExceptionType.unknown);
    expect(await store.exists(CassetteName('invalid-bad-response')), isFalse);
  });

  test('closes the wrapped adapter at most once', () {
    dio.close(force: true);
    dio.close();

    expect(inner.closeCount, 1);
    expect(inner.lastCloseWasForced, isTrue);
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
  final inner = _StubHttpClientAdapter()
    ..response = ResponseBody.fromBytes(
      originalBytes,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
        Headers.contentEncodingHeader: <String>['gzip'],
      },
    );
  final dio = Dio()..httpClientAdapter = inner;
  addTearDown(() => dio.close(force: true));
  dio.installHttpCassette(engine);
  final options = RequestOptions(path: 'https://example.test/gzip');

  final recording = await engine.startRecording('gzip-response');
  final live = await dio.httpClientAdapter.fetch(options, null, null);
  final liveBytes = await live.stream.expand((chunk) => chunk).toList();

  expect(liveBytes, originalBytes);
  expect(live.headers[Headers.contentEncodingHeader], <String>['gzip']);
  expect(inner.fetchCount, 1);
  await recording.close();

  final snapshot = await store.read(CassetteName('gzip-response'));
  final cassette =
      jsonDecode(utf8.decode(snapshot.bytes)) as Map<String, Object?>;
  final interaction = (cassette['interactions']! as List<Object?>).single
      as Map<String, Object?>;
  final storedOutcome = interaction['outcome']! as Map<String, Object?>;
  final storedBody = storedOutcome['body']! as Map<String, Object?>;
  expect(storedBody['encoding'], expectedPersistedEncoding);

  inner.response = ResponseBody.fromString('unexpected network response', 200);
  final replay = await engine.startReplay('gzip-response');
  addTearDown(replay.discard);
  final replayed = await dio.httpClientAdapter.fetch(options, null, null);
  final replayedBytes = await replayed.stream.expand((chunk) => chunk).toList();

  expect(inner.fetchCount, 1);
  expect(
    replayed.headers[Headers.contentEncodingHeader],
    <String>['gzip'],
  );
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
  final inner = _StubHttpClientAdapter()
    ..response = ResponseBody.fromBytes(
      responseBytes,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
        Headers.contentEncodingHeader: <String>['gzip'],
      },
    );
  final dio = Dio()..httpClientAdapter = inner;
  addTearDown(() => dio.close(force: true));
  dio.installHttpCassette(engine);
  final cassetteName = 'gzip-$failureKind';
  final recording = await engine.startRecording(cassetteName);

  final live = await dio.httpClientAdapter.fetch(
    RequestOptions(path: 'https://example.test/gzip-failure'),
    null,
    null,
  );
  final liveBytes = await live.stream.expand((chunk) => chunk).toList();

  expect(liveBytes, responseBytes);
  expect(live.headers[Headers.contentEncodingHeader], <String>['gzip']);
  expect(inner.fetchCount, 1);
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

final class _StubHttpClientAdapter implements HttpClientAdapter {
  ResponseBody response = ResponseBody.fromString('', 200);
  Future<ResponseBody>? responseFuture;
  Completer<void>? fetchStarted;
  Object? thrownFailure;
  String? failureMessage;
  DioException? failure;
  int fetchCount = 0;
  RequestOptions? requestOptions;
  Stream<Uint8List>? requestStream;
  Future<void>? cancelFuture;
  int closeCount = 0;
  bool? lastCloseWasForced;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    fetchCount += 1;
    requestOptions = options;
    this.requestStream = requestStream;
    this.cancelFuture = cancelFuture;
    final started = fetchStarted;
    if (started != null && !started.isCompleted) {
      started.complete();
    }
    final directFailure = thrownFailure;
    if (directFailure != null) {
      throw directFailure;
    }
    final message = failureMessage;
    if (message != null) {
      final error = DioException(requestOptions: options, message: message);
      failure = error;
      throw error;
    }
    final pendingResponse = responseFuture;
    if (pendingResponse != null) {
      return pendingResponse;
    }
    return response;
  }

  @override
  void close({bool force = false}) {
    closeCount += 1;
    lastCloseWasForced = force;
  }
}

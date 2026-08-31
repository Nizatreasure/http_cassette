import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette_dio/http_cassette_dio.dart';
import 'package:test/test.dart';

void main() {
  late CassetteEngine engine;
  late Dio dio;
  late _StubHttpClientAdapter inner;

  setUp(() {
    engine = CassetteEngine(store: MemoryCassetteStore());
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

  test('fails closed during an active session', () async {
    final session = await engine.startRecording('active');
    addTearDown(session.discard);

    await expectLater(
      dio.get<void>('https://example.test/active'),
      throwsA(
        isA<DioException>().having(
          (error) => error.message,
          'message',
          'Active HTTP Cassette Dio execution is not available yet.',
        ),
      ),
    );

    expect(inner.fetchCount, 0);
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

  test('consumes an active request stream once before failing closed',
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

    await expectLater(
      dio.httpClientAdapter.fetch(options, stream, null),
      throwsA(isA<DioException>()),
    );

    expect(listenCount, 1);
    expect(inner.fetchCount, 0);
  });

  test('closes the wrapped adapter at most once', () {
    dio.close(force: true);
    dio.close();

    expect(inner.closeCount, 1);
    expect(inner.lastCloseWasForced, isTrue);
  });
}

final class _StubHttpClientAdapter implements HttpClientAdapter {
  ResponseBody response = ResponseBody.fromString('', 200);
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
    final message = failureMessage;
    if (message != null) {
      final error = DioException(requestOptions: options, message: message);
      failure = error;
      throw error;
    }
    return response;
  }

  @override
  void close({bool force = false}) {
    closeCount += 1;
    lastCloseWasForced = force;
  }
}

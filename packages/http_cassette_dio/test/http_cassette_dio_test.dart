import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette_dio/http_cassette_dio.dart';
import 'package:test/test.dart';

void main() {
  late CassetteEngine engine;
  late Dio dio;
  late _StubHttpClientAdapter adapter;

  setUp(() {
    engine = CassetteEngine(store: MemoryCassetteStore());
    adapter = _StubHttpClientAdapter();
    dio = Dio()..httpClientAdapter = adapter;
    dio.interceptors.add(CassetteDioInterceptor(engine));
  });

  tearDown(() {
    dio.close(force: true);
  });

  test('passes an inactive request and successful response through unchanged',
      () async {
    final body = <String, Object?>{'message': 'hello'};
    RequestOptions? observedOptions;
    Object? observedBody;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          observedOptions = options;
          observedBody = options.data;
          handler.next(options);
        },
      ),
    );
    adapter.response = ResponseBody.fromString(
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

    expect(adapter.fetchCount, 1);
    expect(observedOptions, same(adapter.requestOptions));
    expect(observedBody, same(body));
    expect(response.statusCode, 201);
    expect(response.data, 'response body');
  });

  test('passes an inactive transport failure through unchanged', () async {
    adapter.failureMessage = 'transport failed';
    DioException? caught;

    try {
      await dio.get<void>('https://example.test/failure');
    } on DioException catch (error) {
      caught = error;
    }

    expect(adapter.fetchCount, 1);
    expect(caught, same(adapter.failure));
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
          'Active HTTP Cassette Dio interception is not available yet.',
        ),
      ),
    );

    expect(adapter.fetchCount, 0);
  });
}

final class _StubHttpClientAdapter implements HttpClientAdapter {
  ResponseBody response = ResponseBody.fromString('', 200);
  String? failureMessage;
  DioException? failure;
  int fetchCount = 0;
  RequestOptions? requestOptions;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    fetchCount += 1;
    requestOptions = options;
    final message = failureMessage;
    if (message != null) {
      final error = DioException(requestOptions: options, message: message);
      failure = error;
      throw error;
    }
    return response;
  }

  @override
  void close({bool force = false}) {}
}

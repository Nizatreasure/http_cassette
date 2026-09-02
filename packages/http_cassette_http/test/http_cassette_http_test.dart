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
    expect(response, same(inner.response));
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

  test('fails closed during an active session', () async {
    final session = await engine.startRecording('active');
    addTearDown(session.discard);
    final request = http.Request(
      'GET',
      Uri.parse('https://example.test/items'),
    );

    expect(
      () => client.send(request),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Active package:http cassette execution is not implemented yet.',
        ),
      ),
    );

    expect(inner.sendCount, 0);
    expect(request.finalized, isFalse);
  });

  test('closes the inner client at most once', () {
    client.close();
    client.close();

    expect(inner.closeCount, 1);
  });
}

final class _StubClient extends http.BaseClient {
  http.StreamedResponse response = http.StreamedResponse(
    const Stream<List<int>>.empty(),
    200,
  );
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
    return response;
  }

  @override
  void close() {
    closeCount += 1;
  }
}

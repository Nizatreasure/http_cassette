import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette_dio/http_cassette_dio.dart';
import 'package:http_cassette_http/http_cassette_http.dart';
import 'package:test/test.dart';

import 'support/transport_equivalence_fixture.dart';

void main() {
  test('official adapters persist equivalent canonical requests', () async {
    final dioRequest = await _recordDioRequest();
    final httpRequest = await _recordHttpRequest();

    expect(dioRequest, httpRequest);
  });
}

Future<Map<String, Object?>> _recordDioRequest() async {
  final store = MemoryCassetteStore();
  final engine = CassetteEngine(store: store);
  final inner = _DioTransport();
  final adapter = CassetteHttpClientAdapter(engine: engine, inner: inner);
  final recording = await engine.startRecording('equivalence/request');

  await adapter.fetch(
    RequestOptions(
      path: TransportEquivalenceFixture.uri.toString(),
      method: TransportEquivalenceFixture.method,
      headers: TransportEquivalenceFixture.requestHeaders,
    ),
    Stream<Uint8List>.value(
      Uint8List.fromList(TransportEquivalenceFixture.requestBody),
    ),
    null,
  );
  await recording.close();
  adapter.close(force: true);

  final snapshot = await store.read(CassetteName('equivalence/request'));
  return TransportEquivalenceFixture.recordedRequest(snapshot);
}

Future<Map<String, Object?>> _recordHttpRequest() async {
  final store = MemoryCassetteStore();
  final engine = CassetteEngine(store: store);
  final client = CassetteHttpClient(engine, inner: _HttpTransport());
  final recording = await engine.startRecording('equivalence/request');
  final request = http.Request(
    TransportEquivalenceFixture.method,
    TransportEquivalenceFixture.uri,
  )
    ..headers.addAll(TransportEquivalenceFixture.requestHeaders)
    ..bodyBytes = TransportEquivalenceFixture.requestBody;

  final response = await client.send(request);
  await response.stream.drain<void>();
  await recording.close();
  client.close();

  final snapshot = await store.read(CassetteName('equivalence/request'));
  return TransportEquivalenceFixture.recordedRequest(snapshot);
}

final class _DioTransport implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await requestStream?.drain<void>();
    return ResponseBody.fromBytes(
      TransportEquivalenceFixture.responseBody,
      200,
      headers: <String, List<String>>{
        for (final entry in TransportEquivalenceFixture.responseHeaders.entries)
          entry.key: <String>[entry.value],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

final class _HttpTransport extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().drain<void>();
    return http.StreamedResponse(
      Stream<List<int>>.value(TransportEquivalenceFixture.responseBody),
      200,
      headers: TransportEquivalenceFixture.responseHeaders,
      request: request,
    );
  }
}

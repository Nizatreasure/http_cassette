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
    final dioInteraction = await _recordDioInteraction();
    final httpInteraction = await _recordHttpInteraction();
    final dioRequest =
        TransportEquivalenceFixture.recordedRequest(dioInteraction);
    final httpRequest =
        TransportEquivalenceFixture.recordedRequest(httpInteraction);

    expect(dioRequest, httpRequest);
  });

  test('official adapters persist equivalent canonical responses', () async {
    final dioInteraction = await _recordDioInteraction();
    final httpInteraction = await _recordHttpInteraction();
    final dioOutcome =
        TransportEquivalenceFixture.recordedOutcome(dioInteraction);
    final httpOutcome =
        TransportEquivalenceFixture.recordedOutcome(httpInteraction);

    expect(dioOutcome['type'], 'response');
    expect(httpOutcome['type'], 'response');
    expect(dioOutcome, httpOutcome);
  });

  test('official adapters persist equivalent portable failures', () async {
    final dioInteraction = await _recordDioFailureInteraction();
    final httpInteraction = await _recordHttpFailureInteraction();
    final dioOutcome =
        TransportEquivalenceFixture.recordedOutcome(dioInteraction);
    final httpOutcome =
        TransportEquivalenceFixture.recordedOutcome(httpInteraction);

    expect(dioOutcome['type'], 'transportFailure');
    expect(dioOutcome['category'], 'other');
    expect(
      dioOutcome['message'],
      TransportEquivalenceFixture.safeFailureMessage,
    );
    expect(dioOutcome, httpOutcome);
    expect(
      dioOutcome.toString(),
      isNot(contains(TransportEquivalenceFixture.privateFailureMessage)),
    );
  });

  test('replays a Dio recording through package:http without transport',
      () async {
    final snapshot = await _recordDioSnapshot();
    final store = MemoryCassetteStore();
    await store.create(CassetteName('equivalence/request'), snapshot.bytes);
    final engine = CassetteEngine(store: store);
    final inner = _HttpTransport();
    final client = CassetteHttpClient(engine, inner: inner);
    final replay = await engine.startReplay('equivalence/request');

    final response = await client.send(_httpRequest());
    final body = await response.stream.toBytes();
    await replay.close();
    client.close();

    expect(response.statusCode, 200);
    expect(response.headers, TransportEquivalenceFixture.responseHeaders);
    expect(body, TransportEquivalenceFixture.responseBody);
    expect(inner.sendCount, 0);
  });

  test('replays a package:http recording through Dio without transport',
      () async {
    final snapshot = await _recordHttpSnapshot();
    final store = MemoryCassetteStore();
    await store.create(CassetteName('equivalence/request'), snapshot.bytes);
    final engine = CassetteEngine(store: store);
    final inner = _DioTransport();
    final adapter = CassetteHttpClientAdapter(engine: engine, inner: inner);
    final replay = await engine.startReplay('equivalence/request');

    final response = await adapter.fetch(
      _dioRequestOptions(),
      _dioRequestStream(),
      null,
    );
    final body = await response.stream.expand((chunk) => chunk).toList();
    await replay.close();
    adapter.close(force: true);

    expect(response.statusCode, 200);
    expect(
      response.headers['content-type'],
      <String>['application/json'],
    );
    expect(body, TransportEquivalenceFixture.responseBody);
    expect(inner.fetchCount, 0);
  });
}

Future<Map<String, Object?>> _recordDioInteraction() async =>
    TransportEquivalenceFixture.recordedInteraction(
      await _recordDioSnapshot(),
    );

Future<CassetteSnapshot> _recordDioSnapshot() async {
  final store = MemoryCassetteStore();
  final engine = CassetteEngine(store: store);
  final inner = _DioTransport();
  final adapter = CassetteHttpClientAdapter(engine: engine, inner: inner);
  final recording = await engine.startRecording('equivalence/request');

  await adapter.fetch(
    _dioRequestOptions(),
    _dioRequestStream(),
    null,
  );
  await recording.close();
  adapter.close(force: true);

  return store.read(CassetteName('equivalence/request'));
}

Future<Map<String, Object?>> _recordHttpInteraction() async =>
    TransportEquivalenceFixture.recordedInteraction(
      await _recordHttpSnapshot(),
    );

Future<CassetteSnapshot> _recordHttpSnapshot() async {
  final store = MemoryCassetteStore();
  final engine = CassetteEngine(store: store);
  final client = CassetteHttpClient(engine, inner: _HttpTransport());
  final recording = await engine.startRecording('equivalence/request');
  final response = await client.send(_httpRequest());
  await response.stream.drain<void>();
  await recording.close();
  client.close();

  return store.read(CassetteName('equivalence/request'));
}

Future<Map<String, Object?>> _recordDioFailureInteraction() async {
  final store = MemoryCassetteStore();
  final engine = CassetteEngine(store: store);
  final adapter = CassetteHttpClientAdapter(
    engine: engine,
    inner: _FailingDioTransport(),
  );
  final recording = await engine.startRecording('equivalence/failure');

  await expectLater(
    adapter.fetch(
      _dioRequestOptions(),
      _dioRequestStream(),
      null,
    ),
    throwsA(isA<DioException>()),
  );
  await recording.close();
  adapter.close(force: true);

  final snapshot = await store.read(CassetteName('equivalence/failure'));
  return TransportEquivalenceFixture.recordedInteraction(snapshot);
}

Future<Map<String, Object?>> _recordHttpFailureInteraction() async {
  final store = MemoryCassetteStore();
  final engine = CassetteEngine(store: store);
  final client = CassetteHttpClient(engine, inner: _FailingHttpTransport());
  final recording = await engine.startRecording('equivalence/failure');
  await expectLater(
    client.send(_httpRequest()),
    throwsA(isA<http.ClientException>()),
  );
  await recording.close();
  client.close();

  final snapshot = await store.read(CassetteName('equivalence/failure'));
  return TransportEquivalenceFixture.recordedInteraction(snapshot);
}

RequestOptions _dioRequestOptions() => RequestOptions(
      path: TransportEquivalenceFixture.uri.toString(),
      method: TransportEquivalenceFixture.method,
      headers: TransportEquivalenceFixture.requestHeaders,
    );

Stream<Uint8List> _dioRequestStream() => Stream<Uint8List>.value(
      Uint8List.fromList(TransportEquivalenceFixture.requestBody),
    );

http.Request _httpRequest() => http.Request(
      TransportEquivalenceFixture.method,
      TransportEquivalenceFixture.uri,
    )
      ..headers.addAll(TransportEquivalenceFixture.requestHeaders)
      ..bodyBytes = TransportEquivalenceFixture.requestBody;

final class _DioTransport implements HttpClientAdapter {
  var fetchCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    fetchCount += 1;
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
  var sendCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sendCount += 1;
    await request.finalize().drain<void>();
    return http.StreamedResponse(
      Stream<List<int>>.value(TransportEquivalenceFixture.responseBody),
      200,
      headers: TransportEquivalenceFixture.responseHeaders,
      request: request,
    );
  }
}

final class _FailingDioTransport implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await requestStream?.drain<void>();
    throw DioException(
      requestOptions: options,
      message: TransportEquivalenceFixture.privateFailureMessage,
    );
  }

  @override
  void close({bool force = false}) {}
}

final class _FailingHttpTransport extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().drain<void>();
    throw http.ClientException(
      TransportEquivalenceFixture.privateFailureMessage,
      request.url,
    );
  }
}

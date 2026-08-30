import 'package:http_cassette/http_cassette.dart';
import 'package:test/test.dart';

typedef AdapterContractTransport = Future<AdapterContractResponse> Function(
  AdapterContractRequest request,
);

typedef AdapterContractDriverFactory = AdapterContractDriver Function(
  CassetteEngine engine,
  AdapterContractTransport transport,
);

abstract interface class AdapterContractDriver {
  int get canonicalRequestCount;

  int get realAttemptCount;

  Future<AdapterContractResponse> send(AdapterContractRequest request);
}

final class AdapterContractRequest {
  const AdapterContractRequest({
    required this.method,
    required this.uri,
    this.headers = const <String, List<String>>{},
    this.body = const <int>[],
  });

  final String method;
  final Uri uri;
  final Map<String, List<String>> headers;
  final List<int> body;
}

final class AdapterContractResponse {
  const AdapterContractResponse({
    required this.statusCode,
    this.headers = const <String, List<String>>{},
    this.body = const <int>[],
  });

  final int statusCode;
  final Map<String, List<String>> headers;
  final List<int> body;
}

void runBasicPublicAdapterContract(AdapterContractDriverFactory createDriver) {
  group('basic public adapter contract', () {
    test('passes through without canonicalising while inactive', () async {
      final engine = CassetteEngine(store: MemoryCassetteStore());
      final response = AdapterContractResponse(
        statusCode: 202,
        headers: <String, List<String>>{
          'x-source': <String>['transport'],
        },
        body: <int>[1, 2, 3],
      );
      late AdapterContractRequest observedRequest;
      final driver = createDriver(engine, (request) async {
        observedRequest = request;
        return response;
      });
      final request = AdapterContractRequest(
        method: 'GET',
        uri: Uri.parse('https://example.test/inactive'),
      );

      final result = await driver.send(request);

      expect(observedRequest, same(request));
      expect(result, same(response));
      expect(driver.canonicalRequestCount, 0);
      expect(driver.realAttemptCount, 1);
    });

    test('records and replays one canonical response', () async {
      final store = MemoryCassetteStore();
      final engine = CassetteEngine(store: store);
      final response = AdapterContractResponse(
        statusCode: 201,
        headers: <String, List<String>>{
          'content-type': <String>['application/octet-stream'],
          'x-repeat': <String>['first', 'second'],
        },
        body: <int>[0, 127, 255],
      );
      final driver = createDriver(engine, (_) async => response);
      final request = AdapterContractRequest(
        method: 'POST',
        uri: Uri.parse('https://example.test/items?part=one&part=two'),
        headers: <String, List<String>>{
          'accept': <String>['application/octet-stream'],
        },
        body: <int>[4, 5, 6],
      );
      final recording = await engine.startRecording('adapter/basic-response');

      final liveResult = await driver.send(request);
      await recording.close();
      final replay = await engine.startReplay('adapter/basic-response');
      final replayResult = await driver.send(request);

      _expectResponse(liveResult, response);
      _expectResponse(replayResult, response);
      expect(driver.canonicalRequestCount, 2);
      expect(driver.realAttemptCount, 1);
      await replay.discard();
    });
  });
}

void _expectResponse(
  AdapterContractResponse actual,
  AdapterContractResponse expected,
) {
  expect(actual.statusCode, expected.statusCode);
  expect(actual.headers, expected.headers);
  expect(actual.body, expected.body);
}

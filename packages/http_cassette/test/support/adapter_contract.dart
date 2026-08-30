import 'package:http_cassette/http_cassette.dart';
import 'package:test/test.dart';

typedef AdapterContractTransport = Future<AdapterContractOutcome> Function(
  AdapterContractRequest request,
);

typedef AdapterContractDriverFactory = AdapterContractDriver Function(
  CassetteEngine engine,
  AdapterContractTransport transport,
);

abstract interface class AdapterContractDriver {
  int get canonicalRequestCount;

  int get realAttemptCount;

  Future<AdapterContractOutcome> send(AdapterContractRequest request);
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

sealed class AdapterContractOutcome {
  const AdapterContractOutcome();
}

final class AdapterContractResponse extends AdapterContractOutcome {
  const AdapterContractResponse({
    required this.statusCode,
    this.headers = const <String, List<String>>{},
    this.body = const <int>[],
  });

  final int statusCode;
  final Map<String, List<String>> headers;
  final List<int> body;
}

final class AdapterContractFailure extends AdapterContractOutcome {
  const AdapterContractFailure({
    required this.category,
    required this.message,
  });

  final TransportFailureCategory category;
  final String message;
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

    test('records and replays every portable transport failure', () async {
      final store = MemoryCassetteStore();
      final engine = CassetteEngine(store: store);
      const message = 'The transport failed safely.';
      final driver = createDriver(engine, (request) async {
        final category = TransportFailureCategory.values.singleWhere(
          (value) => value.name == request.uri.pathSegments.last,
        );
        return AdapterContractFailure(category: category, message: message);
      });
      final recording = await engine.startRecording('adapter/failures');

      for (final category in TransportFailureCategory.values) {
        final result = await driver.send(_failureRequest(category));
        _expectFailure(result, category, message);
      }
      await recording.close();
      final replay = await engine.startReplay('adapter/failures');
      for (final category in TransportFailureCategory.values) {
        final result = await driver.send(_failureRequest(category));
        _expectFailure(result, category, message);
      }

      expect(
        driver.canonicalRequestCount,
        TransportFailureCategory.values.length * 2,
      );
      expect(
        driver.realAttemptCount,
        TransportFailureCategory.values.length,
      );
      await replay.discard();
    });
  });
}

AdapterContractRequest _failureRequest(TransportFailureCategory category) {
  return AdapterContractRequest(
    method: 'GET',
    uri: Uri.parse('https://example.test/failures/${category.name}'),
  );
}

void _expectResponse(
  AdapterContractOutcome actual,
  AdapterContractResponse expected,
) {
  expect(actual, isA<AdapterContractResponse>());
  actual as AdapterContractResponse;
  expect(actual.statusCode, expected.statusCode);
  expect(actual.headers, expected.headers);
  expect(actual.body, expected.body);
}

void _expectFailure(
  AdapterContractOutcome actual,
  TransportFailureCategory category,
  String message,
) {
  expect(actual, isA<AdapterContractFailure>());
  actual as AdapterContractFailure;
  expect(actual.category, category);
  expect(actual.message, message);
}

import 'dart:async';

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

  Future<AdapterContractOutcome> send(
    AdapterContractRequest request, {
    CassetteCancellation? cancellation,
  });
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

void runPublicAdapterContract(AdapterContractDriverFactory createDriver) {
  group('public adapter contract', () {
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

    test('does not attempt transport after pre-entry cancellation', () async {
      final engine = CassetteEngine(store: MemoryCassetteStore());
      final driver = createDriver(
        engine,
        (_) async => const AdapterContractResponse(statusCode: 200),
      );
      final recording = await engine.startRecording(
        'adapter/pre-entry-cancellation',
      );
      final cancellation = _ManualCancellation()..cancel();

      await expectLater(
        driver.send(_cancellationRequest(), cancellation: cancellation),
        throwsA(
          isA<CassetteException>()
              .having(
                (exception) => exception.diagnostic.category,
                'category',
                DiagnosticCategory.cancelled,
              )
              .having(
                (exception) => exception.diagnostic.networkAccess,
                'network access',
                NetworkAccess.notAttempted,
              ),
        ),
      );
      expect(driver.realAttemptCount, 0);
      await recording.discard();
    });

    test('does not persist in-flight recording cancellation', () async {
      final store = MemoryCassetteStore();
      final engine = CassetteEngine(store: store);
      final attemptStarted = Completer<void>();
      final attemptResult = Completer<AdapterContractOutcome>();
      final driver = createDriver(engine, (_) {
        attemptStarted.complete();
        return attemptResult.future;
      });
      final request = _cancellationRequest();
      final cancellation = _ManualCancellation();
      final recording = await engine.startRecording(
        'adapter/in-flight-cancellation',
      );

      final result = driver.send(request, cancellation: cancellation);
      await attemptStarted.future;
      cancellation.cancel();
      await expectLater(
        result,
        throwsA(
          isA<CassetteException>()
              .having(
                (exception) => exception.diagnostic.category,
                'category',
                DiagnosticCategory.cancelled,
              )
              .having(
                (exception) => exception.diagnostic.networkAccess,
                'network access',
                NetworkAccess.attempted,
              ),
        ),
      );
      attemptResult.complete(
        const AdapterContractResponse(statusCode: 200),
      );
      await Future<void>.delayed(Duration.zero);
      await recording.discard();
      await expectLater(
        store.read(CassetteName('adapter/in-flight-cancellation')),
        throwsA(
          isA<CassetteStoreException>().having(
            (exception) => exception.kind,
            'kind',
            CassetteStoreFailureKind.notFound,
          ),
        ),
      );
      expect(driver.realAttemptCount, 1);
    });

    test('pre-selection replay cancellation consumes no interaction', () async {
      final store = MemoryCassetteStore();
      final engine = CassetteEngine(store: store);
      const response = AdapterContractResponse(statusCode: 204);
      final driver = createDriver(engine, (_) async => response);
      final request = _cancellationRequest();
      final recording = await engine.startRecording(
        'adapter/replay-cancellation',
      );
      await driver.send(request);
      await recording.close();
      final replay = await engine.startReplay('adapter/replay-cancellation');
      final cancellation = _ManualCancellation()..cancel();

      await expectLater(
        driver.send(request, cancellation: cancellation),
        throwsA(
          isA<CassetteException>()
              .having(
                (exception) => exception.diagnostic.category,
                'category',
                DiagnosticCategory.cancelled,
              )
              .having(
                (exception) => exception.diagnostic.networkAccess,
                'network access',
                NetworkAccess.disabled,
              ),
        ),
      );
      _expectResponse(await driver.send(request), response);
      expect(driver.realAttemptCount, 1);
      await replay.discard();
    });

    test('accepts request and response bodies exactly at their limits',
        () async {
      final store = MemoryCassetteStore();
      final engine = CassetteEngine(
        store: store,
        configuration: CassetteConfiguration(
          bodyLimits: BodyLimits(requestBytes: 3, responseBytes: 4),
        ),
      );
      const response = AdapterContractResponse(
        statusCode: 200,
        body: <int>[5, 6, 7, 8],
      );
      final driver = createDriver(engine, (_) async => response);
      final request = AdapterContractRequest(
        method: 'POST',
        uri: Uri.parse('https://example.test/body-limit-boundary'),
        body: const <int>[1, 2, 3],
      );
      final recording = await engine.startRecording('adapter/body-boundary');

      _expectResponse(await driver.send(request), response);
      await recording.close();
      final replay = await engine.startReplay('adapter/body-boundary');
      _expectResponse(await driver.send(request), response);

      expect(driver.realAttemptCount, 1);
      await replay.discard();
    });

    test('rejects an oversized request before the transport attempt', () async {
      final store = MemoryCassetteStore();
      final engine = CassetteEngine(
        store: store,
        configuration: CassetteConfiguration(
          bodyLimits: BodyLimits(requestBytes: 2),
        ),
      );
      final driver = createDriver(
        engine,
        (_) async => const AdapterContractResponse(statusCode: 200),
      );
      final request = AdapterContractRequest(
        method: 'POST',
        uri: Uri.parse('https://example.test/request-limit'),
        body: const <int>[1, 2, 3],
      );
      final recording = await engine.startRecording('adapter/request-limit');

      await expectLater(
        driver.send(request),
        throwsA(_bodyLimitFailure(NetworkAccess.notAttempted)),
      );
      expect(driver.canonicalRequestCount, 0);
      expect(driver.realAttemptCount, 0);
      await recording.close();

      final replay = await engine.startReplay('adapter/request-limit');
      await expectLater(
        driver.send(
          AdapterContractRequest(
            method: request.method,
            uri: request.uri,
            body: const <int>[1, 2],
          ),
        ),
        throwsA(
          isA<CassetteException>().having(
            (exception) => exception.diagnostic.category,
            'category',
            DiagnosticCategory.noMatchingInteraction,
          ),
        ),
      );
      expect(driver.realAttemptCount, 0);
      await replay.discard();
    });

    test('rejects an oversized response without persisting it', () async {
      final store = MemoryCassetteStore();
      final engine = CassetteEngine(
        store: store,
        configuration: CassetteConfiguration(
          bodyLimits: BodyLimits(responseBytes: 2),
        ),
      );
      final driver = createDriver(
        engine,
        (_) async => const AdapterContractResponse(
          statusCode: 200,
          body: <int>[1, 2, 3],
        ),
      );
      final recording = await engine.startRecording('adapter/response-limit');

      await expectLater(
        driver.send(
          AdapterContractRequest(
            method: 'GET',
            uri: Uri.parse('https://example.test/response-limit'),
          ),
        ),
        throwsA(_bodyLimitFailure(NetworkAccess.attempted)),
      );
      expect(driver.realAttemptCount, 1);
      await recording.discard();
      await expectLater(
        store.read(CassetteName('adapter/response-limit')),
        throwsA(
          isA<CassetteStoreException>().having(
            (exception) => exception.kind,
            'kind',
            CassetteStoreFailureKind.notFound,
          ),
        ),
      );
    });
  });
}

Matcher _bodyLimitFailure(NetworkAccess networkAccess) =>
    isA<CassetteException>()
        .having(
          (exception) => exception.diagnostic.category,
          'category',
          DiagnosticCategory.bodyLimitExceeded,
        )
        .having(
          (exception) => exception.diagnostic.networkAccess,
          'network access',
          networkAccess,
        );

AdapterContractRequest _cancellationRequest() => AdapterContractRequest(
      method: 'GET',
      uri: Uri.parse('https://example.test/cancellation'),
    );

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

final class _ManualCancellation implements CassetteCancellation {
  final _completion = Completer<void>();

  @override
  bool get isCancelled => _completion.isCompleted;

  @override
  Future<void> get whenCancelled => _completion.future;

  void cancel() {
    if (!_completion.isCompleted) {
      _completion.complete();
    }
  }
}

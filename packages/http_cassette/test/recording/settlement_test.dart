import 'dart:async';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/recording/active_state.dart';
import 'package:test/test.dart';

void main() {
  group('recording request settlement', () {
    test('waits until every admitted recording request settles', () async {
      final state = _state();
      final firstOutcome = Completer<CassetteOutcome>();
      final secondOutcome = Completer<CassetteOutcome>();
      final first = state.recordRequest(
        _request('/first'),
        () => firstOutcome.future,
      );
      final second = state.recordRequest(
        _request('/second'),
        () => secondOutcome.future,
      );
      var settled = false;
      final allSettled = state.whenRequestsSettled.then((_) {
        settled = true;
      });

      expect(state.pendingRequestCount, 2);
      secondOutcome.complete(_response(202));
      await second;
      expect(state.pendingRequestCount, 1);
      expect(settled, isFalse);

      firstOutcome.complete(_response(201));
      await first;
      await allSettled;
      expect(state.pendingRequestCount, 0);
      expect(state.hasFailedRequests, isFalse);
    });

    test('counts a safely mapped transport failure as successful settlement',
        () async {
      final state = _state();

      await state.recordRequest(
        _request('/unavailable'),
        () async => CassetteTransportFailure(
          category: TransportFailureCategory.connection,
          message: 'The connection failed.',
        ),
      );

      expect(state.pendingRequestCount, 0);
      expect(state.hasFailedRequests, isFalse);
      expect(state.interactions, hasLength(1));
    });

    test('settles and remembers a recording-pipeline failure', () async {
      final state = _state();

      await expectLater(
        state.recordRequest(_request('/failure'), () {
          throw StateError('private adapter failure');
        }),
        throwsA(isA<CassetteException>()),
      );

      await state.whenRequestsSettled;
      expect(state.pendingRequestCount, 0);
      expect(state.hasFailedRequests, isTrue);
      expect(state.failedRequestNetworkAccess, NetworkAccess.attempted);
      expect(state.interactions, isEmpty);
    });

    test('retains a pre-attempt cancellation network status', () async {
      final state = _state();
      final cancellation = _CancelledRequest();

      await expectLater(
        state.recordRequest(
          _request('/cancelled'),
          () async => _response(200),
          cancellation: cancellation,
        ),
        throwsA(isA<CassetteException>()),
      );

      expect(state.hasFailedRequests, isTrue);
      expect(state.failedRequestNetworkAccess, NetworkAccess.notAttempted);
    });

    test('an idle recording is already settled', () async {
      final state = _state();

      await state.whenRequestsSettled;

      expect(state.pendingRequestCount, 0);
      expect(state.hasFailedRequests, isFalse);
    });

    test('seals admission and waits once for all pending requests', () async {
      final state = _state();
      final outcome = Completer<CassetteOutcome>();
      final request = state.recordRequest(
        _request('/pending'),
        () => outcome.future,
      );

      final settlement = state.sealAndWaitForRequests();

      expect(state.acceptsRequests, isFalse);
      expect(
        () => state.beginRequest(_request('/late')),
        throwsStateError,
      );
      outcome.complete(_response(200));
      await request;
      expect(await settlement, RecordingSettlementResult.settled);
    });

    test('reports when the complete grace period expires', () async {
      final outcome = Completer<CassetteOutcome>();
      final state = _state(
        closeGracePeriod: const Duration(milliseconds: 10),
      );
      final request = state.recordRequest(
        _request('/slow'),
        () => outcome.future,
      );

      final settlement = await state.sealAndWaitForRequests();

      expect(settlement, RecordingSettlementResult.timedOut);
      expect(state.acceptsRequests, isFalse);
      expect(state.pendingRequestCount, 1);

      outcome.complete(_response(200));
      await request;
    });
  });
}

ActiveRecordingState _state({
  Duration closeGracePeriod = RecordingConfiguration.defaultCloseGracePeriod,
}) =>
    ActiveRecordingState(
      cassetteName: CassetteName('recording'),
      configuration: CassetteConfiguration(
        recording: RecordingConfiguration(
          closeGracePeriod: closeGracePeriod,
        ),
      ),
      options: const RecordingOptions(),
    );

CassetteRequest _request(String path) => CassetteRequest(
      method: 'GET',
      uri: Uri.parse('https://example.test$path'),
    );

CassetteOutcome _response(int statusCode) => CassetteResponseOutcome(
      CassetteResponse(statusCode: statusCode),
    );

final class _CancelledRequest implements CassetteCancellation {
  @override
  bool get isCancelled => true;

  @override
  Future<void> get whenCancelled => Future<void>.value();
}

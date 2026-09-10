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
      expect(state.interactions, isEmpty);
    });

    test('an idle recording is already settled', () async {
      final state = _state();

      await state.whenRequestsSettled;

      expect(state.pendingRequestCount, 0);
      expect(state.hasFailedRequests, isFalse);
    });
  });
}

ActiveRecordingState _state() => ActiveRecordingState(
      cassetteName: CassetteName('recording'),
      configuration: CassetteConfiguration(),
      options: const RecordingOptions(),
    );

CassetteRequest _request(String path) => CassetteRequest(
      method: 'GET',
      uri: Uri.parse('https://example.test$path'),
    );

CassetteOutcome _response(int statusCode) => CassetteResponseOutcome(
      CassetteResponse(statusCode: statusCode),
    );

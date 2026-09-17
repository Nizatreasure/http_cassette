import 'dart:async';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/recording/active_state.dart';
import 'package:http_cassette/src/recording/request_attempt.dart';
import 'package:test/test.dart';

void main() {
  group('recording interaction retention', () {
    test('retains reverse completions in request-arrival order', () async {
      final state = _state();
      final firstCompletion = Completer<CassetteOutcome>();
      final secondCompletion = Completer<CassetteOutcome>();
      final firstAttempt = state.beginRequest(_request('/first'));
      final secondAttempt = state.beginRequest(_request('/second'));
      final firstResult = firstAttempt.run(() => firstCompletion.future);
      final secondResult = secondAttempt.run(() => secondCompletion.future);

      secondCompletion.complete(_outcome(202));
      state.retainResult(await secondResult);
      expect(state.interactions.map((value) => value.index), <int>[1]);

      firstCompletion.complete(_outcome(201));
      state.retainResult(await firstResult);

      expect(state.interactions.map((value) => value.index), <int>[0, 1]);
      expect(
        state.interactions.map(
          (value) =>
              (value.outcome as CassetteResponseOutcome).response.statusCode,
        ),
        <int>[201, 202],
      );
    });

    test('retains only the sanitised interaction', () async {
      final state = _state();
      final attempt = state.beginRequest(
        CassetteRequest(
          method: 'GET',
          uri: Uri.parse('https://example.test/?token=secret'),
        ),
      );

      final live = await attempt.run(() async => _outcome(200));
      final retained = state.retainResult(live);

      expect(retained, same(state.interactions.single));
      expect(retained.request.uri.queryParameters['token'], '[REDACTED]');
      expect(live.request.uri.queryParameters['token'], 'secret');
    });

    test('returns an immutable point-in-time snapshot', () async {
      final state = _state();
      final first = state.beginRequest(_request('/first'));
      final firstResult = await first.run(() async => _outcome(200));
      state.retainResult(firstResult);
      final snapshot = state.interactions;

      final second = state.beginRequest(_request('/second'));
      final secondResult = await second.run(() async => _outcome(201));
      state.retainResult(secondResult);

      expect(snapshot.map((value) => value.index), <int>[0]);
      expect(state.interactions.map((value) => value.index), <int>[0, 1]);
      expect(
        () => snapshot.add(state.interactions.last),
        throwsUnsupportedError,
      );
    });

    test('rejects duplicate and unadmitted indices before sanitisation',
        () async {
      var sanitiserCalls = 0;
      final state = _state(
        sanitisation: SanitisationConfiguration(
          requestSanitisers: <RequestSanitiser>[
            _CountingRequestSanitiser(() => sanitiserCalls++),
          ],
        ),
      );
      final attempt = state.beginRequest(_request('/first'));
      final result = await attempt.run(() async => _outcome(200));
      state.retainResult(result);
      expect(sanitiserCalls, 1);

      expect(() => state.retainResult(result), throwsStateError);
      expect(
        () => state.retainResult(
          RecordingRequestResult(
            arrivalIndex: 1,
            request: _request('/unadmitted'),
            outcome: _outcome(200),
          ),
        ),
        throwsStateError,
      );
      expect(sanitiserCalls, 1);
      expect(state.interactions, hasLength(1));
    });

    test('retains nothing when sanitisation fails', () async {
      final error = StateError('test sanitisation failure');
      final state = _state(
        sanitisation: SanitisationConfiguration(
          requestSanitisers: <RequestSanitiser>[
            _ThrowingRequestSanitiser(error),
          ],
        ),
      );
      final attempt = state.beginRequest(_request('/failure'));
      final result = await attempt.run(() async => _outcome(200));

      expect(() => state.retainResult(result), throwsA(same(error)));
      expect(state.interactions, isEmpty);
    });

    test('abandons retained interactions and rejects direct retention',
        () async {
      final state = _state();
      final first = state.beginRequest(_request('/first'));
      final firstResult = await first.run(() async => _outcome(200));
      state.retainResult(firstResult);
      final late = state.beginRequest(_request('/late'));
      final lateResult = await late.run(() async => _outcome(201));

      state.abandon();

      expect(state.acceptsRequests, isFalse);
      expect(state.interactions, isEmpty);
      expect(() => state.retainResult(lateResult), throwsStateError);
    });
  });
}

ActiveRecordingState _state({
  SanitisationConfiguration? sanitisation,
}) =>
    ActiveRecordingState(
      cassetteName: CassetteName('recording'),
      configuration: CassetteConfiguration(sanitisation: sanitisation),
      options: const RecordingOptions(),
      targetPresence: RecordingTargetPresence.absent,
    );

CassetteRequest _request(String path) => CassetteRequest(
      method: 'GET',
      uri: Uri.parse('https://example.test$path'),
    );

CassetteOutcome _outcome(int statusCode) => CassetteResponseOutcome(
      CassetteResponse(statusCode: statusCode),
    );

final class _CountingRequestSanitiser implements RequestSanitiser {
  const _CountingRequestSanitiser(this.onCall);

  final void Function() onCall;

  @override
  SanitisedRequest sanitise(CassetteRequest request) {
    onCall();
    return SanitisedRequest(
      request: request,
      exclusions: MatchingExclusions.none,
    );
  }
}

final class _ThrowingRequestSanitiser implements RequestSanitiser {
  const _ThrowingRequestSanitiser(this.error);

  final Object error;

  @override
  SanitisedRequest sanitise(CassetteRequest request) => throw error;
}

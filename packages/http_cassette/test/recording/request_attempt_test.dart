import 'dart:async';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/recording/active_state.dart';
import 'package:test/test.dart';

void main() {
  group('recording request attempt', () {
    test('assigns the index before starting asynchronous transport work',
        () async {
      final state = _state();
      final firstCompletion = Completer<CassetteOutcome>();
      final secondCompletion = Completer<CassetteOutcome>();
      final firstRequest = _request('/first');
      final secondRequest = _request('/second');

      final firstAttempt = state.beginRequest(firstRequest);
      final firstResult = firstAttempt.run(() => firstCompletion.future);
      final secondAttempt = state.beginRequest(secondRequest);
      final secondResult = secondAttempt.run(() => secondCompletion.future);

      expect(firstAttempt.arrivalIndex, 0);
      expect(secondAttempt.arrivalIndex, 1);
      secondCompletion.complete(_outcome(202));
      firstCompletion.complete(_outcome(201));

      final completedSecond = await secondResult;
      final completedFirst = await firstResult;
      expect(completedFirst.arrivalIndex, 0);
      expect(completedFirst.request, same(firstRequest));
      expect(
          (completedFirst.outcome as CassetteResponseOutcome)
              .response
              .statusCode,
          201);
      expect(completedSecond.arrivalIndex, 1);
      expect(completedSecond.request, same(secondRequest));
      expect(
          (completedSecond.outcome as CassetteResponseOutcome)
              .response
              .statusCode,
          202);
    });

    test('uses an independent one-shot guard for each admitted request',
        () async {
      final state = _state();
      final first = state.beginRequest(_request('/first'));
      final second = state.beginRequest(_request('/second'));
      var repeatedCallbackInvoked = false;

      await first.run(() async => _outcome(200));
      await expectLater(
        first.run(() async {
          repeatedCallbackInvoked = true;
          return _outcome(500);
        }),
        throwsA(
          isA<CassetteException>().having(
            (exception) => exception.diagnostic.category,
            'category',
            DiagnosticCategory.realTransportAttemptRepeated,
          ),
        ),
      );
      final secondResult = await second.run(() async => _outcome(204));

      expect(repeatedCallbackInvoked, isFalse);
      expect(
        (secondResult.outcome as CassetteResponseOutcome).response.statusCode,
        204,
      );
    });

    test('produces no result when the real attempt fails', () async {
      final state = _state();
      final operation = state.beginRequest(_request('/failure'));
      final error = StateError('test adapter failure');

      await expectLater(
        operation.run(() {
          throw error;
        }),
        throwsA(same(error)),
      );

      expect(state.assignArrivalIndex(), 1);
    });
  });
}

ActiveRecordingState _state() => ActiveRecordingState(
      cassetteName: CassetteName('recording'),
      configuration: CassetteConfiguration(),
      options: const RecordingOptions(),
    );

CassetteRequest _request(String path) => CassetteRequest(
      method: 'POST',
      uri: Uri.parse('https://example.test$path'),
    );

CassetteOutcome _outcome(int statusCode) => CassetteResponseOutcome(
      CassetteResponse(statusCode: statusCode),
    );

import 'dart:async';
import 'dart:convert';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/recording/active_state.dart';
import 'package:test/test.dart';

void main() {
  group('active recording capture', () {
    test('returns the live outcome and retains only sanitised values',
        () async {
      final state = _state();
      final request = CassetteRequest(
        method: 'POST',
        uri: Uri.parse('https://example.test/orders?token=request-secret'),
        headers: CassetteHeaders(<String, Iterable<String>>{
          'authorization': <String>['Bearer request-secret'],
        }),
      );
      final liveOutcome = CassetteResponseOutcome(
        CassetteResponse(
          statusCode: 201,
          headers: CassetteHeaders(<String, Iterable<String>>{
            'content-type': <String>['application/json'],
          }),
          body: utf8.encode('{"token":"response-secret"}'),
        ),
      );
      var invocationCount = 0;

      final returned = await state.recordRequest(request, () async {
        invocationCount++;
        return liveOutcome;
      });

      expect(returned, same(liveOutcome));
      expect(invocationCount, 1);
      final retained = state.interactions.single;
      expect(retained.index, 0);
      expect(retained.request.uri.queryParameters['token'], '[REDACTED]');
      expect(
        retained.request.headers.values('authorization'),
        <String>['[REDACTED]'],
      );
      expect(request.uri.queryParameters['token'], 'request-secret');
      final retainedResponse =
          (retained.outcome as CassetteResponseOutcome).response;
      expect(
        jsonDecode(utf8.decode(retainedResponse.body)),
        <String, Object?>{'token': '[REDACTED]'},
      );
      expect(
        jsonDecode(utf8.decode(liveOutcome.response.body)),
        <String, Object?>{'token': 'response-secret'},
      );
    });

    test('retains concurrent captures in admission order', () async {
      final state = _state();
      final firstCompletion = Completer<CassetteOutcome>();
      final secondCompletion = Completer<CassetteOutcome>();

      final first = state.recordRequest(
        _request('/first'),
        () => firstCompletion.future,
      );
      final second = state.recordRequest(
        _request('/second'),
        () => secondCompletion.future,
      );
      secondCompletion.complete(_outcome(202));
      await second;
      firstCompletion.complete(_outcome(201));
      await first;

      expect(state.interactions.map((value) => value.index), <int>[0, 1]);
      expect(
        state.interactions.map(
          (value) =>
              (value.outcome as CassetteResponseOutcome).response.statusCode,
        ),
        <int>[201, 202],
      );
    });

    test('retains nothing when the real attempt fails', () async {
      final state = _state();
      final error = StateError('test adapter failure');

      await expectLater(
        state.recordRequest(_request('/failure'), () {
          throw error;
        }),
        throwsA(same(error)),
      );

      expect(state.interactions, isEmpty);
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
      var invocationCount = 0;

      await expectLater(
        state.recordRequest(_request('/failure'), () async {
          invocationCount++;
          return _outcome(200);
        }),
        throwsA(same(error)),
      );

      expect(invocationCount, 1);
      expect(state.interactions, isEmpty);
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
    );

CassetteRequest _request(String path) => CassetteRequest(
      method: 'GET',
      uri: Uri.parse('https://example.test$path'),
    );

CassetteOutcome _outcome(int statusCode) => CassetteResponseOutcome(
      CassetteResponse(statusCode: statusCode),
    );

final class _ThrowingRequestSanitiser implements RequestSanitiser {
  const _ThrowingRequestSanitiser(this.error);

  final Object error;

  @override
  SanitisedRequest sanitise(CassetteRequest request) => throw error;
}

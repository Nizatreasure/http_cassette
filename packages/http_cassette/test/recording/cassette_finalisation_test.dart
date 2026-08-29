import 'dart:async';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/cassette.dart';
import 'package:http_cassette/src/recording/active_state.dart';
import 'package:test/test.dart';

void main() {
  group('recording cassette finalisation', () {
    test('creates a valid empty current-writable cassette', () {
      final cassette = _state().finaliseCassette();

      expect(cassette.schemaVersion, currentWritableCassetteSchemaVersion);
      expect(cassette.interactions, isEmpty);
    });

    test('uses retained interactions in request-arrival order', () async {
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

      final cassette = state.finaliseCassette();

      expect(cassette.interactions.map((value) => value.index), <int>[0, 1]);
      expect(
        cassette.interactions.map(
          (value) =>
              (value.outcome as CassetteResponseOutcome).response.statusCode,
        ),
        <int>[201, 202],
      );
      expect(
        () => cassette.interactions.add(cassette.interactions.first),
        throwsUnsupportedError,
      );
    });

    test('rejects finalisation while an admitted request is pending', () async {
      final state = _state();
      final completion = Completer<CassetteOutcome>();
      final capture = state.recordRequest(
        _request('/pending'),
        () => completion.future,
      );

      expect(state.finaliseCassette, throwsStateError);

      completion.complete(_outcome(200));
      await capture;
      expect(state.finaliseCassette().interactions, hasLength(1));
    });

    test('rejects finalisation after an admitted attempt fails', () async {
      final state = _state();

      await expectLater(
        state.recordRequest(_request('/failed'), () async {
          throw StateError('test transport failure');
        }),
        throwsA(
          isA<CassetteException>().having(
            (exception) => exception.diagnostic.category,
            'category',
            DiagnosticCategory.adapterContractViolation,
          ),
        ),
      );

      expect(state.interactions, isEmpty);
      expect(state.finaliseCassette, throwsStateError);
    });

    test('seals request admission after successful finalisation', () {
      final state = _state();
      final cassette = state.finaliseCassette();

      expect(state.acceptsRequests, isFalse);
      expect(state.isFinalised, isTrue);
      expect(state.finaliseCassette(), same(cassette));
      expect(() => state.beginRequest(_request('/late')), throwsStateError);
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

CassetteOutcome _outcome(int statusCode) => CassetteResponseOutcome(
      CassetteResponse(statusCode: statusCode),
    );

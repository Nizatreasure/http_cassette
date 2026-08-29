import 'dart:async';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/cassette.dart';
import 'package:http_cassette/src/engine/cassette_engine.dart';
import 'package:http_cassette/src/replay/active_state.dart';
import 'package:test/test.dart';

void main() {
  group('EngineState recording execution', () {
    test('captures through the retained active recording state', () async {
      final state = _engineState();
      await state.startRecording(
        CassetteName('recording'),
        const RecordingOptions(),
      );
      final outcome = CassetteResponseOutcome(
        CassetteResponse(statusCode: 201),
      );
      var attempts = 0;

      final result = await state.executeActiveRecordingRequest(
        _request('/items'),
        () async {
          attempts++;
          return outcome;
        },
      );

      expect(result, same(outcome));
      expect(attempts, 1);
      expect(state.activeRecording!.interactions, hasLength(1));
      expect(state.activeRecording!.interactions.single.index, 0);
    });

    test('threads cancellation through the active recording route', () async {
      final state = _engineState();
      await state.startRecording(
        CassetteName('cancelled-recording'),
        const RecordingOptions(),
      );
      final cancellation = _ManualCancellation();
      final completion = Completer<CassetteOutcome>();

      final execution = state.executeActiveRecordingRequest(
        _request('/cancelled'),
        () => completion.future,
        cancellation: cancellation,
      );
      cancellation.cancel();

      await expectLater(
        execution,
        throwsA(
          isA<CassetteException>().having(
            (exception) => exception.diagnostic.category,
            'category',
            DiagnosticCategory.cancelled,
          ),
        ),
      );
      expect(state.activeRecording!.interactions, isEmpty);

      completion.complete(_outcome());
      await Future<void>.delayed(Duration.zero);
      expect(state.activeRecording!.interactions, isEmpty);
    });

    test('rejects execution when no cassette session is active', () async {
      final state = _engineState();
      var attempted = false;

      await expectLater(
        state.executeActiveRecordingRequest(_request('/items'), () async {
          attempted = true;
          return _outcome();
        }),
        throwsA(
          isA<CassetteException>()
              .having(
                (exception) => exception.diagnostic.category,
                'category',
                DiagnosticCategory.noActiveSession,
              )
              .having(
                (exception) => exception.diagnostic.networkAccess,
                'network access',
                NetworkAccess.notAttempted,
              ),
        ),
      );
      expect(attempted, isFalse);
    });

    test('rejects recording execution during a replay session', () async {
      final state = _engineState();
      _activateReplay(state);
      var attempted = false;

      await expectLater(
        state.executeActiveRecordingRequest(_request('/items'), () async {
          attempted = true;
          return _outcome();
        }),
        throwsA(
          isA<CassetteException>()
              .having(
                (exception) => exception.diagnostic.category,
                'category',
                DiagnosticCategory.conflictingSessionOperation,
              )
              .having(
                (exception) => exception.diagnostic.networkAccess,
                'network access',
                NetworkAccess.disabled,
              ),
        ),
      );
      expect(attempted, isFalse);
    });

    test('rejects execution after the recording session closes', () async {
      final state = _engineState();
      final session = await state.startRecording(
        CassetteName('recording'),
        const RecordingOptions(),
      );
      await session.close();
      var attempted = false;

      await expectLater(
        state.executeActiveRecordingRequest(_request('/items'), () async {
          attempted = true;
          return _outcome();
        }),
        throwsA(
          isA<CassetteException>().having(
            (exception) => exception.diagnostic.category,
            'category',
            DiagnosticCategory.noActiveSession,
          ),
        ),
      );
      expect(attempted, isFalse);
    });
  });
}

EngineState _engineState() => EngineState(
      store: MemoryCassetteStore(),
      configuration: CassetteConfiguration(),
    );

void _activateReplay(EngineState state) {
  final name = CassetteName('replay');
  state.activeReplay = ActiveReplayState(
    cassetteName: name,
    cassette: Cassette(),
    configuration: state.configuration,
    options: const ReplayOptions(),
  );
  state.sessions.acquire(
    name: name,
    mode: CassetteMode.replay,
    closeAction: state.completeReplayLifecycleOnly,
    discardAction: state.completeReplayLifecycleOnly,
  );
}

CassetteRequest _request(String path) => CassetteRequest(
      method: 'POST',
      uri: Uri.parse('https://example.test$path'),
    );

CassetteOutcome _outcome() => CassetteResponseOutcome(
      CassetteResponse(statusCode: 200),
    );

final class _ManualCancellation implements CassetteCancellation {
  final _completion = Completer<void>();

  var _isCancelled = false;

  @override
  bool get isCancelled => _isCancelled;

  @override
  Future<void> get whenCancelled => _completion.future;

  void cancel() {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    _completion.complete();
  }
}

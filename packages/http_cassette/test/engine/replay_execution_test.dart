import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/cassette.dart';
import 'package:http_cassette/src/cassette/interaction.dart';
import 'package:http_cassette/src/engine/cassette_engine.dart';
import 'package:http_cassette/src/replay/active_state.dart';
import 'package:test/test.dart';

void main() {
  group('EngineState replay execution', () {
    test('resolves through the retained active replay state', () {
      final state = _engineState();
      final outcome = CassetteResponseOutcome(
        CassetteResponse(statusCode: 204),
      );
      _activateReplay(
        state,
        Cassette(
          interactions: <CassetteInteraction>[
            CassetteInteraction(
              index: 0,
              request: _request('/items'),
              outcome: outcome,
            ),
          ],
        ),
      );

      final result = state.executeActiveReplayRequest(_request('/items'));

      expect(result, same(outcome));
    });

    test('rejects execution when no cassette session is active', () {
      final state = _engineState();

      expect(
        () => state.executeActiveReplayRequest(_request('/items')),
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
                NetworkAccess.disabled,
              ),
        ),
      );
    });

    test('rejects replay execution during a recording session', () {
      final state = _engineState();
      state.sessions.acquire(
        name: CassetteName('recording'),
        mode: CassetteMode.record,
        closeAction: _complete,
        discardAction: _complete,
      );

      expect(
        () => state.executeActiveReplayRequest(_request('/items')),
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
    });

    test('retains no replay executor after successful close', () async {
      final state = _engineState();
      final session = _activateReplay(state, Cassette());

      await session.close();

      expect(state.activeReplay, isNull);
      expect(
        () => state.executeActiveReplayRequest(_request('/items')),
        throwsA(
          isA<CassetteException>().having(
            (exception) => exception.diagnostic.category,
            'category',
            DiagnosticCategory.noActiveSession,
          ),
        ),
      );
    });
  });
}

EngineState _engineState() => EngineState(
      store: MemoryCassetteStore(),
      configuration: CassetteConfiguration(),
    );

CassetteSession _activateReplay(EngineState state, Cassette cassette) {
  final name = CassetteName('replay');
  state.activeReplay = ActiveReplayState(
    cassetteName: name,
    cassette: cassette,
    configuration: state.configuration,
    options: const ReplayOptions(),
  );
  return state.sessions.acquire(
    name: name,
    mode: CassetteMode.replay,
    closeAction: state.completeReplayLifecycleOnly,
    discardAction: state.completeReplayLifecycleOnly,
  );
}

CassetteRequest _request(String path) => CassetteRequest(
      method: 'GET',
      uri: Uri.parse('https://example.test$path'),
    );

Future<void> _complete() => Future<void>.value();

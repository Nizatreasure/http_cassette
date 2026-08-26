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

    test('consumes matching interactions in recorded-index order', () {
      final state = _engineState();
      final firstOutcome = CassetteResponseOutcome(
        CassetteResponse(statusCode: 201),
      );
      final secondOutcome = CassetteResponseOutcome(
        CassetteResponse(statusCode: 202),
      );
      _activateReplay(
        state,
        Cassette(
          interactions: <CassetteInteraction>[
            CassetteInteraction(
              index: 0,
              request: _request('/items'),
              outcome: firstOutcome,
            ),
            CassetteInteraction(
              index: 1,
              request: _request('/items'),
              outcome: secondOutcome,
            ),
          ],
        ),
      );

      final first = state.executeActiveReplayRequest(_request('/items'));
      final second = state.executeActiveReplayRequest(_request('/items'));

      expect(first, same(firstOutcome));
      expect(second, same(secondOutcome));
      expect(
        state.activeReplay!.selectionStates.single.usageSnapshot
            .usedRecordedIndices,
        <int>[0, 1],
      );
    });

    test('reports a no-match failure through the engine route', () {
      final state = _engineState();
      _activateReplay(
        state,
        Cassette(
          interactions: <CassetteInteraction>[
            _interaction(0, '/items'),
          ],
        ),
      );

      expect(
        () => state.executeActiveReplayRequest(_request('/missing')),
        throwsA(
          isA<CassetteException>()
              .having(
                (exception) => exception.diagnostic.category,
                'category',
                DiagnosticCategory.noMatchingInteraction,
              )
              .having(
                (exception) => exception.diagnostic.networkAccess,
                'network access',
                NetworkAccess.disabled,
              ),
        ),
      );
    });

    test('reports exhaustion only after consuming every strict match', () {
      final state = _engineState();
      _activateReplay(
        state,
        Cassette(
          interactions: <CassetteInteraction>[
            _interaction(0, '/items'),
            _interaction(1, '/items'),
          ],
        ),
      );

      expect(
        state.executeActiveReplayRequest(_request('/items')),
        isA<CassetteResponseOutcome>(),
      );
      expect(
        state.executeActiveReplayRequest(_request('/items')),
        isA<CassetteResponseOutcome>(),
      );
      expect(
        () => state.executeActiveReplayRequest(_request('/items')),
        throwsA(
          isA<CassetteException>()
              .having(
                (exception) => exception.diagnostic.category,
                'category',
                DiagnosticCategory.interactionsExhausted,
              )
              .having(
                (exception) => exception.diagnostic.networkAccess,
                'network access',
                NetworkAccess.disabled,
              ),
        ),
      );
      expect(
        state.activeReplay!.selectionStates.single.usageSnapshot
            .usedRecordedIndices,
        <int>[0, 1],
      );
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

CassetteInteraction _interaction(int index, String path) => CassetteInteraction(
      index: index,
      request: _request(path),
      outcome: CassetteResponseOutcome(
        CassetteResponse(statusCode: 200 + index),
      ),
    );

Future<void> _complete() => Future<void>.value();

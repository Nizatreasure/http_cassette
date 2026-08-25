import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/cassette.dart';
import 'package:http_cassette/src/cassette/interaction.dart';
import 'package:http_cassette/src/replay/active_state.dart';
import 'package:http_cassette/src/replay/execution.dart';
import 'package:test/test.dart';

void main() {
  group('executeReplayRequest', () {
    test('returns the exact recorded outcome selected by replay state', () {
      final outcome = CassetteResponseOutcome(
        CassetteResponse(statusCode: 204),
      );
      final state = _state(
        interactions: <CassetteInteraction>[
          CassetteInteraction(
            index: 0,
            request: _request('/items'),
            outcome: outcome,
          ),
        ],
      );

      final result = executeReplayRequest(
        state: state,
        request: _request('/items'),
      );

      expect(result, same(outcome));
    });

    test('throws a safe specialised no-match exception', () {
      final state = _state(
        name: 'missing',
        interactions: <CassetteInteraction>[
          _interaction(0, '/items'),
        ],
      );

      expect(
        () => executeReplayRequest(
          state: state,
          request: _request('/missing'),
        ),
        throwsA(
          isA<CassetteException>()
              .having(
                (exception) => exception.diagnostic.category,
                'category',
                DiagnosticCategory.noMatchingInteraction,
              )
              .having(
                (exception) => exception.toString(),
                'safe specialised text',
                allOf(
                  contains('Cassette: missing'),
                  contains(
                      'Network access: disabled; no real request was made'),
                ),
              ),
        ),
      );
    });

    test('throws a safe specialised exception after strict exhaustion', () {
      final state = _state(
        name: 'exhausted',
        interactions: <CassetteInteraction>[
          _interaction(0, '/items'),
        ],
      );
      executeReplayRequest(state: state, request: _request('/items'));

      expect(
        () => executeReplayRequest(
          state: state,
          request: _request('/items'),
        ),
        throwsA(
          isA<CassetteException>()
              .having(
                (exception) => exception.diagnostic.category,
                'category',
                DiagnosticCategory.interactionsExhausted,
              )
              .having(
                (exception) => exception.toString(),
                'safe specialised text',
                allOf(
                  contains('Cassette: exhausted'),
                  contains('Request: method=GET; arrival=1'),
                  contains(
                      'Network access: disabled; no real request was made'),
                ),
              ),
        ),
      );
    });
  });
}

ActiveReplayState _state({
  String name = 'replay',
  required Iterable<CassetteInteraction> interactions,
}) =>
    ActiveReplayState(
      cassetteName: CassetteName(name),
      cassette: Cassette(interactions: interactions),
      configuration: CassetteConfiguration(),
      options: const ReplayOptions(),
    );

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

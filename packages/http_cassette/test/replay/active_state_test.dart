import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/cassette.dart';
import 'package:http_cassette/src/cassette/interaction.dart';
import 'package:http_cassette/src/replay/active_state.dart';
import 'package:http_cassette/src/replay/selection.dart';
import 'package:test/test.dart';

void main() {
  group('ActiveReplayState', () {
    test('retains validated identity, cassette and matching configuration', () {
      final name = CassetteName('checkout/success');
      final cassette = Cassette();
      final configuration = CassetteConfiguration(
        matching: MatchingConfiguration(
          includedHeaders: const <String>['accept'],
        ),
      );

      final state = ActiveReplayState(
        cassetteName: name,
        cassette: cassette,
        configuration: configuration,
        options: const ReplayOptions(),
      );

      expect(state.cassetteName, same(name));
      expect(state.cassette, same(cassette));
      expect(state.matcher.configuration, same(configuration.matching));
    });

    test('resolves the engine replay policy once by default', () {
      final state = ActiveReplayState(
        cassetteName: CassetteName('default-policy'),
        cassette: Cassette(),
        configuration: CassetteConfiguration(
          defaultReplayPolicy: ReplayPolicy.last,
        ),
        options: const ReplayOptions(),
      );

      expect(state.replayPolicy, ReplayPolicy.last);
      expect(state.requireAllInteractions, isFalse);
    });

    test('retains the session policy override and verification choice', () {
      final state = ActiveReplayState(
        cassetteName: CassetteName('session-policy'),
        cassette: Cassette(),
        configuration: CassetteConfiguration(
          defaultReplayPolicy: ReplayPolicy.strict,
        ),
        options: const ReplayOptions(
          policy: ReplayPolicy.cycle,
          requireAllInteractions: true,
        ),
      );

      expect(state.replayPolicy, ReplayPolicy.cycle);
      expect(state.requireAllInteractions, isTrue);
    });

    test('assigns monotonic request-arrival indices from zero', () {
      final state = _state('arrival');

      expect(state.selectRequest(_request('/one')).arrivalIndex, 0);
      expect(state.selectRequest(_request('/two')).arrivalIndex, 1);
      expect(state.selectRequest(_request('/three')).arrivalIndex, 2);
    });

    test('keeps arrival indices independent between sessions', () {
      final first = _state('first');
      final second = _state('second');

      expect(first.selectRequest(_request('/one')).arrivalIndex, 0);
      expect(first.selectRequest(_request('/two')).arrivalIndex, 1);
      expect(second.selectRequest(_request('/one')).arrivalIndex, 0);
    });

    test('assigns, matches and consumes one group synchronously', () {
      final state = _state(
        'strict',
        interactions: <CassetteInteraction>[
          _interaction(0, '/items'),
          _interaction(1, '/items'),
          _interaction(2, '/other'),
        ],
      );
      final incoming = _request('/items');

      final first = state.selectRequest(incoming);
      final second = state.selectRequest(_request('/items'));
      final exhausted = state.selectRequest(incoming);

      expect(first.arrivalIndex, 0);
      expect(
        (first.result as ReplayInteractionSelected).interaction.index,
        0,
      );
      expect(second.arrivalIndex, 1);
      expect(
        (second.result as ReplayInteractionSelected).interaction.index,
        1,
      );
      expect(exhausted.arrivalIndex, 2);
      expect(exhausted.result, isA<ReplayGroupExhausted>());
      expect(first.state, same(second.state));
      expect(second.state, same(exhausted.state));
      expect(state.selectionStates, <ReplaySelectionState>[first.state]);
    });

    test('keeps different recorded-index groups independent', () {
      final state = _state(
        'groups',
        interactions: <CassetteInteraction>[
          _interaction(0, '/items'),
          _interaction(1, '/items'),
          _interaction(2, '/other'),
        ],
      );

      final items = state.selectRequest(_request('/items'));
      final other = state.selectRequest(_request('/other'));

      expect(items.state, isNot(same(other.state)));
      expect(
        (other.result as ReplayInteractionSelected).interaction.index,
        2,
      );
      expect(state.selectionStates, <ReplaySelectionState>[
        items.state,
        other.state,
      ]);
      expect(
        () => state.selectionStates.add(items.state),
        throwsUnsupportedError,
      );
    });

    test('applies the resolved reusable policy to each matching group', () {
      final state = _state(
        'last',
        interactions: <CassetteInteraction>[
          _interaction(0, '/items'),
          _interaction(1, '/items'),
        ],
        policy: ReplayPolicy.last,
      );

      final first = state.selectRequest(_request('/items'));
      final second = state.selectRequest(_request('/items'));

      expect(
        (first.result as ReplayInteractionSelected).interaction.index,
        1,
      );
      expect(
        (second.result as ReplayInteractionSelected).interaction.index,
        1,
      );
      expect(first.state, same(second.state));
    });

    test('assigns an arrival index when no interaction matches', () {
      final state = _state(
        'missing',
        interactions: <CassetteInteraction>[_interaction(0, '/items')],
      );

      final selection = state.selectRequest(_request('/missing'));

      expect(selection.arrivalIndex, 0);
      expect(selection.result, isA<ReplayNoMatch>());
      expect(selection.state.matchingInteractions, isEmpty);
      expect(selection.noMatchDiagnostic, isNotNull);
      expect(
          selection.noMatchDiagnostic!.context.cassetteName.value, 'missing');
      expect(selection.noMatchDiagnostic!.context.request.arrivalIndex, 0);
      expect(selection.noMatchDiagnostic!.consideredInteractionCount, 1);
      expect(selection.noMatchDiagnostic!.closestRecordedIndex, 0);
    });

    test('does not assemble a no-match diagnostic for other results', () {
      final state = _state(
        'selected',
        interactions: <CassetteInteraction>[_interaction(0, '/items')],
      );

      final selected = state.selectRequest(_request('/items'));
      final exhausted = state.selectRequest(_request('/items'));

      expect(selected.noMatchDiagnostic, isNull);
      expect(exhausted.result, isA<ReplayGroupExhausted>());
      expect(exhausted.noMatchDiagnostic, isNull);
    });

    test('does not compare candidates again for no-match diagnostics', () {
      final component = _CountingMatcherComponent();
      final state = ActiveReplayState(
        cassetteName: CassetteName('single-pass'),
        cassette: Cassette(
          interactions: <CassetteInteraction>[
            _interaction(0, '/first'),
            _interaction(1, '/second'),
          ],
        ),
        configuration: CassetteConfiguration(
          matching: MatchingConfiguration(
            customComponents: <RequestMatcherComponent>[component],
          ),
        ),
        options: const ReplayOptions(),
      );

      final selection = state.selectRequest(_request('/missing'));

      expect(selection.result, isA<ReplayNoMatch>());
      expect(selection.noMatchDiagnostic, isNotNull);
      expect(component.comparisonCount, 2);
    });
  });
}

ActiveReplayState _state(
  String name, {
  Iterable<CassetteInteraction> interactions = const <CassetteInteraction>[],
  ReplayPolicy policy = ReplayPolicy.strict,
}) =>
    ActiveReplayState(
      cassetteName: CassetteName(name),
      cassette: Cassette(interactions: interactions),
      configuration: CassetteConfiguration(defaultReplayPolicy: policy),
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

final class _CountingMatcherComponent implements RequestMatcherComponent {
  var comparisonCount = 0;

  @override
  String get name => 'counting';

  @override
  MatchComponentResult compare(
    CassetteRequest expected,
    CassetteRequest actual,
    MatchContext context,
  ) {
    comparisonCount++;
    return MatchComponentResult(matches: true);
  }
}

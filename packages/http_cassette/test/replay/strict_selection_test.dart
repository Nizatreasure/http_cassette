import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/interaction.dart';
import 'package:http_cassette/src/replay/selection.dart';
import 'package:test/test.dart';

void main() {
  test('reports no match for an empty group without consuming', () {
    final state = ReplaySelectionState.strict(const <CassetteInteraction>[]);

    expect(state.select(), isA<ReplayNoMatch>());
    expect(state.select(), isA<ReplayNoMatch>());
    expect(state.consumedCount, 0);
    expect(state.policy, ReplayPolicy.strict);
  });

  test('selects the lowest recorded unconsumed index each time', () {
    final state = ReplaySelectionState.strict(<CassetteInteraction>[
      _interaction(5),
      _interaction(1),
      _interaction(3),
    ]);

    expect(_selectedIndex(state.select()), 1);
    expect(_selectedIndex(state.select()), 3);
    expect(_selectedIndex(state.select()), 5);
    expect(state.consumedCount, 3);
  });

  test('reports exhaustion after consuming every match once', () {
    final state = ReplaySelectionState.strict(<CassetteInteraction>[
      _interaction(0),
      _interaction(1),
    ]);

    expect(state.select(), isA<ReplayInteractionSelected>());
    expect(state.select(), isA<ReplayInteractionSelected>());
    expect(state.select(), isA<ReplayGroupExhausted>());
    expect(state.select(), isA<ReplayGroupExhausted>());
    expect(state.consumedCount, 2);
  });

  test('preserves identical interactions as separate consumable entries', () {
    final first = _interaction(0);
    final second = _interaction(1);
    final state = ReplaySelectionState.strict(<CassetteInteraction>[
      first,
      second,
    ]);

    expect((state.select() as ReplayInteractionSelected).interaction, first);
    expect((state.select() as ReplayInteractionSelected).interaction, second);
  });

  test('copies and exposes the matching group immutably', () {
    final source = <CassetteInteraction>[_interaction(0)];
    final state = ReplaySelectionState.strict(source);
    source.clear();

    expect(state.matchingInteractions.length, 1);
    expect(
      () => state.matchingInteractions.add(_interaction(1)),
      throwsUnsupportedError,
    );
  });

  test('rejects duplicate recorded indices', () {
    expect(
      () => ReplaySelectionState.strict(<CassetteInteraction>[
        _interaction(0),
        _interaction(0),
      ]),
      throwsArgumentError,
    );
  });
}

int _selectedIndex(ReplaySelectionResult result) =>
    (result as ReplayInteractionSelected).interaction.index;

CassetteInteraction _interaction(int index) => CassetteInteraction(
      index: index,
      request: CassetteRequest(
        method: 'GET',
        uri: Uri.parse('https://example.test/items'),
      ),
      outcome: CassetteResponseOutcome(
        CassetteResponse(statusCode: 200),
      ),
    );

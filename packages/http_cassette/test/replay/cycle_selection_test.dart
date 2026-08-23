import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/interaction.dart';
import 'package:http_cassette/src/replay/selection.dart';
import 'package:test/test.dart';

void main() {
  test('advances in recorded-index order and wraps to the first', () {
    final state = ReplaySelectionState.cycle(<CassetteInteraction>[
      _interaction(5),
      _interaction(1),
      _interaction(3),
    ]);

    expect(_selectedIndex(state.select()), 1);
    expect(state.consumedCount, 1);
    expect(_selectedIndex(state.select()), 3);
    expect(state.consumedCount, 2);
    expect(_selectedIndex(state.select()), 5);
    expect(state.consumedCount, 3);
    expect(_selectedIndex(state.select()), 1);
    expect(_selectedIndex(state.select()), 3);
    expect(_selectedIndex(state.select()), 5);
    expect(_selectedIndex(state.select()), 1);
    expect(state.consumedCount, 3);
    expect(state.policy, ReplayPolicy.cycle);
  });

  test('reports no match for an empty group without exhaustion', () {
    final state = ReplaySelectionState.cycle(const <CassetteInteraction>[]);

    expect(state.select(), isA<ReplayNoMatch>());
    expect(state.select(), isA<ReplayNoMatch>());
    expect(state.consumedCount, 0);
  });

  test('reuses a sole interaction indefinitely', () {
    final interaction = _interaction(2);
    final state = ReplaySelectionState.cycle(
      <CassetteInteraction>[interaction],
    );

    for (var call = 0; call < 4; call++) {
      final selected = state.select() as ReplayInteractionSelected;
      expect(selected.interaction, same(interaction));
    }
    expect(state.consumedCount, 1);
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
      outcome: CassetteResponseOutcome(CassetteResponse(statusCode: 200)),
    );

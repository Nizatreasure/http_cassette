import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/interaction.dart';
import 'package:http_cassette/src/replay/selection.dart';
import 'package:test/test.dart';

void main() {
  test('first always reuses the lowest recorded index', () {
    final state = ReplaySelectionState.first(<CassetteInteraction>[
      _interaction(5),
      _interaction(1),
      _interaction(3),
    ]);

    expect(_selectedIndex(state.select()), 1);
    expect(_selectedIndex(state.select()), 1);
    expect(_selectedIndex(state.select()), 1);
    expect(state.policy, ReplayPolicy.first);
    expect(state.consumedCount, 1);
  });

  test('last always reuses the highest recorded index', () {
    final state = ReplaySelectionState.last(<CassetteInteraction>[
      _interaction(5),
      _interaction(1),
      _interaction(3),
    ]);

    expect(_selectedIndex(state.select()), 5);
    expect(_selectedIndex(state.select()), 5);
    expect(_selectedIndex(state.select()), 5);
    expect(state.policy, ReplayPolicy.last);
    expect(state.consumedCount, 1);
  });

  test('first reports no match for an empty group without exhaustion', () {
    final state = ReplaySelectionState.first(const <CassetteInteraction>[]);

    expect(state.select(), isA<ReplayNoMatch>());
    expect(state.select(), isA<ReplayNoMatch>());
    expect(state.consumedCount, 0);
  });

  test('last reports no match for an empty group without exhaustion', () {
    final state = ReplaySelectionState.last(const <CassetteInteraction>[]);

    expect(state.select(), isA<ReplayNoMatch>());
    expect(state.select(), isA<ReplayNoMatch>());
    expect(state.consumedCount, 0);
  });

  test('first and last select the same sole interaction indefinitely', () {
    final interaction = _interaction(4);
    final first =
        ReplaySelectionState.first(<CassetteInteraction>[interaction]);
    final last = ReplaySelectionState.last(<CassetteInteraction>[interaction]);

    for (var call = 0; call < 3; call++) {
      expect(
        (first.select() as ReplayInteractionSelected).interaction,
        same(interaction),
      );
      expect(
        (last.select() as ReplayInteractionSelected).interaction,
        same(interaction),
      );
    }
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

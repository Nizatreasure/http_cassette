import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/interaction.dart';
import 'package:http_cassette/src/replay/exhaustion.dart';
import 'package:http_cassette/src/replay/selection.dart';
import 'package:test/test.dart';

void main() {
  test('captures complete value-free facts from actual exhaustion', () {
    final state = ReplaySelectionState.strict(<CassetteInteraction>[
      _interaction(5),
      _interaction(1),
      _interaction(3),
    ]);
    state.select();
    state.select();
    state.select();
    final exhausted = state.select();

    final details = ReplayExhaustionDetails.fromSelection(
      state: state,
      result: exhausted,
    );

    expect(details.replayPolicy, ReplayPolicy.strict);
    expect(details.matchingGroupSize, 3);
    expect(details.usedInteractionCount, 3);
    expect(details.recordedIndices, <int>[1, 3, 5]);
    expect(details.networkAccess, NetworkAccess.disabled);
  });

  test('copies recorded indices immutably', () {
    final state = ReplaySelectionState.strict(<CassetteInteraction>[
      _interaction(0),
    ]);
    state.select();
    final details = ReplayExhaustionDetails.fromSelection(
      state: state,
      result: state.select(),
    );

    expect(
      () => details.recordedIndices.add(1),
      throwsUnsupportedError,
    );
  });

  test('rejects an exhausted result from another selection state', () {
    final exhaustedState = ReplaySelectionState.strict(<CassetteInteraction>[
      _interaction(0),
    ]);
    exhaustedState.select();
    final exhausted = exhaustedState.select();
    final otherState = ReplaySelectionState.strict(<CassetteInteraction>[
      _interaction(0),
    ]);
    otherState.select();

    expect(
      () => ReplayExhaustionDetails.fromSelection(
        state: otherState,
        result: exhausted,
      ),
      throwsArgumentError,
    );
  });

  test('rejects selected and no-match results', () {
    final state = ReplaySelectionState.strict(<CassetteInteraction>[
      _interaction(0),
    ]);
    final selected = state.select();

    for (final result in <ReplaySelectionResult>[
      selected,
      const ReplayNoMatch(),
    ]) {
      expect(
        () => ReplayExhaustionDetails.fromSelection(
          state: state,
          result: result,
        ),
        throwsArgumentError,
      );
    }
  });

  test('has structural equality and matching hash codes', () {
    ReplayExhaustionDetails details() {
      final state = ReplaySelectionState.strict(<CassetteInteraction>[
        _interaction(0),
      ]);
      state.select();
      return ReplayExhaustionDetails.fromSelection(
        state: state,
        result: state.select(),
      );
    }

    final first = details();
    final second = details();

    expect(first, second);
    expect(first.hashCode, second.hashCode);
  });
}

CassetteInteraction _interaction(int index) => CassetteInteraction(
      index: index,
      request: CassetteRequest(
        method: 'POST',
        uri: Uri.parse(
          'https://example.test/private/$index?field=private-value',
        ),
      ),
      outcome: CassetteResponseOutcome(
        CassetteResponse(statusCode: 200, body: <int>[1, 2, 3]),
      ),
    );

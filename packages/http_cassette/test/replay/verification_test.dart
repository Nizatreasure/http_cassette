import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/cassette.dart';
import 'package:http_cassette/src/cassette/interaction.dart';
import 'package:http_cassette/src/replay/selection.dart';
import 'package:http_cassette/src/replay/verification.dart';
import 'package:test/test.dart';

void main() {
  group('ReplayUsageSnapshot', () {
    test('is an immutable canonical point-in-time value', () {
      final state = ReplaySelectionState.strict(<CassetteInteraction>[
        _interaction(3),
        _interaction(1),
      ]);
      state.select();
      final first = state.usageSnapshot;
      state.select();

      expect(first.usedRecordedIndices, <int>[1]);
      expect(state.usageSnapshot.usedRecordedIndices, <int>[1, 3]);
      expect(
        () => first.usedRecordedIndices.add(5),
        throwsUnsupportedError,
      );
    });

    test('canonicalises duplicates and rejects negative indices', () {
      final snapshot = ReplayUsageSnapshot(<int>[3, 1, 3]);

      expect(snapshot.usedRecordedIndices, <int>[1, 3]);
      expect(() => ReplayUsageSnapshot(<int>[-1]), throwsArgumentError);
    });
  });

  group('verifyReplayUsage', () {
    test('skips verification by default without inspecting usage', () {
      final result = verifyReplayUsage(
        cassette: _cassette(3),
        usageSnapshots: <ReplayUsageSnapshot>[
          ReplayUsageSnapshot(<int>[99]),
        ],
      );

      expect(result, isA<ReplayVerificationSkipped>());
    });

    test('passes when snapshots collectively cover the cassette', () {
      final result = verifyReplayUsage(
        cassette: _cassette(4),
        usageSnapshots: <ReplayUsageSnapshot>[
          ReplayUsageSnapshot(<int>[2, 0]),
          ReplayUsageSnapshot(<int>[3, 1, 2]),
        ],
        requireAllInteractions: true,
      );

      expect(result, isA<ReplayVerificationPassed>());
    });

    test('reports every unused index in recorded order immutably', () {
      final result = verifyReplayUsage(
        cassette: _cassette(5),
        usageSnapshots: <ReplayUsageSnapshot>[
          ReplayUsageSnapshot(<int>[4, 0, 2]),
        ],
        requireAllInteractions: true,
      ) as ReplayUnusedInteractions;

      expect(result.totalInteractionCount, 5);
      expect(result.usedInteractionCount, 3);
      expect(result.unusedRecordedIndices, <int>[1, 3]);
      expect(
        () => result.unusedRecordedIndices.add(5),
        throwsUnsupportedError,
      );
      final equivalent = verifyReplayUsage(
        cassette: _cassette(5),
        usageSnapshots: <ReplayUsageSnapshot>[
          ReplayUsageSnapshot(<int>[0, 2, 4]),
        ],
        requireAllInteractions: true,
      );
      expect(result, equivalent);
      expect(result.hashCode, equivalent.hashCode);
    });

    test('passes an empty cassette when verification is required', () {
      final result = verifyReplayUsage(
        cassette: Cassette(),
        usageSnapshots: const <ReplayUsageSnapshot>[],
        requireAllInteractions: true,
      );

      expect(result, isA<ReplayVerificationPassed>());
    });

    test('rejects usage outside the cassette when verification runs', () {
      expect(
        () => verifyReplayUsage(
          cassette: _cassette(2),
          usageSnapshots: <ReplayUsageSnapshot>[
            ReplayUsageSnapshot(<int>[2]),
          ],
          requireAllInteractions: true,
        ),
        throwsStateError,
      );
    });
  });
}

Cassette _cassette(int length) => Cassette(
      interactions: List<CassetteInteraction>.generate(
        length,
        _interaction,
        growable: false,
      ),
    );

CassetteInteraction _interaction(int index) => CassetteInteraction(
      index: index,
      request: CassetteRequest(
        method: 'GET',
        uri: Uri.parse('https://example.test/items/$index'),
      ),
      outcome: CassetteResponseOutcome(CassetteResponse(statusCode: 200)),
    );

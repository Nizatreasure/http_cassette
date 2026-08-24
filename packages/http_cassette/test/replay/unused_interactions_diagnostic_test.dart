import 'package:http_cassette/src/cassette/cassette.dart';
import 'package:http_cassette/src/cassette/interaction.dart';
import 'package:http_cassette/src/cassette/name.dart';
import 'package:http_cassette/src/diagnostics/diagnostic.dart';
import 'package:http_cassette/src/model/http_message.dart';
import 'package:http_cassette/src/model/outcome.dart';
import 'package:http_cassette/src/replay/configuration.dart';
import 'package:http_cassette/src/replay/selection.dart';
import 'package:http_cassette/src/replay/unused_interactions_diagnostic.dart';
import 'package:http_cassette/src/replay/verification.dart';
import 'package:test/test.dart';

void main() {
  test('assembles complete fixed unused-interaction semantics', () {
    final diagnostic = _diagnostic();

    expect(
      diagnostic.envelope.category,
      DiagnosticCategory.unusedInteractions,
    );
    expect(
      diagnostic.envelope.summary,
      'Replay completed with unused interactions.',
    );
    expect(diagnostic.envelope.networkAccess, NetworkAccess.disabled);
    expect(diagnostic.cassetteName.value, 'checkout/declined');
    expect(diagnostic.replayPolicy, ReplayPolicy.strict);
    expect(diagnostic.totalInteractionCount, 4);
    expect(diagnostic.usedInteractionCount, 2);
    expect(diagnostic.unusedRecordedIndices, <int>[1, 3]);
  });

  test('rejects skipped and passed verification', () {
    for (final result in <ReplayVerificationResult>[
      const ReplayVerificationSkipped(),
      const ReplayVerificationPassed(),
    ]) {
      expect(
        () => ReplayUnusedInteractionsDiagnostic.fromVerification(
          cassetteName: CassetteName('checkout/declined'),
          replayPolicy: ReplayPolicy.strict,
          result: result,
        ),
        throwsArgumentError,
      );
    }
  });

  test('has structural equality and matching hash codes', () {
    expect(_diagnostic(), _diagnostic());
    expect(_diagnostic().hashCode, _diagnostic().hashCode);
  });
}

ReplayUnusedInteractionsDiagnostic _diagnostic() {
  final result = verifyReplayUsage(
    cassette: _cassette(4),
    usageSnapshots: <ReplayUsageSnapshot>[
      ReplayUsageSnapshot(<int>[0, 2]),
    ],
    requireAllInteractions: true,
  );
  return ReplayUnusedInteractionsDiagnostic.fromVerification(
    cassetteName: CassetteName('checkout/declined'),
    replayPolicy: ReplayPolicy.strict,
    result: result,
  );
}

Cassette _cassette(int length) => Cassette(
      interactions: List<CassetteInteraction>.generate(
        length,
        (index) => CassetteInteraction(
          index: index,
          request: CassetteRequest(
            method: 'GET',
            uri: Uri.parse('https://example.test/items/$index'),
          ),
          outcome: CassetteResponseOutcome(
            CassetteResponse(statusCode: 200),
          ),
        ),
        growable: false,
      ),
    );

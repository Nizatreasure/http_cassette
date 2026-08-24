import 'package:http_cassette/src/cassette/cassette.dart';
import 'package:http_cassette/src/cassette/interaction.dart';
import 'package:http_cassette/src/cassette/name.dart';
import 'package:http_cassette/src/model/http_message.dart';
import 'package:http_cassette/src/model/outcome.dart';
import 'package:http_cassette/src/replay/configuration.dart';
import 'package:http_cassette/src/replay/selection.dart';
import 'package:http_cassette/src/replay/unused_interactions_diagnostic.dart';
import 'package:http_cassette/src/replay/unused_interactions_formatter.dart';
import 'package:http_cassette/src/replay/verification.dart';
import 'package:test/test.dart';

void main() {
  test('renders complete verification information in stable order', () {
    final diagnostic = _diagnostic(
      cassetteName: 'checkout/declined',
      interactionCount: 4,
      usedIndices: <int>[0, 2],
    );

    expect(
      diagnostic.format(),
      '''HTTP Cassette failure: Replay completed with unused interactions.
Category: unusedInteractions
Cassette: checkout/declined
Verification: 4 interactions; 2 used; 2 unused
Replay policy: strict
Unused indices: 1, 3
Network access: disabled; no real request was made''',
    );
    expect(diagnostic.format(), diagnostic.format());
    expect(diagnostic.format(), isNot(endsWith('\n')));
  });

  test('bounds cassette identity and unused indices explicitly', () {
    final cassetteName = List<String>.filled(140, 'a').join();
    final text = _diagnostic(
      cassetteName: cassetteName,
      interactionCount: 20,
      usedIndices: const <int>[],
    ).format();

    final displayedName = List<String>.filled(128, 'a').join();
    expect(text, contains('$displayedName... (140 characters)'));
    expect(
      text,
      contains(
        'Unused indices: 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, '
        '12, 13, 14, 15 ... (4 omitted)',
      ),
    );
    expect(text, isNot(contains('16, 17')));
  });
}

ReplayUnusedInteractionsDiagnostic _diagnostic({
  required String cassetteName,
  required int interactionCount,
  required List<int> usedIndices,
}) {
  final cassette = Cassette(
    interactions: List<CassetteInteraction>.generate(
      interactionCount,
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
  final result = verifyReplayUsage(
    cassette: cassette,
    usageSnapshots: <ReplayUsageSnapshot>[
      ReplayUsageSnapshot(usedIndices),
    ],
    requireAllInteractions: true,
  );
  return ReplayUnusedInteractionsDiagnostic.fromVerification(
    cassetteName: CassetteName(cassetteName),
    replayPolicy: ReplayPolicy.strict,
    result: result,
  );
}

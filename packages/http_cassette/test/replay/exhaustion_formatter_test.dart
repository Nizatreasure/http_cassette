import 'package:http_cassette/src/cassette/interaction.dart';
import 'package:http_cassette/src/cassette/name.dart';
import 'package:http_cassette/src/model/http_message.dart';
import 'package:http_cassette/src/model/outcome.dart';
import 'package:http_cassette/src/replay/diagnostic_context.dart';
import 'package:http_cassette/src/replay/exhaustion.dart';
import 'package:http_cassette/src/replay/exhaustion_diagnostic.dart';
import 'package:http_cassette/src/replay/exhaustion_formatter.dart';
import 'package:http_cassette/src/replay/selection.dart';
import 'package:test/test.dart';

void main() {
  test('renders complete exhaustion information in stable order', () {
    final diagnostic = _diagnostic(
      cassetteName: 'checkout/declined',
      interactionCount: 2,
    );

    expect(
      diagnostic.format(),
      '''HTTP Cassette failure: Matching interactions were exhausted.
Category: interactionsExhausted
Cassette: checkout/declined
Request: method=POST; arrival=6; body=3 bytes
Matching group: 2 interactions; 2 used
Replay policy: strict
Recorded indices: 0, 1
Network access: disabled; no real request was made''',
    );
    expect(diagnostic.format(), diagnostic.format());
    expect(diagnostic.format(), isNot(endsWith('\n')));
  });

  test('bounds cassette identity and recorded indices explicitly', () {
    final cassetteName = List<String>.filled(140, 'a').join();
    final text = _diagnostic(
      cassetteName: cassetteName,
      interactionCount: 20,
    ).format();

    final displayedName = List<String>.filled(128, 'a').join();
    expect(text, contains('$displayedName... (140 characters)'));
    expect(
      text,
      contains(
        'Recorded indices: 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, '
        '12, 13, 14, 15 ... (4 omitted)',
      ),
    );
    expect(text, isNot(contains('16, 17')));
  });

  test('does not render URI, body or response values', () {
    final text = _diagnostic(
      cassetteName: 'safe-name',
      interactionCount: 1,
    ).format();

    expect(text, isNot(contains('example.test')));
    expect(text, isNot(contains('private-value')));
    expect(text, isNot(contains('response-value')));
  });
}

ReplayExhaustionDiagnostic _diagnostic({
  required String cassetteName,
  required int interactionCount,
}) {
  final request = CassetteRequest(
    method: 'POST',
    uri: Uri.parse('https://example.test/private?field=private-value'),
    body: const <int>[1, 2, 3],
  );
  final state = ReplaySelectionState.strict(
    List<CassetteInteraction>.generate(
      interactionCount,
      (index) => CassetteInteraction(
        index: index,
        request: request,
        outcome: CassetteResponseOutcome(
          CassetteResponse(
            statusCode: 200,
            body: 'response-value'.codeUnits,
          ),
        ),
      ),
    ),
  );
  for (var index = 0; index < interactionCount; index++) {
    state.select();
  }
  final exhausted = state.select();

  return ReplayExhaustionDiagnostic(
    context: ReplayDiagnosticContext(
      cassetteName: CassetteName(cassetteName),
      request: ReplayRequestSummary.fromRequest(
        request: request,
        arrivalIndex: 6,
      ),
    ),
    details: ReplayExhaustionDetails.fromSelection(
      state: state,
      result: exhausted,
    ),
  );
}

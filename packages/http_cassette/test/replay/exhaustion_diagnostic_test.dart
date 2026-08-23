import 'package:http_cassette/src/cassette/interaction.dart';
import 'package:http_cassette/src/cassette/name.dart';
import 'package:http_cassette/src/diagnostics/diagnostic.dart';
import 'package:http_cassette/src/model/http_message.dart';
import 'package:http_cassette/src/model/outcome.dart';
import 'package:http_cassette/src/replay/diagnostic_context.dart';
import 'package:http_cassette/src/replay/exhaustion.dart';
import 'package:http_cassette/src/replay/exhaustion_diagnostic.dart';
import 'package:http_cassette/src/replay/selection.dart';
import 'package:test/test.dart';

void main() {
  test('assembles complete fixed exhaustion semantics', () {
    final diagnostic = _diagnostic();

    expect(
      diagnostic.envelope.category,
      DiagnosticCategory.interactionsExhausted,
    );
    expect(
      diagnostic.envelope.summary,
      'Matching interactions were exhausted.',
    );
    expect(diagnostic.envelope.networkAccess, NetworkAccess.disabled);
    expect(diagnostic.context.cassetteName.value, 'checkout/declined');
    expect(diagnostic.context.request.method, 'POST');
    expect(diagnostic.context.request.arrivalIndex, 6);
    expect(diagnostic.details.matchingGroupSize, 2);
    expect(diagnostic.details.usedInteractionCount, 2);
    expect(diagnostic.details.recordedIndices, <int>[0, 1]);
  });

  test('does not retain request or response values through assembly', () {
    final diagnostic = _diagnostic();
    final renderedObject = diagnostic.toString();

    expect(renderedObject, isNot(contains('private-value')));
    expect(renderedObject, isNot(contains('response-value')));
    expect(diagnostic.context.request.bodyByteLength, 3);
  });

  test('has structural equality and matching hash codes', () {
    expect(_diagnostic(), _diagnostic());
    expect(_diagnostic().hashCode, _diagnostic().hashCode);
  });
}

ReplayExhaustionDiagnostic _diagnostic() {
  final request = CassetteRequest(
    method: 'POST',
    uri: Uri.parse('https://example.test/private?field=private-value'),
    body: const <int>[1, 2, 3],
  );
  final state = ReplaySelectionState.strict(<CassetteInteraction>[
    _interaction(0, request),
    _interaction(1, request),
  ]);
  state.select();
  state.select();
  final exhausted = state.select();

  return ReplayExhaustionDiagnostic(
    context: ReplayDiagnosticContext(
      cassetteName: CassetteName('checkout/declined'),
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

CassetteInteraction _interaction(int index, CassetteRequest request) =>
    CassetteInteraction(
      index: index,
      request: request,
      outcome: CassetteResponseOutcome(
        CassetteResponse(
          statusCode: 200,
          body: 'response-value'.codeUnits,
        ),
      ),
    );

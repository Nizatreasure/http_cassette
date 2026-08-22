import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/interaction.dart';
import 'package:test/test.dart';

void main() {
  group('CassetteInteraction', () {
    test('contains one canonical response outcome', () {
      final request = _request();
      final outcome = CassetteResponseOutcome(
        CassetteResponse(statusCode: 204),
      );
      final exclusions = MatchingExclusions(
        headers: <String>{'authorization'},
      );

      final interaction = CassetteInteraction(
        index: 0,
        request: request,
        matchingExclusions: exclusions,
        outcome: outcome,
      );

      expect(interaction.index, 0);
      expect(interaction.request, same(request));
      expect(interaction.matchingExclusions, same(exclusions));
      expect(interaction.outcome, same(outcome));
    });

    test('contains one portable transport failure outcome', () {
      final outcome = CassetteTransportFailure(
        category: TransportFailureCategory.timeout,
        message: 'The request timed out.',
      );

      final interaction = CassetteInteraction(
        index: 1,
        request: _request(),
        outcome: outcome,
      );

      expect(interaction.outcome, same(outcome));
      expect(interaction.matchingExclusions, same(MatchingExclusions.none));
    });

    test('rejects a negative arrival index', () {
      expect(
        () => CassetteInteraction(
          index: -1,
          request: _request(),
          outcome: CassetteResponseOutcome(
            CassetteResponse(statusCode: 200),
          ),
        ),
        throwsArgumentError,
      );
    });

    test('uses structural equality and matching hash codes', () {
      CassetteInteraction interaction() => CassetteInteraction(
            index: 2,
            request: _request(),
            matchingExclusions: MatchingExclusions(
              queryParameters: <String>{'token'},
              body: true,
            ),
            outcome: CassetteTransportFailure(
              category: TransportFailureCategory.connection,
              message: 'Connection failed.',
            ),
          );

      final first = interaction();
      final second = interaction();

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });
  });
}

CassetteRequest _request() => CassetteRequest(
      method: 'GET',
      uri: Uri.parse('https://example.test/items'),
    );

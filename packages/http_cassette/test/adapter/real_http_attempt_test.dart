import 'package:http_cassette/http_cassette.dart';
import 'package:test/test.dart';

void main() {
  group('RealHttpAttempt', () {
    test('returns a canonical response outcome', () async {
      final outcome = CassetteResponseOutcome(
        CassetteResponse(statusCode: 204),
      );
      Future<CassetteOutcome> attempt() async => outcome;

      expect(await _run(attempt), same(outcome));
    });

    test('returns a canonical transport failure', () async {
      final outcome = CassetteTransportFailure(
        category: TransportFailureCategory.connection,
        message: 'The connection failed.',
      );
      Future<CassetteOutcome> attempt() async => outcome;

      expect(await _run(attempt), same(outcome));
    });
  });
}

Future<CassetteOutcome> _run(RealHttpAttempt attempt) => attempt();

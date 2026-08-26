import 'dart:convert';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/recording/active_state.dart';
import 'package:http_cassette/src/recording/request_attempt.dart';
import 'package:test/test.dart';

void main() {
  group('recording interaction projection', () {
    test('sanitises request and response before creating the interaction', () {
      final state = _state();
      final result = RecordingRequestResult(
        arrivalIndex: 3,
        request: CassetteRequest(
          method: 'POST',
          uri: Uri.parse(
            'https://example.test/orders?access_token=request-secret',
          ),
          headers: CassetteHeaders(<String, Iterable<String>>{
            'authorization': <String>['Bearer request-secret'],
            'content-type': <String>['application/json'],
          }),
          body: utf8.encode('{"token":"request-secret"}'),
        ),
        outcome: CassetteResponseOutcome(
          CassetteResponse(
            statusCode: 201,
            headers: CassetteHeaders(<String, Iterable<String>>{
              'content-type': <String>['application/json'],
              'set-cookie': <String>['session=response-secret'],
            }),
            body: utf8.encode('{"token":"response-secret"}'),
          ),
        ),
      );

      final interaction = state.sanitiseResult(result);

      expect(interaction.index, 3);
      expect(
        interaction.request.uri.queryParameters['access_token'],
        '[REDACTED]',
      );
      expect(
        interaction.request.headers.values('authorization'),
        <String>['[REDACTED]'],
      );
      expect(
        jsonDecode(utf8.decode(interaction.request.body)),
        <String, Object?>{'token': '[REDACTED]'},
      );
      expect(
        interaction.matchingExclusions.queryParameters,
        <String>{'access_token'},
      );
      expect(
        interaction.matchingExclusions.headers,
        <String>{'authorization'},
      );
      expect(interaction.matchingExclusions.jsonPointers, <String>{'/token'});
      final response =
          (interaction.outcome as CassetteResponseOutcome).response;
      expect(response.headers.values('set-cookie'), <String>['[REDACTED]']);
      expect(
        jsonDecode(utf8.decode(response.body)),
        <String, Object?>{'token': '[REDACTED]'},
      );
      expect(
        result.request.headers.values('authorization'),
        <String>['Bearer request-secret'],
      );
      expect(
        (result.outcome as CassetteResponseOutcome)
            .response
            .headers
            .values('set-cookie'),
        <String>['session=response-secret'],
      );
    });

    test('preserves a safe canonical transport failure unchanged', () {
      final state = _state();
      final failure = CassetteTransportFailure(
        category: TransportFailureCategory.timeout,
        message: 'The request timed out.',
      );
      final result = RecordingRequestResult(
        arrivalIndex: 0,
        request: CassetteRequest(
          method: 'GET',
          uri: Uri.parse('https://example.test/?token=secret'),
        ),
        outcome: failure,
      );

      final interaction = state.sanitiseResult(result);

      expect(interaction.outcome, same(failure));
      expect(interaction.request.uri.queryParameters['token'], '[REDACTED]');
      expect(
        interaction.matchingExclusions.queryParameters,
        <String>{'token'},
      );
    });

    test('returns no interaction when sanitisation fails', () {
      final error = StateError('test sanitisation failure');
      final state = _state(
        sanitisation: SanitisationConfiguration(
          requestSanitisers: <RequestSanitiser>[
            _ThrowingRequestSanitiser(error),
          ],
        ),
      );
      final result = RecordingRequestResult(
        arrivalIndex: 0,
        request: CassetteRequest(
          method: 'GET',
          uri: Uri.parse('https://example.test/'),
        ),
        outcome: CassetteResponseOutcome(CassetteResponse(statusCode: 200)),
      );

      expect(() => state.sanitiseResult(result), throwsA(same(error)));
    });
  });
}

ActiveRecordingState _state({
  SanitisationConfiguration? sanitisation,
}) =>
    ActiveRecordingState(
      cassetteName: CassetteName('recording'),
      configuration: CassetteConfiguration(sanitisation: sanitisation),
      options: const RecordingOptions(),
    );

final class _ThrowingRequestSanitiser implements RequestSanitiser {
  const _ThrowingRequestSanitiser(this.error);

  final Object error;

  @override
  SanitisedRequest sanitise(CassetteRequest request) => throw error;
}

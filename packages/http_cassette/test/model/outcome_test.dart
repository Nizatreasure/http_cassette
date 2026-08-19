import 'package:http_cassette/http_cassette.dart';
import 'package:test/test.dart';

void main() {
  group('CassetteResponseOutcome', () {
    test('retains a canonical response', () {
      final response = CassetteResponse(statusCode: 204);
      final outcome = CassetteResponseOutcome(response);

      expect(outcome.response, same(response));
    });

    test('has structural equality and matching hash codes', () {
      final first = CassetteResponseOutcome(
        CassetteResponse(statusCode: 200, body: <int>[1, 2, 3]),
      );
      final second = CassetteResponseOutcome(
        CassetteResponse(statusCode: 200, body: <int>[1, 2, 3]),
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });
  });

  group('CassetteTransportFailure', () {
    test('retains portable safe failure information', () {
      final failure = CassetteTransportFailure(
        category: TransportFailureCategory.connection,
        message: 'The connection could not be completed.',
      );

      expect(failure.category, TransportFailureCategory.connection);
      expect(failure.message, 'The connection could not be completed.');
    });

    test('has structural equality and matching hash codes', () {
      final first = CassetteTransportFailure(
        category: TransportFailureCategory.timeout,
        message: 'The operation timed out.',
      );
      final second = CassetteTransportFailure(
        category: TransportFailureCategory.timeout,
        message: 'The operation timed out.',
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    test('distinguishes different structured values', () {
      final failure = CassetteTransportFailure(
        category: TransportFailureCategory.connection,
        message: 'The connection could not be completed.',
      );

      expect(
        failure,
        isNot(
          CassetteTransportFailure(
            category: TransportFailureCategory.timeout,
            message: 'The connection could not be completed.',
          ),
        ),
      );
      expect(
        failure,
        isNot(
          CassetteTransportFailure(
            category: TransportFailureCategory.connection,
            message: 'The connection ended unexpectedly.',
          ),
        ),
      );
    });

    test('rejects empty and surrounding whitespace', () {
      expect(
        () => CassetteTransportFailure(
          category: TransportFailureCategory.other,
          message: '',
        ),
        throwsArgumentError,
      );
      expect(
        () => CassetteTransportFailure(
          category: TransportFailureCategory.other,
          message: ' Unsafe message ',
        ),
        throwsArgumentError,
      );
    });

    test('rejects control and bidirectional formatting characters safely', () {
      for (final message in <String>[
        'Unsafe\nmessage',
        'Unsafe\tmessage',
        'Unsafe\u2028message',
        'Unsafe\u202Emessage',
        'Unsafe\u2066message',
      ]) {
        expect(
          () => CassetteTransportFailure(
            category: TransportFailureCategory.other,
            message: message,
          ),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.toString(),
              'message',
              isNot(contains(message)),
            ),
          ),
          reason: message.codeUnits.toString(),
        );
      }
    });

    test('accepts at most 256 Unicode code points', () {
      final accepted = CassetteTransportFailure(
        category: TransportFailureCategory.other,
        message: List<String>.filled(256, 'é').join(),
      );

      expect(accepted.message.runes, hasLength(256));
      expect(
        () => CassetteTransportFailure(
          category: TransportFailureCategory.other,
          message: List<String>.filled(257, 'é').join(),
        ),
        throwsArgumentError,
      );
    });

    test('defines every portable V1 category', () {
      expect(TransportFailureCategory.values, <TransportFailureCategory>[
        TransportFailureCategory.nameResolution,
        TransportFailureCategory.connection,
        TransportFailureCategory.secureConnection,
        TransportFailureCategory.timeout,
        TransportFailureCategory.protocol,
        TransportFailureCategory.other,
      ]);
    });
  });

  test('outcome variants support exhaustive handling', () {
    String describe(CassetteOutcome outcome) => switch (outcome) {
          CassetteResponseOutcome() => 'response',
          CassetteTransportFailure() => 'transport failure',
        };

    expect(
      describe(CassetteResponseOutcome(CassetteResponse(statusCode: 200))),
      'response',
    );
    expect(
      describe(
        CassetteTransportFailure(
          category: TransportFailureCategory.protocol,
          message: 'The response was invalid.',
        ),
      ),
      'transport failure',
    );
  });
}

import 'package:http/http.dart' as http;
import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette_http/http_cassette_http.dart';
import 'package:http_cassette_http/src/http_transport_failure_translation.dart';
import 'package:test/test.dart';

void main() {
  test('maps a client failure conservatively without retaining its values', () {
    const secret = 'private host, path and transport detail';
    final failure = http.ClientException(
      secret,
      Uri.parse('https://user:password@example.test/private'),
    );

    final outcome = translateHttpTransportFailure(failure);

    expect(outcome.category, TransportFailureCategory.other);
    expect(outcome.message, 'The HTTP transport failed.');
    expect(outcome.message, isNot(contains(secret)));
    expect(outcome.message, isNot(contains('password')));
  });

  test('does not guess a category from client exception text', () {
    const messages = <String>[
      'DNS lookup failed',
      'certificate rejected',
      'connection timed out',
      'invalid HTTP protocol',
    ];

    for (final message in messages) {
      final outcome = translateHttpTransportFailure(
        http.ClientException(message),
      );

      expect(outcome.category, TransportFailureCategory.other);
      expect(outcome.message, 'The HTTP transport failed.');
    }
  });

  test('refuses to record caller cancellation', () {
    expect(
      () => translateHttpTransportFailure(
        http.RequestAbortedException(
          Uri.parse('https://example.test/items'),
        ),
      ),
      throwsArgumentError,
    );
  });

  test('reconstructs every portable category with safe metadata', () {
    for (final category in TransportFailureCategory.values) {
      final portable = CassetteTransportFailure(
        category: category,
        message: 'Safe replay failure.',
      );

      final reconstructed = reconstructHttpTransportFailure(portable);

      expect(reconstructed.message, 'Safe replay failure.');
      expect(reconstructed.uri, isNull);
      expect(reconstructed.cassetteException, isNull);
      expect(reconstructed.cassetteTransportFailure, same(portable));
    }
  });
}

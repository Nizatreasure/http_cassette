import 'package:dio/dio.dart';
import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette_dio/src/dio_transport_failure_translation.dart';
import 'package:test/test.dart';

void main() {
  final options = RequestOptions(path: 'https://example.test/items');

  test('maps every Dio timeout to one portable timeout', () {
    final timeoutTypes = DioExceptionType.values.where(
      (type) => type.name.endsWith('Timeout'),
    );

    for (final type in timeoutTypes) {
      final outcome = translateDioTransportFailure(
        DioException(requestOptions: options, type: type),
      );

      expect(outcome.category, TransportFailureCategory.timeout);
      expect(outcome.message, 'The HTTP transport operation timed out.');
    }
  });

  test('maps certificate failure without retaining Dio values', () {
    final secret = 'private certificate path and host';
    final outcome = translateDioTransportFailure(
      DioException(
        requestOptions: options,
        type: DioExceptionType.badCertificate,
        message: secret,
        error: StateError(secret),
      ),
    );

    expect(outcome.category, TransportFailureCategory.secureConnection);
    expect(outcome.message, 'The secure HTTP connection failed.');
    expect(outcome.message, isNot(contains(secret)));
  });

  test('maps connection failure without guessing name resolution', () {
    final outcome = translateDioTransportFailure(
      DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      ),
    );

    expect(outcome.category, TransportFailureCategory.connection);
    expect(outcome.message, 'The HTTP connection failed.');
  });

  test('maps an unknown failure to the portable fallback', () {
    final outcome = translateDioTransportFailure(
      DioException(
        requestOptions: options,
        error: StateError('machine-specific detail'),
      ),
    );

    expect(outcome.category, TransportFailureCategory.other);
    expect(outcome.message, 'The HTTP transport failed.');
  });

  test('refuses to record caller cancellation', () {
    final failure = DioException.requestCancelled(
      requestOptions: options,
      reason: 'caller reason',
    );

    expect(
      () => translateDioTransportFailure(failure),
      throwsArgumentError,
    );
  });

  test('refuses to turn a rejected status response into a failure', () {
    final failure = DioException.badResponse(
      statusCode: 500,
      requestOptions: options,
      response: Response<dynamic>(
        requestOptions: options,
        statusCode: 500,
      ),
    );

    expect(
      () => translateDioTransportFailure(failure),
      throwsArgumentError,
    );
  });
}

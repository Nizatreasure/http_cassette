import 'package:dio/dio.dart';
import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette_dio/http_cassette_dio.dart';
import 'package:http_cassette_dio/src/dio_cassette_exception.dart'
    show wrapCassetteExceptionForDio;
import 'package:test/test.dart';

void main() {
  final options = RequestOptions(path: 'https://example.test/items');

  test('wraps and exposes the exact safe cassette exception', () {
    final failure = CassetteException(
      CassetteDiagnostic(
        category: DiagnosticCategory.noMatchingInteraction,
        summary: 'No recorded interaction matched the request.',
        networkAccess: NetworkAccess.disabled,
      ),
    );
    final stackTrace = StackTrace.current;

    final wrapped = wrapCassetteExceptionForDio(
      failure,
      requestOptions: options,
      stackTrace: stackTrace,
    );

    expect(wrapped.type, DioExceptionType.unknown);
    expect(wrapped.requestOptions, same(options));
    expect(wrapped.error, same(failure));
    expect(wrapped.cassetteException, same(failure));
    expect(wrapped.message, failure.toString());
    expect(wrapped.stackTrace, same(stackTrace));
  });

  test('does not classify an ordinary Dio failure as a cassette failure', () {
    final failure = DioException.connectionError(
      requestOptions: options,
      reason: 'connection failed',
    );

    expect(failure.cassetteException, isNull);
  });

  test('does not classify a portable transport failure as a system failure',
      () {
    final portableFailure = CassetteTransportFailure(
      category: TransportFailureCategory.timeout,
      message: 'The HTTP transport operation timed out.',
    );
    final failure = DioException(
      requestOptions: options,
      error: portableFailure,
    );

    expect(failure.cassetteException, isNull);
  });
}

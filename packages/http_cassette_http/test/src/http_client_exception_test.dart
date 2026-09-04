import 'package:http/http.dart' as http;
import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette_http/src/http_client_exception.dart';
import 'package:test/test.dart';

void main() {
  test('ordinary client failures carry no cassette failure', () {
    final failure = http.ClientException(
      'ordinary failure',
      Uri.parse('https://example.test/items'),
    );

    expect(failure.cassetteException, isNull);
    expect(failure.cassetteTransportFailure, isNull);
  });

  test('retains one exact safe cassette-system failure without a URI', () {
    final cassetteFailure = CassetteException(
      CassetteDiagnostic(
        category: DiagnosticCategory.noMatchingInteraction,
        summary: 'No recorded interaction matched the HTTP request.',
        networkAccess: NetworkAccess.disabled,
      ),
    );

    final failure = wrapCassetteExceptionForHttp(cassetteFailure);

    expect(failure.cassetteException, same(cassetteFailure));
    expect(failure.cassetteTransportFailure, isNull);
    expect(failure.message, cassetteFailure.toString());
    expect(failure.uri, isNull);
  });

  test('cancellation carries no cassette failure', () {
    final failure = http.RequestAbortedException(
      Uri.parse('https://example.test/items'),
    );

    expect(failure.cassetteException, isNull);
    expect(failure.cassetteTransportFailure, isNull);
  });
}

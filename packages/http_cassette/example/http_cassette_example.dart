import 'package:http_cassette/http_cassette.dart';

void main() {
  final headers = CassetteHeaders(<String, Iterable<String>>{
    'Accept': <String>['application/json'],
  });
  final request = CassetteRequest(
    method: 'get',
    uri: Uri.parse('https://api.example.test/profile'),
    headers: headers,
  );
  final response = CassetteResponse(
    statusCode: 200,
    headers: CassetteHeaders(<String, Iterable<String>>{
      'Content-Type': <String>['application/json'],
    }),
    body: <int>[123, 125],
  );
  final outcome = CassetteResponseOutcome(response);
  final diagnostic = CassetteDiagnostic(
    category: DiagnosticCategory.cassetteMissing,
    summary: 'The cassette does not exist.',
    networkAccess: NetworkAccess.disabled,
  );

  assert(
    request.method == 'GET' &&
        outcome.response.body.length == 2 &&
        diagnostic.format().contains(
              'Network access: disabled; no real request was made',
            ),
  );
}

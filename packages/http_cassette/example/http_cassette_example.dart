import 'package:http_cassette/http_cassette.dart';

void main() {
  final cassetteName = CassetteName('profiles/current-user');
  final bodyLimits = BodyLimits();
  final matching = MatchingConfiguration(
    includedHeaders: <String>{'accept'},
    ignoredQueryParameters: <String>{'request_id'},
    customComponents: const <RequestMatcherComponent>[_ApiVersionMatcher()],
  );
  final sanitisation = SanitisationConfiguration(
    additionalHeaders: <String>{'x-project-secret'},
    additionalJsonPointers: <String>{'/customer/account_number'},
  );
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
    cassetteName.value == 'profiles/current-user' &&
        bodyLimits.requestBytes == 2 * 1024 * 1024 &&
        matching.includedHeaders.contains('accept') &&
        sanitisation.additionalHeaders.contains('x-project-secret') &&
        request.method == 'GET' &&
        outcome.response.body.length == 2 &&
        diagnostic.format().contains(
              'Network access: disabled; no real request was made',
            ),
  );
}

final class _ApiVersionMatcher implements RequestMatcherComponent {
  const _ApiVersionMatcher();

  @override
  String get name => 'api-version';

  @override
  MatchComponentResult compare(
    CassetteRequest expected,
    CassetteRequest actual,
    MatchContext context,
  ) {
    final matches = _equalValues(
      expected.headers.values('x-api-version'),
      actual.headers.values('x-api-version'),
    );
    return MatchComponentResult(
      matches: matches,
      differences: matches
          ? const <MatchDifference>[]
          : <MatchDifference>[
              MatchDifference(
                kind: MatchDifferenceKind.customComponentDifference,
                location: 'x-api-version',
              ),
            ],
    );
  }
}

bool _equalValues(List<String>? first, List<String>? second) {
  if (first == null || second == null) {
    return first == null && second == null;
  }
  if (first.length != second.length) {
    return false;
  }
  for (var index = 0; index < first.length; index += 1) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}

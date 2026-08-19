import 'package:http_cassette/http_cassette.dart';

void main() {
  final headers = CassetteHeaders(<String, Iterable<String>>{
    'Accept': <String>['application/json'],
  });
  final diagnostic = CassetteDiagnostic(
    category: DiagnosticCategory.cassetteMissing,
    summary: 'The cassette does not exist.',
    networkAccess: NetworkAccess.disabled,
  );

  assert(
    headers.values('accept')?.single == 'application/json' &&
        diagnostic.format().contains(
              'Network access: disabled; no real request was made',
            ),
  );
}

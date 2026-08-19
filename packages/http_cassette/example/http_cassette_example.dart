import 'package:http_cassette/http_cassette.dart';

void main() {
  final diagnostic = CassetteDiagnostic(
    category: DiagnosticCategory.cassetteMissing,
    summary: 'The cassette does not exist.',
    networkAccess: NetworkAccess.disabled,
  );

  assert(diagnostic.networkAccess == NetworkAccess.disabled);
}

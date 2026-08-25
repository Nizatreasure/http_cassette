import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/replay/store_read_diagnostic.dart';
import 'package:test/test.dart';

void main() {
  group('ReplayStoreReadDiagnostic', () {
    test('maps a missing replay cassette', () {
      final name = CassetteName('checkout/missing');

      final diagnostic = ReplayStoreReadDiagnostic.fromStoreFailure(
        CassetteStoreException.notFound(
          name: name,
          operation: CassetteStoreOperation.read,
        ),
      );

      expect(diagnostic.cassetteName, same(name));
      expect(diagnostic.storeFailureKind, CassetteStoreFailureKind.notFound);
      expect(diagnostic.envelope.category, DiagnosticCategory.cassetteMissing);
      expect(diagnostic.envelope.networkAccess, NetworkAccess.disabled);
      expect(
        diagnostic.envelope.summary,
        'The replay cassette does not exist.',
      );
    });

    test('maps a failed replay read as unreadable', () {
      final diagnostic = ReplayStoreReadDiagnostic.fromStoreFailure(
        CassetteStoreException.operationFailed(
          name: CassetteName('checkout/unreadable'),
          operation: CassetteStoreOperation.read,
        ),
      );

      expect(
        diagnostic.storeFailureKind,
        CassetteStoreFailureKind.operationFailed,
      );
      expect(
        diagnostic.envelope.category,
        DiagnosticCategory.cassetteUnreadable,
      );
      expect(diagnostic.envelope.networkAccess, NetworkAccess.disabled);
      expect(
        diagnostic.envelope.summary,
        'The replay cassette could not be read.',
      );
    });

    test('maps an unsupported replay read as unreadable', () {
      final diagnostic = ReplayStoreReadDiagnostic.fromStoreFailure(
        CassetteStoreException.unsupported(
          name: CassetteName('unsupported'),
          operation: CassetteStoreOperation.read,
        ),
      );

      expect(
        diagnostic.storeFailureKind,
        CassetteStoreFailureKind.unsupportedOperation,
      );
      expect(
        diagnostic.envelope.category,
        DiagnosticCategory.cassetteUnreadable,
      );
    });

    test('rejects a failure from a non-read store operation', () {
      expect(
        () => ReplayStoreReadDiagnostic.fromStoreFailure(
          CassetteStoreException.operationFailed(
            name: CassetteName('recording'),
            operation: CassetteStoreOperation.create,
          ),
        ),
        throwsArgumentError,
      );
    });

    test('has structural equality without retaining store values', () {
      ReplayStoreReadDiagnostic diagnostic(String name) =>
          ReplayStoreReadDiagnostic.fromStoreFailure(
            CassetteStoreException.operationFailed(
              name: CassetteName(name),
              operation: CassetteStoreOperation.read,
            ),
          );

      final first = diagnostic('checkout/failure');
      final second = diagnostic('checkout/failure');

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first, isNot(diagnostic('checkout/other')));
    });
  });
}

import 'package:http_cassette/http_cassette.dart';
import 'package:test/test.dart';

void main() {
  group('CassetteStoreException', () {
    test('represents every stable failure category', () {
      final name = CassetteName('checkout/failure');
      final failures = <CassetteStoreException>[
        CassetteStoreException.notFound(
          name: name,
          operation: CassetteStoreOperation.read,
        ),
        CassetteStoreException.alreadyExists(name),
        CassetteStoreException.revisionChanged(name),
        CassetteStoreException.unsupported(
          name: name,
          operation: CassetteStoreOperation.replaceIfUnchanged,
        ),
        CassetteStoreException.operationFailed(
          name: name,
          operation: CassetteStoreOperation.create,
        ),
      ];

      expect(
        failures.map((failure) => failure.kind),
        CassetteStoreFailureKind.values,
      );
      expect(failures.every((failure) => failure.name == name), isTrue);
    });

    test('fixes operation-specific failure combinations', () {
      final name = CassetteName('checkout');

      expect(
        CassetteStoreException.alreadyExists(name).operation,
        CassetteStoreOperation.create,
      );
      expect(
        CassetteStoreException.revisionChanged(name).operation,
        CassetteStoreOperation.replaceIfUnchanged,
      );
    });

    test('allows missing failures only for meaningful operations', () {
      final name = CassetteName('checkout');

      for (final operation in <CassetteStoreOperation>[
        CassetteStoreOperation.read,
        CassetteStoreOperation.replace,
        CassetteStoreOperation.replaceIfUnchanged,
      ]) {
        expect(
          CassetteStoreException.notFound(
            name: name,
            operation: operation,
          ).operation,
          operation,
        );
      }

      for (final operation in <CassetteStoreOperation>[
        CassetteStoreOperation.exists,
        CassetteStoreOperation.create,
      ]) {
        expect(
          () => CassetteStoreException.notFound(
            name: name,
            operation: operation,
          ),
          throwsArgumentError,
        );
      }
    });

    test('supports exhaustive category handling', () {
      String describe(CassetteStoreFailureKind kind) => switch (kind) {
            CassetteStoreFailureKind.notFound => 'not found',
            CassetteStoreFailureKind.alreadyExists => 'already exists',
            CassetteStoreFailureKind.revisionChanged => 'revision changed',
            CassetteStoreFailureKind.unsupportedOperation => 'unsupported',
            CassetteStoreFailureKind.operationFailed => 'failed',
          };

      expect(
        CassetteStoreFailureKind.values.map(describe),
        <String>[
          'not found',
          'already exists',
          'revision changed',
          'unsupported',
          'failed',
        ],
      );
    });

    test('formats only safe structured fields', () {
      final failure = CassetteStoreException.operationFailed(
        name: CassetteName('checkout/failure'),
        operation: CassetteStoreOperation.replace,
      );

      expect(
        failure.toString(),
        'CassetteStoreException('
        'operationFailed, replace, checkout/failure)',
      );
      expect(failure.toString(), isNot(contains('/Users/')));
    });
  });
}

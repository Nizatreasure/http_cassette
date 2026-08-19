import 'package:http_cassette/http_cassette.dart';
import 'package:test/test.dart';

void main() {
  group('DefaultCassetteDiagnosticFormatter', () {
    test('renders stable plain text without a trailing line feed', () {
      final diagnostic = CassetteDiagnostic(
        category: DiagnosticCategory.cassetteMissing,
        summary: 'The cassette does not exist.',
        networkAccess: NetworkAccess.disabled,
      );

      expect(
        const DefaultCassetteDiagnosticFormatter().format(diagnostic),
        '''HTTP Cassette failure: The cassette does not exist.
Category: cassetteMissing
Network access: disabled; no real request was made''',
      );
    });

    test('describes every network-access state explicitly', () {
      expect(
        _formatWith(NetworkAccess.disabled),
        contains('Network access: disabled; no real request was made'),
      );
      expect(
        _formatWith(NetworkAccess.notAttempted),
        contains('Network access: permitted; no real request was attempted'),
      );
      expect(
        _formatWith(NetworkAccess.attempted),
        contains('Network access: permitted; a real request was attempted'),
      );
    });

    test('renders every category by its stable name', () {
      for (final category in DiagnosticCategory.values) {
        final diagnostic = CassetteDiagnostic(
          category: category,
          summary: 'A safe failure occurred.',
          networkAccess: NetworkAccess.notAttempted,
        );

        expect(diagnostic.format(), contains('Category: ${category.name}\n'));
      }
    });

    test('is deterministic across repeated formatting', () {
      final diagnostic = CassetteDiagnostic(
        category: DiagnosticCategory.internalInvariantFailure,
        summary: 'An internal invariant failed.',
        networkAccess: NetworkAccess.notAttempted,
      );
      final formatter = const DefaultCassetteDiagnosticFormatter();

      expect(formatter.format(diagnostic), formatter.format(diagnostic));
    });

    test('keeps maximum-size output bounded', () {
      final diagnostic = CassetteDiagnostic(
        category: DiagnosticCategory.internalInvariantFailure,
        summary: List<String>.filled(256, 'é').join(),
        networkAccess: NetworkAccess.notAttempted,
      );

      expect(diagnostic.format().runes.length, lessThan(512));
    });
  });

  group('CassetteDiagnosticFormatting', () {
    test('supports an explicit custom formatter', () {
      final diagnostic = CassetteDiagnostic(
        category: DiagnosticCategory.cassetteMissing,
        summary: 'The cassette does not exist.',
        networkAccess: NetworkAccess.disabled,
      );

      expect(diagnostic.format(const _CategoryFormatter()), 'cassetteMissing');
    });
  });

  test('CassetteException uses the default formatter', () {
    final diagnostic = CassetteDiagnostic(
      category: DiagnosticCategory.cassetteMissing,
      summary: 'The cassette does not exist.',
      networkAccess: NetworkAccess.disabled,
    );

    expect(CassetteException(diagnostic).toString(), diagnostic.format());
  });
}

String _formatWith(NetworkAccess networkAccess) => CassetteDiagnostic(
      category: DiagnosticCategory.internalInvariantFailure,
      summary: 'A safe failure occurred.',
      networkAccess: networkAccess,
    ).format();

final class _CategoryFormatter implements CassetteDiagnosticFormatter {
  const _CategoryFormatter();

  @override
  String format(CassetteDiagnostic diagnostic) => diagnostic.category.name;
}

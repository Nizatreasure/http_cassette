import 'package:http_cassette/http_cassette.dart';
import 'package:test/test.dart';

void main() {
  group('CassetteDiagnostic', () {
    test('retains safe structured failure information', () {
      final diagnostic = CassetteDiagnostic(
        category: DiagnosticCategory.noMatchingInteraction,
        summary: 'No recorded interaction matched the request.',
        networkAccess: NetworkAccess.disabled,
      );

      expect(
        diagnostic.category,
        DiagnosticCategory.noMatchingInteraction,
      );
      expect(
        diagnostic.summary,
        'No recorded interaction matched the request.',
      );
      expect(diagnostic.networkAccess, NetworkAccess.disabled);
    });

    test('has structural equality and matching hash codes', () {
      final first = CassetteDiagnostic(
        category: DiagnosticCategory.cassetteMissing,
        summary: 'The cassette does not exist.',
        networkAccess: NetworkAccess.disabled,
      );
      final second = CassetteDiagnostic(
        category: DiagnosticCategory.cassetteMissing,
        summary: 'The cassette does not exist.',
        networkAccess: NetworkAccess.disabled,
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    test('distinguishes different structured values', () {
      final diagnostic = CassetteDiagnostic(
        category: DiagnosticCategory.cassetteMissing,
        summary: 'The cassette does not exist.',
        networkAccess: NetworkAccess.disabled,
      );

      expect(
        diagnostic,
        isNot(
          CassetteDiagnostic(
            category: DiagnosticCategory.cassetteUnreadable,
            summary: 'The cassette does not exist.',
            networkAccess: NetworkAccess.disabled,
          ),
        ),
      );
      expect(
        diagnostic,
        isNot(
          CassetteDiagnostic(
            category: DiagnosticCategory.cassetteMissing,
            summary: 'The cassette could not be found.',
            networkAccess: NetworkAccess.disabled,
          ),
        ),
      );
      expect(
        diagnostic,
        isNot(
          CassetteDiagnostic(
            category: DiagnosticCategory.cassetteMissing,
            summary: 'The cassette does not exist.',
            networkAccess: NetworkAccess.notAttempted,
          ),
        ),
      );
    });

    test('rejects empty and surrounding whitespace', () {
      expect(
        () => CassetteDiagnostic(
          category: DiagnosticCategory.internalInvariantFailure,
          summary: '',
          networkAccess: NetworkAccess.notAttempted,
        ),
        throwsArgumentError,
      );
      expect(
        () => CassetteDiagnostic(
          category: DiagnosticCategory.internalInvariantFailure,
          summary: ' Unsafe summary ',
          networkAccess: NetworkAccess.notAttempted,
        ),
        throwsArgumentError,
      );
    });

    test('rejects control and bidirectional formatting characters', () {
      for (final summary in <String>[
        'Unsafe\nsummary',
        'Unsafe\tsummary',
        'Unsafe\u2028summary',
        'Unsafe\u202Esummary',
        'Unsafe\u2066summary',
      ]) {
        expect(
          () => CassetteDiagnostic(
            category: DiagnosticCategory.internalInvariantFailure,
            summary: summary,
            networkAccess: NetworkAccess.notAttempted,
          ),
          throwsArgumentError,
          reason: summary.codeUnits.toString(),
        );
      }
    });

    test('accepts at most 256 Unicode code points', () {
      final accepted = CassetteDiagnostic(
        category: DiagnosticCategory.internalInvariantFailure,
        summary: List<String>.filled(256, 'é').join(),
        networkAccess: NetworkAccess.notAttempted,
      );

      expect(accepted.summary.runes, hasLength(256));
      expect(
        () => CassetteDiagnostic(
          category: DiagnosticCategory.internalInvariantFailure,
          summary: List<String>.filled(257, 'é').join(),
          networkAccess: NetworkAccess.notAttempted,
        ),
        throwsArgumentError,
      );
    });
  });

  group('CassetteException', () {
    test('carries the authoritative diagnostic', () {
      final diagnostic = CassetteDiagnostic(
        category: DiagnosticCategory.cassetteMissing,
        summary: 'The cassette does not exist.',
        networkAccess: NetworkAccess.disabled,
      );
      final exception = CassetteException(diagnostic);

      expect(exception, isA<Exception>());
      expect(exception.diagnostic, same(diagnostic));
    });
  });
}

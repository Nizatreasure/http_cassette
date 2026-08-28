import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/engine/scoped_action.dart';
import 'package:http_cassette/src/engine/scoped_cleanup.dart';
import 'package:http_cassette/src/engine/scoped_failure.dart';
import 'package:test/test.dart';

void main() {
  group('composeScopedCassetteException', () {
    test('retains the exact primary error and stack trace', () {
      final primaryError = StateError('primary callback failure');
      final primaryStackTrace = StackTrace.current;

      final exception = composeScopedCassetteException<void>(
        _result(
          primaryError: primaryError,
          primaryStackTrace: primaryStackTrace,
          cleanupError: StateError('private cleanup details'),
        ),
      );

      expect(exception.primaryError, same(primaryError));
      expect(exception.primaryStackTrace, same(primaryStackTrace));
      expect(
        exception.cleanupDiagnostic.category,
        DiagnosticCategory.sessionCleanupFailure,
      );
      expect(
        exception.cleanupDiagnostic.networkAccess,
        NetworkAccess.notAttempted,
      );
    });

    test('preserves a safe cassette cleanup diagnostic', () {
      final diagnostic = CassetteDiagnostic(
        category: DiagnosticCategory.conflictingSessionOperation,
        summary: 'Safe cleanup failure.',
        networkAccess: NetworkAccess.notAttempted,
      );

      final exception = composeScopedCassetteException<void>(
        _result(
          primaryError: StateError('primary'),
          primaryStackTrace: StackTrace.current,
          cleanupError: CassetteException(diagnostic),
        ),
      );

      expect(exception.cleanupDiagnostic, same(diagnostic));
      expect(exception.diagnostic, same(diagnostic));
    });

    test('formats neither primary nor cleanup error values', () {
      final exception = composeScopedCassetteException<void>(
        _result(
          primaryError: StateError('private primary value'),
          primaryStackTrace: StackTrace.current,
          cleanupError: StateError('private cleanup value'),
        ),
      );

      expect(exception.toString(), isNot(contains('private primary value')));
      expect(exception.toString(), isNot(contains('private cleanup value')));
      expect(exception.toString(), contains('session cleanup'));
    });

    test('rejects composition when cleanup succeeded', () {
      final primary = ScopedActionResult<void>.failed(
        StateError('primary'),
        StackTrace.current,
      ) as ScopedActionFailed<void>;

      expect(
        () => composeScopedCassetteException<void>(
          ScopedFailureCleanupResult<void>(failure: primary),
        ),
        throwsStateError,
      );
    });

    test('is available through the public package library', () {
      final exception = ScopedCassetteException(
        primaryError: StateError('primary'),
        primaryStackTrace: StackTrace.current,
        cleanupDiagnostic: CassetteDiagnostic(
          category: DiagnosticCategory.sessionCleanupFailure,
          summary: 'Cleanup failed.',
          networkAccess: NetworkAccess.notAttempted,
        ),
      );

      expect(exception, isA<CassetteException>());
    });
  });
}

ScopedFailureCleanupResult<void> _result({
  required Object primaryError,
  required StackTrace primaryStackTrace,
  required Object cleanupError,
}) {
  final primary = ScopedActionResult<void>.failed(
    primaryError,
    primaryStackTrace,
  ) as ScopedActionFailed<void>;
  return ScopedFailureCleanupResult<void>(
    failure: primary,
    cleanupFailure: ScopedCleanupFailure(
      cleanupError,
      StackTrace.current,
    ),
  );
}

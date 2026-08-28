import '../diagnostics/diagnostic.dart';
import '../diagnostics/exception.dart';
import 'scoped_cleanup.dart';

/// Composes one captured dual failure for the public exception boundary.
///
/// The cleanup error and stack trace are deliberately projected away.
ScopedCassetteException composeScopedCassetteException<T>(
  ScopedFailureCleanupResult<T> result,
) {
  final cleanupFailure = result.cleanupFailure;
  if (cleanupFailure == null) {
    throw StateError('Scoped failure composition requires a cleanup failure.');
  }
  final cleanupError = cleanupFailure.error;
  final diagnostic = cleanupError is CassetteException
      ? cleanupError.diagnostic
      : CassetteDiagnostic(
          category: DiagnosticCategory.sessionCleanupFailure,
          summary: 'Session cleanup failed after a scoped callback failure.',
          networkAccess: NetworkAccess.notAttempted,
        );
  return ScopedCassetteException(
    primaryError: result.failure.error,
    primaryStackTrace: result.failure.stackTrace,
    cleanupDiagnostic: diagnostic,
  );
}

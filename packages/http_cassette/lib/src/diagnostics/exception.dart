import '../replay/exhaustion_diagnostic.dart';
import '../replay/exhaustion_formatter.dart';
import '../replay/loading_failure.dart';
import '../replay/loading_failure_formatter.dart';
import '../replay/no_match_diagnostic.dart';
import '../replay/no_match_formatter.dart';
import '../replay/unused_interactions_diagnostic.dart';
import '../replay/unused_interactions_formatter.dart';
import 'diagnostic.dart';
import 'formatter.dart';

/// Base exception for expected HTTP Cassette operational failures.
///
/// The structured [diagnostic] is authoritative. Human-readable formatting is
/// added separately and should not be parsed for program logic.
sealed class CassetteException implements Exception {
  /// Creates an exception carrying [diagnostic].
  factory CassetteException(CassetteDiagnostic diagnostic) = _CassetteException;

  const CassetteException._(this.diagnostic);

  /// Safe structured information about the failure.
  final CassetteDiagnostic diagnostic;

  /// Formats [diagnostic] with the safe default diagnostic formatter.
  @override
  String toString() => diagnostic.format();
}

final class _CassetteException extends CassetteException {
  const _CassetteException(super.diagnostic) : super._();
}

/// Whether [error] is the exact safe local failure an adapter may report after
/// starting an authorised HTTP attempt.
///
/// This deliberately excludes subclasses which can retain arbitrary errors or
/// stack traces, and it rejects diagnostics with inconsistent network state.
bool isAllowedAdapterAttemptFailure(Object error) =>
    error is _CassetteException &&
    error.diagnostic.category == DiagnosticCategory.bodyLimitExceeded &&
    error.diagnostic.networkAccess == NetworkAccess.attempted;

/// Reports a callback failure accompanied by a secondary cleanup failure.
///
/// This exception occurs only when a scoped callback and the session cleanup
/// triggered by that callback both fail. [primaryError] remains the exact
/// callback error and [primaryStackTrace] remains its original stack trace.
/// [cleanupDiagnostic] contains only safe structured information about the
/// secondary failure; the cleanup error and its stack trace are not retained.
///
/// When cleanup succeeds, scoped operations rethrow the callback error directly
/// and do not use this wrapper.
final class ScopedCassetteException extends CassetteException {
  /// Creates a dual-failure exception.
  ScopedCassetteException({
    required this.primaryError,
    required this.primaryStackTrace,
    required CassetteDiagnostic cleanupDiagnostic,
  }) : super._(cleanupDiagnostic);

  /// The exact error thrown by the scoped callback.
  final Object primaryError;

  /// The original stack trace captured with [primaryError].
  final StackTrace primaryStackTrace;

  /// Safe structured information about the secondary cleanup failure.
  CassetteDiagnostic get cleanupDiagnostic => diagnostic;

  /// Formats only the safe cleanup diagnostic, never [primaryError].
  @override
  String toString() => 'The scoped callback and its session cleanup failed.\n'
      '${cleanupDiagnostic.format()}';
}

/// Creates an exception from one safe replay-loading [failure].
CassetteException replayCassetteLoadException(
  ReplayCassetteLoadFailure failure,
) =>
    _ReplayCassetteLoadException(failure);

final class _ReplayCassetteLoadException extends CassetteException {
  _ReplayCassetteLoadException(this.failure) : super._(failure.envelope);

  final ReplayCassetteLoadFailure failure;

  @override
  String toString() => failure.format();
}

/// Creates an exception from one safe no-match [diagnostic].
CassetteException replayNoMatchException(ReplayNoMatchDiagnostic diagnostic) =>
    _ReplayNoMatchException(diagnostic);

final class _ReplayNoMatchException extends CassetteException {
  _ReplayNoMatchException(this.details) : super._(details.envelope);

  final ReplayNoMatchDiagnostic details;

  @override
  String toString() => details.format();
}

/// Creates an exception from one safe exhaustion [diagnostic].
CassetteException replayExhaustionException(
  ReplayExhaustionDiagnostic diagnostic,
) =>
    _ReplayExhaustionException(diagnostic);

final class _ReplayExhaustionException extends CassetteException {
  _ReplayExhaustionException(this.details) : super._(details.envelope);

  final ReplayExhaustionDiagnostic details;

  @override
  String toString() => details.format();
}

/// Creates an exception from failed replay usage verification.
CassetteException replayUnusedInteractionsException(
  ReplayUnusedInteractionsDiagnostic diagnostic,
) =>
    _ReplayUnusedInteractionsException(diagnostic);

final class _ReplayUnusedInteractionsException extends CassetteException {
  _ReplayUnusedInteractionsException(this.details) : super._(details.envelope);

  final ReplayUnusedInteractionsDiagnostic details;

  @override
  String toString() => details.format();
}

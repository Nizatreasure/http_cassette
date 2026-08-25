import '../replay/exhaustion_diagnostic.dart';
import '../replay/exhaustion_formatter.dart';
import '../replay/loading_failure.dart';
import '../replay/loading_failure_formatter.dart';
import '../replay/no_match_diagnostic.dart';
import '../replay/no_match_formatter.dart';
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

/// Converts one safe replay-loading failure to the public exception boundary.
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

/// Converts one safe no-match diagnostic to the public exception boundary.
CassetteException replayNoMatchException(ReplayNoMatchDiagnostic diagnostic) =>
    _ReplayNoMatchException(diagnostic);

final class _ReplayNoMatchException extends CassetteException {
  _ReplayNoMatchException(this.details) : super._(details.envelope);

  final ReplayNoMatchDiagnostic details;

  @override
  String toString() => details.format();
}

/// Converts one safe exhaustion diagnostic to the public exception boundary.
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

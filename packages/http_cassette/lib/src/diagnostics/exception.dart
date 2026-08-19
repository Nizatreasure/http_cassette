import 'diagnostic.dart';

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
}

final class _CassetteException extends CassetteException {
  const _CassetteException(super.diagnostic) : super._();
}

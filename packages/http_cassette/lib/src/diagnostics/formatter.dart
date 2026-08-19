import 'diagnostic.dart';

/// Formats safe structured cassette diagnostics.
///
/// Implementations receive only [CassetteDiagnostic] values that have already
/// passed the diagnostic safety boundary. A formatter must remain a pure
/// operation and must not perform logging or other output itself.
abstract interface class CassetteDiagnosticFormatter {
  /// Returns a human-readable representation of [diagnostic].
  String format(CassetteDiagnostic diagnostic);
}

/// The deterministic, plain-text diagnostic formatter supplied by the core.
///
/// Output contains no ANSI colour and has no trailing line feed, making it
/// suitable for exception text, CI output and application-selected logging.
final class DefaultCassetteDiagnosticFormatter
    implements CassetteDiagnosticFormatter {
  /// Creates the default formatter.
  const DefaultCassetteDiagnosticFormatter();

  @override
  String format(CassetteDiagnostic diagnostic) => <String>[
        'HTTP Cassette failure: ${diagnostic.summary}',
        'Category: ${diagnostic.category.name}',
        'Network access: ${_formatNetworkAccess(diagnostic.networkAccess)}',
      ].join('\n');
}

/// Human-readable formatting for a safe structured diagnostic.
extension CassetteDiagnosticFormatting on CassetteDiagnostic {
  /// Formats this diagnostic with [formatter].
  ///
  /// When omitted, [DefaultCassetteDiagnosticFormatter] is used.
  String format([
    CassetteDiagnosticFormatter formatter =
        const DefaultCassetteDiagnosticFormatter(),
  ]) =>
      formatter.format(this);
}

String _formatNetworkAccess(NetworkAccess networkAccess) =>
    switch (networkAccess) {
      NetworkAccess.disabled => 'disabled; no real request was made',
      NetworkAccess.notAttempted => 'permitted; no real request was attempted',
      NetworkAccess.attempted => 'permitted; a real request was attempted',
    };

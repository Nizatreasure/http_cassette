import '../diagnostics/diagnostic.dart';
import 'diagnostic_context.dart';
import 'exhaustion.dart';

/// Complete safe structured information for one replay exhaustion failure.
///
/// It combines validated context and exhaustion facts, and fixes the category,
/// summary and network status so exhaustion cannot be represented as a request
/// mismatch.
final class ReplayExhaustionDiagnostic {
  /// Assembles an exhaustion diagnostic from safe [context] and [details].
  ReplayExhaustionDiagnostic({
    required this.context,
    required this.details,
  }) : envelope = CassetteDiagnostic(
          category: DiagnosticCategory.interactionsExhausted,
          summary: 'Matching interactions were exhausted.',
          networkAccess: details.networkAccess,
        );

  /// The validated logical cassette and value-free request context.
  final ReplayDiagnosticContext context;

  /// The verified policy, consumption counts and recorded indices.
  final ReplayExhaustionDetails details;

  /// The common diagnostic envelope with fixed exhaustion semantics.
  final CassetteDiagnostic envelope;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReplayExhaustionDiagnostic &&
          context == other.context &&
          details == other.details;

  @override
  int get hashCode => Object.hash(context, details);
}

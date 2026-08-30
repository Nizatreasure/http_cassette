import '../configuration/body_limits.dart';
import '../diagnostics/diagnostic.dart';
import '../diagnostics/exception.dart';
import '../model/http_message.dart';
import '../model/outcome.dart';
import '../session/cassette_mode.dart';
import '../session/cassette_session.dart';
import 'cancellation.dart';
import 'real_http_attempt.dart';

/// Routes one claimed interception through its exact pinned session.
///
/// This implementation callback is not exported from the public library.
typedef CassetteInterceptionExecutor = Future<CassetteOutcome> Function(
  CassetteSession session,
  CassetteRequest request,
  RealHttpAttempt realAttempt,
  CassetteCancellation? cancellation,
);

/// An immutable adapter decision for one intercepted transport request.
///
/// An inactive interception has [isActive] set to false and no [bodyLimits].
/// The adapter must pass its original transport request through without
/// canonical buffering. An active interception carries the exact buffering
/// limits for the session to which the request is pinned.
final class CassetteInterception {
  const CassetteInterception._inactive()
      : isActive = false,
        bodyLimits = null,
        _claimState = null;

  CassetteInterception._active({
    required BodyLimits limits,
    required CassetteSession session,
    required CassetteInterceptionExecutor executor,
  })  : isActive = true,
        bodyLimits = limits,
        _claimState = _CassetteInterceptionClaimState(session, executor);

  /// Whether this request entered an active cassette session.
  final bool isActive;

  /// Buffering limits for an active request, or null while inactive.
  final BodyLimits? bodyLimits;

  final _CassetteInterceptionClaimState? _claimState;

  /// Executes [request] through this permit's pinned cassette session.
  ///
  /// Adapters must call this only for an active permit and at most once. During
  /// recording, [realAttempt] is authorised at most once. During replay it is
  /// never invoked. An optional [cancellation] follows the session mode's
  /// deterministic cancellation ordering.
  ///
  /// A contract violation, cancelled request, unavailable pinned session,
  /// replay failure or recording failure throws a [CassetteException].
  Future<CassetteOutcome> proceed(
    CassetteRequest request,
    RealHttpAttempt realAttempt, {
    CassetteCancellation? cancellation,
  }) async {
    final session = claimCassetteInterception(
      this,
      cancellation: cancellation,
    );
    return _claimState!.executor(
      session,
      request,
      realAttempt,
      cancellation,
    );
  }
}

/// Creates the immutable inactive adapter decision.
///
/// This implementation function is not exported from the public library.
CassetteInterception createInactiveCassetteInterception() =>
    const CassetteInterception._inactive();

/// Creates one active decision pinned to [session].
///
/// This implementation function is not exported from the public library.
CassetteInterception createActiveCassetteInterception({
  required CassetteSession session,
  required BodyLimits bodyLimits,
  required CassetteInterceptionExecutor executor,
}) =>
    CassetteInterception._active(
      limits: bodyLimits,
      session: session,
      executor: executor,
    );

/// Whether [interception] is pinned to the exact [session] object.
///
/// This implementation check is not exported from the public library.
bool cassetteInterceptionPinsSession(
  CassetteInterception interception,
  CassetteSession session,
) =>
    identical(interception._claimState?.session, session);

/// Claims [interception] once and returns its pinned session.
///
/// This implementation operation is not exported from the public library.
CassetteSession claimCassetteInterception(
  CassetteInterception interception, {
  CassetteCancellation? cancellation,
}) {
  final claimState = interception._claimState;
  if (claimState == null) {
    throw CassetteException(
      CassetteDiagnostic(
        category: DiagnosticCategory.adapterContractViolation,
        summary: 'An inactive cassette interception cannot proceed.',
        networkAccess: NetworkAccess.notAttempted,
      ),
    );
  }
  final session = claimState.claim();
  if (cancellation?.isCancelled ?? false) {
    throw CassetteException(
      CassetteDiagnostic(
        category: DiagnosticCategory.cancelled,
        summary: 'The HTTP request was cancelled before cassette execution.',
        networkAccess: switch (session.mode) {
          CassetteMode.record => NetworkAccess.notAttempted,
          CassetteMode.replay => NetworkAccess.disabled,
        },
      ),
    );
  }
  return session;
}

final class _CassetteInterceptionClaimState {
  _CassetteInterceptionClaimState(this.session, this.executor);

  final CassetteSession session;
  final CassetteInterceptionExecutor executor;

  var _claimed = false;

  CassetteSession claim() {
    if (_claimed) {
      throw CassetteException(
        CassetteDiagnostic(
          category: DiagnosticCategory.adapterContractViolation,
          summary: 'A cassette interception can proceed only once.',
          networkAccess: switch (session.mode) {
            CassetteMode.record => NetworkAccess.notAttempted,
            CassetteMode.replay => NetworkAccess.disabled,
          },
        ),
      );
    }
    _claimed = true;
    return session;
  }
}

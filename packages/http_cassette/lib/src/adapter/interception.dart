import '../configuration/body_limits.dart';
import '../diagnostics/diagnostic.dart';
import '../diagnostics/exception.dart';
import '../model/http_message.dart';
import '../model/outcome.dart';
import '../session/cassette_mode.dart';
import '../session/cassette_session.dart';
import 'cancellation.dart';
import 'real_http_attempt.dart';

/// Executes one canonical request for the session pinned by an interception.
typedef CassetteInterceptionExecutor = Future<CassetteOutcome> Function(
  CassetteSession session,
  CassetteRequest request,
  RealHttpAttempt realAttempt,
  CassetteCancellation? cancellation,
);

/// The engine's immutable decision for one intercepted transport request.
///
/// An inactive interception has [isActive] set to false and no [bodyLimits].
/// The adapter must pass its original transport request through without
/// canonical buffering. An active interception carries the exact buffering
/// limits for the session to which the request is pinned and may [proceed]
/// once.
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

  /// Whether the request must be processed by the pinned cassette session.
  final bool isActive;

  /// The limits an adapter must apply before proceeding, or `null` for exact
  /// pass-through.
  final BodyLimits? bodyLimits;

  final _CassetteInterceptionClaimState? _claimState;

  /// Resolves canonical [request] through the pinned cassette session.
  ///
  /// Adapters must call this only for an active permit and at most once.
  /// [realAttempt] represents one prepared transport attempt. Recording may
  /// invoke it once; replay never invokes it. [cancellation] connects the
  /// caller's cancellation signal to deterministic session ordering.
  ///
  /// Throws a [CassetteException] for repeated use, inactive use,
  /// cancellation, an unavailable pinned session, or a recording or replay
  /// failure.
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

/// Creates an interception which requires exact transport pass-through.
CassetteInterception createInactiveCassetteInterception() =>
    const CassetteInterception._inactive();

/// Creates one active interception pinned to [session] and [bodyLimits].
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

/// Whether [interception] is pinned to the exact [session] instance.
bool cassetteInterceptionPinsSession(
  CassetteInterception interception,
  CassetteSession session,
) =>
    identical(interception._claimState?.session, session);

/// Claims [interception] for its only execution and returns its pinned session.
///
/// Throws a safe [CassetteException] when the interception is inactive, was
/// already claimed, or was cancelled before execution.
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

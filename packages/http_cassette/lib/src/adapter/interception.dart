import '../configuration/body_limits.dart';
import '../diagnostics/diagnostic.dart';
import '../diagnostics/exception.dart';
import '../session/cassette_mode.dart';
import '../session/cassette_session.dart';
import 'cancellation.dart';

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
  })  : isActive = true,
        bodyLimits = limits,
        _claimState = _CassetteInterceptionClaimState(session);

  /// Whether this request entered an active cassette session.
  final bool isActive;

  /// Buffering limits for an active request, or null while inactive.
  final BodyLimits? bodyLimits;

  final _CassetteInterceptionClaimState? _claimState;
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
}) =>
    CassetteInterception._active(limits: bodyLimits, session: session);

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
  _CassetteInterceptionClaimState(this.session);

  final CassetteSession session;

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

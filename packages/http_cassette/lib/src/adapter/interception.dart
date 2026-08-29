import '../configuration/body_limits.dart';
import '../session/cassette_session.dart';

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
        _sessionIdentity = null;

  const CassetteInterception._active({
    required BodyLimits limits,
    required CassetteSession session,
  })  : isActive = true,
        bodyLimits = limits,
        _sessionIdentity = session;

  /// Whether this request entered an active cassette session.
  final bool isActive;

  /// Buffering limits for an active request, or null while inactive.
  final BodyLimits? bodyLimits;

  final Object? _sessionIdentity;
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
    identical(interception._sessionIdentity, session);

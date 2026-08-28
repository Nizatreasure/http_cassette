import '../configuration/body_limits.dart';

/// An immutable adapter decision for one intercepted transport request.
///
/// An inactive interception has [isActive] set to false and no [bodyLimits].
/// The adapter must pass its original transport request through without
/// canonical buffering. Active interception is added in a later stage.
final class CassetteInterception {
  const CassetteInterception._inactive()
      : isActive = false,
        bodyLimits = null;

  /// Whether this request entered an active cassette session.
  final bool isActive;

  /// Buffering limits for an active request, or null while inactive.
  final BodyLimits? bodyLimits;
}

/// Creates the immutable inactive adapter decision.
///
/// This implementation function is not exported from the public library.
CassetteInterception createInactiveCassetteInterception() =>
    const CassetteInterception._inactive();

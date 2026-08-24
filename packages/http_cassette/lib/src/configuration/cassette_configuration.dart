import '../replay/configuration.dart';
import '../sanitisation/configuration.dart';
import 'body_limits.dart';
import 'matching_configuration.dart';

/// Immutable configuration shared by cassette sessions on one engine.
///
/// Session-specific options may override the applicable engine default. This
/// value only groups configuration; it does not start a cassette session.
final class CassetteConfiguration {
  /// Creates engine configuration with secure project defaults.
  factory CassetteConfiguration({
    MatchingConfiguration? matching,
    SanitisationConfiguration? sanitisation,
    BodyLimits? bodyLimits,
    ReplayPolicy defaultReplayPolicy = ReplayPolicy.strict,
  }) =>
      CassetteConfiguration._(
        matching: matching ?? MatchingConfiguration(),
        sanitisation: sanitisation ?? SanitisationConfiguration(),
        bodyLimits: bodyLimits ?? BodyLimits(),
        defaultReplayPolicy: defaultReplayPolicy,
      );

  const CassetteConfiguration._({
    required this.matching,
    required this.sanitisation,
    required this.bodyLimits,
    required this.defaultReplayPolicy,
  });

  /// Request-matching configuration used by cassette sessions.
  final MatchingConfiguration matching;

  /// Sanitisation configuration applied before future persistence.
  final SanitisationConfiguration sanitisation;

  /// Limits for future canonical request and response body buffering.
  final BodyLimits bodyLimits;

  /// Replay policy used when a replay session supplies no override.
  final ReplayPolicy defaultReplayPolicy;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CassetteConfiguration &&
          matching == other.matching &&
          sanitisation == other.sanitisation &&
          bodyLimits == other.bodyLimits &&
          defaultReplayPolicy == other.defaultReplayPolicy;

  @override
  int get hashCode => Object.hash(
        matching,
        sanitisation,
        bodyLimits,
        defaultReplayPolicy,
      );
}

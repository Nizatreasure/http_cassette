import '../recording/configuration.dart';
import '../replay/configuration.dart';
import '../sanitisation/configuration.dart';
import 'body_limits.dart';
import 'matching_configuration.dart';

/// Groups the behaviour shared by every session on one cassette engine.
///
/// Recording and replay sessions use the same matching, sanitisation and body
/// limits. A replay session may override the default replay policy.
final class CassetteConfiguration {
  /// Creates configuration with secure sanitisation, default matching, measured
  /// body limits and strict replay unless values are supplied explicitly.
  factory CassetteConfiguration({
    MatchingConfiguration? matching,
    SanitisationConfiguration? sanitisation,
    BodyLimits? bodyLimits,
    RecordingConfiguration? recording,
    ReplayPolicy defaultReplayPolicy = ReplayPolicy.strict,
  }) =>
      CassetteConfiguration._(
        matching: matching ?? MatchingConfiguration(),
        sanitisation: sanitisation ?? SanitisationConfiguration(),
        bodyLimits: bodyLimits ?? BodyLimits(),
        recording: recording ?? RecordingConfiguration(),
        defaultReplayPolicy: defaultReplayPolicy,
      );

  const CassetteConfiguration._({
    required this.matching,
    required this.sanitisation,
    required this.bodyLimits,
    required this.recording,
    required this.defaultReplayPolicy,
  });

  /// Request-matching configuration used by cassette sessions.
  final MatchingConfiguration matching;

  /// Sanitisation configuration applied before recording persistence.
  final SanitisationConfiguration sanitisation;

  /// Limits for canonical request and response body buffering.
  final BodyLimits bodyLimits;

  /// Recording lifecycle behaviour shared by every recording session.
  final RecordingConfiguration recording;

  /// Replay policy used when a replay session supplies no override.
  final ReplayPolicy defaultReplayPolicy;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CassetteConfiguration &&
          matching == other.matching &&
          sanitisation == other.sanitisation &&
          bodyLimits == other.bodyLimits &&
          recording == other.recording &&
          defaultReplayPolicy == other.defaultReplayPolicy;

  @override
  int get hashCode => Object.hash(
        matching,
        sanitisation,
        bodyLimits,
        recording,
        defaultReplayPolicy,
      );
}

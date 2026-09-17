/// Immutable recording behaviour shared by every session on one engine.
final class RecordingConfiguration {
  /// Creates recording configuration.
  ///
  /// [closeGracePeriod] is the single positive duration allowed for requests
  /// admitted before recording close to settle. It defaults to 30 seconds.
  factory RecordingConfiguration({
    Duration closeGracePeriod = defaultCloseGracePeriod,
  }) {
    if (closeGracePeriod <= Duration.zero) {
      throw ArgumentError.value(
        closeGracePeriod,
        'closeGracePeriod',
        'Recording close grace period must be positive.',
      );
    }
    return RecordingConfiguration._(closeGracePeriod);
  }

  const RecordingConfiguration._(this.closeGracePeriod);

  /// The default time allowed for admitted recording requests to settle.
  static const defaultCloseGracePeriod = Duration(seconds: 30);

  /// The complete wait allowed after recording close seals request admission.
  final Duration closeGracePeriod;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecordingConfiguration &&
          closeGracePeriod == other.closeGracePeriod;

  @override
  int get hashCode => closeGracePeriod.hashCode;
}

/// How a recording session handles its target cassette.
enum ExistingCassette {
  /// Fail when the target cassette already exists.
  fail,

  /// Create an absent target or replace an existing target on successful close.
  replace,

  /// Keep a valid current-version target and add newly recorded interactions.
  append,
}

/// Immutable options for one recording session.
final class RecordingOptions {
  /// Creates recording options.
  ///
  /// Existing cassettes are rejected unless [existingCassette] explicitly
  /// requests replacement or append behaviour.
  const RecordingOptions({
    this.existingCassette = ExistingCassette.fail,
  });

  /// How recording handles a cassette which already exists at the target name.
  ///
  /// The target name is supplied when starting the recording operation.
  final ExistingCassette existingCassette;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecordingOptions && existingCassette == other.existingCassette;

  @override
  int get hashCode => existingCassette.hashCode;
}

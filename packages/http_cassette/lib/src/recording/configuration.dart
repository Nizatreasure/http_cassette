/// How a recording session handles its target cassette.
enum ExistingCassette {
  /// Fail when the target cassette already exists.
  fail,

  /// Replace an existing target when the recording closes successfully.
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

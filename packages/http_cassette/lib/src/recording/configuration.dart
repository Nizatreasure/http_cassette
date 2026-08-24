/// How a recording session handles its target cassette.
///
/// This value configures later recording behaviour. It does not inspect or
/// modify a cassette by itself.
enum ExistingCassette {
  /// Fail when the target cassette already exists.
  fail,

  /// Replace an existing target when the recording closes successfully.
  replace,

  /// Append to a valid target using the current writable schema version.
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

  /// The requested handling of the target cassette.
  final ExistingCassette existingCassette;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecordingOptions && existingCassette == other.existingCassette;

  @override
  int get hashCode => existingCassette.hashCode;
}

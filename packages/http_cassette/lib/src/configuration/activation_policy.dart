/// Controls whether a cassette engine accepts recording and replay commands.
enum CassetteActivationPolicy {
  /// Starts ordinary recording and replay sessions.
  enabled,

  /// Rejects session commands before cassette or transport work begins.
  disabledWithException,

  /// Returns inert sessions and leaves installed adapters in pass-through mode.
  ///
  /// No cassette is read or changed. Because the engine remains inactive,
  /// transport requests may access the network normally.
  disabledWithPassThrough,
}

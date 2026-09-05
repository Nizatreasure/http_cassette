/// Controls whether one cassette engine may start sessions.
enum CassetteActivationPolicy {
  /// Recording and replay commands operate normally.
  enabled,

  /// Recording and replay commands fail before cassette or transport work.
  disabledWithException,

  /// Commands return inert sessions while normal transport traffic passes.
  disabledWithPassThrough,
}

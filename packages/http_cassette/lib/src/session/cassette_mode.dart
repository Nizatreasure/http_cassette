/// The explicit operation performed by an active cassette session.
///
/// Recording and replay are never inferred from the environment.
enum CassetteMode {
  /// Identify an explicit recording operation.
  record,

  /// Identify an explicit replay operation.
  replay,
}

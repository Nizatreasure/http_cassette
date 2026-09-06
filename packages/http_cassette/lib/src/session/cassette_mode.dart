/// The explicit operation performed by an active cassette session.
///
/// Recording and replay are never inferred from the environment.
enum CassetteMode {
  /// An operation which captures real HTTP outcomes for persistence.
  record,

  /// An operation which returns persisted outcomes without network access.
  replay,
}

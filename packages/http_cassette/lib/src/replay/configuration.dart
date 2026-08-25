/// The strategy used to select from matching recorded interactions.
///
/// This value configures later replay behaviour. It does not itself select or
/// consume interactions.
enum ReplayPolicy {
  /// Consume each matching interaction once in recorded order.
  strict,

  /// Reuse the first matching interaction.
  first,

  /// Reuse the last matching interaction.
  last,

  /// Advance through matches and then retain the final interaction.
  sequence,

  /// Advance through matches and wrap to the first interaction.
  cycle,
}

/// Immutable options for one replay session.
final class ReplayOptions {
  /// Creates replay options.
  ///
  /// A null [policy] uses the engine configuration's default.
  /// [requireAllInteractions] controls successful-close verification once
  /// replay execution is connected.
  const ReplayOptions({
    this.policy,
    this.requireAllInteractions = false,
  });

  /// The session policy override, or null to use the engine default.
  final ReplayPolicy? policy;

  /// Whether successful session close must verify that every interaction ran.
  final bool requireAllInteractions;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReplayOptions &&
          policy == other.policy &&
          requireAllInteractions == other.requireAllInteractions;

  @override
  int get hashCode => Object.hash(policy, requireAllInteractions);
}

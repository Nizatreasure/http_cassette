import '../cassette/interaction.dart';
import 'configuration.dart';

/// The typed result of one synchronous replay-selection attempt.
sealed class ReplaySelectionResult {
  const ReplaySelectionResult();
}

/// A replay-selection result containing the chosen [interaction].
final class ReplayInteractionSelected extends ReplaySelectionResult {
  /// Creates a selected-interaction result.
  const ReplayInteractionSelected(this.interaction);

  /// The recorded interaction chosen for this request.
  final CassetteInteraction interaction;
}

/// A replay-selection result for an empty matching group.
final class ReplayNoMatch extends ReplaySelectionResult {
  /// Creates a no-match result.
  const ReplayNoMatch();
}

/// A replay-selection result for a fully consumed matching group.
final class ReplayGroupExhausted extends ReplaySelectionResult {
  /// Creates an exhausted-group result.
  const ReplayGroupExhausted();
}

/// Isolate-local synchronous selection state for one matching group.
final class ReplaySelectionState {
  /// Creates strict selection state for [matchingInteractions].
  ///
  /// The iterable is copied, validated for unique recorded indices and ordered
  /// by those indices. Identical interactions with distinct indices remain
  /// separate consumable entries.
  ReplaySelectionState.strict(
    Iterable<CassetteInteraction> matchingInteractions,
  )   : policy = ReplayPolicy.strict,
        _matchingInteractions = _prepareGroup(matchingInteractions);

  /// The policy controlling this state.
  final ReplayPolicy policy;

  final List<CassetteInteraction> _matchingInteractions;
  var _consumedCount = 0;

  /// Immutable matching interactions in recorded-index order.
  List<CassetteInteraction> get matchingInteractions => _matchingInteractions;

  /// The number of interactions consumed by successful selections.
  int get consumedCount => _consumedCount;

  /// Selects and consumes the next strict interaction synchronously.
  ReplaySelectionResult select() {
    if (_matchingInteractions.isEmpty) {
      return const ReplayNoMatch();
    }
    if (_consumedCount == _matchingInteractions.length) {
      return const ReplayGroupExhausted();
    }
    final interaction = _matchingInteractions[_consumedCount];
    _consumedCount++;
    return ReplayInteractionSelected(interaction);
  }
}

List<CassetteInteraction> _prepareGroup(
  Iterable<CassetteInteraction> interactions,
) {
  final copied = List<CassetteInteraction>.of(interactions)
    ..sort((first, second) => first.index.compareTo(second.index));
  for (var position = 1; position < copied.length; position++) {
    if (copied[position - 1].index == copied[position].index) {
      throw ArgumentError(
        'Matching interaction indices must be unique.',
      );
    }
  }
  return List<CassetteInteraction>.unmodifiable(copied);
}

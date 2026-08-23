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
  ) : this._(ReplayPolicy.strict, matchingInteractions);

  /// Creates reusable first-match selection state for [matchingInteractions].
  ReplaySelectionState.first(
    Iterable<CassetteInteraction> matchingInteractions,
  ) : this._(ReplayPolicy.first, matchingInteractions);

  /// Creates reusable last-match selection state for [matchingInteractions].
  ReplaySelectionState.last(
    Iterable<CassetteInteraction> matchingInteractions,
  ) : this._(ReplayPolicy.last, matchingInteractions);

  ReplaySelectionState._(
    this.policy,
    Iterable<CassetteInteraction> matchingInteractions,
  ) : _matchingInteractions = _prepareGroup(matchingInteractions);

  /// The policy controlling this state.
  final ReplayPolicy policy;

  final List<CassetteInteraction> _matchingInteractions;
  final Set<int> _usedRecordedIndices = <int>{};
  var _nextPosition = 0;

  /// Immutable matching interactions in recorded-index order.
  List<CassetteInteraction> get matchingInteractions => _matchingInteractions;

  /// The number of distinct interactions used by successful selections.
  int get consumedCount => _usedRecordedIndices.length;

  /// Selects an interaction and updates policy state synchronously.
  ReplaySelectionResult select() {
    if (_matchingInteractions.isEmpty) {
      return const ReplayNoMatch();
    }
    return switch (policy) {
      ReplayPolicy.strict => _selectStrict(),
      ReplayPolicy.first => _selectReusable(0),
      ReplayPolicy.last => _selectReusable(_matchingInteractions.length - 1),
      ReplayPolicy.sequence ||
      ReplayPolicy.cycle =>
        throw StateError('The replay policy is not implemented yet.'),
    };
  }

  ReplaySelectionResult _selectStrict() {
    if (_nextPosition == _matchingInteractions.length) {
      return const ReplayGroupExhausted();
    }
    final interaction = _matchingInteractions[_nextPosition];
    _nextPosition++;
    _usedRecordedIndices.add(interaction.index);
    return ReplayInteractionSelected(interaction);
  }

  ReplaySelectionResult _selectReusable(int position) {
    final interaction = _matchingInteractions[position];
    _usedRecordedIndices.add(interaction.index);
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

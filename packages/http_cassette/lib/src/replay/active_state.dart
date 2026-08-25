import '../cassette/cassette.dart';
import '../cassette/interaction.dart';
import '../cassette/name.dart';
import '../configuration/cassette_configuration.dart';
import '../matching/ranking.dart';
import '../matching/request_matcher.dart';
import '../model/http_message.dart';
import 'configuration.dart';
import 'diagnostic_context.dart';
import 'exhaustion.dart';
import 'exhaustion_diagnostic.dart';
import 'grouping.dart';
import 'matcher_description.dart';
import 'no_match.dart';
import 'no_match_diagnostic.dart';
import 'policy_resolution.dart';
import 'selection.dart';

/// The result of one atomic internal replay matching and selection operation.
final class ReplayRequestSelection {
  /// Creates a result from one assigned request and its matching-group state.
  const ReplayRequestSelection({
    required this.arrivalIndex,
    required this.state,
    required this.result,
    required this.noMatchDiagnostic,
    required this.exhaustionDiagnostic,
  });

  /// The request-arrival index assigned before matching began.
  final int arrivalIndex;

  /// The persistent selection state for the resulting matching group.
  final ReplaySelectionState state;

  /// The selected interaction, no-match result or exhaustion result.
  final ReplaySelectionResult result;

  /// Safe no-match details when [result] is [ReplayNoMatch].
  final ReplayNoMatchDiagnostic? noMatchDiagnostic;

  /// Safe exhaustion details when [result] is [ReplayGroupExhausted].
  final ReplayExhaustionDiagnostic? exhaustionDiagnostic;
}

/// Session-local configuration and state for one active replay session.
final class ActiveReplayState {
  /// Creates active state from validated session inputs.
  ActiveReplayState({
    required this.cassetteName,
    required this.cassette,
    required CassetteConfiguration configuration,
    required ReplayOptions options,
  })  : matcher = DefaultRequestMatcher(configuration: configuration.matching),
        replayPolicy = resolveReplayPolicy(
          defaultPolicy: configuration.defaultReplayPolicy,
          options: options,
        ),
        requireAllInteractions = options.requireAllInteractions;

  /// The validated logical identity of the loaded cassette.
  final CassetteName cassetteName;

  /// The immutable decoded cassette used throughout the session.
  final Cassette cassette;

  /// The matcher configured once from the engine's immutable settings.
  final DefaultRequestMatcher matcher;

  /// The replay policy resolved once when the session starts.
  final ReplayPolicy replayPolicy;

  /// Whether successful close must later verify complete cassette usage.
  final bool requireAllInteractions;

  var _nextArrivalIndex = 0;
  final Map<_ReplayMatchingGroupKey, ReplaySelectionState> _selectionStates =
      <_ReplayMatchingGroupKey, ReplaySelectionState>{};

  /// Assigns, matches and selects one [incoming] request synchronously.
  ///
  /// Requests producing the same ordered recorded-index group share selection
  /// state. There is no asynchronous gap between arrival assignment and state
  /// mutation.
  ReplayRequestSelection selectRequest(CassetteRequest incoming) {
    final arrivalIndex = _nextArrivalIndex++;
    final evaluation = evaluateReplayRequest(
      cassette: cassette,
      incoming: incoming,
      matcher: matcher,
    );
    final matchingInteractions = evaluation.matchingInteractions;
    final key = _ReplayMatchingGroupKey(matchingInteractions);
    final state = _selectionStates.putIfAbsent(
      key,
      () => _createSelectionState(matchingInteractions),
    );
    final result = state.select();
    return ReplayRequestSelection(
      arrivalIndex: arrivalIndex,
      state: state,
      result: result,
      noMatchDiagnostic: result is ReplayNoMatch
          ? _createNoMatchDiagnostic(
              incoming: incoming,
              arrivalIndex: arrivalIndex,
              candidates: evaluation.candidates,
            )
          : null,
      exhaustionDiagnostic: result is ReplayGroupExhausted
          ? ReplayExhaustionDiagnostic(
              context: _createDiagnosticContext(
                incoming: incoming,
                arrivalIndex: arrivalIndex,
              ),
              details: ReplayExhaustionDetails.fromSelection(
                state: state,
                result: result,
              ),
            )
          : null,
    );
  }

  /// Point-in-time selection states for every matching group encountered.
  List<ReplaySelectionState> get selectionStates =>
      List<ReplaySelectionState>.unmodifiable(_selectionStates.values);

  ReplaySelectionState _createSelectionState(
    Iterable<CassetteInteraction> matchingInteractions,
  ) =>
      switch (replayPolicy) {
        ReplayPolicy.strict =>
          ReplaySelectionState.strict(matchingInteractions),
        ReplayPolicy.first => ReplaySelectionState.first(matchingInteractions),
        ReplayPolicy.last => ReplaySelectionState.last(matchingInteractions),
        ReplayPolicy.sequence =>
          ReplaySelectionState.sequence(matchingInteractions),
        ReplayPolicy.cycle => ReplaySelectionState.cycle(matchingInteractions),
      };

  ReplayNoMatchDiagnostic _createNoMatchDiagnostic({
    required CassetteRequest incoming,
    required int arrivalIndex,
    required Iterable<RequestMatchCandidate> candidates,
  }) =>
      ReplayNoMatchDiagnostic(
        context: _createDiagnosticContext(
          incoming: incoming,
          arrivalIndex: arrivalIndex,
        ),
        replayPolicy: replayPolicy,
        matcher: ReplayMatcherDescription.fromConfiguration(
          matcher.configuration,
        ),
        details: ReplayNoMatchDetails.fromRanking(
          rankRequestMatchCandidates(candidates),
        ),
      );

  ReplayDiagnosticContext _createDiagnosticContext({
    required CassetteRequest incoming,
    required int arrivalIndex,
  }) =>
      ReplayDiagnosticContext(
        cassetteName: cassetteName,
        request: ReplayRequestSummary.fromRequest(
          request: incoming,
          arrivalIndex: arrivalIndex,
        ),
      );
}

final class _ReplayMatchingGroupKey {
  factory _ReplayMatchingGroupKey(
    Iterable<CassetteInteraction> interactions,
  ) =>
      _ReplayMatchingGroupKey._(
        List<int>.unmodifiable(
          interactions.map((interaction) => interaction.index),
        ),
      );

  const _ReplayMatchingGroupKey._(this.recordedIndices);

  final List<int> recordedIndices;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ReplayMatchingGroupKey &&
          _listsEqual(recordedIndices, other.recordedIndices);

  @override
  int get hashCode => Object.hashAll(recordedIndices);
}

bool _listsEqual<T>(List<T> first, List<T> second) {
  if (first.length != second.length) {
    return false;
  }
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}

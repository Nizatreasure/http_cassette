import 'dart:async';

import '../adapter/cancellation.dart';
import '../adapter/real_http_attempt.dart';
import '../cassette/cassette.dart';
import '../cassette/interaction.dart';
import '../cassette/name.dart';
import '../configuration/cassette_configuration.dart';
import '../model/http_message.dart';
import '../model/outcome.dart';
import '../sanitisation/configuration.dart';
import '../store/snapshot.dart';
import 'append_preparation.dart';
import 'configuration.dart';
import 'interaction_projection.dart';
import 'request_attempt.dart';

/// Session-local configuration and state for one active recording session.
final class ActiveRecordingState {
  /// Creates active state from validated session inputs.
  ///
  /// Supplying [appendPreparation] requires append [options] and the same
  /// [cassetteName]. Its existing interactions seed the combined state.
  factory ActiveRecordingState({
    required CassetteName cassetteName,
    required CassetteConfiguration configuration,
    required RecordingOptions options,
    AppendCassettePrepared? appendPreparation,
  }) {
    if (appendPreparation != null) {
      if (options.existingCassette != ExistingCassette.append) {
        throw ArgumentError(
          'Append preparation requires append recording options.',
        );
      }
      if (appendPreparation.snapshot.name != cassetteName) {
        throw ArgumentError(
          'Append preparation must use the recording cassette name.',
        );
      }
    }
    final initialInteractions = appendPreparation?.cassette.interactions ??
        const <CassetteInteraction>[];
    return ActiveRecordingState._(
      cassetteName: cassetteName,
      sanitisation: configuration.sanitisation,
      options: options,
      appendSnapshot: appendPreparation?.snapshot,
      initialInteractions: initialInteractions,
    );
  }

  ActiveRecordingState._({
    required this.cassetteName,
    required this.sanitisation,
    required this.options,
    required this.appendSnapshot,
    required List<CassetteInteraction> initialInteractions,
  })  : _nextArrivalIndex = initialInteractions.length,
        _interactions = <int, CassetteInteraction>{
          for (final interaction in initialInteractions)
            interaction.index: interaction,
        };

  /// The validated logical identity of the cassette being recorded.
  final CassetteName cassetteName;

  /// The sanitisation configuration fixed when the session starts.
  final SanitisationConfiguration sanitisation;

  /// The target-handling options fixed when the session starts.
  final RecordingOptions options;

  /// The exact append target snapshot, or null for create and replacement.
  final CassetteSnapshot? appendSnapshot;

  int _nextArrivalIndex;
  final Map<int, CassetteInteraction> _interactions;
  var _acceptsRequests = true;
  Cassette? _finalisedCassette;
  var _pendingRequestCount = 0;
  var _failedRequestCount = 0;
  Completer<void>? _requestsSettled;

  /// Whether another request may enter this recording state.
  bool get acceptsRequests => _acceptsRequests;

  /// Whether this state has fixed its final immutable cassette value.
  bool get isFinalised => _finalisedCassette != null;

  /// The number of admitted recording requests which have not settled.
  int get pendingRequestCount => _pendingRequestCount;

  /// Whether an admitted request failed before producing a retained interaction.
  bool get hasFailedRequests => _failedRequestCount > 0;

  /// Completes when every currently admitted recording request has settled.
  ///
  /// Requests admitted after this getter is read are not part of the returned
  /// wait. Call [sealRequestAdmission] first when a stable complete-session wait
  /// is required.
  Future<void> get whenRequestsSettled =>
      _requestsSettled?.future ?? Future<void>.value();

  /// Prevents any later request admission without affecting pending attempts.
  void sealRequestAdmission() {
    _acceptsRequests = false;
  }

  /// Assigns the next request-arrival index synchronously.
  int assignArrivalIndex() {
    if (!acceptsRequests) {
      throw StateError('A sealed recording cannot admit another request.');
    }
    return _nextArrivalIndex++;
  }

  /// Admits [request] and assigns its arrival index synchronously.
  ///
  /// The returned operation can make the single real HTTP attempt. Admission
  /// alone does not retain the request or an outcome in the cassette.
  RecordingRequestAttempt beginRequest(CassetteRequest request) =>
      RecordingRequestAttempt(
        arrivalIndex: assignArrivalIndex(),
        request: request,
      );

  /// Records one [request] through a single authorised real [attempt].
  ///
  /// The request is admitted synchronously. After the attempt succeeds, its
  /// result is sanitised and retained before the original live outcome is
  /// returned. Any failure before retention adds no interaction.
  Future<CassetteOutcome> recordRequest(
    CassetteRequest request,
    RealHttpAttempt attempt, {
    CassetteCancellation? cancellation,
  }) async {
    final requestAttempt = beginRequest(request);
    _beginRequestSettlement();
    var succeeded = false;
    try {
      final result = await requestAttempt.run(
        attempt,
        cancellation: cancellation,
      );
      retainResult(result);
      succeeded = true;
      return result.outcome;
    } finally {
      _settleRequest(succeeded: succeeded);
    }
  }

  /// Sanitises [result] into an interaction without retaining it.
  CassetteInteraction sanitiseResult(RecordingRequestResult result) =>
      sanitiseRecordingResult(result, sanitisation);

  /// Sanitises and retains one successful admitted request [result].
  ///
  /// Retention occurs synchronously after complete sanitisation. A result index
  /// must have been assigned by this session and may be retained only once.
  CassetteInteraction retainResult(RecordingRequestResult result) {
    final index = result.arrivalIndex;
    if (index < 0 || index >= _nextArrivalIndex) {
      throw StateError(
        'A recording result must use an index admitted by this session.',
      );
    }
    if (_interactions.containsKey(index)) {
      throw StateError(
        'A recording result index may be retained only once.',
      );
    }
    final interaction = sanitiseResult(result);
    _interactions[index] = interaction;
    return interaction;
  }

  /// Immutable existing and newly retained interactions in arrival order.
  List<CassetteInteraction> get interactions {
    final sorted = _interactions.values.toList()
      ..sort((first, second) => first.index.compareTo(second.index));
    return List<CassetteInteraction>.unmodifiable(sorted);
  }

  /// Finalises the complete retained interactions as an immutable cassette.
  ///
  /// Every admitted request must have completed sanitisation and retention.
  /// A rejected finalisation does not change the active recording state.
  Cassette finaliseCassette() {
    final finalised = _finalisedCassette;
    if (finalised != null) {
      return finalised;
    }
    if (_interactions.length != _nextArrivalIndex) {
      throw StateError(
        'A recording cassette cannot be finalised while admitted requests '
        'remain incomplete.',
      );
    }
    final cassette = Cassette(interactions: interactions);
    sealRequestAdmission();
    return _finalisedCassette = cassette;
  }

  void _beginRequestSettlement() {
    if (_pendingRequestCount == 0) {
      _requestsSettled = Completer<void>();
    }
    _pendingRequestCount += 1;
  }

  void _settleRequest({required bool succeeded}) {
    if (_pendingRequestCount <= 0) {
      throw StateError('Recording request settlement is not pending.');
    }
    if (!succeeded) {
      _failedRequestCount += 1;
    }
    _pendingRequestCount -= 1;
    if (_pendingRequestCount == 0) {
      _requestsSettled!.complete();
      _requestsSettled = null;
    }
  }
}

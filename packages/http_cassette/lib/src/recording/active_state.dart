import 'dart:async';

import '../adapter/cancellation.dart';
import '../adapter/real_http_attempt.dart';
import '../cassette/cassette.dart';
import '../cassette/interaction.dart';
import '../cassette/name.dart';
import '../configuration/cassette_configuration.dart';
import '../diagnostics/diagnostic.dart';
import '../diagnostics/exception.dart';
import '../model/http_message.dart';
import '../model/outcome.dart';
import '../sanitisation/configuration.dart';
import '../store/snapshot.dart';
import 'append_preparation.dart';
import 'configuration.dart';
import 'interaction_projection.dart';
import 'request_attempt.dart';

/// The result of waiting for admitted recording requests to settle.
enum RecordingSettlementResult {
  /// Every admitted request settled before the grace period ended.
  settled,

  /// At least one admitted request remained pending when the period ended.
  timedOut,
}

/// Whether the recording target existed when session startup checked it.
enum RecordingTargetPresence {
  /// No target existed at startup.
  absent,

  /// A target existed at startup.
  present,
}

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
    required RecordingTargetPresence targetPresence,
    AppendCassettePrepared? appendPreparation,
  }) {
    if (options.existingCassette == ExistingCassette.fail &&
        targetPresence != RecordingTargetPresence.absent) {
      throw ArgumentError(
        'Create-only recording requires an absent startup target.',
      );
    }
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
    if (options.existingCassette == ExistingCassette.append &&
        targetPresence != RecordingTargetPresence.present) {
      throw ArgumentError(
        'Append recording requires a present startup target.',
      );
    }
    final initialInteractions = appendPreparation?.cassette.interactions ??
        const <CassetteInteraction>[];
    return ActiveRecordingState._(
      cassetteName: cassetteName,
      sanitisation: configuration.sanitisation,
      maximumDecodedResponseBodyBytes: configuration.bodyLimits.responseBytes,
      recording: configuration.recording,
      options: options,
      targetPresence: targetPresence,
      appendSnapshot: appendPreparation?.snapshot,
      initialInteractions: initialInteractions,
    );
  }

  ActiveRecordingState._({
    required this.cassetteName,
    required this.sanitisation,
    required this.maximumDecodedResponseBodyBytes,
    required this.recording,
    required this.options,
    required this.targetPresence,
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

  /// The maximum decoded response size fixed when the session starts.
  final int maximumDecodedResponseBodyBytes;

  /// The recording lifecycle configuration fixed when the session starts.
  final RecordingConfiguration recording;

  /// The target-handling options fixed when the session starts.
  final RecordingOptions options;

  /// Whether the target existed when this recording started.
  final RecordingTargetPresence targetPresence;

  /// The exact append target snapshot, or null for create and replacement.
  final CassetteSnapshot? appendSnapshot;

  int _nextArrivalIndex;
  final Map<int, CassetteInteraction> _interactions;
  var _acceptsRequests = true;
  Cassette? _finalisedCassette;
  var _pendingRequestCount = 0;
  var _failedRequestCount = 0;
  var _failedRequestNetworkAccess = NetworkAccess.notAttempted;
  Completer<void>? _requestsSettled;
  var _isAbandoned = false;

  /// Whether another request may enter this recording state.
  bool get acceptsRequests => _acceptsRequests;

  /// Whether this state has fixed its final immutable cassette value.
  bool get isFinalised => _finalisedCassette != null;

  /// The number of admitted recording requests which have not settled.
  int get pendingRequestCount => _pendingRequestCount;

  /// Whether an admitted request failed before producing a retained interaction.
  bool get hasFailedRequests => _failedRequestCount > 0;

  /// The strongest network-access state observed among failed requests.
  NetworkAccess get failedRequestNetworkAccess => _failedRequestNetworkAccess;

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

  /// Abandons every retained interaction and rejects later retention.
  ///
  /// A pending real request may still return its live outcome, but that result
  /// cannot enter this recording after abandonment.
  void abandon() {
    sealRequestAdmission();
    _isAbandoned = true;
    _interactions.clear();
  }

  /// Seals request admission and waits for admitted requests to settle.
  ///
  /// The complete wait uses one [RecordingConfiguration.closeGracePeriod]. A
  /// settled result does not mean every request succeeded; inspect
  /// [hasFailedRequests] after settlement to distinguish that case.
  Future<RecordingSettlementResult> sealAndWaitForRequests() {
    sealRequestAdmission();
    return whenRequestsSettled
        .then((_) => RecordingSettlementResult.settled)
        .timeout(
          recording.closeGracePeriod,
          onTimeout: () => RecordingSettlementResult.timedOut,
        );
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
    Object? failure;
    try {
      final result = await requestAttempt.run(
        attempt,
        cancellation: cancellation,
      );
      if (!_isAbandoned) {
        retainResult(result);
      }
      succeeded = true;
      return result.outcome;
    } catch (error) {
      failure = error;
      rethrow;
    } finally {
      _settleRequest(succeeded: succeeded, failure: failure);
    }
  }

  /// Sanitises [result] into an interaction without retaining it.
  CassetteInteraction sanitiseResult(RecordingRequestResult result) =>
      sanitiseRecordingResult(
        result,
        sanitisation,
        maximumDecodedResponseBodyBytes: maximumDecodedResponseBodyBytes,
      );

  /// Sanitises and retains one successful admitted request [result].
  ///
  /// Retention occurs synchronously after complete sanitisation. A result index
  /// must have been assigned by this session and may be retained only once.
  CassetteInteraction retainResult(RecordingRequestResult result) {
    if (_isAbandoned) {
      throw StateError('An abandoned recording cannot retain a result.');
    }
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

  void _settleRequest({required bool succeeded, required Object? failure}) {
    if (_pendingRequestCount <= 0) {
      throw StateError('Recording request settlement is not pending.');
    }
    if (!succeeded) {
      _failedRequestCount += 1;
      final networkAccess = failure is CassetteException
          ? failure.diagnostic.networkAccess
          : NetworkAccess.attempted;
      if (networkAccess == NetworkAccess.attempted) {
        _failedRequestNetworkAccess = NetworkAccess.attempted;
      }
    }
    _pendingRequestCount -= 1;
    if (_pendingRequestCount == 0) {
      _requestsSettled!.complete();
      _requestsSettled = null;
    }
  }
}

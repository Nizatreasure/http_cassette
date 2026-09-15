import 'dart:async';

import '../adapter/cancellation.dart';
import '../adapter/interception.dart';
import '../adapter/real_http_attempt.dart';
import '../cassette/name.dart';
import '../configuration/activation_policy.dart';
import '../configuration/cassette_configuration.dart';
import '../diagnostics/diagnostic.dart';
import '../diagnostics/exception.dart';
import '../model/http_message.dart';
import '../model/outcome.dart';
import '../recording/active_state.dart';
import '../recording/append_preparation.dart';
import '../recording/cassette_committer.dart';
import '../recording/configuration.dart';
import '../replay/active_state.dart';
import '../replay/cassette_loader.dart';
import '../replay/configuration.dart';
import '../replay/execution.dart';
import '../replay/unused_interactions_diagnostic.dart';
import '../replay/verification.dart';
import '../session/cassette_mode.dart';
import '../session/cassette_session.dart';
import '../store/exception.dart';
import '../store/operation_timeout.dart';
import '../store/store.dart';
import 'scoped_session.dart';
import 'session_ownership.dart';

/// Coordinates cassette sessions independently of any HTTP transport.
///
/// One engine owns one store, one immutable configuration and at most one
/// pending or active session. HTTP client adapters use
/// [beginInterception] to connect transport traffic to that session.
final class CassetteEngine {
  /// Creates an inactive engine backed by [store].
  ///
  /// Omitting [configuration] uses secure matching and sanitisation defaults,
  /// measured body limits and strict replay selection. [activationPolicy]
  /// controls whether recording and replay commands may activate the engine.
  factory CassetteEngine({
    required CassetteStore store,
    CassetteConfiguration? configuration,
    CassetteActivationPolicy activationPolicy =
        CassetteActivationPolicy.enabled,
  }) =>
      CassetteEngine._(
        EngineState(
          store: store,
          configuration: configuration ?? CassetteConfiguration(),
        ),
        activationPolicy,
      );

  const CassetteEngine._(this._state, this.activationPolicy);

  final EngineState _state;

  /// The immutable policy controlling whether this engine may start sessions.
  final CassetteActivationPolicy activationPolicy;

  /// Whether this engine owns a pending or active session.
  bool get isActive => _state.sessions.isActive;

  /// The current session, or null when this engine is inactive.
  CassetteSession? get activeSession => _state.sessions.activeSession;

  /// Begins one immutable adapter interception decision.
  ///
  /// An inactive permit tells an adapter to pass the original transport request
  /// through without canonical buffering. An active permit pins the current
  /// session, exposes its body limits and may execute one canonical request.
  ///
  /// Throws [StateError] when session startup is pending and no completed
  /// session can be pinned safely.
  CassetteInterception beginInterception() {
    final session = activeSession;
    if (session != null) {
      final recording = _state.activeRecording;
      if (session.mode == CassetteMode.record &&
          recording != null &&
          !recording.acceptsRequests) {
        return createInactiveCassetteInterception();
      }
      return createActiveCassetteInterception(
        session: session,
        bodyLimits: _state.configuration.bodyLimits,
        executor: _state.executePinnedInterception,
      );
    }
    if (isActive) {
      throw StateError(
        'Cassette interception cannot pin a session while startup is pending.',
      );
    }
    return createInactiveCassetteInterception();
  }

  /// Runs [action] within an explicit recording session named [name].
  ///
  /// The session commits only after [action] succeeds. A callback failure
  /// discards the session and is rethrown with its original stack trace. If
  /// cleanup also fails, a [ScopedCassetteException] retains the callback as
  /// the primary failure with a safe secondary diagnostic.
  Future<T> record<T>(
    String name,
    FutureOr<T> Function() action, {
    RecordingOptions options = const RecordingOptions(),
  }) async {
    final session = await startRecording(name, options: options);
    return runScopedSession(session: session, action: action);
  }

  /// Starts a recording session named [name].
  ///
  /// The [options] determine whether an existing target is rejected, replaced
  /// or appended. Startup validates the required target state but writes
  /// nothing. The returned session collects interactions until it is closed or
  /// discarded.
  ///
  /// Throws [CassetteException] when activation is disabled, another session
  /// owns the engine, or cassette preparation fails.
  Future<CassetteSession> startRecording(
    String name, {
    RecordingOptions options = const RecordingOptions(),
  }) async {
    final disabledSession = _sessionWhenDisabled(name, CassetteMode.record);
    if (disabledSession != null) {
      return disabledSession;
    }
    return _state.startRecording(CassetteName(name), options);
  }

  /// Runs [action] within an explicit replay session named [name].
  ///
  /// The cassette is fully loaded before [action] is invoked. Successful close
  /// applies optional unused-interaction verification. A callback failure
  /// discards replay state and is rethrown with its original stack trace. If
  /// cleanup also fails, [ScopedCassetteException] retains the callback as the
  /// primary failure with a safe secondary diagnostic.
  Future<T> replay<T>(
    String name,
    FutureOr<T> Function() action, {
    ReplayOptions options = const ReplayOptions(),
  }) async {
    final session = await startReplay(name, options: options);
    return runScopedSession(session: session, action: action);
  }

  /// Loads and starts a replay session named [name].
  ///
  /// The complete cassette is read and validated before [activeSession]
  /// exposes the returned session. [options] may override replay selection and
  /// require every interaction to be used before successful close.
  ///
  /// A loading failure leaves the engine inactive and throws a safe
  /// [CassetteException].
  Future<CassetteSession> startReplay(
    String name, {
    ReplayOptions options = const ReplayOptions(),
  }) async {
    final disabledSession = _sessionWhenDisabled(name, CassetteMode.replay);
    if (disabledSession != null) {
      return disabledSession;
    }
    return _state.startReplay(CassetteName(name), options);
  }

  CassetteSession? _sessionWhenDisabled(String name, CassetteMode mode) =>
      switch (activationPolicy) {
        CassetteActivationPolicy.enabled => null,
        CassetteActivationPolicy.disabledWithException =>
          throw _activationDisabledException(),
        CassetteActivationPolicy.disabledWithPassThrough =>
          createCassetteSession(
            name: CassetteName(name),
            mode: mode,
            closeAction: _completeInertSession,
            discardAction: _completeInertSession,
          ),
      };
}

CassetteException _activationDisabledException() => CassetteException(
      CassetteDiagnostic(
        category: DiagnosticCategory.cassetteActivationDisabled,
        summary: 'HTTP Cassette activation is disabled for this engine.',
        networkAccess: NetworkAccess.notAttempted,
      ),
    );

Future<void> _completeInertSession() async {}

/// Holds the dependencies and mutable session state owned by one engine.
final class EngineState {
  /// Creates state retaining the engine's [store] and [configuration].
  EngineState({required this.store, required this.configuration});

  /// The store used to load and commit cassettes.
  final CassetteStore store;

  /// Immutable shared engine configuration.
  final CassetteConfiguration configuration;

  /// One-active-session ownership for this engine only.
  final EngineSessionOwnership sessions = EngineSessionOwnership();

  /// The resolved replay state retained only while its session is active.
  ActiveReplayState? activeReplay;

  /// The recording state retained only while its session is active.
  ActiveRecordingState? activeRecording;

  /// Loads, starts and retains one active replay session.
  Future<CassetteSession> startReplay(
    CassetteName name,
    ReplayOptions options,
  ) async {
    final reservation = sessions.reserve(CassetteMode.replay);
    ActiveReplayState? preparedReplay;
    try {
      final result = await ReplayCassetteLoader(
        store,
        operationTimeout: configuration.storeOperations.timeout,
      ).load(name);
      switch (result) {
        case ReplayCassetteLoadFailed(:final failure):
          throw replayCassetteLoadException(failure);
        case ReplayCassetteLoaded(:final cassette):
          preparedReplay = ActiveReplayState(
            cassetteName: name,
            cassette: cassette,
            configuration: configuration,
            options: options,
          );
          activeReplay = preparedReplay;
          return reservation.activate(
            name: name,
            mode: CassetteMode.replay,
            closeAction: completeActiveReplay,
            discardAction: completeReplayLifecycleOnly,
          );
      }
    } catch (_) {
      if (identical(activeReplay, preparedReplay)) {
        activeReplay = null;
      }
      reservation.cancel();
      rethrow;
    }
  }

  /// Preflights, starts and retains one active recording session.
  Future<CassetteSession> startRecording(
    CassetteName name,
    RecordingOptions options,
  ) async {
    final reservation = sessions.reserve(CassetteMode.record);
    AppendCassettePrepared? appendPreparation;
    ActiveRecordingState? preparedRecording;
    try {
      if (options.existingCassette == ExistingCassette.append) {
        final result = await AppendCassettePreparer(
          store,
          operationTimeout: configuration.storeOperations.timeout,
        ).prepare(name);
        switch (result) {
          case AppendCassettePrepared():
            appendPreparation = result;
          case AppendCassettePreparationFailed(:final failure):
            throw CassetteException(failure.envelope);
        }
      } else {
        await _preflightRecordingTarget(name, options.existingCassette);
      }
      preparedRecording = ActiveRecordingState(
        cassetteName: name,
        configuration: configuration,
        options: options,
        appendPreparation: appendPreparation,
      );
      activeRecording = preparedRecording;
      return reservation.activate(
        name: name,
        mode: CassetteMode.record,
        closeAction: commitActiveRecording,
        discardAction: completeRecordingLifecycleOnly,
      );
    } catch (_) {
      if (identical(activeRecording, preparedRecording)) {
        activeRecording = null;
      }
      reservation.cancel();
      rethrow;
    }
  }

  Future<void> _preflightRecordingTarget(
    CassetteName name,
    ExistingCassette handling,
  ) async {
    if (handling == ExistingCassette.append) {
      throw StateError('Append uses dedicated target preparation.');
    }

    late final bool targetExists;
    try {
      targetExists = await runStoreOperation(
        action: () => store.exists(name),
        timeout: configuration.storeOperations.timeout,
        name: name,
        operation: CassetteStoreOperation.exists,
      );
    } on CassetteStoreException catch (failure) {
      if (failure.name != name ||
          failure.operation != CassetteStoreOperation.exists ||
          failure.kind == CassetteStoreFailureKind.notFound ||
          failure.kind == CassetteStoreFailureKind.alreadyExists ||
          failure.kind == CassetteStoreFailureKind.revisionChanged) {
        throw StateError(
          'A cassette store reported an invalid existence-check failure.',
        );
      }
      throw CassetteException(
        CassetteDiagnostic(
          category: DiagnosticCategory.storeReadFailure,
          summary: 'The recording target could not be checked.',
          networkAccess: NetworkAccess.notAttempted,
        ),
      );
    }

    if (handling == ExistingCassette.fail && targetExists) {
      throw CassetteException(
        CassetteDiagnostic(
          category: DiagnosticCategory.targetCassetteExists,
          summary: 'The recording target already exists.',
          networkAccess: NetworkAccess.notAttempted,
        ),
      );
    }
    if (handling == ExistingCassette.replace && !targetExists) {
      throw CassetteException(
        CassetteDiagnostic(
          category: DiagnosticCategory.cassetteMissing,
          summary: 'The recording replacement target does not exist.',
          networkAccess: NetworkAccess.notAttempted,
        ),
      );
    }
  }

  /// Resolves [request] through the currently active replay session.
  ///
  /// Replay has no real-transport callback. Calling this method without an
  /// active replay session throws a safe lifecycle exception.
  CassetteOutcome executeActiveReplayRequest(
    CassetteRequest request, {
    CassetteCancellation? cancellation,
  }) {
    final replay = activeReplay;
    if (replay == null) {
      final hasActiveSession = sessions.activeSession != null;
      throw CassetteException(
        CassetteDiagnostic(
          category: hasActiveSession
              ? DiagnosticCategory.conflictingSessionOperation
              : DiagnosticCategory.noActiveSession,
          summary: hasActiveSession
              ? 'The active cassette session is not a replay session.'
              : 'Replay execution requires an active cassette session.',
          networkAccess: NetworkAccess.disabled,
        ),
      );
    }
    return executeReplayRequest(
      state: replay,
      request: request,
      cancellation: cancellation,
    );
  }

  /// Routes one request only through its exact pinned [session].
  ///
  /// A completed or replaced session fails before recording can invoke
  /// [realAttempt]. Replay routing never invokes [realAttempt].
  Future<CassetteOutcome> executePinnedInterception(
    CassetteSession session,
    CassetteRequest request,
    RealHttpAttempt realAttempt,
    CassetteCancellation? cancellation,
  ) {
    if (!identical(sessions.activeSession, session)) {
      return Future<CassetteOutcome>.error(
        CassetteException(
          CassetteDiagnostic(
            category: DiagnosticCategory.sessionAlreadyClosed,
            summary: 'The pinned cassette session is no longer active.',
            networkAccess: switch (session.mode) {
              CassetteMode.record => NetworkAccess.notAttempted,
              CassetteMode.replay => NetworkAccess.disabled,
            },
          ),
        ),
      );
    }
    return switch (session.mode) {
      CassetteMode.record => executeActiveRecordingRequest(
          request,
          realAttempt,
          cancellation: cancellation,
        ),
      CassetteMode.replay => Future<CassetteOutcome>.sync(
          () => executeActiveReplayRequest(
            request,
            cancellation: cancellation,
          ),
        ),
    };
  }

  /// Resolves [request] through the currently active recording session.
  ///
  /// The supplied real [attempt] is invoked only when a recording session is
  /// active. Lifecycle rejection occurs before the callback can be invoked.
  Future<CassetteOutcome> executeActiveRecordingRequest(
    CassetteRequest request,
    RealHttpAttempt attempt, {
    CassetteCancellation? cancellation,
  }) {
    final recording = activeRecording;
    if (recording == null) {
      final activeSession = sessions.activeSession;
      final isReplay = activeSession?.mode == CassetteMode.replay;
      return Future<CassetteOutcome>.error(
        CassetteException(
          CassetteDiagnostic(
            category: activeSession == null
                ? DiagnosticCategory.noActiveSession
                : DiagnosticCategory.conflictingSessionOperation,
            summary: activeSession == null
                ? 'Recording execution requires an active cassette session.'
                : 'The active cassette session is not a recording session.',
            networkAccess:
                isReplay ? NetworkAccess.disabled : NetworkAccess.notAttempted,
          ),
        ),
      );
    }
    if (!recording.acceptsRequests) {
      return Future<CassetteOutcome>.error(
        CassetteException(
          CassetteDiagnostic(
            category: DiagnosticCategory.conflictingSessionOperation,
            summary: 'The recording session is completing.',
            networkAccess: NetworkAccess.notAttempted,
          ),
        ),
      );
    }
    return recording.recordRequest(
      request,
      attempt,
      cancellation: cancellation,
    );
  }

  /// Clears lifecycle-only replay state before ownership is released.
  Future<void> completeReplayLifecycleOnly() {
    activeReplay = null;
    return Future<void>.value();
  }

  /// Verifies and clears the active replay after successful scoped work.
  Future<void> completeActiveReplay() {
    final replay = activeReplay;
    if (replay == null) {
      throw StateError('Replay completion requires active replay state.');
    }
    late final ReplayVerificationResult result;
    try {
      result = verifyReplayUsage(
        cassette: replay.cassette,
        usageSnapshots: replay.selectionStates.map(
          (state) => state.usageSnapshot,
        ),
        requireAllInteractions: replay.requireAllInteractions,
      );
    } finally {
      activeReplay = null;
    }
    if (result is ReplayUnusedInteractions) {
      throw replayUnusedInteractionsException(
        ReplayUnusedInteractionsDiagnostic.fromVerification(
          cassetteName: replay.cassetteName,
          replayPolicy: replay.replayPolicy,
          result: result,
        ),
      );
    }
    return Future<void>.value();
  }

  /// Commits create or replacement state before releasing it.
  Future<void> commitActiveRecording() async {
    final recording = activeRecording;
    if (recording == null) {
      throw StateError('Recording commit requires active recording state.');
    }
    var settlementCompleted = false;
    try {
      final settlement = await recording.sealAndWaitForRequests();
      settlementCompleted = true;
      if (settlement == RecordingSettlementResult.timedOut) {
        _endRecordingWithoutWrite(
          recording,
          category: DiagnosticCategory.recordingCloseTimedOut,
          summary: 'Recording close timed out before every request settled.',
        );
      }
      if (recording.hasFailedRequests) {
        _endRecordingWithoutWrite(
          recording,
          category: DiagnosticCategory.recordingRequestFailed,
          summary:
              'Recording was discarded because an admitted request failed.',
          networkAccess: recording.failedRequestNetworkAccess,
        );
      }
      await RecordingCassetteCommitter(
        store,
        operationTimeout: configuration.storeOperations.timeout,
      ).commit(recording);
    } finally {
      if (!settlementCompleted) {
        recording.abandon();
      }
      if (identical(activeRecording, recording)) {
        activeRecording = null;
      }
    }
  }

  Never _endRecordingWithoutWrite(
    ActiveRecordingState recording, {
    required DiagnosticCategory category,
    required String summary,
    NetworkAccess networkAccess = NetworkAccess.attempted,
  }) {
    if (!identical(activeRecording, recording)) {
      throw StateError('Only the active recording can end without a write.');
    }
    recording.abandon();
    activeRecording = null;
    throw CassetteException(
      CassetteDiagnostic(
        category: category,
        summary: summary,
        networkAccess: networkAccess,
      ),
    );
  }

  /// Clears lifecycle-only recording state before ownership is released.
  Future<void> completeRecordingLifecycleOnly() {
    activeRecording = null;
    return Future<void>.value();
  }
}

import '../cassette/name.dart';
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
import '../session/cassette_mode.dart';
import '../session/cassette_session.dart';
import '../store/exception.dart';
import '../store/store.dart';
import 'session_ownership.dart';

/// Coordinates cassette sessions independently of any HTTP transport.
///
/// The current engine retains recording state and executes replay internally,
/// but does not yet expose transport interception. Recording capture and
/// persistence are connected in later stages.
final class CassetteEngine {
  /// Creates an inactive engine backed by [store].
  ///
  /// Omitting [configuration] uses secure matching and sanitisation defaults,
  /// measured body limits and strict replay selection.
  factory CassetteEngine({
    required CassetteStore store,
    CassetteConfiguration? configuration,
  }) =>
      CassetteEngine._(
        EngineState(
          store: store,
          configuration: configuration ?? CassetteConfiguration(),
        ),
      );

  const CassetteEngine._(this._state);

  final EngineState _state;

  /// Whether this engine owns a pending, active or uncertain session.
  bool get isActive => _state.sessions.isActive;

  /// The current session, or null when this engine is inactive.
  CassetteSession? get activeSession => _state.sessions.activeSession;

  /// Starts a recording session named [name].
  ///
  /// Default create and explicit replacement first check whether the target
  /// has the required existence state. No cassette is written at startup.
  Future<CassetteSession> startRecording(
    String name, {
    RecordingOptions options = const RecordingOptions(),
  }) =>
      _state.startRecording(CassetteName(name), options);

  /// Loads and starts a replay session named [name].
  ///
  /// The complete cassette is read and validated before [activeSession]
  /// exposes the returned session. A loading failure leaves the engine
  /// inactive and throws a safe [CassetteException]. Request interception is
  /// not implemented yet.
  Future<CassetteSession> startReplay(
    String name, {
    ReplayOptions options = const ReplayOptions(),
  }) async {
    final cassetteName = CassetteName(name);
    final reservation = _state.sessions.reserve(CassetteMode.replay);
    late final ReplayCassetteLoadResult result;
    try {
      result = await ReplayCassetteLoader(_state.store).load(cassetteName);
    } catch (_) {
      reservation.cancel();
      rethrow;
    }

    switch (result) {
      case ReplayCassetteLoadFailed(:final failure):
        reservation.cancel();
        throw replayCassetteLoadException(failure);
      case ReplayCassetteLoaded(:final cassette):
        _state.activeReplay = ActiveReplayState(
          cassetteName: cassetteName,
          cassette: cassette,
          configuration: _state.configuration,
          options: options,
        );
        return reservation.activate(
          name: cassetteName,
          mode: CassetteMode.replay,
          closeAction: _state.completeReplayLifecycleOnly,
          discardAction: _state.completeReplayLifecycleOnly,
        );
    }
  }
}

/// Dependencies and mutable session ownership retained by one engine.
///
/// This internal value is not exported from the package's public library.
final class EngineState {
  /// Creates state retaining the engine's [store] and [configuration].
  EngineState({required this.store, required this.configuration});

  /// The store used by later loading and persistence stages.
  final CassetteStore store;

  /// Immutable shared engine configuration.
  final CassetteConfiguration configuration;

  /// One-active-session ownership for this engine only.
  final EngineSessionOwnership sessions = EngineSessionOwnership();

  /// The resolved replay state retained only while its session is active.
  ActiveReplayState? activeReplay;

  /// The recording state retained only while its session is active.
  ActiveRecordingState? activeRecording;

  /// Preflights, starts and retains one active recording session.
  Future<CassetteSession> startRecording(
    CassetteName name,
    RecordingOptions options,
  ) async {
    final reservation = sessions.reserve(CassetteMode.record);
    AppendCassettePrepared? appendPreparation;
    try {
      if (options.existingCassette == ExistingCassette.append) {
        final result = await AppendCassettePreparer(store).prepare(name);
        switch (result) {
          case AppendCassettePrepared():
            appendPreparation = result;
          case AppendCassettePreparationFailed(:final failure):
            throw CassetteException(failure.envelope);
        }
      } else {
        await _preflightRecordingTarget(name, options.existingCassette);
      }
    } catch (_) {
      reservation.cancel();
      rethrow;
    }
    activeRecording = ActiveRecordingState(
      cassetteName: name,
      configuration: configuration,
      options: options,
      appendPreparation: appendPreparation,
    );
    return reservation.activate(
      name: name,
      mode: CassetteMode.record,
      closeAction: commitActiveRecording,
      discardAction: completeRecordingLifecycleOnly,
    );
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
      targetExists = await store.exists(name);
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
  /// This internal operation has no real-transport callback. Calling it while
  /// no replay session is active throws a safe lifecycle exception.
  CassetteOutcome executeActiveReplayRequest(CassetteRequest request) {
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
    return executeReplayRequest(state: replay, request: request);
  }

  /// Resolves [request] through the currently active recording session.
  ///
  /// The supplied real [attempt] is invoked only when a recording session is
  /// active. Lifecycle rejection occurs before the callback can be invoked.
  Future<CassetteOutcome> executeActiveRecordingRequest(
    CassetteRequest request,
    Future<CassetteOutcome> Function() attempt,
  ) {
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
    return recording.recordRequest(request, attempt);
  }

  /// Clears lifecycle-only replay state before ownership is released.
  Future<void> completeReplayLifecycleOnly() {
    activeReplay = null;
    return Future<void>.value();
  }

  /// Commits create or replacement state before releasing it.
  Future<void> commitActiveRecording() async {
    final recording = activeRecording;
    if (recording == null) {
      throw StateError('Recording commit requires active recording state.');
    }
    recording.sealRequestAdmission();
    await RecordingCassetteCommitter(store).commit(recording);
    activeRecording = null;
  }

  /// Clears lifecycle-only recording state before ownership is released.
  Future<void> completeRecordingLifecycleOnly() {
    activeRecording = null;
    return Future<void>.value();
  }
}

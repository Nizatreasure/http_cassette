import '../cassette/cassette.dart';
import '../cassette/name.dart';
import '../configuration/cassette_configuration.dart';
import '../diagnostics/exception.dart';
import '../recording/configuration.dart';
import '../replay/cassette_loader.dart';
import '../replay/configuration.dart';
import '../session/cassette_mode.dart';
import '../session/cassette_session.dart';
import '../store/store.dart';
import 'session_ownership.dart';

/// Coordinates cassette sessions independently of any HTTP transport.
///
/// The current engine loads replay sessions but does not yet intercept traffic.
/// Recording, replay execution and persistence are connected in later stages.
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

  /// Starts a lifecycle-only recording session named [name].
  ///
  /// [options] becomes operational when recording persistence is connected.
  /// The current implementation performs no store or transport work.
  Future<CassetteSession> startRecording(
    String name, {
    RecordingOptions options = const RecordingOptions(),
  }) =>
      Future<CassetteSession>.sync(
        () => _startSession(name, CassetteMode.record),
      );

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
        _state.activeReplayCassette = cassette;
        return reservation.activate(
          name: cassetteName,
          mode: CassetteMode.replay,
          closeAction: _state.completeReplayLifecycleOnly,
          discardAction: _state.completeReplayLifecycleOnly,
        );
    }
  }

  CassetteSession _startSession(String name, CassetteMode mode) =>
      _state.sessions.acquire(
        name: CassetteName(name),
        mode: mode,
        closeAction: _completeLifecycleOnly,
        discardAction: _completeLifecycleOnly,
      );
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

  /// The validated cassette retained only while its replay session is active.
  Cassette? activeReplayCassette;

  /// Clears lifecycle-only replay state before ownership is released.
  Future<void> completeReplayLifecycleOnly() {
    activeReplayCassette = null;
    return Future<void>.value();
  }
}

Future<void> _completeLifecycleOnly() => Future<void>.value();

import '../cassette/name.dart';
import '../diagnostics/exception.dart';
import 'cassette_mode.dart';
import 'session_lifecycle.dart';

/// A handle to one active cassette operation.
///
/// Sessions are created by a cassette engine in a later implementation stage.
/// Closing or discarding may perform asynchronous completion work supplied by
/// the engine.
final class CassetteSession {
  CassetteSession._({
    required CassetteName name,
    required this.mode,
    required Future<void> Function() closeAction,
    required Future<void> Function() discardAction,
  })  : name = name.value,
        _closeAction = closeAction,
        _discardAction = discardAction,
        _lifecycle = SessionLifecycle(mode);

  /// The validated slash-separated logical cassette name.
  final String name;

  /// Whether this session records or replays interactions.
  final CassetteMode mode;

  final Future<void> Function() _closeAction;
  final Future<void> Function() _discardAction;
  final SessionLifecycle _lifecycle;

  /// Whether close or discard completed successfully.
  ///
  /// This remains false when completion fails and leaves an uncertain state.
  bool get isClosed => _lifecycle.isClosed;

  /// Completes this session successfully.
  ///
  /// A recording session will commit its pending cassette and a replay session
  /// will perform configured verification in later engine stages. Concurrent
  /// completion or completion after a failure throws a [CassetteException].
  Future<void> close() async {
    if (_lifecycle.startClose() == SessionLifecycleStart.alreadyClosed) {
      return;
    }
    try {
      await _closeAction();
    } catch (_) {
      _lifecycle.closeFailed();
      rethrow;
    }
    _lifecycle.closeSucceeded();
  }

  /// Abandons pending successful-completion work and closes this session.
  ///
  /// Concurrent completion or completion after a failure throws a
  /// [CassetteException]. Recording and replay discard behaviour is connected
  /// by later engine stages.
  Future<void> discard() async {
    if (_lifecycle.startDiscard() == SessionLifecycleStart.alreadyClosed) {
      return;
    }
    try {
      await _discardAction();
    } catch (_) {
      _lifecycle.discardFailed();
      rethrow;
    }
    _lifecycle.discardSucceeded();
  }
}

/// Creates a session for internal engine composition.
///
/// This function is deliberately not exported from the package's public
/// library. [name] is already validated before lifecycle state is created.
CassetteSession createCassetteSession({
  required CassetteName name,
  required CassetteMode mode,
  required Future<void> Function() closeAction,
  required Future<void> Function() discardAction,
}) =>
    CassetteSession._(
      name: name,
      mode: mode,
      closeAction: closeAction,
      discardAction: discardAction,
    );

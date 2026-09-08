import '../cassette/name.dart';
import '../diagnostics/exception.dart';
import 'cassette_mode.dart';
import 'session_lifecycle.dart';

/// A handle to one active cassette operation.
///
/// A [CassetteEngine] creates this handle after recording or replay startup
/// succeeds. Use [close] to complete the operation or [discard] to abandon its
/// pending completion work.
final class CassetteSession {
  CassetteSession._({
    required CassetteName name,
    required this.mode,
    required Future<void> Function() closeAction,
    required Future<void> Function() discardAction,
    required void Function() completionSucceeded,
  })  : name = name.value,
        _closeAction = closeAction,
        _discardAction = discardAction,
        _completionSucceeded = completionSucceeded,
        _lifecycle = SessionLifecycle(mode);

  /// The validated slash-separated logical cassette name.
  final String name;

  /// Whether this session records or replays interactions.
  final CassetteMode mode;

  final Future<void> Function() _closeAction;
  final Future<void> Function() _discardAction;
  final void Function() _completionSucceeded;
  final SessionLifecycle _lifecycle;

  /// Whether close or discard completed successfully.
  ///
  /// This remains false when completion fails and leaves an uncertain state.
  bool get isClosed => _lifecycle.isClosed;

  /// Completes this recording or replay session.
  ///
  /// Recording close writes the complete sanitised cassette. Append close keeps
  /// the existing interactions and conditionally replaces the stored cassette.
  /// Replay close performs unused-interaction verification when configured.
  /// Repeated close after successful completion is harmless. Concurrent
  /// completion, or completion after a failed close or discard, throws a
  /// [CassetteException].
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
    _completionSucceeded();
  }

  /// Ends this session without running its successful completion work.
  ///
  /// Recording discard performs no cassette write. Replay discard skips
  /// unused-interaction verification. Repeated discard after successful
  /// completion is harmless. Concurrent completion, or completion after a
  /// failed close or discard, throws a [CassetteException].
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
    _completionSucceeded();
  }
}

/// Creates a session with validated identity and supplied completion actions.
///
/// [closeAction] performs successful completion work, while [discardAction]
/// abandons it. [completionSucceeded] runs after either action succeeds.
CassetteSession createCassetteSession({
  required CassetteName name,
  required CassetteMode mode,
  required Future<void> Function() closeAction,
  required Future<void> Function() discardAction,
  void Function()? completionSucceeded,
}) =>
    CassetteSession._(
      name: name,
      mode: mode,
      closeAction: closeAction,
      discardAction: discardAction,
      completionSucceeded: completionSucceeded ?? _noOp,
    );

void _noOp() {}

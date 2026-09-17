import '../cassette/name.dart';
import '../diagnostics/exception.dart';
import 'cassette_mode.dart';
import 'session_lifecycle.dart';

/// A handle to one active cassette operation.
///
/// A [CassetteEngine] creates this handle after recording or replay startup
/// succeeds. Use [close] to complete the operation or [discard] to abandon its
/// successful completion work.
final class CassetteSession {
  CassetteSession._({
    required CassetteName name,
    required this.mode,
    required Future<void> Function() closeAction,
    required Future<void> Function() discardAction,
    required void Function() completionFinished,
  })  : name = name.value,
        _closeAction = closeAction,
        _discardAction = discardAction,
        _completionFinished = completionFinished,
        _lifecycle = SessionLifecycle(mode);

  /// The validated slash-separated logical cassette name.
  final String name;

  /// Whether this session records or replays interactions.
  final CassetteMode mode;

  final Future<void> Function() _closeAction;
  final Future<void> Function() _discardAction;
  final void Function() _completionFinished;
  final SessionLifecycle _lifecycle;

  /// Whether the session has reached a final state.
  bool get isClosed => _lifecycle.isClosed;

  /// Completes this recording or replay session.
  ///
  /// Recording close writes the complete sanitised cassette. Append close keeps
  /// the existing interactions and conditionally replaces the stored cassette.
  /// Replay close performs unused-interaction verification when configured.
  /// Close failure ends the session and leaves its error as the description of
  /// that operation. Repeated completion after close returns or throws is
  /// harmless. Concurrent completion throws a [CassetteException].
  Future<void> close() => _complete(
        start: _lifecycle.startClose,
        action: _closeAction,
        succeeded: _lifecycle.closeSucceeded,
        failed: _lifecycle.closeFailed,
      );

  /// Ends this session without running its successful completion work.
  ///
  /// Recording discard performs no cassette write. Replay discard skips
  /// unused-interaction verification. Repeated discard after successful
  /// completion is harmless. A discard failure ends the session and leaves its
  /// error as the description of that operation. Concurrent completion throws
  /// a [CassetteException].
  Future<void> discard() => _complete(
        start: _lifecycle.startDiscard,
        action: _discardAction,
        succeeded: _lifecycle.discardSucceeded,
        failed: _lifecycle.discardFailed,
      );

  Future<void> _complete({
    required SessionLifecycleStart Function() start,
    required Future<void> Function() action,
    required void Function() succeeded,
    required void Function() failed,
  }) async {
    if (start() == SessionLifecycleStart.alreadyClosed) {
      return;
    }
    var actionSucceeded = false;
    try {
      await action();
      actionSucceeded = true;
    } finally {
      try {
        if (actionSucceeded) {
          succeeded();
        } else {
          failed();
        }
      } finally {
        _completionFinished();
      }
    }
  }
}

/// Creates a session with validated identity and supplied completion actions.
///
/// [closeAction] performs successful completion work, while [discardAction]
/// abandons it. [completionFinished] runs when either action leaves the session
/// in a known final state.
CassetteSession createCassetteSession({
  required CassetteName name,
  required CassetteMode mode,
  required Future<void> Function() closeAction,
  required Future<void> Function() discardAction,
  void Function()? completionFinished,
}) =>
    CassetteSession._(
      name: name,
      mode: mode,
      closeAction: closeAction,
      discardAction: discardAction,
      completionFinished: completionFinished ?? _noOp,
    );

void _noOp() {}

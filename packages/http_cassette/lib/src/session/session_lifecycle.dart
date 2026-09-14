import '../diagnostics/diagnostic.dart';
import '../diagnostics/exception.dart';
import 'cassette_mode.dart';

/// The lifecycle state of one cassette session.
enum SessionLifecycleState {
  /// The session can begin closing or discarding.
  open,

  /// Successful close work is in progress.
  closing,

  /// Discard work is in progress.
  discarding,

  /// The session completed or ended with a known final state.
  closed,
}

/// The result of trying to begin close or discard work.
enum SessionLifecycleStart {
  /// The caller owns the requested completion work.
  proceed,

  /// The session already reached a final state, so no work remains.
  alreadyClosed,
}

/// Synchronous state control for one cassette session.
///
/// Starting an operation is synchronous so competing asynchronous callers
/// cannot both acquire completion work in one isolate.
final class SessionLifecycle {
  /// Creates an open lifecycle for an explicit session [mode].
  SessionLifecycle(this.mode);

  /// The session mode used to describe network availability safely.
  final CassetteMode mode;

  var _state = SessionLifecycleState.open;

  /// The current lifecycle state.
  SessionLifecycleState get state => _state;

  /// Whether the session has reached a known final state.
  bool get isClosed => _state == SessionLifecycleState.closed;

  /// Begins close work or reports that the session already ended.
  SessionLifecycleStart startClose() => _start(SessionLifecycleState.closing);

  /// Marks in-progress close work as successful.
  void closeSucceeded() => _succeed(SessionLifecycleState.closing);

  /// Marks failed close work as terminal.
  void closeFailed() => _succeed(SessionLifecycleState.closing);

  /// Begins discard work or reports that the session already ended.
  SessionLifecycleStart startDiscard() =>
      _start(SessionLifecycleState.discarding);

  /// Marks in-progress discard work as successful.
  void discardSucceeded() => _succeed(SessionLifecycleState.discarding);

  /// Marks failed discard work as terminal.
  void discardFailed() => _succeed(SessionLifecycleState.discarding);

  SessionLifecycleStart _start(SessionLifecycleState operation) {
    switch (_state) {
      case SessionLifecycleState.open:
        _state = operation;
        return SessionLifecycleStart.proceed;
      case SessionLifecycleState.closed:
        return SessionLifecycleStart.alreadyClosed;
      case SessionLifecycleState.closing:
      case SessionLifecycleState.discarding:
        throw _conflict(
          'A cassette session completion operation is already in progress.',
        );
    }
  }

  void _succeed(SessionLifecycleState expected) {
    _requireInProgress(expected);
    _state = SessionLifecycleState.closed;
  }

  void _requireInProgress(SessionLifecycleState expected) {
    if (_state != expected) {
      throw StateError(
        'Lifecycle completion does not match the in-progress operation.',
      );
    }
  }

  CassetteException _conflict(String summary) => CassetteException(
        CassetteDiagnostic(
          category: DiagnosticCategory.conflictingSessionOperation,
          summary: summary,
          networkAccess: switch (mode) {
            CassetteMode.record => NetworkAccess.notAttempted,
            CassetteMode.replay => NetworkAccess.disabled,
          },
        ),
      );
}

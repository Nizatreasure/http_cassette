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

  /// Close or discard completed successfully.
  closed,

  /// Completion failed, so the session's final state cannot be assumed.
  uncertain,
}

/// The result of trying to begin close or discard work.
enum SessionLifecycleStart {
  /// The caller owns the requested completion work.
  proceed,

  /// Earlier completion succeeded, so no work remains.
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

  /// Whether close or discard completed successfully.
  bool get isClosed => _state == SessionLifecycleState.closed;

  /// Begins close work or reports that completion already succeeded.
  SessionLifecycleStart startClose() => _start(SessionLifecycleState.closing);

  /// Marks in-progress close work as successful.
  void closeSucceeded() => _succeed(SessionLifecycleState.closing);

  /// Marks in-progress close work as failed and the state as uncertain.
  void closeFailed() => _fail(SessionLifecycleState.closing);

  /// Begins discard work or reports that completion already succeeded.
  SessionLifecycleStart startDiscard() =>
      _start(SessionLifecycleState.discarding);

  /// Marks in-progress discard work as successful.
  void discardSucceeded() => _succeed(SessionLifecycleState.discarding);

  /// Marks in-progress discard work as failed and the state as uncertain.
  void discardFailed() => _fail(SessionLifecycleState.discarding);

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
      case SessionLifecycleState.uncertain:
        throw _conflict(
          'The cassette session state is uncertain after a completion failure.',
        );
    }
  }

  void _succeed(SessionLifecycleState expected) {
    _requireInProgress(expected);
    _state = SessionLifecycleState.closed;
  }

  void _fail(SessionLifecycleState expected) {
    _requireInProgress(expected);
    _state = SessionLifecycleState.uncertain;
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

import '../cassette/name.dart';
import '../diagnostics/diagnostic.dart';
import '../diagnostics/exception.dart';
import '../session/cassette_mode.dart';
import '../session/cassette_session.dart';

/// Isolate-local ownership of at most one cassette session for an engine.
final class EngineSessionOwnership {
  Object? _reservation;
  CassetteSession? _activeSession;

  /// Whether this owner currently has a reservation or active session.
  bool get isActive => _reservation != null;

  /// The current session, or null when this owner is inactive.
  CassetteSession? get activeSession => _activeSession;

  /// Creates and reserves one session synchronously.
  ///
  /// The reservation remains until close or discard completes successfully.
  /// A completion failure deliberately retains ownership because final state is
  /// uncertain.
  CassetteSession acquire({
    required CassetteName name,
    required CassetteMode mode,
    required Future<void> Function() closeAction,
    required Future<void> Function() discardAction,
  }) {
    final reservation = reserve(mode);
    return reservation.activate(
      name: name,
      mode: mode,
      closeAction: closeAction,
      discardAction: discardAction,
    );
  }

  /// Reserves this owner while asynchronous session preparation runs.
  EngineSessionReservation reserve(CassetteMode mode) {
    if (_reservation != null) {
      throw CassetteException(
        CassetteDiagnostic(
          category: DiagnosticCategory.conflictingSessionOperation,
          summary: 'A cassette session is already active on this engine.',
          networkAccess: switch (mode) {
            CassetteMode.record => NetworkAccess.notAttempted,
            CassetteMode.replay => NetworkAccess.disabled,
          },
        ),
      );
    }

    final token = Object();
    _reservation = token;
    return EngineSessionReservation._(this, token);
  }

  CassetteSession _activate({
    required Object token,
    required CassetteName name,
    required CassetteMode mode,
    required Future<void> Function() closeAction,
    required Future<void> Function() discardAction,
  }) {
    if (!identical(_reservation, token) || _activeSession != null) {
      throw StateError('Only the current reservation can activate a session.');
    }
    late final CassetteSession session;
    session = createCassetteSession(
      name: name,
      mode: mode,
      closeAction: closeAction,
      discardAction: discardAction,
      completionSucceeded: () => _release(session),
    );
    _activeSession = session;
    return session;
  }

  void _cancel(Object token) {
    if (!identical(_reservation, token) || _activeSession != null) {
      throw StateError('Only a pending reservation can be cancelled.');
    }
    _reservation = null;
  }

  void _release(CassetteSession session) {
    if (!identical(_activeSession, session)) {
      throw StateError(
          'Only the active cassette session can release ownership.');
    }
    _reservation = null;
    _activeSession = null;
  }
}

/// A pending ownership reservation during asynchronous session preparation.
final class EngineSessionReservation {
  EngineSessionReservation._(this._owner, this._token);

  final EngineSessionOwnership _owner;
  final Object _token;
  bool _completed = false;

  /// Converts this reservation into the active session.
  CassetteSession activate({
    required CassetteName name,
    required CassetteMode mode,
    required Future<void> Function() closeAction,
    required Future<void> Function() discardAction,
  }) {
    if (_completed) {
      throw StateError('A session reservation can be completed only once.');
    }
    final session = _owner._activate(
      token: _token,
      name: name,
      mode: mode,
      closeAction: closeAction,
      discardAction: discardAction,
    );
    _completed = true;
    return session;
  }

  /// Releases this reservation after session preparation fails.
  void cancel() {
    if (_completed) {
      throw StateError('A session reservation can be completed only once.');
    }
    _owner._cancel(_token);
    _completed = true;
  }
}

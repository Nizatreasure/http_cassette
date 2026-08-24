import '../cassette/name.dart';
import '../diagnostics/diagnostic.dart';
import '../diagnostics/exception.dart';
import '../session/cassette_mode.dart';
import '../session/cassette_session.dart';

/// Isolate-local ownership of at most one cassette session for an engine.
final class EngineSessionOwnership {
  CassetteSession? _activeSession;

  /// Whether this owner currently has a session.
  bool get isActive => _activeSession != null;

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
    if (_activeSession != null) {
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

  void _release(CassetteSession session) {
    if (!identical(_activeSession, session)) {
      throw StateError(
          'Only the active cassette session can release ownership.');
    }
    _activeSession = null;
  }
}

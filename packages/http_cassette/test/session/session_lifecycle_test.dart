import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/session/session_lifecycle.dart';
import 'package:test/test.dart';

void main() {
  group('SessionLifecycle', () {
    test('starts open and completes close', () {
      final lifecycle = SessionLifecycle(CassetteMode.record);

      expect(lifecycle.state, SessionLifecycleState.open);
      expect(lifecycle.isClosed, isFalse);
      expect(lifecycle.startClose(), SessionLifecycleStart.proceed);
      expect(lifecycle.state, SessionLifecycleState.closing);

      lifecycle.closeSucceeded();

      expect(lifecycle.state, SessionLifecycleState.closed);
      expect(lifecycle.isClosed, isTrue);
    });

    test('starts open and completes discard', () {
      final lifecycle = SessionLifecycle(CassetteMode.replay);

      expect(lifecycle.startDiscard(), SessionLifecycleStart.proceed);
      expect(lifecycle.state, SessionLifecycleState.discarding);

      lifecycle.discardSucceeded();

      expect(lifecycle.state, SessionLifecycleState.closed);
      expect(lifecycle.isClosed, isTrue);
    });

    test('treats close and discard as complete after successful closure', () {
      final lifecycle = SessionLifecycle(CassetteMode.record);
      lifecycle
        ..startClose()
        ..closeSucceeded();

      expect(lifecycle.startClose(), SessionLifecycleStart.alreadyClosed);
      expect(lifecycle.startDiscard(), SessionLifecycleStart.alreadyClosed);
      expect(lifecycle.state, SessionLifecycleState.closed);
    });

    test('rejects competing completion while close is in progress', () {
      final lifecycle = SessionLifecycle(CassetteMode.record)..startClose();

      _expectLifecycleConflict(
        lifecycle.startClose,
        networkAccess: NetworkAccess.notAttempted,
      );
      _expectLifecycleConflict(
        lifecycle.startDiscard,
        networkAccess: NetworkAccess.notAttempted,
      );
      expect(lifecycle.state, SessionLifecycleState.closing);
    });

    test('rejects competing completion while discard is in progress', () {
      final lifecycle = SessionLifecycle(CassetteMode.replay)..startDiscard();

      _expectLifecycleConflict(
        lifecycle.startClose,
        networkAccess: NetworkAccess.disabled,
      );
      _expectLifecycleConflict(
        lifecycle.startDiscard,
        networkAccess: NetworkAccess.disabled,
      );
      expect(lifecycle.state, SessionLifecycleState.discarding);
    });

    test('retains an uncertain state after close failure', () {
      final lifecycle = SessionLifecycle(CassetteMode.replay)
        ..startClose()
        ..closeFailed();

      expect(lifecycle.state, SessionLifecycleState.uncertain);
      expect(lifecycle.isClosed, isFalse);
      _expectLifecycleConflict(
        lifecycle.startClose,
        networkAccess: NetworkAccess.disabled,
      );
      _expectLifecycleConflict(
        lifecycle.startDiscard,
        networkAccess: NetworkAccess.disabled,
      );
    });

    test('ends close with a known final state after safe failure', () {
      final lifecycle = SessionLifecycle(CassetteMode.record)
        ..startClose()
        ..closeFailedWithoutUncertainty();

      expect(lifecycle.state, SessionLifecycleState.closed);
      expect(lifecycle.isClosed, isTrue);
      expect(lifecycle.startClose(), SessionLifecycleStart.alreadyClosed);
      expect(lifecycle.startDiscard(), SessionLifecycleStart.alreadyClosed);
    });

    test('retains an uncertain state after discard failure', () {
      final lifecycle = SessionLifecycle(CassetteMode.record)
        ..startDiscard()
        ..discardFailed();

      expect(lifecycle.state, SessionLifecycleState.uncertain);
      expect(lifecycle.isClosed, isFalse);
      _expectLifecycleConflict(
        lifecycle.startClose,
        networkAccess: NetworkAccess.notAttempted,
      );
    });

    test('rejects mismatched internal completion without changing state', () {
      final lifecycle = SessionLifecycle(CassetteMode.record)..startClose();

      expect(lifecycle.discardSucceeded, throwsStateError);
      expect(lifecycle.discardFailed, throwsStateError);
      expect(lifecycle.state, SessionLifecycleState.closing);
    });
  });
}

void _expectLifecycleConflict(
  Object? Function() action, {
  required NetworkAccess networkAccess,
}) {
  expect(
    action,
    throwsA(
      isA<CassetteException>()
          .having(
            (error) => error.diagnostic.category,
            'category',
            DiagnosticCategory.conflictingSessionOperation,
          )
          .having(
            (error) => error.diagnostic.networkAccess,
            'networkAccess',
            networkAccess,
          ),
    ),
  );
}

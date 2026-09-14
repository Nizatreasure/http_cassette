import 'dart:async';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/engine/scoped_session.dart';
import 'package:http_cassette/src/session/cassette_session.dart';
import 'package:test/test.dart';

void main() {
  group('runScopedSession', () {
    test('closes after an asynchronous callback and returns its value',
        () async {
      final events = <String>[];
      final completion = Completer<String>();
      final session = _session(
        closeAction: () async {
          events.add('close');
        },
      );
      final running = runScopedSession<String>(
        session: session,
        action: () {
          events.add('action');
          return completion.future;
        },
      );

      await Future<void>.delayed(Duration.zero);
      expect(events, <String>['action']);
      completion.complete('value');

      expect(await running, 'value');
      expect(events, <String>['action', 'close']);
      expect(session.isClosed, isTrue);
    });

    test('propagates a successful-callback close failure unchanged', () async {
      final closeError = StateError('close failed');
      final closeStackTrace = StackTrace.current;
      var discardCalls = 0;
      final session = _session(
        closeAction: () => Future<void>.error(closeError, closeStackTrace),
        discardAction: () async {
          discardCalls++;
        },
      );

      try {
        await runScopedSession<int>(session: session, action: () => 7);
        fail('The close failure should have been thrown.');
      } on Object catch (error, stackTrace) {
        expect(error, same(closeError));
        expect(stackTrace, same(closeStackTrace));
      }

      expect(discardCalls, 0);
      expect(session.isClosed, isTrue);
    });

    test('discards then rethrows the exact callback failure', () async {
      final callbackError = ArgumentError('callback failed');
      final callbackStackTrace = StackTrace.current;
      var closeCalls = 0;
      var discardCalls = 0;
      final session = _session(
        closeAction: () async {
          closeCalls++;
        },
        discardAction: () async {
          discardCalls++;
        },
      );

      try {
        await runScopedSession<void>(
          session: session,
          action: () => Future<void>.error(
            callbackError,
            callbackStackTrace,
          ),
        );
        fail('The callback failure should have been rethrown.');
      } on Object catch (error, stackTrace) {
        expect(error, same(callbackError));
        expect(stackTrace, same(callbackStackTrace));
      }

      expect(closeCalls, 0);
      expect(discardCalls, 1);
      expect(session.isClosed, isTrue);
    });

    test('wraps callback and cleanup failures without retaining cleanup error',
        () async {
      final callbackError = StateError('private callback');
      final callbackStackTrace = StackTrace.current;
      final cleanupError = StateError('private cleanup');
      final session = _session(
        discardAction: () async => throw cleanupError,
      );

      final exception = await _captureScopedException(
        runScopedSession<void>(
          session: session,
          action: () => Future<void>.error(
            callbackError,
            callbackStackTrace,
          ),
        ),
      );

      expect(exception.primaryError, same(callbackError));
      expect(exception.primaryStackTrace, same(callbackStackTrace));
      expect(
        exception.cleanupDiagnostic.category,
        DiagnosticCategory.sessionCleanupFailure,
      );
      expect(exception.toString(), isNot(contains('private callback')));
      expect(exception.toString(), isNot(contains('private cleanup')));
      expect(session.isClosed, isTrue);
    });

    test('preserves a safe cassette cleanup diagnostic', () async {
      final cleanupDiagnostic = CassetteDiagnostic(
        category: DiagnosticCategory.conflictingSessionOperation,
        summary: 'Safe cleanup failure.',
        networkAccess: NetworkAccess.notAttempted,
      );
      final session = _session(
        discardAction: () async => throw CassetteException(cleanupDiagnostic),
      );

      final exception = await _captureScopedException(
        runScopedSession<void>(
          session: session,
          action: () async => throw StateError('callback failed'),
        ),
      );

      expect(exception.cleanupDiagnostic, same(cleanupDiagnostic));
      expect(session.isClosed, isTrue);
    });
  });
}

Future<ScopedCassetteException> _captureScopedException(
  Future<void> operation,
) async {
  try {
    await operation;
  } on ScopedCassetteException catch (exception) {
    return exception;
  }
  throw StateError('Expected a ScopedCassetteException.');
}

CassetteSession _session({
  Future<void> Function()? closeAction,
  Future<void> Function()? discardAction,
}) =>
    createCassetteSession(
      name: CassetteName('scoped'),
      mode: CassetteMode.record,
      closeAction: closeAction ?? () async {},
      discardAction: discardAction ?? () async {},
    );

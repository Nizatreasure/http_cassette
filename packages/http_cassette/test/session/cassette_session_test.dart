import 'dart:async';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/session/cassette_session.dart';
import 'package:test/test.dart';

void main() {
  group('CassetteSession', () {
    test('exposes its validated name, mode and initial state', () {
      final session = _session(
        name: 'checkout/declined',
        mode: CassetteMode.record,
      );

      expect(session.name, 'checkout/declined');
      expect(session.mode, CassetteMode.record);
      expect(session.isClosed, isFalse);
    });

    test('runs close work once and makes later completion idempotent',
        () async {
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

      await session.close();
      await session.close();
      await session.discard();

      expect(session.isClosed, isTrue);
      expect(closeCalls, 1);
      expect(discardCalls, 0);
    });

    test('runs discard work once and makes later completion idempotent',
        () async {
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

      await session.discard();
      await session.discard();
      await session.close();

      expect(session.isClosed, isTrue);
      expect(closeCalls, 0);
      expect(discardCalls, 1);
    });

    test('notifies internal ownership only after successful completion',
        () async {
      var successfulCompletions = 0;
      final session = _session(
        completionFinished: () {
          successfulCompletions++;
        },
      );

      await session.close();
      await session.discard();

      expect(successfulCompletions, 1);
    });

    test('rejects a concurrent completion operation', () async {
      final completion = Completer<void>();
      final session = _session(closeAction: () => completion.future);

      final firstClose = session.close();

      await expectLater(
        session.discard(),
        throwsA(
          isA<CassetteException>().having(
            (error) => error.diagnostic.category,
            'category',
            DiagnosticCategory.conflictingSessionOperation,
          ),
        ),
      );
      expect(session.isClosed, isFalse);

      completion.complete();
      await firstClose;
      expect(session.isClosed, isTrue);
    });

    test('preserves a close failure and rejects later completion', () async {
      final failure = StateError('safe test failure');
      final session = _session(closeAction: () async => throw failure);

      await expectLater(session.close(), throwsA(same(failure)));
      expect(session.isClosed, isFalse);
      await expectLater(
        session.discard(),
        throwsA(
          isA<CassetteException>().having(
            (error) => error.diagnostic.category,
            'category',
            DiagnosticCategory.conflictingSessionOperation,
          ),
        ),
      );
    });

    test('ends and notifies ownership after a known close failure', () async {
      final exception = CassetteException(
        CassetteDiagnostic(
          category: DiagnosticCategory.bodyLimitExceeded,
          summary: 'The admitted request could not be recorded.',
          networkAccess: NetworkAccess.notAttempted,
        ),
      );
      final stackTrace = StackTrace.current;
      var finishedCompletions = 0;
      final session = _session(
        closeAction: () async {
          throw KnownSessionCloseFailure(exception, stackTrace);
        },
        completionFinished: () {
          finishedCompletions++;
        },
      );

      await expectLater(session.close(), throwsA(same(exception)));

      expect(session.isClosed, isTrue);
      expect(finishedCompletions, 1);
      await session.close();
      await session.discard();
      expect(finishedCompletions, 1);
    });

    test('preserves a discard failure and rejects later completion', () async {
      final failure = StateError('safe test failure');
      final session = _session(discardAction: () async => throw failure);

      await expectLater(session.discard(), throwsA(same(failure)));
      expect(session.isClosed, isFalse);
      await expectLater(
        session.close(),
        throwsA(isA<CassetteException>()),
      );
    });
  });
}

CassetteSession _session({
  String name = 'example',
  CassetteMode mode = CassetteMode.replay,
  Future<void> Function()? closeAction,
  Future<void> Function()? discardAction,
  void Function()? completionFinished,
}) =>
    createCassetteSession(
      name: CassetteName(name),
      mode: mode,
      closeAction: closeAction ?? () async {},
      discardAction: discardAction ?? () async {},
      completionFinished: completionFinished,
    );

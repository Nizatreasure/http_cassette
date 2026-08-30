import 'dart:async';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/recording/attempt.dart';
import 'package:test/test.dart';

void main() {
  group('RecordingAttemptRunner', () {
    test('invokes one response attempt and returns its exact outcome',
        () async {
      final runner = RecordingAttemptRunner();
      final outcome = CassetteResponseOutcome(
        CassetteResponse(statusCode: 201),
      );
      var invocationCount = 0;

      final result = await runner.run(() async {
        invocationCount++;
        return outcome;
      });

      expect(result, same(outcome));
      expect(invocationCount, 1);
    });

    test('returns a transport-failure outcome unchanged', () async {
      final runner = RecordingAttemptRunner();
      final outcome = CassetteTransportFailure(
        category: TransportFailureCategory.timeout,
        message: 'The request timed out.',
      );

      final result = await runner.run(() async => outcome);

      expect(result, same(outcome));
    });

    test('rejects a second run without invoking its callback', () async {
      final runner = RecordingAttemptRunner();
      var invocationCount = 0;
      Future<CassetteOutcome> attempt() async {
        invocationCount++;
        return CassetteResponseOutcome(CassetteResponse(statusCode: 200));
      }

      await runner.run(attempt);

      await expectLater(
        runner.run(attempt),
        throwsA(
          isA<CassetteException>()
              .having(
                (exception) => exception.diagnostic.category,
                'category',
                DiagnosticCategory.realTransportAttemptRepeated,
              )
              .having(
                (exception) => exception.diagnostic.networkAccess,
                'network access',
                NetworkAccess.attempted,
              ),
        ),
      );
      expect(invocationCount, 1);
    });

    test('reserves the single invocation before awaiting completion', () async {
      final runner = RecordingAttemptRunner();
      final completion = Completer<CassetteOutcome>();
      var secondInvoked = false;

      final first = runner.run(() => completion.future);
      await expectLater(
        runner.run(() async {
          secondInvoked = true;
          return CassetteResponseOutcome(CassetteResponse(statusCode: 200));
        }),
        throwsA(isA<CassetteException>()),
      );
      completion.complete(
        CassetteResponseOutcome(CassetteResponse(statusCode: 204)),
      );

      await first;
      expect(secondInvoked, isFalse);
    });

    test('maps a synchronous attempt error safely and remains spent', () async {
      final runner = RecordingAttemptRunner();
      final error = StateError('secret adapter failure');
      var laterInvoked = false;

      await expectLater(
        runner.run(() {
          throw error;
        }),
        throwsA(
          isA<CassetteException>()
              .having(
                (exception) => exception.diagnostic.category,
                'category',
                DiagnosticCategory.adapterContractViolation,
              )
              .having(
                (exception) => exception.diagnostic.networkAccess,
                'network access',
                NetworkAccess.attempted,
              )
              .having(
                (exception) => exception.toString(),
                'safe text',
                isNot(contains('secret adapter failure')),
              ),
        ),
      );
      await expectLater(
        runner.run(() async {
          laterInvoked = true;
          return CassetteResponseOutcome(CassetteResponse(statusCode: 200));
        }),
        throwsA(isA<CassetteException>()),
      );

      expect(laterInvoked, isFalse);
    });

    test('maps an asynchronous attempt error without retaining its value',
        () async {
      final runner = RecordingAttemptRunner();

      await expectLater(
        runner.run(() async {
          await Future<void>.delayed(Duration.zero);
          throw ArgumentError('secret asynchronous failure');
        }),
        throwsA(
          isA<CassetteException>()
              .having(
                (exception) => exception.diagnostic.category,
                'category',
                DiagnosticCategory.adapterContractViolation,
              )
              .having(
                (exception) => exception.toString(),
                'safe text',
                isNot(contains('secret asynchronous failure')),
              ),
        ),
      );
    });

    test('preserves a safe attempted body-limit failure', () async {
      final runner = RecordingAttemptRunner();
      final failure = CassetteException(
        CassetteDiagnostic(
          category: DiagnosticCategory.bodyLimitExceeded,
          summary: 'The response body exceeded its configured limit.',
          networkAccess: NetworkAccess.attempted,
        ),
      );

      await expectLater(
        runner.run(() async => throw failure),
        throwsA(same(failure)),
      );
    });

    test('maps a body-limit failure with inconsistent network state', () async {
      final runner = RecordingAttemptRunner();

      await expectLater(
        runner.run(
          () async => throw CassetteException(
            CassetteDiagnostic(
              category: DiagnosticCategory.bodyLimitExceeded,
              summary: 'The response body exceeded its configured limit.',
              networkAccess: NetworkAccess.notAttempted,
            ),
          ),
        ),
        throwsA(
          isA<CassetteException>().having(
            (exception) => exception.diagnostic.category,
            'category',
            DiagnosticCategory.adapterContractViolation,
          ),
        ),
      );
    });

    test('maps other safe cassette failures from an attempt', () async {
      final runner = RecordingAttemptRunner();

      await expectLater(
        runner.run(
          () async => throw CassetteException(
            CassetteDiagnostic(
              category: DiagnosticCategory.unmappedAdapterFailure,
              summary: 'The adapter could not classify the failure.',
              networkAccess: NetworkAccess.attempted,
            ),
          ),
        ),
        throwsA(
          isA<CassetteException>().having(
            (exception) => exception.diagnostic.category,
            'category',
            DiagnosticCategory.adapterContractViolation,
          ),
        ),
      );
    });

    test('maps a body-limit exception subclass without retaining its error',
        () async {
      final runner = RecordingAttemptRunner();
      final failure = ScopedCassetteException(
        primaryError: StateError('secret primary failure'),
        primaryStackTrace: StackTrace.current,
        cleanupDiagnostic: CassetteDiagnostic(
          category: DiagnosticCategory.bodyLimitExceeded,
          summary: 'The response body exceeded its configured limit.',
          networkAccess: NetworkAccess.attempted,
        ),
      );

      await expectLater(
        runner.run(() async => throw failure),
        throwsA(
          isA<CassetteException>()
              .having(
                (exception) => exception.diagnostic.category,
                'category',
                DiagnosticCategory.adapterContractViolation,
              )
              .having(
                (exception) => exception.toString(),
                'safe text',
                isNot(contains('secret primary failure')),
              ),
        ),
      );
    });

    test('returns an outcome which completes before cancellation', () async {
      final runner = RecordingAttemptRunner();
      final cancellation = _ManualCancellation();
      final completion = Completer<CassetteOutcome>();
      final outcome = CassetteResponseOutcome(
        CassetteResponse(statusCode: 200),
      );

      final result = runner.run(
        () => completion.future,
        cancellation: cancellation,
      );
      completion.complete(outcome);
      expect(await result, same(outcome));

      cancellation.cancel();
      await cancellation.whenCancelled;
    });

    test('rejects and observes an attempt which loses to cancellation',
        () async {
      final runner = RecordingAttemptRunner();
      final cancellation = _ManualCancellation();
      final completion = Completer<CassetteOutcome>();

      final result = runner.run(
        () => completion.future,
        cancellation: cancellation,
      );
      cancellation.cancel();

      await expectLater(
        result,
        throwsA(
          isA<CassetteException>()
              .having(
                (exception) => exception.diagnostic.category,
                'category',
                DiagnosticCategory.cancelled,
              )
              .having(
                (exception) => exception.diagnostic.networkAccess,
                'network access',
                NetworkAccess.attempted,
              ),
        ),
      );
      completion.completeError(StateError('late adapter failure'));
      await Future<void>.delayed(Duration.zero);
    });

    test('does not invoke an attempt for an already-cancelled signal',
        () async {
      final runner = RecordingAttemptRunner();
      final cancellation = _ManualCancellation()..cancel();
      var invoked = false;

      await expectLater(
        runner.run(
          () async {
            invoked = true;
            return CassetteResponseOutcome(CassetteResponse(statusCode: 200));
          },
          cancellation: cancellation,
        ),
        throwsA(
          isA<CassetteException>().having(
            (exception) => exception.diagnostic.networkAccess,
            'network access',
            NetworkAccess.notAttempted,
          ),
        ),
      );
      expect(invoked, isFalse);
    });
  });
}

final class _ManualCancellation implements CassetteCancellation {
  final _completion = Completer<void>();

  var _isCancelled = false;

  @override
  bool get isCancelled => _isCancelled;

  @override
  Future<void> get whenCancelled => _completion.future;

  void cancel() {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    _completion.complete();
  }
}

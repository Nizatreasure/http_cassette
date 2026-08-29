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

    test('propagates an attempt exception unchanged and remains spent',
        () async {
      final runner = RecordingAttemptRunner();
      final error = StateError('test adapter failure');
      var laterInvoked = false;

      await expectLater(
        runner.run(() {
          throw error;
        }),
        throwsA(same(error)),
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

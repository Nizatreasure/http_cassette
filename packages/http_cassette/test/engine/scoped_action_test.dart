import 'dart:async';

import 'package:http_cassette/src/engine/scoped_action.dart';
import 'package:test/test.dart';

void main() {
  group('runScopedAction', () {
    test('retains a synchronous generic value', () async {
      var calls = 0;

      final result = await runScopedAction<List<int>>(() {
        calls++;
        return <int>[1, 2];
      });

      expect(calls, 1);
      expect(result, isA<ScopedActionSucceeded<List<int>>>());
      expect(
        (result as ScopedActionSucceeded<List<int>>).value,
        <int>[1, 2],
      );
    });

    test('awaits and retains an asynchronous generic value', () async {
      final completion = Completer<String>();
      final resultFuture = runScopedAction<String>(() => completion.future);

      completion.complete('complete');
      final result = await resultFuture;

      expect(result, isA<ScopedActionSucceeded<String>>());
      expect((result as ScopedActionSucceeded<String>).value, 'complete');
    });

    test('captures the exact synchronous error and stack trace', () async {
      final error = StateError('callback failed');
      late StackTrace callbackStackTrace;

      final result = await runScopedAction<void>(() {
        try {
          throw error;
        } on Object catch (_, stackTrace) {
          callbackStackTrace = stackTrace;
          Error.throwWithStackTrace(error, stackTrace);
        }
      });

      expect(result, isA<ScopedActionFailed<void>>());
      final failed = result as ScopedActionFailed<void>;
      expect(failed.error, same(error));
      expect(failed.stackTrace, same(callbackStackTrace));
    });

    test('captures the exact asynchronous error and stack trace', () async {
      final error = ArgumentError('callback failed');
      final stackTrace = StackTrace.current;

      final result = await runScopedAction<int>(
        () => Future<int>.error(error, stackTrace),
      );

      expect(result, isA<ScopedActionFailed<int>>());
      final failed = result as ScopedActionFailed<int>;
      expect(failed.error, same(error));
      expect(failed.stackTrace, same(stackTrace));
    });
  });
}

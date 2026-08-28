import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/engine/scoped_action.dart';
import 'package:http_cassette/src/engine/scoped_cleanup.dart';
import 'package:http_cassette/src/session/cassette_session.dart';
import 'package:test/test.dart';

void main() {
  group('cleanupFailedScopedAction', () {
    for (final mode in CassetteMode.values) {
      test('discards one failed ${mode.name} session', () async {
        final callbackError = StateError('callback failed');
        final callbackStackTrace = StackTrace.current;
        final failure = _failure<int>(callbackError, callbackStackTrace);
        var discardCalls = 0;
        final session = _session(
          mode: mode,
          discardAction: () async {
            discardCalls++;
          },
        );

        final result = await cleanupFailedScopedAction<int>(
          session: session,
          failure: failure,
        );

        expect(discardCalls, 1);
        expect(session.isClosed, isTrue);
        expect(result.failure, same(failure));
        expect(result.failure.error, same(callbackError));
        expect(result.failure.stackTrace, same(callbackStackTrace));
        expect(result.cleanupFailure, isNull);
      });
    }

    test('retains cleanup failure separately from the primary failure',
        () async {
      final callbackError = StateError('callback failed');
      final callbackStackTrace = StackTrace.current;
      final cleanupError = ArgumentError('cleanup failed');
      final cleanupStackTrace = StackTrace.current;
      final failure = _failure<void>(callbackError, callbackStackTrace);
      final session = _session(
        mode: CassetteMode.record,
        discardAction: () => Future<void>.error(
          cleanupError,
          cleanupStackTrace,
        ),
      );

      final result = await cleanupFailedScopedAction<void>(
        session: session,
        failure: failure,
      );

      expect(result.failure, same(failure));
      expect(result.cleanupFailure, isNotNull);
      expect(result.cleanupFailure!.error, same(cleanupError));
      expect(result.cleanupFailure!.stackTrace, same(cleanupStackTrace));
      expect(session.isClosed, isFalse);
    });
  });
}

ScopedActionFailed<T> _failure<T>(Object error, StackTrace stackTrace) =>
    ScopedActionResult<T>.failed(error, stackTrace) as ScopedActionFailed<T>;

CassetteSession _session({
  required CassetteMode mode,
  required Future<void> Function() discardAction,
}) =>
    createCassetteSession(
      name: CassetteName('scoped'),
      mode: mode,
      closeAction: () async {},
      discardAction: discardAction,
    );

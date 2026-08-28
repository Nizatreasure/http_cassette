import 'dart:async';

import '../session/cassette_session.dart';
import 'scoped_action.dart';
import 'scoped_cleanup.dart';
import 'scoped_failure.dart';

/// Runs one callback within an already active [session].
///
/// Successful callbacks close the session before their value is returned.
/// Failed callbacks discard the session and retain the callback failure as the
/// primary failure even when cleanup also fails.
Future<T> runScopedSession<T>({
  required CassetteSession session,
  required FutureOr<T> Function() action,
}) async {
  final result = await runScopedAction(action);
  switch (result) {
    case ScopedActionSucceeded<T>(:final value):
      await session.close();
      return value;
    case ScopedActionFailed<T>():
      final cleanup = await cleanupFailedScopedAction(
        session: session,
        failure: result,
      );
      if (cleanup.cleanupFailure != null) {
        throw composeScopedCassetteException(cleanup);
      }
      Error.throwWithStackTrace(result.error, result.stackTrace);
  }
}

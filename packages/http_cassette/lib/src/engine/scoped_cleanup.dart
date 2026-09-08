import '../session/cassette_session.dart';
import 'scoped_action.dart';

/// The result of cleaning up after one failed scoped action.
final class ScopedFailureCleanupResult<T> {
  /// Creates a cleanup result retaining the primary action [failure].
  const ScopedFailureCleanupResult({
    required this.failure,
    this.cleanupFailure,
  });

  /// The original callback failure, which always remains primary.
  final ScopedActionFailed<T> failure;

  /// A separate cleanup failure, or null when cleanup succeeded.
  final ScopedCleanupFailure? cleanupFailure;
}

/// One failure raised while cleaning up a failed scoped action.
final class ScopedCleanupFailure {
  /// Creates a cleanup failure retaining [error] and [stackTrace].
  const ScopedCleanupFailure(this.error, this.stackTrace);

  /// The exact object thrown by session cleanup.
  final Object error;

  /// The stack trace captured with [error].
  final StackTrace stackTrace;
}

/// Discards [session] after a failed scoped action.
///
/// The original [failure] always remains primary. A cleanup failure is captured
/// separately and is never thrown in place of it.
Future<ScopedFailureCleanupResult<T>> cleanupFailedScopedAction<T>({
  required CassetteSession session,
  required ScopedActionFailed<T> failure,
}) async {
  try {
    await session.discard();
    return ScopedFailureCleanupResult<T>(failure: failure);
  } on Object catch (error, stackTrace) {
    return ScopedFailureCleanupResult<T>(
      failure: failure,
      cleanupFailure: ScopedCleanupFailure(error, stackTrace),
    );
  }
}

import 'dart:async';

/// The captured result of invoking one scoped cassette action.
sealed class ScopedActionResult<T> {
  const ScopedActionResult._();

  /// Creates a successful result containing [value].
  const factory ScopedActionResult.succeeded(T value) =
      ScopedActionSucceeded<T>._;

  /// Creates a failed result retaining [error] and [stackTrace].
  const factory ScopedActionResult.failed(
    Object error,
    StackTrace stackTrace,
  ) = ScopedActionFailed<T>._;
}

/// A successful scoped action result.
final class ScopedActionSucceeded<T> extends ScopedActionResult<T> {
  const ScopedActionSucceeded._(this.value) : super._();

  /// The exact value returned by the action.
  final T value;
}

/// A failed scoped action result retained while session cleanup runs.
final class ScopedActionFailed<T> extends ScopedActionResult<T> {
  const ScopedActionFailed._(this.error, this.stackTrace) : super._();

  /// The exact object thrown by the action.
  final Object error;

  /// The stack trace captured with [error].
  final StackTrace stackTrace;
}

/// Invokes [action] once and captures its synchronous or asynchronous result.
///
/// This function performs no session cleanup and does not rethrow. Its caller
/// remains responsible for preserving failure ordering.
Future<ScopedActionResult<T>> runScopedAction<T>(
  FutureOr<T> Function() action,
) async {
  try {
    final value = await action();
    return ScopedActionResult<T>.succeeded(value);
  } on Object catch (error, stackTrace) {
    return ScopedActionResult<T>.failed(error, stackTrace);
  }
}

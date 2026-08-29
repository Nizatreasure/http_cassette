/// A transport-neutral signal for caller cancellation.
///
/// Adapters implement this interface by wrapping their transport's own
/// cancellation mechanism. The signal is control flow only and must never be
/// stored in a cassette.
abstract interface class CassetteCancellation {
  /// Whether cancellation has occurred.
  ///
  /// Once true, this value must remain true.
  bool get isCancelled;

  /// Completes normally when cancellation occurs.
  ///
  /// This future must remain pending while [isCancelled] is false. The state
  /// must be true by the time the future completes.
  Future<void> get whenCancelled;
}

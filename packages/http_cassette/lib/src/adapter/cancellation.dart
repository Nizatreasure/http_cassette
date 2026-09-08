/// A transport-neutral signal for caller cancellation.
///
/// An adapter wraps its client's cancellation mechanism with this contract so
/// request buffering, recording and replay selection observe the same signal.
/// Cancellation controls one request and is never stored as an interaction.
abstract interface class CassetteCancellation {
  /// Whether the caller has cancelled the request.
  ///
  /// Once true, this value must remain true.
  bool get isCancelled;

  /// Completes normally when the caller cancels the request.
  ///
  /// This future must remain pending while [isCancelled] is false. The state
  /// must be true by the time the future completes.
  Future<void> get whenCancelled;
}

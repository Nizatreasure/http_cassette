import '../adapter/cancellation.dart';
import '../adapter/real_http_attempt.dart';
import '../model/http_message.dart';
import '../model/outcome.dart';
import 'attempt.dart';

/// The transient successful result of one recording request attempt.
///
/// This value is not sanitised and must not enter persistable session state.
final class RecordingRequestResult {
  /// Creates a result from one assigned request and canonical [outcome].
  const RecordingRequestResult({
    required this.arrivalIndex,
    required this.request,
    required this.outcome,
  });

  /// The index assigned when the request entered the recording core.
  final int arrivalIndex;

  /// The canonical request supplied by the adapter.
  final CassetteRequest request;

  /// The canonical live transport outcome.
  final CassetteOutcome outcome;
}

/// One indexed recording request awaiting its real HTTP attempt.
final class RecordingRequestAttempt {
  /// Creates an operation for the already assigned [arrivalIndex] and [request].
  RecordingRequestAttempt({
    required this.arrivalIndex,
    required this.request,
  }) : _runner = RecordingAttemptRunner();

  /// The index assigned synchronously before transport work begins.
  final int arrivalIndex;

  /// The immutable canonical request being recorded.
  final CassetteRequest request;

  final RecordingAttemptRunner _runner;

  /// Runs [attempt] once and returns its transient unsanitised result.
  Future<RecordingRequestResult> run(
    RealHttpAttempt attempt, {
    CassetteCancellation? cancellation,
  }) async {
    final outcome = await _runner.run(attempt, cancellation: cancellation);
    return RecordingRequestResult(
      arrivalIndex: arrivalIndex,
      request: request,
      outcome: outcome,
    );
  }
}

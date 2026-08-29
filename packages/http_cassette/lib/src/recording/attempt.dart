import '../adapter/cancellation.dart';
import '../adapter/real_http_attempt.dart';
import '../diagnostics/diagnostic.dart';
import '../diagnostics/exception.dart';
import '../model/outcome.dart';

/// Guards the real transport attempt for one internal recording request.
///
/// The public permit route remains later integration work.
final class RecordingAttemptRunner {
  var _started = false;

  /// Invokes [attempt] once and returns its canonical outcome unchanged.
  ///
  /// A later call throws a safe [CassetteException] without invoking its
  /// supplied callback.
  Future<CassetteOutcome> run(
    RealHttpAttempt attempt, {
    CassetteCancellation? cancellation,
  }) {
    if (_started) {
      return Future<CassetteOutcome>.error(
        CassetteException(
          CassetteDiagnostic(
            category: DiagnosticCategory.realTransportAttemptRepeated,
            summary: 'The real transport attempt was requested more than once.',
            networkAccess: NetworkAccess.attempted,
          ),
        ),
      );
    }
    _started = true;
    if (cancellation?.isCancelled ?? false) {
      return Future<CassetteOutcome>.error(
        _cancellationException(NetworkAccess.notAttempted),
      );
    }
    final attemptFuture = Future<CassetteOutcome>.sync(attempt).onError(
      (Object error, StackTrace stackTrace) =>
          throw _adapterContractException(),
    );
    if (cancellation == null) {
      return attemptFuture;
    }
    return Future.any<_RecordingAttemptCompletion>(
      <Future<_RecordingAttemptCompletion>>[
        attemptFuture.then<_RecordingAttemptCompletion>(
          _RecordingAttemptOutcome.new,
        ),
        cancellation.whenCancelled.then<_RecordingAttemptCompletion>(
          (_) => const _RecordingAttemptCancelled(),
        ),
      ],
    ).then(
      (completion) => switch (completion) {
        _RecordingAttemptOutcome(:final outcome) => outcome,
        _RecordingAttemptCancelled() =>
          throw _cancellationException(NetworkAccess.attempted),
      },
    );
  }
}

sealed class _RecordingAttemptCompletion {
  const _RecordingAttemptCompletion();
}

final class _RecordingAttemptOutcome extends _RecordingAttemptCompletion {
  const _RecordingAttemptOutcome(this.outcome);

  final CassetteOutcome outcome;
}

final class _RecordingAttemptCancelled extends _RecordingAttemptCompletion {
  const _RecordingAttemptCancelled();
}

CassetteException _cancellationException(NetworkAccess networkAccess) =>
    CassetteException(
      CassetteDiagnostic(
        category: DiagnosticCategory.cancelled,
        summary: 'The HTTP request was cancelled during recording.',
        networkAccess: networkAccess,
      ),
    );

CassetteException _adapterContractException() => CassetteException(
      CassetteDiagnostic(
        category: DiagnosticCategory.adapterContractViolation,
        summary: 'The real HTTP attempt did not return a canonical outcome.',
        networkAccess: NetworkAccess.attempted,
      ),
    );

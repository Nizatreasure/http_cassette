import '../diagnostics/diagnostic.dart';
import '../diagnostics/exception.dart';
import '../model/outcome.dart';

/// Guards the real transport attempt for one internal recording request.
///
/// The public adapter callback contract, cancellation and adapter exception
/// mapping remain later integration work.
final class RecordingAttemptRunner {
  var _started = false;

  /// Invokes [attempt] once and returns its canonical outcome unchanged.
  ///
  /// A later call throws a safe [CassetteException] without invoking its
  /// supplied callback.
  Future<CassetteOutcome> run(
    Future<CassetteOutcome> Function() attempt,
  ) {
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
    return Future<CassetteOutcome>.sync(attempt);
  }
}

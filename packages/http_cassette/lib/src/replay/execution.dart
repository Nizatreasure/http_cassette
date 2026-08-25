import '../diagnostics/exception.dart';
import '../model/http_message.dart';
import '../model/outcome.dart';
import 'active_state.dart';
import 'selection.dart';

/// Resolves one canonical request entirely from an active replay session.
///
/// This internal boundary has no real-transport callback. A selected
/// interaction returns its recorded outcome; no-match and exhaustion results
/// throw safe cassette exceptions with their specialised diagnostic text.
CassetteOutcome executeReplayRequest({
  required ActiveReplayState state,
  required CassetteRequest request,
}) {
  final selection = state.selectRequest(request);
  return switch (selection.result) {
    ReplayInteractionSelected(:final interaction) => interaction.outcome,
    ReplayNoMatch() => throw replayNoMatchException(
        selection.noMatchDiagnostic!,
      ),
    ReplayGroupExhausted() => throw replayExhaustionException(
        selection.exhaustionDiagnostic!,
      ),
  };
}

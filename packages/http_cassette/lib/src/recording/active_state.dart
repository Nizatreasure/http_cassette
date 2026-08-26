import '../cassette/interaction.dart';
import '../cassette/name.dart';
import '../configuration/cassette_configuration.dart';
import '../model/http_message.dart';
import '../sanitisation/configuration.dart';
import 'configuration.dart';
import 'interaction_projection.dart';
import 'request_attempt.dart';

/// Session-local configuration and state for one active recording session.
final class ActiveRecordingState {
  /// Creates active state from validated session inputs.
  ActiveRecordingState({
    required this.cassetteName,
    required CassetteConfiguration configuration,
    required this.options,
  }) : sanitisation = configuration.sanitisation;

  /// The validated logical identity of the cassette being recorded.
  final CassetteName cassetteName;

  /// The sanitisation configuration fixed when the session starts.
  final SanitisationConfiguration sanitisation;

  /// The target-handling options fixed when the session starts.
  final RecordingOptions options;

  var _nextArrivalIndex = 0;
  final Map<int, CassetteInteraction> _interactions =
      <int, CassetteInteraction>{};

  /// Assigns the next request-arrival index synchronously.
  int assignArrivalIndex() => _nextArrivalIndex++;

  /// Admits [request] and assigns its arrival index synchronously.
  ///
  /// The returned operation owns the later asynchronous real attempt. It does
  /// not add the request or its outcome to session state.
  RecordingRequestAttempt beginRequest(CassetteRequest request) =>
      RecordingRequestAttempt(
        arrivalIndex: assignArrivalIndex(),
        request: request,
      );

  /// Sanitises [result] into an interaction without retaining it.
  CassetteInteraction sanitiseResult(RecordingRequestResult result) =>
      sanitiseRecordingResult(result, sanitisation);

  /// Sanitises and retains one successful admitted request [result].
  ///
  /// Retention occurs synchronously after complete sanitisation. A result index
  /// must have been assigned by this session and may be retained only once.
  CassetteInteraction retainResult(RecordingRequestResult result) {
    final index = result.arrivalIndex;
    if (index < 0 || index >= _nextArrivalIndex) {
      throw StateError(
        'A recording result must use an index admitted by this session.',
      );
    }
    if (_interactions.containsKey(index)) {
      throw StateError(
        'A recording result index may be retained only once.',
      );
    }
    final interaction = sanitiseResult(result);
    _interactions[index] = interaction;
    return interaction;
  }

  /// Immutable retained interactions in request-arrival order.
  List<CassetteInteraction> get interactions {
    final sorted = _interactions.values.toList()
      ..sort((first, second) => first.index.compareTo(second.index));
    return List<CassetteInteraction>.unmodifiable(sorted);
  }
}

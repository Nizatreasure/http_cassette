import '../cassette/name.dart';
import '../configuration/cassette_configuration.dart';
import '../sanitisation/configuration.dart';
import 'configuration.dart';

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

  /// Assigns the next request-arrival index synchronously.
  int assignArrivalIndex() => _nextArrivalIndex++;
}

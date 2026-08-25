import '../cassette/cassette.dart';
import '../cassette/name.dart';
import '../configuration/cassette_configuration.dart';
import '../matching/request_matcher.dart';
import 'configuration.dart';
import 'policy_resolution.dart';

/// Session-local configuration and state for one active replay session.
final class ActiveReplayState {
  /// Creates active state from validated session inputs.
  ActiveReplayState({
    required this.cassetteName,
    required this.cassette,
    required CassetteConfiguration configuration,
    required ReplayOptions options,
  })  : matcher = DefaultRequestMatcher(configuration: configuration.matching),
        replayPolicy = resolveReplayPolicy(
          defaultPolicy: configuration.defaultReplayPolicy,
          options: options,
        ),
        requireAllInteractions = options.requireAllInteractions;

  /// The validated logical identity of the loaded cassette.
  final CassetteName cassetteName;

  /// The immutable decoded cassette used throughout the session.
  final Cassette cassette;

  /// The matcher configured once from the engine's immutable settings.
  final DefaultRequestMatcher matcher;

  /// The replay policy resolved once when the session starts.
  final ReplayPolicy replayPolicy;

  /// Whether successful close must later verify complete cassette usage.
  final bool requireAllInteractions;

  var _nextArrivalIndex = 0;

  /// Assigns the next unique request-arrival index synchronously.
  ///
  /// Indices start at zero and increase monotonically within this session.
  int assignArrivalIndex() => _nextArrivalIndex++;
}

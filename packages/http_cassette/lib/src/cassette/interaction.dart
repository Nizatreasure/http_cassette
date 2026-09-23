import '../matching/exclusions.dart';
import '../model/http_message.dart';
import '../model/outcome.dart';
import 'body_codec.dart';

/// One immutable, sanitised interaction ready for cassette persistence.
final class CassetteInteraction {
  /// Creates a validated interaction in request-arrival order.
  ///
  /// [index] must be non-negative. Contiguous ordering across interactions is
  /// validated by the containing cassette value.
  CassetteInteraction({
    required int index,
    required this.request,
    required this.outcome,
    this.matchingExclusions = MatchingExclusions.none,
    this.persistedResponseBody,
  }) : index = _validateIndex(index);

  /// The request-arrival index within the containing cassette.
  final int index;

  /// The sanitised canonical request.
  final CassetteRequest request;

  /// The sanitisation-derived request matching exclusions.
  final MatchingExclusions matchingExclusions;

  /// The sanitised canonical response or portable transport failure.
  final CassetteOutcome outcome;

  /// The response body representation retained from cassette decoding.
  ///
  /// A new recording normally leaves this absent so persistence selects the
  /// canonical representation. Decoding retains storage-only representations
  /// so append can reproduce them deterministically.
  final PersistedBody? persistedResponseBody;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CassetteInteraction &&
          index == other.index &&
          request == other.request &&
          matchingExclusions == other.matchingExclusions &&
          outcome == other.outcome &&
          persistedResponseBody == other.persistedResponseBody;

  @override
  int get hashCode => Object.hash(
        index,
        request,
        matchingExclusions,
        outcome,
        persistedResponseBody,
      );
}

int _validateIndex(int index) {
  if (index < 0) {
    throw ArgumentError('Cassette interaction index must be non-negative.');
  }
  return index;
}

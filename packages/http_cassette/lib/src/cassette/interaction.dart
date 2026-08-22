import '../matching/exclusions.dart';
import '../model/http_message.dart';
import '../model/outcome.dart';

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
  }) : index = _validateIndex(index);

  /// The request-arrival index within the containing cassette.
  final int index;

  /// The sanitised canonical request.
  final CassetteRequest request;

  /// The sanitisation-derived request matching exclusions.
  final MatchingExclusions matchingExclusions;

  /// The sanitised canonical response or portable transport failure.
  final CassetteOutcome outcome;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CassetteInteraction &&
          index == other.index &&
          request == other.request &&
          matchingExclusions == other.matchingExclusions &&
          outcome == other.outcome;

  @override
  int get hashCode => Object.hash(
        index,
        request,
        matchingExclusions,
        outcome,
      );
}

int _validateIndex(int index) {
  if (index < 0) {
    throw ArgumentError('Cassette interaction index must be non-negative.');
  }
  return index;
}

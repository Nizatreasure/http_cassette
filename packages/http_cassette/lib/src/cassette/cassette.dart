import 'interaction.dart';

/// The schema version produced by the current cassette encoder.
///
/// Readable versions are a separate decoder policy and are not implied by this
/// value.
const int currentWritableCassetteSchemaVersion = 1;

/// An immutable cassette ready for deterministic encoding.
final class Cassette {
  /// Creates a cassette from interactions in request-arrival order.
  ///
  /// Interaction indices must start at zero, be contiguous and appear in
  /// ascending order. The iterable is copied defensively.
  factory Cassette({
    Iterable<CassetteInteraction> interactions = const <CassetteInteraction>[],
  }) {
    final copied = List<CassetteInteraction>.unmodifiable(interactions);
    for (var position = 0; position < copied.length; position++) {
      if (copied[position].index != position) {
        throw ArgumentError(
          'Cassette interaction indices must start at zero and be contiguous '
          'in ascending order.',
        );
      }
    }
    return Cassette._(copied);
  }

  const Cassette._(this.interactions);

  /// The schema version used when this cassette is encoded.
  int get schemaVersion => currentWritableCassetteSchemaVersion;

  /// Interactions in request-arrival order.
  final List<CassetteInteraction> interactions;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Cassette && _listsEqual(interactions, other.interactions);

  @override
  int get hashCode => Object.hash(
        schemaVersion,
        Object.hashAll(interactions),
      );
}

bool _listsEqual<T>(List<T> first, List<T> second) {
  if (first.length != second.length) {
    return false;
  }
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}

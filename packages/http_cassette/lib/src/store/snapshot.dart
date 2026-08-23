import 'dart:typed_data';

import '../cassette/name.dart';

/// An opaque store-owned revision used for conditional replacement.
///
/// Revisions have identity equality and expose no value. A store creates a new
/// revision whenever its encoded cassette bytes change.
final class CassetteRevision {
  /// Creates a new unique opaque revision.
  CassetteRevision();

  @override
  bool operator ==(Object other) => identical(this, other);

  @override
  int get hashCode => 0;

  @override
  String toString() => 'CassetteRevision(<opaque>)';
}

/// One immutable encoded cassette read from a store.
final class CassetteSnapshot {
  /// Creates a snapshot for [name] with store-owned [revision].
  ///
  /// [bytes] are copied defensively and every value must be from 0 through 255.
  factory CassetteSnapshot({
    required CassetteName name,
    required List<int> bytes,
    required CassetteRevision revision,
  }) {
    for (final byte in bytes) {
      if (byte < 0 || byte > 255) {
        throw ArgumentError(
          'Cassette snapshot values must be bytes from 0 through 255.',
        );
      }
    }
    return CassetteSnapshot._(
      name: name,
      bytes: Uint8List.fromList(bytes).asUnmodifiableView(),
      revision: revision,
    );
  }

  const CassetteSnapshot._({
    required this.name,
    required this.bytes,
    required this.revision,
  });

  /// The logical name read by the store.
  final CassetteName name;

  /// Immutable encoded cassette bytes.
  final Uint8List bytes;

  /// The opaque revision to use only for conditional replacement.
  final CassetteRevision revision;
}

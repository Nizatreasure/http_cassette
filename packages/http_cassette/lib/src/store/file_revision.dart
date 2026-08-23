import 'dart:typed_data';

import 'snapshot.dart';

/// A private content snapshot behind one opaque file-store revision.
final class FileCassetteRevision {
  /// Takes ownership of [bytes] and creates its public opaque identity.
  FileCassetteRevision.takeOwnership(Uint8List bytes)
      : _bytes = bytes.asUnmodifiableView();

  final Uint8List _bytes;

  /// The identity exposed through a public cassette snapshot.
  final CassetteRevision opaque = CassetteRevision();

  /// Whether [bytes] exactly match the content captured by this revision.
  bool matches(List<int> bytes) {
    if (bytes.length != _bytes.length) {
      return false;
    }
    for (var index = 0; index < bytes.length; index++) {
      if (bytes[index] != _bytes[index]) {
        return false;
      }
    }
    return true;
  }
}

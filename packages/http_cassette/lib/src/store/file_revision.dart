import 'dart:typed_data';

import '../cassette/name.dart';
import 'snapshot.dart';

/// The captured file content represented by one opaque store revision.
final class FileCassetteRevision {
  /// Takes ownership of [bytes] and creates its opaque revision identity.
  FileCassetteRevision.takeOwnership(this.name, Uint8List bytes)
      : _bytes = bytes.asUnmodifiableView();

  /// The logical cassette whose content was observed.
  final CassetteName name;

  final Uint8List _bytes;

  /// The identity carried by the corresponding cassette snapshot.
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

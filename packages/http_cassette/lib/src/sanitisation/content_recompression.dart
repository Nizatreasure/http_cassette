import 'dart:typed_data';

import 'content_recompression_stub.dart'
    if (dart.library.io) 'content_recompression_io.dart' as platform;

export 'content_recompression_types.dart';

/// Recompresses one gzip representation without producing more than [maximumBytes].
Uint8List recompressGzipContent(
  List<int> bytes, {
  required int maximumBytes,
}) {
  if (maximumBytes <= 0) {
    throw ArgumentError.value(
      maximumBytes,
      'maximumBytes',
      'Maximum recompressed byte count must be positive.',
    );
  }
  for (final byte in bytes) {
    if (byte < 0 || byte > 255) {
      throw ArgumentError(
        'Content values must be bytes from 0 to 255.',
      );
    }
  }
  return platform.recompressGzipContent(
    Uint8List.fromList(bytes),
    maximumBytes: maximumBytes,
  );
}

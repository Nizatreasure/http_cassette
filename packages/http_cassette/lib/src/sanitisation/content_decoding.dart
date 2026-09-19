import 'dart:typed_data';

import 'content_decoding_stub.dart'
    if (dart.library.io) 'content_decoding_io.dart' as platform;

export 'content_decoding_types.dart';

/// Decodes one gzip representation without producing more than [maximumBytes].
Uint8List decodeGzipContent(
  List<int> bytes, {
  required int maximumBytes,
}) {
  if (maximumBytes <= 0) {
    throw ArgumentError.value(
      maximumBytes,
      'maximumBytes',
      'Maximum decoded byte count must be positive.',
    );
  }
  for (final byte in bytes) {
    if (byte < 0 || byte > 255) {
      throw ArgumentError(
          'Encoded content values must be bytes from 0 to 255.');
    }
  }
  return platform.decodeGzipContent(
    Uint8List.fromList(bytes),
    maximumBytes: maximumBytes,
  );
}

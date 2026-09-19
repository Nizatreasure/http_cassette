import 'dart:io';
import 'dart:typed_data';

import 'bounded_byte_sink.dart';
import 'content_recompression_types.dart';

/// Recompresses gzip content incrementally on platforms supporting `dart:io`.
Uint8List recompressGzipContent(
  Uint8List bytes, {
  required int maximumBytes,
}) {
  final output = BoundedByteSink(maximumBytes);
  try {
    final encoder = gzip.encoder.startChunkedConversion(output);
    encoder
      ..add(bytes)
      ..close();
    return output.takeBytes();
  } on ByteLimitExceeded {
    throw ContentRecompressionException(
      kind: ContentRecompressionFailureKind.recompressedBodyTooLarge,
      maximumBytes: maximumBytes,
    );
  }
}

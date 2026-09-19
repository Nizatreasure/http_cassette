import 'dart:typed_data';

import 'content_recompression_types.dart';

/// Reports unavailable gzip recompression without importing `dart:io`.
Uint8List recompressGzipContent(
  Uint8List bytes, {
  required int maximumBytes,
}) {
  throw const ContentRecompressionException(
    kind: ContentRecompressionFailureKind.unsupportedPlatform,
  );
}

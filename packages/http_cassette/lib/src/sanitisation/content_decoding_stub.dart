import 'dart:typed_data';

import 'content_decoding_types.dart';

/// Reports that gzip decoding is unavailable on this platform.
Uint8List decodeGzipContent(
  Uint8List bytes, {
  required int maximumBytes,
}) =>
    throw const ContentDecodingException(
      kind: ContentDecodingFailureKind.unsupportedPlatform,
    );

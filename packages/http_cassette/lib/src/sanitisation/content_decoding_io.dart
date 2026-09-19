import 'dart:io';
import 'dart:typed_data';

import 'bounded_byte_sink.dart';
import 'content_decoding_types.dart';

/// Decodes gzip content incrementally on platforms supporting `dart:io`.
Uint8List decodeGzipContent(
  Uint8List bytes, {
  required int maximumBytes,
}) {
  final output = BoundedByteSink(maximumBytes);
  try {
    final decoder = gzip.decoder.startChunkedConversion(output);
    decoder
      ..add(bytes)
      ..close();
    return output.takeBytes();
  } on ByteLimitExceeded {
    throw ContentDecodingException(
      kind: ContentDecodingFailureKind.decodedBodyTooLarge,
      maximumBytes: maximumBytes,
    );
  } on FormatException {
    throw const ContentDecodingException(
      kind: ContentDecodingFailureKind.invalidContent,
    );
  }
}

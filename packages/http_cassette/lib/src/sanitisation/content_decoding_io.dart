import 'dart:io';
import 'dart:typed_data';

import 'content_decoding_types.dart';

/// Decodes gzip content incrementally on platforms supporting `dart:io`.
Uint8List decodeGzipContent(
  Uint8List bytes, {
  required int maximumBytes,
}) {
  final output = _BoundedByteSink(maximumBytes);
  try {
    final decoder = gzip.decoder.startChunkedConversion(output);
    decoder
      ..add(bytes)
      ..close();
    return output.takeBytes();
  } on _DecodedBodyLimitExceeded {
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

final class _BoundedByteSink implements Sink<List<int>> {
  _BoundedByteSink(this.maximumBytes);

  final int maximumBytes;
  final BytesBuilder _bytes = BytesBuilder(copy: false);
  var _isClosed = false;

  @override
  void add(List<int> chunk) {
    if (_isClosed) {
      throw StateError('Decoded content sink is closed.');
    }
    if (chunk.length > maximumBytes - _bytes.length) {
      throw const _DecodedBodyLimitExceeded();
    }
    _bytes.add(chunk);
  }

  @override
  void close() {
    _isClosed = true;
  }

  Uint8List takeBytes() {
    if (!_isClosed) {
      throw StateError('Decoded content is not complete.');
    }
    return _bytes.takeBytes().asUnmodifiableView();
  }
}

final class _DecodedBodyLimitExceeded implements Exception {
  const _DecodedBodyLimitExceeded();
}

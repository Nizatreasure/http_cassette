import 'dart:typed_data';

import 'dio_byte_stream_buffer.dart';

/// The completed bytes and equivalent replacement stream for one Dio body.
typedef BufferedDioRequestBody = ({
  Uint8List bytes,
  Stream<Uint8List>? replacementStream,
});

/// Buffers [stream] once without retaining more than [maximumBytes].
///
/// A null stream produces an empty body and null replacement. A non-null stream
/// always produces a non-null replacement with the same complete byte sequence.
Future<BufferedDioRequestBody> bufferDioRequestBody(
  Stream<Uint8List>? stream, {
  required int maximumBytes,
  Future<void>? cancellation,
}) async {
  if (stream == null) {
    return (
      bytes: Uint8List(0),
      replacementStream: null,
    );
  }

  final bytes = await bufferDioByteStream(
    stream,
    maximumBytes: maximumBytes,
    cancellation: cancellation,
  );
  return (
    bytes: bytes,
    replacementStream: createDioByteStream(bytes),
  );
}

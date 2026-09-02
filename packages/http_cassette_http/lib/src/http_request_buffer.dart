import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'http_byte_stream_buffer.dart';
import 'http_cancellation.dart';

/// A completely buffered HTTP request and its one equivalent live request.
typedef BufferedHttpRequest = ({
  Uint8List bytes,
  http.BaseRequest replacementRequest,
  HttpCassetteCancellation? cancellation,
});

/// Finalises and buffers [request] once within [maximumBytes].
///
/// A trustworthy declared length over the limit fails before finalisation. The
/// replacement retains the standard metadata exposed by `BaseRequest` after
/// finalisation and emits an independent copy of the exact captured bytes.
Future<BufferedHttpRequest> bufferHttpRequest(
  http.BaseRequest request, {
  required int maximumBytes,
}) async {
  if (maximumBytes <= 0) {
    throw ArgumentError.value(
      maximumBytes,
      'maximumBytes',
      'Maximum byte count must be positive.',
    );
  }

  final declaredLength = request.contentLength;
  if (declaredLength != null && declaredLength > maximumBytes) {
    throw const HttpByteStreamLimitExceeded();
  }

  final cancellation = createHttpCassetteCancellation(request);
  final bytes = await bufferHttpByteStream(
    request.finalize(),
    maximumBytes: maximumBytes,
    cancellation: cancellation?.whenCancelled,
  );
  final replacement = cancellation == null
      ? _BufferedRequest(request, bytes)
      : _AbortableBufferedRequest(request, bytes, cancellation.abortTrigger);

  return (
    bytes: bytes,
    replacementRequest: replacement,
    cancellation: cancellation,
  );
}

base class _BufferedRequestBase extends http.BaseRequest {
  _BufferedRequestBase(http.BaseRequest source, Uint8List bytes)
      : _bytes = Uint8List.fromList(bytes),
        super(source.method, source.url) {
    headers.addAll(source.headers);
    contentLength = source.contentLength;
    persistentConnection = source.persistentConnection;
    followRedirects = source.followRedirects;
    maxRedirects = source.maxRedirects;
  }

  final Uint8List _bytes;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream.fromBytes(_bytes);
  }
}

final class _BufferedRequest extends _BufferedRequestBase {
  _BufferedRequest(super.source, super.bytes);
}

final class _AbortableBufferedRequest extends _BufferedRequestBase
    with http.Abortable {
  _AbortableBufferedRequest(
    super.source,
    super.bytes,
    this.abortTrigger,
  );

  @override
  final Future<void> abortTrigger;
}

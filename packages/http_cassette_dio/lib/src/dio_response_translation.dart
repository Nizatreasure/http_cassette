import 'package:dio/dio.dart';
import 'package:http_cassette/http_cassette.dart';

import 'dio_byte_stream_buffer.dart';

/// The canonical and equivalent Dio forms of one completely captured response.
typedef CapturedDioResponse = ({
  CassetteResponse canonicalResponse,
  ResponseBody replacementResponse,
});

/// Captures [response] within [maximumBytes] and translates both result forms.
Future<CapturedDioResponse> captureDioResponse(
  ResponseBody response, {
  required int maximumBytes,
  Future<void>? cancellation,
}) async {
  final bytes = await bufferDioByteStream(
    response.stream,
    maximumBytes: maximumBytes,
    cancellation: cancellation,
  );
  final canonicalResponse = CassetteResponse(
    statusCode: response.statusCode,
    headers: CassetteHeaders(response.headers),
    body: bytes,
    reasonPhrase: switch (response.statusMessage) {
      final String message when message.isNotEmpty => message,
      _ => null,
    },
  );
  final replacementResponse = ResponseBody.fromBytes(
    bytes,
    response.statusCode,
    statusMessage: response.statusMessage,
    isRedirect: response.isRedirect,
    headers: response.headers,
  )
    ..redirects = response.redirects
    ..extra = response.extra;

  return (
    canonicalResponse: canonicalResponse,
    replacementResponse: replacementResponse,
  );
}

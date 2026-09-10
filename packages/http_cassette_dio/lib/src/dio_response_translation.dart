import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http_cassette/http_cassette.dart';

import 'dio_byte_stream_buffer.dart';

/// The canonical and equivalent `dio` forms of one captured response.
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

/// Reconstructs a raw `dio` response from a canonical replay [response].
ResponseBody reconstructDioResponse(CassetteResponse response) {
  final headers = <String, List<String>>{
    for (final entry in response.headers.toMap().entries)
      entry.key: List<String>.of(entry.value),
  };
  return ResponseBody.fromBytes(
    Uint8List.fromList(response.body),
    response.statusCode,
    statusMessage: response.reasonPhrase,
    headers: headers,
  );
}

import 'package:http/http.dart' as http;
import 'package:http_cassette/http_cassette.dart';

import 'http_byte_stream_buffer.dart';

/// The canonical and caller-equivalent forms of one captured HTTP response.
typedef CapturedHttpResponse = ({
  CassetteResponse canonicalResponse,
  http.StreamedResponse replacementResponse,
});

/// Captures one live [response] within [maximumBytes].
///
/// The returned response contains an independent stream of the complete bytes
/// and refers to the caller's original [request], rather than an internal
/// replacement request used by the wrapped client.
Future<CapturedHttpResponse> captureHttpResponse(
  http.StreamedResponse response, {
  required http.BaseRequest request,
  required int maximumBytes,
  Future<void>? cancellation,
}) async {
  if (maximumBytes <= 0) {
    throw ArgumentError.value(
      maximumBytes,
      'maximumBytes',
      'Maximum byte count must be positive.',
    );
  }
  final declaredLength = response.contentLength;
  if (declaredLength != null && declaredLength > maximumBytes) {
    throw const HttpByteStreamLimitExceeded();
  }

  final bytes = await bufferHttpByteStream(
    response.stream,
    maximumBytes: maximumBytes,
    cancellation: cancellation,
  );
  final canonicalResponse = CassetteResponse(
    statusCode: response.statusCode,
    headers: CassetteHeaders(response.headersSplitValues),
    body: bytes,
    reasonPhrase: switch (response.reasonPhrase) {
      final String phrase when phrase.isNotEmpty => phrase,
      _ => null,
    },
  );
  final replacementResponse = switch (response) {
    http.BaseResponseWithUrl(:final url) => _HttpStreamedResponseWithUrl(
        http.ByteStream.fromBytes(bytes),
        response.statusCode,
        url: url,
        contentLength: response.contentLength,
        request: request,
        headers: Map<String, String>.of(response.headers),
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      ),
    _ => http.StreamedResponse(
        http.ByteStream.fromBytes(bytes),
        response.statusCode,
        contentLength: response.contentLength,
        request: request,
        headers: Map<String, String>.of(response.headers),
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      ),
  };

  return (
    canonicalResponse: canonicalResponse,
    replacementResponse: replacementResponse,
  );
}

/// Reconstructs a canonical replay [response] for a `package:http` caller.
///
/// Repeated canonical header values are joined because `package:http` exposes
/// one string per response header. Redirect state, connection persistence and
/// a final response URL are not cassette data and are not invented.
http.StreamedResponse reconstructHttpResponse(
  CassetteResponse response, {
  required http.BaseRequest request,
}) {
  final headers = <String, String>{
    for (final entry in response.headers.toMap().entries)
      entry.key: entry.value.join(', '),
  };
  return http.StreamedResponse(
    http.ByteStream.fromBytes(response.body.toList(growable: false)),
    response.statusCode,
    contentLength: _persistedContentLength(response.headers),
    request: request,
    headers: headers,
    reasonPhrase: response.reasonPhrase,
  );
}

int? _persistedContentLength(CassetteHeaders headers) {
  final values = headers.values('content-length');
  if (values == null || values.length != 1) {
    return null;
  }
  final value = int.tryParse(values.single);
  return value != null && value >= 0 ? value : null;
}

final class _HttpStreamedResponseWithUrl extends http.StreamedResponse
    implements http.BaseResponseWithUrl {
  _HttpStreamedResponseWithUrl(
    super.stream,
    super.statusCode, {
    required this.url,
    super.contentLength,
    super.request,
    super.headers,
    super.isRedirect,
    super.persistentConnection,
    super.reasonPhrase,
  });

  @override
  final Uri url;
}

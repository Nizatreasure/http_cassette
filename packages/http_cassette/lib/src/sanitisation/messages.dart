import '../matching/exclusions.dart';
import '../matching/json.dart';
import '../model/content_encoding.dart';
import '../model/headers.dart';
import '../model/http_message.dart';
import 'body.dart';
import 'configuration.dart';
import 'content_decoding.dart';
import 'content_recompression.dart';
import 'request_fields.dart';

/// Immutable output from built-in canonical request sanitisation.
final class BuiltInRequestSanitisationResult {
  BuiltInRequestSanitisationResult._({
    required this.request,
    required this.exclusions,
  });

  /// Canonical request with every built-in sensitive value replaced.
  final CassetteRequest request;

  /// Request locations changed by built-in sanitisation.
  final MatchingExclusions exclusions;
}

/// Applies built-in field and JSON body sanitisation to [request].
BuiltInRequestSanitisationResult sanitiseBuiltInRequest(
  CassetteRequest request,
  SanitisationConfiguration configuration,
) {
  final bodyResult = sanitiseJsonBody(
    request.headers,
    request.body,
    configuration,
  );
  final fieldResult = sanitiseRequestFields(request, configuration);
  final bodyChanged = bodyResult.sanitisedPointers.isNotEmpty;
  final exclusions = fieldResult.exclusions.mergedWith(
    MatchingExclusions(jsonPointers: bodyResult.sanitisedPointers),
  );

  return BuiltInRequestSanitisationResult._(
    request: bodyChanged
        ? CassetteRequest(
            method: fieldResult.request.method,
            uri: fieldResult.request.uri,
            headers: fieldResult.request.headers,
            body: bodyResult.body,
          )
        : fieldResult.request,
    exclusions: exclusions,
  );
}

/// Applies built-in header and JSON body sanitisation to [response].
CassetteResponse sanitiseBuiltInResponse(
  CassetteResponse response,
  SanitisationConfiguration configuration, {
  required int maximumTransformedBodyBytes,
}) {
  final prepared = _prepareEncodedJsonResponse(
    response,
    configuration,
    maximumTransformedBodyBytes: maximumTransformedBodyBytes,
  );
  final bodyResult = sanitiseJsonBody(
    prepared.response.headers,
    prepared.response.body,
    configuration,
  );
  final bodyChanged = bodyResult.sanitisedPointers.isNotEmpty;
  var body = bodyChanged ? bodyResult.body : prepared.response.body;
  var headers = prepared.response.headers;
  if (prepared.recompress) {
    body = recompressGzipContent(
      body,
      maximumBytes: maximumTransformedBodyBytes,
    );
    headers = _withGzipContentEncoding(headers);
  }
  final headerResult = sanitiseHeaders(headers, configuration);
  final headersChanged = headerResult.headers != headers;
  if (identical(prepared.response, response) &&
      !bodyChanged &&
      !headersChanged) {
    return response;
  }

  return CassetteResponse(
    statusCode: prepared.response.statusCode,
    headers: headerResult.headers,
    body: body,
    reasonPhrase: prepared.response.reasonPhrase,
  );
}

_EncodedJsonPreparation _prepareEncodedJsonResponse(
  CassetteResponse response,
  SanitisationConfiguration configuration, {
  required int maximumTransformedBodyBytes,
}) {
  if (configuration.encodedJsonResponses ==
          EncodedJsonResponseHandling.opaque ||
      response.body.isEmpty ||
      !hasGzipContentEncoding(response.headers) ||
      !hasJsonMediaType(response.headers)) {
    return _EncodedJsonPreparation(response: response, recompress: false);
  }

  final decoded = _hasGzipSignature(response.body)
      ? decodeGzipContent(
          response.body,
          maximumBytes: maximumTransformedBodyBytes,
        )
      : response.body;
  final headers = <String, Iterable<String>>{
    for (final name in response.headers.names)
      if (name != 'content-encoding') name: response.headers.values(name)!,
  };
  return _EncodedJsonPreparation(
    response: CassetteResponse(
      statusCode: response.statusCode,
      headers: CassetteHeaders(headers),
      body: decoded,
      reasonPhrase: response.reasonPhrase,
    ),
    recompress: configuration.encodedJsonResponses ==
        EncodedJsonResponseHandling.decodeAndRecompress,
  );
}

bool _hasGzipSignature(List<int> bytes) =>
    bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;

CassetteHeaders _withGzipContentEncoding(CassetteHeaders headers) =>
    CassetteHeaders(<String, Iterable<String>>{
      for (final name in headers.names) name: headers.values(name)!,
      'content-encoding': const <String>['gzip'],
    });

final class _EncodedJsonPreparation {
  const _EncodedJsonPreparation({
    required this.response,
    required this.recompress,
  });

  final CassetteResponse response;
  final bool recompress;
}

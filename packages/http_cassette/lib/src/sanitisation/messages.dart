import '../matching/exclusions.dart';
import '../matching/json.dart';
import '../model/content_encoding.dart';
import '../model/headers.dart';
import '../model/http_message.dart';
import 'body.dart';
import 'configuration.dart';
import 'content_decoding.dart';
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
  required int maximumDecodedBodyBytes,
}) {
  final prepared = _prepareEncodedJsonResponse(
    response,
    configuration,
    maximumDecodedBodyBytes: maximumDecodedBodyBytes,
  );
  final bodyResult = sanitiseJsonBody(
    prepared.headers,
    prepared.body,
    configuration,
  );
  final headerResult = sanitiseHeaders(prepared.headers, configuration);
  final bodyChanged = bodyResult.sanitisedPointers.isNotEmpty;
  final headersChanged = headerResult.headers != prepared.headers;
  if (identical(prepared, response) && !bodyChanged && !headersChanged) {
    return response;
  }

  return CassetteResponse(
    statusCode: prepared.statusCode,
    headers: headerResult.headers,
    body: bodyChanged ? bodyResult.body : prepared.body,
    reasonPhrase: prepared.reasonPhrase,
  );
}

CassetteResponse _prepareEncodedJsonResponse(
  CassetteResponse response,
  SanitisationConfiguration configuration, {
  required int maximumDecodedBodyBytes,
}) {
  if (configuration.encodedJsonResponses !=
          EncodedJsonResponseHandling.decodeAndStorePlain ||
      response.body.isEmpty ||
      !hasGzipContentEncoding(response.headers) ||
      !hasJsonMediaType(response.headers)) {
    return response;
  }

  final decoded = decodeGzipContent(
    response.body,
    maximumBytes: maximumDecodedBodyBytes,
  );
  final headers = <String, Iterable<String>>{
    for (final name in response.headers.names)
      if (name != 'content-encoding') name: response.headers.values(name)!,
  };
  return CassetteResponse(
    statusCode: response.statusCode,
    headers: CassetteHeaders(headers),
    body: decoded,
    reasonPhrase: response.reasonPhrase,
  );
}

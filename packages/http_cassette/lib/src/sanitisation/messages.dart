import '../cassette/body_codec.dart';
import '../matching/exclusions.dart';
import '../matching/json.dart';
import '../model/content_encoding.dart';
import '../model/headers.dart';
import '../model/http_message.dart';
import 'body.dart';
import 'configuration.dart';
import 'content_decoding.dart';
import 'content_processing_support.dart';
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

/// Immutable built-in response sanitisation and storage selection.
final class BuiltInResponseSanitisationResult {
  const BuiltInResponseSanitisationResult._({
    required this.response,
    required this.persistedBody,
  });

  /// The canonical response reconstructed during replay.
  final CassetteResponse response;

  /// An explicitly selected storage representation, when required.
  final PersistedBody? persistedBody;
}

/// Applies built-in response sanitisation and selects special gzip storage.
BuiltInResponseSanitisationResult sanitiseBuiltInResponseForRecording(
  CassetteResponse response,
  SanitisationConfiguration configuration, {
  required int maximumTransformedBodyBytes,
}) {
  final eligibleGzipJson = response.body.isNotEmpty &&
      hasGzipContentEncoding(response.headers) &&
      hasJsonMediaType(response.headers);
  final capturedBodyWasGzip =
      eligibleGzipJson && _hasGzipSignature(response.body);
  if (eligibleGzipJson &&
      configuration.gzipJsonResponses !=
          GzipJsonResponseHandling.storeWithoutSanitisation &&
      !supportsGzipContentProcessing) {
    if (configuration.gzipJsonResponses ==
        GzipJsonResponseHandling.sanitiseAndStoreCompressed) {
      throw const ContentRecompressionException(
        kind: ContentRecompressionFailureKind.unsupportedPlatform,
      );
    }
    throw const ContentDecodingException(
      kind: ContentDecodingFailureKind.unsupportedPlatform,
    );
  }
  if (eligibleGzipJson &&
      configuration.gzipJsonResponses ==
          GzipJsonResponseHandling.storeWithoutSanitisation) {
    final persistedBody = !_hasGzipSignature(response.body) &&
            _isStrictJsonAfterRemovingGzip(response)
        ? PersistedGzipBase64Body.fromPlainBytes(
            response.body,
            maximumCompressedBytes: maximumTransformedBodyBytes,
          )
        : null;
    return BuiltInResponseSanitisationResult._(
      response: _sanitiseResponseHeaders(response, configuration),
      persistedBody: persistedBody,
    );
  }

  final prepared = eligibleGzipJson
      ? _prepareGzipJsonForSanitisation(
          response,
          maximumTransformedBodyBytes: maximumTransformedBodyBytes,
        )
      : response;
  final bodyResult = sanitiseJsonBody(
    prepared.headers,
    prepared.body,
    configuration,
  );
  final bodyChanged = bodyResult.sanitisedPointers.isNotEmpty;
  var body = bodyChanged ? bodyResult.body : prepared.body;
  PersistedBody? persistedBody;
  if (eligibleGzipJson) {
    final parsed = parseJsonBody(prepared.headers, body);
    if (parsed.status != JsonBodyStatus.valid) {
      throw JsonBodySanitisationException(parsed.status);
    }
    final jsonBody = PersistedJsonBody(parsed.value);
    body = jsonBody.reconstruct();
    if (configuration.gzipJsonResponses ==
        GzipJsonResponseHandling.sanitiseAndStoreCompressed) {
      if (capturedBodyWasGzip) {
        body = recompressGzipContent(
          body,
          maximumBytes: maximumTransformedBodyBytes,
        );
        persistedBody = PersistedBase64Body.fromBytes(body);
      } else {
        persistedBody = PersistedGzipBase64Body.fromPlainBytes(
          body,
          maximumCompressedBytes: maximumTransformedBodyBytes,
        );
      }
    } else {
      persistedBody = jsonBody;
    }
  }
  final headerResult = sanitiseHeaders(response.headers, configuration);
  final headersChanged = headerResult.headers != response.headers;
  if (!eligibleGzipJson &&
      identical(prepared, response) &&
      !bodyChanged &&
      !headersChanged) {
    return BuiltInResponseSanitisationResult._(
      response: response,
      persistedBody: null,
    );
  }

  return BuiltInResponseSanitisationResult._(
    response: CassetteResponse(
      statusCode: response.statusCode,
      headers: headerResult.headers,
      body: body,
      reasonPhrase: response.reasonPhrase,
    ),
    persistedBody: persistedBody,
  );
}

/// Applies built-in header and JSON body sanitisation to [response].
CassetteResponse sanitiseBuiltInResponse(
  CassetteResponse response,
  SanitisationConfiguration configuration, {
  required int maximumTransformedBodyBytes,
}) =>
    sanitiseBuiltInResponseForRecording(
      response,
      configuration,
      maximumTransformedBodyBytes: maximumTransformedBodyBytes,
    ).response;

CassetteResponse _prepareGzipJsonForSanitisation(
  CassetteResponse response, {
  required int maximumTransformedBodyBytes,
}) {
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
  return CassetteResponse(
    statusCode: response.statusCode,
    headers: CassetteHeaders(headers),
    body: decoded,
    reasonPhrase: response.reasonPhrase,
  );
}

bool _hasGzipSignature(List<int> bytes) =>
    bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;

bool _isStrictJsonAfterRemovingGzip(CassetteResponse response) =>
    parseJsonBody(
      _prepareGzipJsonForSanitisation(
        response,
        maximumTransformedBodyBytes: response.body.length,
      ).headers,
      response.body,
    ).status ==
    JsonBodyStatus.valid;

CassetteResponse _sanitiseResponseHeaders(
  CassetteResponse response,
  SanitisationConfiguration configuration,
) {
  final result = sanitiseHeaders(response.headers, configuration);
  if (result.headers == response.headers) {
    return response;
  }
  return CassetteResponse(
    statusCode: response.statusCode,
    headers: result.headers,
    body: response.body,
    reasonPhrase: response.reasonPhrase,
  );
}

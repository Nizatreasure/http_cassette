import '../matching/exclusions.dart';
import '../model/http_message.dart';
import 'body.dart';
import 'configuration.dart';
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
  SanitisationConfiguration configuration,
) {
  final bodyResult = sanitiseJsonBody(
    response.headers,
    response.body,
    configuration,
  );
  final headerResult = sanitiseHeaders(response.headers, configuration);
  final bodyChanged = bodyResult.sanitisedPointers.isNotEmpty;
  final headersChanged = headerResult.headers != response.headers;
  if (!bodyChanged && !headersChanged) {
    return response;
  }

  return CassetteResponse(
    statusCode: response.statusCode,
    headers: headerResult.headers,
    body: bodyChanged ? bodyResult.body : response.body,
    reasonPhrase: response.reasonPhrase,
  );
}

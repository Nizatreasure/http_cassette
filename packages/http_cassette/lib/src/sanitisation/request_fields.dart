import '../matching/exclusions.dart';
import '../matching/uri_component.dart';
import '../model/headers.dart';
import '../model/http_message.dart';
import 'configuration.dart';
import 'placeholders.dart';

/// Immutable output from sanitising canonical HTTP headers.
final class HeaderSanitisationResult {
  HeaderSanitisationResult._({
    required this.headers,
    required Iterable<String> sanitisedNames,
  }) : sanitisedNames = Set<String>.unmodifiable(sanitisedNames);

  /// Canonical headers with sensitive values replaced.
  final CassetteHeaders headers;

  /// Canonical lower-case names whose values were replaced.
  final Set<String> sanitisedNames;
}

/// Replaces complete sensitive header values using [configuration].
HeaderSanitisationResult sanitiseHeaders(
  CassetteHeaders headers,
  SanitisationConfiguration configuration,
) {
  final sensitiveNames = effectiveSensitiveHeaders(configuration);
  final sanitisedNames = <String>{};
  final values = <String, Iterable<String>>{};

  for (final name in headers.names) {
    final fieldValues = headers.values(name)!;
    if (sensitiveNames.contains(name)) {
      sanitisedNames.add(name);
      values[name] = List<String>.filled(
        fieldValues.length,
        redactedStringPlaceholder,
        growable: false,
      );
    } else {
      values[name] = fieldValues;
    }
  }

  return HeaderSanitisationResult._(
    headers: sanitisedNames.isEmpty ? headers : CassetteHeaders(values),
    sanitisedNames: sanitisedNames,
  );
}

/// Immutable output from sanitising a canonical request URI query.
final class QuerySanitisationResult {
  QuerySanitisationResult._({
    required this.uri,
    required Iterable<String> sanitisedNames,
  }) : sanitisedNames = Set<String>.unmodifiable(sanitisedNames);

  /// URI with sensitive query values replaced.
  final Uri uri;

  /// Normalised names, in request casing, whose present values were replaced.
  final Set<String> sanitisedNames;
}

/// Replaces present sensitive query values using [configuration].
QuerySanitisationResult sanitiseQuery(
  Uri uri,
  SanitisationConfiguration configuration,
) {
  if (uri.query.isEmpty) {
    return QuerySanitisationResult._(
      uri: uri,
      sanitisedNames: const <String>{},
    );
  }

  final sensitiveNames = effectiveSensitiveQueryParameters(configuration);
  final sanitisedNames = <String>{};
  final fields = <String>[];

  for (final field in uri.query.split('&')) {
    final equalsIndex = field.indexOf('=');
    if (equalsIndex < 0) {
      fields.add(field);
      continue;
    }

    final encodedName = field.substring(0, equalsIndex);
    final name = normaliseUriComponent(encodedName);
    if (!sensitiveNames.contains(name.toLowerCase())) {
      fields.add(field);
      continue;
    }

    sanitisedNames.add(name);
    fields.add(
        '$encodedName=${Uri.encodeQueryComponent(redactedStringPlaceholder)}');
  }

  return QuerySanitisationResult._(
    uri: sanitisedNames.isEmpty ? uri : uri.replace(query: fields.join('&')),
    sanitisedNames: sanitisedNames,
  );
}

/// Immutable output from sanitising canonical request fields.
final class RequestFieldSanitisationResult {
  RequestFieldSanitisationResult._({
    required this.request,
    required this.exclusions,
  });

  /// Canonical request with sensitive field values replaced.
  final CassetteRequest request;

  /// Request locations changed by sanitisation.
  final MatchingExclusions exclusions;
}

/// Sanitises URI user information, query values and header values.
RequestFieldSanitisationResult sanitiseRequestFields(
  CassetteRequest request,
  SanitisationConfiguration configuration,
) {
  final queryResult = sanitiseQuery(request.uri, configuration);
  final hasSensitiveUserInformation =
      configuration.builtInRulesEnabled && request.uri.userInfo.isNotEmpty;
  final uri = hasSensitiveUserInformation
      ? queryResult.uri.replace(
          userInfo: Uri.encodeComponent(redactedStringPlaceholder),
        )
      : queryResult.uri;
  final headerResult = sanitiseHeaders(request.headers, configuration);
  final exclusions = MatchingExclusions(
    headers: headerResult.sanitisedNames,
    queryParameters: queryResult.sanitisedNames,
    uriUserInformation: hasSensitiveUserInformation,
  );
  final changed = uri != request.uri || headerResult.headers != request.headers;

  return RequestFieldSanitisationResult._(
    request: changed
        ? CassetteRequest(
            method: request.method,
            uri: uri,
            headers: headerResult.headers,
            body: request.body,
          )
        : request,
    exclusions: exclusions,
  );
}

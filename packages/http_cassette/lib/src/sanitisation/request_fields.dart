import '../matching/uri_component.dart';
import '../model/headers.dart';
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

  /// Normalised lower-case names whose present values were replaced.
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
    final name = normaliseUriComponent(encodedName).toLowerCase();
    if (!sensitiveNames.contains(name)) {
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

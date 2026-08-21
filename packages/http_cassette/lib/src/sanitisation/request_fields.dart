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

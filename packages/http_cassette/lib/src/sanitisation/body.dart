import 'dart:typed_data';

import '../matching/json.dart';
import '../model/headers.dart';
import 'configuration.dart';
import 'json.dart';
import 'json_encoding.dart';

/// Immutable output from built-in JSON body sanitisation.
final class JsonBodySanitisationResult {
  JsonBodySanitisationResult._({
    required this.body,
    required Iterable<String> sanitisedPointers,
  }) : sanitisedPointers = Set<String>.unmodifiable(sanitisedPointers);

  /// Immutable canonical body bytes after sanitisation.
  final Uint8List body;

  /// Exact RFC 6901 locations whose scalar values were sanitised.
  final Set<String> sanitisedPointers;
}

/// Safe failure raised when a claimed JSON body cannot be inspected.
final class JsonBodySanitisationException implements Exception {
  /// Creates a failure for the value-free parser [status].
  const JsonBodySanitisationException(this.status);

  /// Why strict JSON inspection was unavailable.
  final JsonBodyStatus status;

  @override
  String toString() =>
      'JSON body sanitisation failed because strict parsing was unavailable: '
      '${status.name}.';
}

/// Sanitises a canonical body when [headers] identify it as JSON.
JsonBodySanitisationResult sanitiseJsonBody(
  CassetteHeaders headers,
  List<int> body,
  SanitisationConfiguration configuration,
) {
  final parsed = parseJsonBody(headers, body);
  if (parsed.status == JsonBodyStatus.notJsonMediaType) {
    return _unchangedBody(body);
  }
  if (parsed.status != JsonBodyStatus.valid) {
    if (_requiresJsonInspection(configuration)) {
      throw JsonBodySanitisationException(parsed.status);
    }
    return _unchangedBody(body);
  }

  final sanitised = sanitiseJsonValue(parsed.value, configuration);
  if (sanitised.sanitisedPointers.isEmpty) {
    return _unchangedBody(body);
  }
  return JsonBodySanitisationResult._(
    body: encodeSanitisedJsonValue(sanitised.value),
    sanitisedPointers: sanitised.sanitisedPointers,
  );
}

JsonBodySanitisationResult _unchangedBody(List<int> body) =>
    JsonBodySanitisationResult._(
      body: Uint8List.fromList(body).asUnmodifiableView(),
      sanitisedPointers: const <String>{},
    );

bool _requiresJsonInspection(SanitisationConfiguration configuration) =>
    configuration.builtInRulesEnabled ||
    configuration.additionalJsonNames.isNotEmpty ||
    configuration.additionalJsonPointers.isNotEmpty;

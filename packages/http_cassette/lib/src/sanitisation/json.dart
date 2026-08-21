import '../matching/json.dart';
import 'configuration.dart';
import 'placeholders.dart';

/// Immutable output from sanitising a parsed JSON value.
final class JsonSanitisationResult {
  JsonSanitisationResult._({
    required this.value,
    required Iterable<String> sanitisedPointers,
  }) : sanitisedPointers = Set<String>.unmodifiable(sanitisedPointers);

  /// Deeply immutable JSON value with sensitive scalar values replaced.
  final Object? value;

  /// Exact RFC 6901 locations whose scalar values were sanitised.
  final Set<String> sanitisedPointers;
}

/// Recursively sanitises JSON using exact names and RFC 6901 pointers.
JsonSanitisationResult sanitiseJsonValue(
  Object? value,
  SanitisationConfiguration configuration,
) {
  final result = _sanitiseJsonValue(
    value,
    '',
    effectiveSensitiveJsonNames(configuration),
    sensitivePointers: effectiveSensitiveJsonPointers(configuration),
    sanitiseDescendants: false,
  );
  final sortedPointers = result.pointers.toList()..sort();
  return JsonSanitisationResult._(
    value: result.pointers.isEmpty ? value : result.value,
    sanitisedPointers: sortedPointers,
  );
}

_SanitisedJsonNode _sanitiseJsonValue(
  Object? value,
  String pointer,
  Set<String> sensitiveNames, {
  required Set<String> sensitivePointers,
  required bool sanitiseDescendants,
}) {
  final sanitiseValue =
      sanitiseDescendants || sensitivePointers.contains(pointer);
  if (value is Map<String, Object?>) {
    final output = <String, Object?>{};
    final pointers = <String>{};
    for (final MapEntry(:key, :value) in value.entries) {
      final memberPointer = '$pointer/${_escapeJsonPointerToken(key)}';
      final child = _sanitiseJsonValue(
        value,
        memberPointer,
        sensitiveNames,
        sensitivePointers: sensitivePointers,
        sanitiseDescendants:
            sanitiseValue || sensitiveNames.contains(key.toLowerCase()),
      );
      output[key] = child.value;
      pointers.addAll(child.pointers);
    }
    return _SanitisedJsonNode(
      value:
          pointers.isEmpty ? value : Map<String, Object?>.unmodifiable(output),
      pointers: pointers,
    );
  }

  if (value is List<Object?>) {
    final output = <Object?>[];
    final pointers = <String>{};
    for (var index = 0; index < value.length; index += 1) {
      final child = _sanitiseJsonValue(
        value[index],
        '$pointer/$index',
        sensitiveNames,
        sensitivePointers: sensitivePointers,
        sanitiseDescendants: sanitiseValue,
      );
      output.add(child.value);
      pointers.addAll(child.pointers);
    }
    return _SanitisedJsonNode(
      value: pointers.isEmpty ? value : List<Object?>.unmodifiable(output),
      pointers: pointers,
    );
  }

  if (!_isJsonScalar(value)) {
    throw ArgumentError.value(value, 'value', 'Not a parsed JSON value.');
  }
  if (!sanitiseValue) {
    return _SanitisedJsonNode(value: value, pointers: const <String>{});
  }
  return _SanitisedJsonNode(
    value: placeholderForJsonScalar(value),
    pointers: <String>{pointer},
  );
}

final class _SanitisedJsonNode {
  const _SanitisedJsonNode({required this.value, required this.pointers});

  final Object? value;
  final Set<String> pointers;
}

bool _isJsonScalar(Object? value) =>
    value == null ||
    value is String ||
    value is bool ||
    value is ParsedJsonNumber;

String _escapeJsonPointerToken(String token) =>
    token.replaceAll('~', '~0').replaceAll('/', '~1');

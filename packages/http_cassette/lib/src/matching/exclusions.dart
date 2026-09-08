import 'header_names.dart';
import 'uri_component.dart';

/// Request locations whose values are ignored during matching.
///
/// Exclusion preserves structure. A named field, query parameter or JSON path
/// must still be present with the same multiplicity; only its value is ignored.
final class MatchingExclusions {
  /// Creates validated matching exclusions.
  ///
  /// Header names use the HTTP token grammar and compare case-insensitively.
  /// Query names are URI-normalised. JSON Pointers compare case-sensitively and
  /// must use exact RFC 6901 syntax.
  factory MatchingExclusions({
    Iterable<String> headers = const <String>[],
    Iterable<String> queryParameters = const <String>[],
    Iterable<String> jsonPointers = const <String>[],
    bool uriUserInformation = false,
    bool body = false,
  }) {
    final canonicalQueryParameters = <String>{};
    for (final name in queryParameters) {
      canonicalQueryParameters.add(normaliseUriComponent(name));
    }

    final validatedPointers = <String>{};
    for (final pointer in jsonPointers) {
      _validateJsonPointer(pointer);
      validatedPointers.add(pointer);
    }

    return MatchingExclusions._(
      headers: canonicaliseHeaderNames(
        headers,
        invalidMessage: 'Excluded header name must use the HTTP token grammar.',
      ),
      queryParameters: _sortedSet(canonicalQueryParameters),
      jsonPointers: _sortedSet(validatedPointers),
      uriUserInformation: uriUserInformation,
      body: body,
    );
  }

  const MatchingExclusions._({
    required this.headers,
    required this.queryParameters,
    required this.jsonPointers,
    required this.uriUserInformation,
    required this.body,
  });

  /// A set which excludes no request values.
  static const none = MatchingExclusions._(
    headers: <String>{},
    queryParameters: <String>{},
    jsonPointers: <String>{},
    uriUserInformation: false,
    body: false,
  );

  /// Canonical lower-case header names excluded from value matching.
  final Set<String> headers;

  /// Normalised query names whose values are excluded from matching.
  final Set<String> queryParameters;

  /// Exact RFC 6901 JSON Pointers excluded from value matching.
  final Set<String> jsonPointers;

  /// Whether URI user information must remain present but its value is ignored.
  final bool uriUserInformation;

  /// Whether the complete request body value is excluded.
  ///
  /// Body presence remains significant, so an empty body does not match a
  /// non-empty body.
  final bool body;

  /// Returns the union of this exclusion set and [other].
  MatchingExclusions mergedWith(MatchingExclusions other) => MatchingExclusions(
        headers: <String>{...headers, ...other.headers},
        queryParameters: <String>{
          ...queryParameters,
          ...other.queryParameters,
        },
        jsonPointers: <String>{...jsonPointers, ...other.jsonPointers},
        uriUserInformation: uriUserInformation || other.uriUserInformation,
        body: body || other.body,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatchingExclusions &&
          _setsEqual(headers, other.headers) &&
          _setsEqual(queryParameters, other.queryParameters) &&
          _setsEqual(jsonPointers, other.jsonPointers) &&
          uriUserInformation == other.uriUserInformation &&
          body == other.body;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(headers),
        Object.hashAll(queryParameters),
        Object.hashAll(jsonPointers),
        uriUserInformation,
        body,
      );
}

Set<String> _sortedSet(Set<String> values) {
  final sorted = values.toList()..sort();
  return Set<String>.unmodifiable(sorted);
}

bool _setsEqual<T>(Set<T> first, Set<T> second) =>
    first.length == second.length && first.containsAll(second);

void _validateJsonPointer(String pointer) {
  if (pointer.isEmpty) {
    return;
  }
  if (!pointer.startsWith('/')) {
    throw ArgumentError('JSON Pointer must be empty or start with a slash.');
  }

  for (var index = 0; index < pointer.length; index += 1) {
    if (pointer.codeUnitAt(index) != 0x7e) {
      continue;
    }
    if (index + 1 >= pointer.length) {
      throw ArgumentError('JSON Pointer contains an invalid escape.');
    }
    final escaped = pointer.codeUnitAt(index + 1);
    if (escaped != 0x30 && escaped != 0x31) {
      throw ArgumentError('JSON Pointer contains an invalid escape.');
    }
    index += 1;
  }
}

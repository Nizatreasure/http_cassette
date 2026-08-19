import 'http_syntax.dart';

/// Immutable, transport-neutral HTTP header fields.
///
/// Header names use lower-case ASCII canonical form. Lookup is
/// case-insensitive, repeated values retain their observed order, and all input
/// collections are copied defensively.
abstract final class CassetteHeaders {
  /// Creates headers from field names and their ordered values.
  ///
  /// Names must use the HTTP token grammar. Values may be empty but must not
  /// contain prohibited control characters. Each field must contain at least
  /// one value.
  ///
  /// Entries whose names differ only by case are combined in input iteration
  /// order.
  factory CassetteHeaders(Map<String, Iterable<String>> values) =
      _CassetteHeaders.from;

  /// Creates an empty header collection.
  const factory CassetteHeaders.empty() = _CassetteHeaders.empty;

  /// Canonical field names in deterministic lexical order.
  Iterable<String> get names;

  /// Returns the ordered values for [name], or `null` when it is absent.
  ///
  /// The returned list is immutable. Lookup is case-insensitive for valid HTTP
  /// field names. An invalid lookup name is treated as absent.
  List<String>? values(String name);

  /// Whether a field named [name] is present.
  ///
  /// Lookup is case-insensitive. An invalid lookup name returns `false`.
  bool contains(String name);

  /// Returns an immutable map with immutable ordered value lists.
  Map<String, List<String>> toMap();
}

final class _CassetteHeaders implements CassetteHeaders {
  factory _CassetteHeaders.from(Map<String, Iterable<String>> values) {
    final accumulated = <String, List<String>>{};

    for (final entry in values.entries) {
      final name = _canonicalName(entry.key);
      final fieldValues = entry.value.toList(growable: false);
      if (fieldValues.isEmpty) {
        throw ArgumentError('Every HTTP header field must have a value.');
      }

      for (final value in fieldValues) {
        _validateValue(value);
      }

      accumulated.putIfAbsent(name, () => <String>[]).addAll(fieldValues);
    }

    final names = accumulated.keys.toList(growable: false)..sort();
    final canonicalValues = <String, List<String>>{
      for (final name in names)
        name: List<String>.unmodifiable(accumulated[name]!),
    };

    return _CassetteHeaders._(
      Map<String, List<String>>.unmodifiable(canonicalValues),
      List<String>.unmodifiable(names),
    );
  }

  const _CassetteHeaders.empty()
      : _values = const <String, List<String>>{},
        _names = const <String>[];

  const _CassetteHeaders._(this._values, this._names);

  final Map<String, List<String>> _values;
  final List<String> _names;

  @override
  Iterable<String> get names => _names;

  @override
  List<String>? values(String name) {
    final canonicalName = _canonicalLookupName(name);
    return canonicalName == null ? null : _values[canonicalName];
  }

  @override
  bool contains(String name) {
    final canonicalName = _canonicalLookupName(name);
    return canonicalName != null && _values.containsKey(canonicalName);
  }

  @override
  Map<String, List<String>> toMap() => Map<String, List<String>>.unmodifiable(
        <String, List<String>>{
          for (final name in _names)
            name: List<String>.unmodifiable(_values[name]!),
        },
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! CassetteHeaders) {
      return false;
    }

    final otherNames = other.names.toList(growable: false);
    if (!_listsEqual(_names, otherNames)) {
      return false;
    }

    for (final name in _names) {
      if (!_listsEqual(_values[name]!, other.values(name)!)) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(<Object>[
        for (final name in _names)
          Object.hash(name, Object.hashAll(_values[name]!)),
      ]);
}

String _canonicalName(String name) {
  if (!isHttpToken(name)) {
    throw ArgumentError('HTTP header name must use the token grammar.');
  }
  return name.toLowerCase();
}

String? _canonicalLookupName(String name) =>
    isHttpToken(name) ? name.toLowerCase() : null;

void _validateValue(String value) {
  validateHttpFieldValue(value, description: 'HTTP header value');
}

bool _listsEqual(List<String> first, List<String> second) {
  if (first.length != second.length) {
    return false;
  }
  for (var index = 0; index < first.length; index += 1) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}

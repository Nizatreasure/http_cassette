import 'dart:convert';
import 'dart:typed_data';

import '../matching/json.dart';
import '../model/content_encoding.dart';
import '../model/headers.dart';
import '../sanitisation/json_encoding.dart';

/// An immutable body representation used by the cassette schema.
sealed class PersistedBody {
  const PersistedBody();

  /// Reconstructs the canonical replay bytes.
  Uint8List reconstruct();
}

/// An immutable persisted body with payload-consistent headers.
final class PreparedPersistedBody {
  PreparedPersistedBody._({
    required this.body,
    required this.headers,
    required Iterable<String> changedHeaderNames,
  }) : changedHeaderNames = Set<String>.unmodifiable(changedHeaderNames);

  /// The selected persisted body representation.
  final PersistedBody body;

  /// Headers corrected for [body]'s reconstructed bytes.
  final CassetteHeaders headers;

  /// Canonical names of headers whose values or presence changed.
  ///
  /// A persisted request must add these names to its matching exclusions.
  final Set<String> changedHeaderNames;
}

/// Selects a persisted body and corrects payload-derived [headers].
PreparedPersistedBody preparePersistedBody(
  CassetteHeaders headers,
  List<int> bytes,
) {
  final body = selectPersistedBody(headers, bytes);
  final reconstructedLength = body.reconstruct().length;
  final changedNames = <String>{};
  final corrected = <String, Iterable<String>>{};

  for (final name in headers.names) {
    final values = headers.values(name)!;
    if (_alwaysRemovedPayloadHeaders.contains(name)) {
      changedNames.add(name);
      continue;
    }
    if (name == 'content-encoding' &&
        (hasIdentityContentEncoding(headers) || body is! PersistedBase64Body)) {
      changedNames.add(name);
      continue;
    }
    if (name == 'content-length') {
      final replacement = <String>['$reconstructedLength'];
      corrected[name] = replacement;
      if (!_stringListsEqual(values, replacement)) {
        changedNames.add(name);
      }
      continue;
    }
    corrected[name] = values;
  }

  final sortedChangedNames = changedNames.toList()..sort();
  return PreparedPersistedBody._(
    body: body,
    headers: changedNames.isEmpty ? headers : CassetteHeaders(corrected),
    changedHeaderNames: sortedChangedNames,
  );
}

const _alwaysRemovedPayloadHeaders = <String>{
  'content-md5',
  'digest',
  'content-digest',
  'etag',
};

/// Selects the V1 persisted representation for canonical [bytes].
///
/// Selection uses empty, JSON, readable UTF-8 text and Base64 precedence.
/// Non-empty content-encoded bytes are always opaque Base64.
PersistedBody selectPersistedBody(
  CassetteHeaders headers,
  List<int> bytes,
) {
  final validated = _validatedBytes(bytes);
  if (validated.isEmpty) {
    return const PersistedEmptyBody();
  }
  if (hasOpaqueContentEncoding(headers)) {
    return PersistedBase64Body.fromBytes(validated);
  }

  final parsed = parseJsonBody(headers, validated);
  if (parsed.status == JsonBodyStatus.valid) {
    return PersistedJsonBody(parsed.value);
  }

  if (_startsWithUtf8ByteOrderMark(validated)) {
    return PersistedBase64Body.fromBytes(validated);
  }

  try {
    return PersistedTextBody(utf8.decode(validated, allowMalformed: false));
  } on FormatException {
    return PersistedBase64Body.fromBytes(validated);
  } on ArgumentError {
    return PersistedBase64Body.fromBytes(validated);
  }
}

bool _startsWithUtf8ByteOrderMark(List<int> bytes) =>
    bytes.length >= 3 &&
    bytes[0] == 0xef &&
    bytes[1] == 0xbb &&
    bytes[2] == 0xbf;

/// A persisted zero-byte body.
final class PersistedEmptyBody extends PersistedBody {
  /// Creates an empty body representation.
  const PersistedEmptyBody();

  static final Uint8List _emptyBytes = Uint8List(0).asUnmodifiableView();

  @override
  Uint8List reconstruct() => _emptyBytes;

  @override
  bool operator ==(Object other) => other is PersistedEmptyBody;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// A persisted structured JSON body.
final class PersistedJsonBody extends PersistedBody {
  /// Creates a deeply immutable representation of strictly parsed [content].
  ///
  /// [content] must use the value types produced by the core's strict JSON
  /// parser, including [ParsedJsonNumber] for every number.
  factory PersistedJsonBody(Object? content) =>
      PersistedJsonBody._(_copyJsonValue(content));

  const PersistedJsonBody._(this.content);

  /// The deeply immutable JSON value stored in the cassette.
  final Object? content;

  @override
  Uint8List reconstruct() => encodeSanitisedJsonValue(content);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistedJsonBody &&
          _bytesEqual(reconstruct(), other.reconstruct());

  @override
  int get hashCode => Object.hashAll(reconstruct());
}

/// A persisted readable UTF-8 body.
final class PersistedTextBody extends PersistedBody {
  /// Creates a validated text representation containing [content].
  ///
  /// Tab, line feed and carriage return are the only permitted C0 controls.
  /// A leading byte-order mark and unpaired UTF-16 surrogates are rejected.
  PersistedTextBody(String content) : content = _validateText(content);

  /// The readable text stored in the cassette.
  final String content;

  @override
  Uint8List reconstruct() =>
      Uint8List.fromList(utf8.encode(content)).asUnmodifiableView();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistedTextBody && content == other.content;

  @override
  int get hashCode => content.hashCode;
}

/// A persisted opaque body encoded with canonical RFC 4648 Base64.
final class PersistedBase64Body extends PersistedBody {
  /// Encodes and defensively copies [bytes] into canonical Base64 text.
  PersistedBase64Body.fromBytes(List<int> bytes)
      : content = base64Encode(_validatedBytes(bytes));

  /// Standard padded Base64 without whitespace or line breaks.
  final String content;

  @override
  Uint8List reconstruct() =>
      Uint8List.fromList(base64Decode(content)).asUnmodifiableView();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistedBase64Body && content == other.content;

  @override
  int get hashCode => content.hashCode;
}

String _validateText(String content) {
  if (content.startsWith('\uFEFF')) {
    throw ArgumentError(
        'Persisted text must not begin with a byte-order mark.');
  }
  for (var index = 0; index < content.length; index += 1) {
    final codeUnit = content.codeUnitAt(index);
    if (codeUnit < 0x20 &&
        codeUnit != 0x09 &&
        codeUnit != 0x0a &&
        codeUnit != 0x0d) {
      throw ArgumentError('Persisted text contains a disallowed control.');
    }
    if (codeUnit >= 0xd800 && codeUnit <= 0xdbff) {
      if (index + 1 >= content.length) {
        throw ArgumentError('Persisted text contains invalid Unicode.');
      }
      final low = content.codeUnitAt(index + 1);
      if (low < 0xdc00 || low > 0xdfff) {
        throw ArgumentError('Persisted text contains invalid Unicode.');
      }
      index += 1;
    } else if (codeUnit >= 0xdc00 && codeUnit <= 0xdfff) {
      throw ArgumentError('Persisted text contains invalid Unicode.');
    }
  }
  return content;
}

List<int> _validatedBytes(List<int> bytes) {
  for (final byte in bytes) {
    if (byte < 0 || byte > 255) {
      throw ArgumentError('Persisted body values must be bytes from 0 to 255.');
    }
  }
  return List<int>.of(bytes);
}

Object? _copyJsonValue(Object? value) {
  switch (value) {
    case Map<String, Object?>():
      final names = value.keys.toList()..sort();
      return Map<String, Object?>.unmodifiable(<String, Object?>{
        for (final name in names) name: _copyJsonValue(value[name]),
      });
    case List<Object?>():
      return List<Object?>.unmodifiable(value.map(_copyJsonValue));
    case String():
      _validateUnicode(value);
      return value;
    case bool() || ParsedJsonNumber() || null:
      return value;
    default:
      throw ArgumentError(
        'Persisted JSON content must come from strict JSON parsing.',
      );
  }
}

void _validateUnicode(String value) {
  for (var index = 0; index < value.length; index += 1) {
    final codeUnit = value.codeUnitAt(index);
    if (codeUnit >= 0xd800 && codeUnit <= 0xdbff) {
      if (index + 1 >= value.length) {
        throw ArgumentError('Persisted JSON contains invalid Unicode.');
      }
      final low = value.codeUnitAt(index + 1);
      if (low < 0xdc00 || low > 0xdfff) {
        throw ArgumentError('Persisted JSON contains invalid Unicode.');
      }
      index += 1;
    } else if (codeUnit >= 0xdc00 && codeUnit <= 0xdfff) {
      throw ArgumentError('Persisted JSON contains invalid Unicode.');
    }
  }
}

bool _bytesEqual(Uint8List first, Uint8List second) {
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

bool _stringListsEqual(List<String> first, List<String> second) {
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

import 'dart:convert';

import '../json/strict_json.dart';
import '../json/value.dart';
import '../matching/exclusions.dart';
import '../matching/uri_component.dart';
import '../model/headers.dart';
import '../model/http_message.dart';
import '../model/http_syntax.dart';
import '../model/outcome.dart';
import 'body_codec.dart';
import 'request_encoding.dart';

/// The schema version understood by the current cassette decoder.
///
/// Readable-version policy is deliberately separate from the writable version.
const int currentReadableCassetteSchemaVersion = 1;

/// The safe category of an internal cassette decode failure.
enum CassetteDecodeFailureKind {
  /// Input bytes are not valid UTF-8.
  invalidUtf8,

  /// The UTF-8 source is not one complete valid JSON value.
  malformedJson,

  /// A JSON object repeats the same decoded member name.
  duplicateObjectMember,

  /// A decoded value does not satisfy the cassette schema.
  invalidStructure,

  /// The cassette schema version predates readable versions.
  unsupportedOlderVersion,

  /// The cassette schema version is newer than readable versions.
  unsupportedNewerVersion,
}

/// A value-free internal cassette decode failure.
final class CassetteDecodeException implements Exception {
  /// Creates a safe failure description.
  const CassetteDecodeException({
    required this.kind,
    required this.location,
    this.line,
    this.column,
    this.observedSchemaVersion,
  });

  /// The failure category.
  final CassetteDecodeFailureKind kind;

  /// The bounded structural JSON Pointer, or the empty string for the root.
  final String location;

  /// The one-based source line when syntax parsing identified it safely.
  final int? line;

  /// The one-based source column when syntax parsing identified it safely.
  final int? column;

  /// The unsupported integer version when it fits safely in an [int].
  final int? observedSchemaVersion;

  /// The schema version supported by this decoder.
  int get supportedSchemaVersion => currentReadableCassetteSchemaVersion;

  @override
  String toString() {
    final position = line == null ? '' : ' at line $line, column $column';
    return 'CassetteDecodeException(${kind.name} at '
        '${location.isEmpty ? '<root>' : location}$position)';
  }
}

/// A strictly validated V1 root whose interactions remain undecoded.
final class CassetteEnvelopeV1 {
  const CassetteEnvelopeV1._(this.interactions);

  /// Raw immutable interaction values in persisted order.
  final List<Object?> interactions;
}

/// A strictly reconstructed V1 request and its persisted exclusions.
final class DecodedCassetteRequestV1 {
  const DecodedCassetteRequestV1._({
    required this.request,
    required this.matchingExclusions,
  });

  /// The canonical request reconstructed from persisted values.
  final CassetteRequest request;

  /// Locations excluded because recording sanitised their values.
  final MatchingExclusions matchingExclusions;
}

/// Decodes UTF-8 [bytes] and validates the exact V1 root envelope.
///
/// Interaction contents are intentionally deferred to later decoder stages.
CassetteEnvelopeV1 decodeCassetteEnvelopeV1(List<int> bytes) {
  late final String source;
  try {
    source = utf8.decode(bytes, allowMalformed: false);
  } on FormatException {
    throw const CassetteDecodeException(
      kind: CassetteDecodeFailureKind.invalidUtf8,
      location: '',
    );
  } on ArgumentError {
    throw const CassetteDecodeException(
      kind: CassetteDecodeFailureKind.invalidUtf8,
      location: '',
    );
  }

  late final Object? decoded;
  try {
    decoded = parseStrictJson(source);
  } on StrictJsonFormatException catch (error) {
    throw CassetteDecodeException(
      kind: error.kind == StrictJsonFailureKind.duplicateObjectMember
          ? CassetteDecodeFailureKind.duplicateObjectMember
          : CassetteDecodeFailureKind.malformedJson,
      location: '',
      line: error.line,
      column: error.column,
    );
  }

  if (decoded is! Map<String, Object?>) {
    _invalidStructure('');
  }
  final root = decoded;
  if (!_keysEqual(root.keys, const <String>['schemaVersion', 'interactions'])) {
    _invalidStructure('');
  }

  final versionValue = root['schemaVersion'];
  if (versionValue is! ParsedJsonNumber || !versionValue.isInteger) {
    _invalidStructure('/schemaVersion');
  }
  final version = BigInt.parse(versionValue.source);
  final supported = BigInt.from(currentReadableCassetteSchemaVersion);
  if (version != supported) {
    throw CassetteDecodeException(
      kind: version < supported
          ? CassetteDecodeFailureKind.unsupportedOlderVersion
          : CassetteDecodeFailureKind.unsupportedNewerVersion,
      location: '/schemaVersion',
      observedSchemaVersion: _safeInt(version),
    );
  }

  final interactions = root['interactions'];
  if (interactions is! List<Object?>) {
    _invalidStructure('/interactions');
  }
  return CassetteEnvelopeV1._(interactions);
}

/// Strictly decodes one V1 persisted body at [location].
PersistedBody decodePersistedBodyV1(
  Object? value, {
  required String location,
}) {
  if (value is! Map<String, Object?>) {
    _invalidStructure(location);
  }
  final encoding = value['encoding'];
  if (encoding is! String) {
    _invalidStructure('$location/encoding');
  }

  return switch (encoding) {
    'empty' => _decodeEmptyBody(value, location),
    'json' => _decodeJsonBody(value, location),
    'text' => _decodeTextBody(value, location),
    'base64' => _decodeBase64Body(value, location),
    _ => _invalidStructure('$location/encoding'),
  };
}

/// Strictly decodes canonical V1 HTTP [value] at [location].
CassetteHeaders decodeCassetteHeadersV1(
  Object? value, {
  required String location,
}) {
  if (value is! Map<String, Object?>) {
    _invalidStructure(location);
  }
  final names = value.keys.toList(growable: false);
  final sortedNames = names.toList()..sort();
  if (!_keysEqual(names, sortedNames)) {
    _invalidStructure(location);
  }

  final decoded = <String, Iterable<String>>{};
  for (final name in names) {
    final nameLocation = '$location/${_escapeJsonPointerToken(name)}';
    if (name != name.toLowerCase() || !isHttpToken(name)) {
      _invalidStructure(nameLocation);
    }
    final rawValues = value[name];
    if (rawValues is! List<Object?> || rawValues.isEmpty) {
      _invalidStructure(nameLocation);
    }
    final values = <String>[];
    for (var index = 0; index < rawValues.length; index += 1) {
      final rawValue = rawValues[index];
      if (rawValue is! String) {
        _invalidStructure('$nameLocation/$index');
      }
      try {
        validateHttpFieldValue(rawValue, description: 'HTTP header value');
      } on ArgumentError {
        _invalidStructure('$nameLocation/$index');
      }
      values.add(rawValue);
    }
    decoded[name] = values;
  }

  try {
    return CassetteHeaders(decoded);
  } on ArgumentError {
    _invalidStructure(location);
  }
}

/// Strictly decodes V1 request matching exclusions at [location].
MatchingExclusions decodeMatchingExclusionsV1(
  Object? value, {
  required String location,
}) {
  if (value is! Map<String, Object?> ||
      !_keysEqual(value.keys, const <String>[
        'uriUserInformation',
        'body',
        'headers',
        'queryParameters',
        'jsonPointers',
      ])) {
    _invalidStructure(location);
  }
  final uriUserInformation = value['uriUserInformation'];
  final body = value['body'];
  if (uriUserInformation is! bool) {
    _invalidStructure('$location/uriUserInformation');
  }
  if (body is! bool) {
    _invalidStructure('$location/body');
  }

  final headers = _decodeCanonicalStringList(
    value['headers'],
    '$location/headers',
  );
  for (var index = 0; index < headers.length; index += 1) {
    final name = headers[index];
    if (name != name.toLowerCase() || !isHttpToken(name)) {
      _invalidStructure('$location/headers/$index');
    }
  }

  final queryParameters = _decodeCanonicalStringList(
    value['queryParameters'],
    '$location/queryParameters',
  );
  for (var index = 0; index < queryParameters.length; index += 1) {
    final name = queryParameters[index];
    try {
      if (normaliseUriComponent(name) != name) {
        _invalidStructure('$location/queryParameters/$index');
      }
    } on ArgumentError {
      _invalidStructure('$location/queryParameters/$index');
    }
  }

  final jsonPointers = _decodeCanonicalStringList(
    value['jsonPointers'],
    '$location/jsonPointers',
  );
  for (var index = 0; index < jsonPointers.length; index += 1) {
    try {
      MatchingExclusions(jsonPointers: <String>[jsonPointers[index]]);
    } on ArgumentError {
      _invalidStructure('$location/jsonPointers/$index');
    }
  }
  try {
    return MatchingExclusions(
      headers: headers,
      queryParameters: queryParameters,
      jsonPointers: jsonPointers,
      uriUserInformation: uriUserInformation,
      body: body,
    );
  } on ArgumentError {
    _invalidStructure(location);
  }
}

/// Strictly reconstructs one complete V1 request at [location].
DecodedCassetteRequestV1 decodeCassetteRequestV1(
  Object? value, {
  required String location,
}) {
  if (value is! Map<String, Object?> ||
      !_keysEqual(value.keys, const <String>[
        'method',
        'uri',
        'headers',
        'body',
        'matchingExclusions',
      ])) {
    _invalidStructure(location);
  }

  final method = value['method'];
  if (method is! String ||
      method != method.toUpperCase() ||
      !isHttpToken(method)) {
    _invalidStructure('$location/method');
  }
  final uriText = value['uri'];
  if (uriText is! String) {
    _invalidStructure('$location/uri');
  }
  final headers = decodeCassetteHeadersV1(
    value['headers'],
    location: '$location/headers',
  );
  final persistedBody = decodePersistedBodyV1(
    value['body'],
    location: '$location/body',
  );
  final matchingExclusions = decodeMatchingExclusionsV1(
    value['matchingExclusions'],
    location: '$location/matchingExclusions',
  );

  late final Uri uri;
  try {
    uri = Uri.parse(uriText);
  } on FormatException {
    _invalidStructure('$location/uri');
  }
  if (!uri.hasScheme || uri.host.isEmpty) {
    _invalidStructure('$location/uri');
  }

  late final CassetteRequest request;
  request = CassetteRequest(
    method: method,
    uri: uri,
    headers: headers,
    body: persistedBody.reconstruct(),
  );
  try {
    if (canonicalisePersistedRequestUri(request) != uriText) {
      _invalidStructure('$location/uri');
    }
  } on ArgumentError {
    _invalidStructure('$location/uri');
  }

  final prepared = preparePersistedBody(headers, request.body);
  if (prepared.body != persistedBody) {
    _invalidStructure('$location/body');
  }
  if (prepared.headers != headers || prepared.changedHeaderNames.isNotEmpty) {
    _invalidStructure('$location/headers');
  }

  return DecodedCassetteRequestV1._(
    request: request,
    matchingExclusions: matchingExclusions,
  );
}

/// Strictly reconstructs one V1 response or transport failure at [location].
CassetteOutcome decodeCassetteOutcomeV1(
  Object? value, {
  required String location,
}) {
  if (value is! Map<String, Object?>) {
    _invalidStructure(location);
  }
  final type = value['type'];
  if (type is! String) {
    _invalidStructure('$location/type');
  }
  return switch (type) {
    'response' => _decodeResponseOutcomeV1(value, location),
    'transportFailure' => _decodeTransportFailureV1(value, location),
    _ => _invalidStructure('$location/type'),
  };
}

CassetteOutcome _decodeResponseOutcomeV1(
  Map<String, Object?> value,
  String location,
) {
  final hasReasonPhrase = value.containsKey('reasonPhrase');
  final expectedKeys = hasReasonPhrase
      ? const <String>['type', 'statusCode', 'reasonPhrase', 'headers', 'body']
      : const <String>['type', 'statusCode', 'headers', 'body'];
  if (!_keysEqual(value.keys, expectedKeys)) {
    _invalidStructure(location);
  }

  final statusCode = _decodeIntegerInRange(
    value['statusCode'],
    '$location/statusCode',
    minimum: 100,
    maximum: 599,
  );
  final reasonPhrase = value['reasonPhrase'];
  if (hasReasonPhrase && reasonPhrase is! String) {
    _invalidStructure('$location/reasonPhrase');
  }
  final headers = decodeCassetteHeadersV1(
    value['headers'],
    location: '$location/headers',
  );
  final persistedBody = decodePersistedBodyV1(
    value['body'],
    location: '$location/body',
  );
  final prepared = preparePersistedBody(headers, persistedBody.reconstruct());
  if (prepared.body != persistedBody) {
    _invalidStructure('$location/body');
  }
  if (prepared.headers != headers || prepared.changedHeaderNames.isNotEmpty) {
    _invalidStructure('$location/headers');
  }

  try {
    return CassetteResponseOutcome(
      CassetteResponse(
        statusCode: statusCode,
        reasonPhrase: reasonPhrase as String?,
        headers: headers,
        body: persistedBody.reconstruct(),
      ),
    );
  } on ArgumentError {
    _invalidStructure('$location/reasonPhrase');
  }
}

CassetteOutcome _decodeTransportFailureV1(
  Map<String, Object?> value,
  String location,
) {
  if (!_keysEqual(value.keys, const <String>['type', 'category', 'message'])) {
    _invalidStructure(location);
  }
  final categoryValue = value['category'];
  if (categoryValue is! String) {
    _invalidStructure('$location/category');
  }
  final category = switch (categoryValue) {
    'nameResolution' => TransportFailureCategory.nameResolution,
    'connection' => TransportFailureCategory.connection,
    'secureConnection' => TransportFailureCategory.secureConnection,
    'timeout' => TransportFailureCategory.timeout,
    'protocol' => TransportFailureCategory.protocol,
    'other' => TransportFailureCategory.other,
    _ => _invalidStructure('$location/category'),
  };
  final message = value['message'];
  if (message is! String) {
    _invalidStructure('$location/message');
  }
  try {
    return CassetteTransportFailure(category: category, message: message);
  } on ArgumentError {
    _invalidStructure('$location/message');
  }
}

int _decodeIntegerInRange(
  Object? value,
  String location, {
  required int minimum,
  required int maximum,
}) {
  if (value is! ParsedJsonNumber || !value.isInteger) {
    _invalidStructure(location);
  }
  final integer = BigInt.parse(value.source);
  if (integer < BigInt.from(minimum) || integer > BigInt.from(maximum)) {
    _invalidStructure(location);
  }
  return integer.toInt();
}

List<String> _decodeCanonicalStringList(Object? value, String location) {
  if (value is! List<Object?>) {
    _invalidStructure(location);
  }
  final result = <String>[];
  for (var index = 0; index < value.length; index += 1) {
    final item = value[index];
    if (item is! String) {
      _invalidStructure('$location/$index');
    }
    if (result.isNotEmpty && result.last.compareTo(item) >= 0) {
      _invalidStructure(location);
    }
    result.add(item);
  }
  return List<String>.unmodifiable(result);
}

PersistedBody _decodeEmptyBody(Map<String, Object?> value, String location) {
  if (!_keysEqual(value.keys, const <String>['encoding'])) {
    _invalidStructure(location);
  }
  return const PersistedEmptyBody();
}

PersistedBody _decodeJsonBody(Map<String, Object?> value, String location) {
  if (!_keysEqual(value.keys, const <String>['encoding', 'content'])) {
    _invalidStructure(location);
  }
  final content = value['content'];
  _validateJsonContent(content, '$location/content');
  try {
    return PersistedJsonBody(content);
  } on ArgumentError {
    _invalidStructure('$location/content');
  }
}

PersistedBody _decodeTextBody(Map<String, Object?> value, String location) {
  if (!_keysEqual(value.keys, const <String>['encoding', 'content'])) {
    _invalidStructure(location);
  }
  final content = value['content'];
  if (content is! String || content.isEmpty) {
    _invalidStructure('$location/content');
  }
  try {
    return PersistedTextBody(content);
  } on ArgumentError {
    _invalidStructure('$location/content');
  }
}

PersistedBody _decodeBase64Body(Map<String, Object?> value, String location) {
  if (!_keysEqual(value.keys, const <String>['encoding', 'content'])) {
    _invalidStructure(location);
  }
  final content = value['content'];
  if (content is! String || content.isEmpty) {
    _invalidStructure('$location/content');
  }
  try {
    final bytes = base64Decode(content);
    if (base64Encode(bytes) != content) {
      _invalidStructure('$location/content');
    }
    return PersistedBase64Body.fromBytes(bytes);
  } on FormatException {
    _invalidStructure('$location/content');
  }
}

void _validateJsonContent(Object? value, String location) {
  switch (value) {
    case Map<String, Object?>():
      final names = value.keys.toList(growable: false);
      final sortedNames = names.toList()..sort();
      if (!_keysEqual(names, sortedNames)) {
        _invalidStructure(location);
      }
      for (final name in names) {
        _validateJsonContent(
          value[name],
          '$location/${_escapeJsonPointerToken(name)}',
        );
      }
    case List<Object?>():
      for (var index = 0; index < value.length; index += 1) {
        _validateJsonContent(value[index], '$location/$index');
      }
    case String():
      if (!_hasValidUnicode(value)) {
        _invalidStructure(location);
      }
    case bool() || ParsedJsonNumber() || null:
      return;
    default:
      _invalidStructure(location);
  }
}

bool _hasValidUnicode(String value) {
  for (var index = 0; index < value.length; index += 1) {
    final codeUnit = value.codeUnitAt(index);
    if (codeUnit >= 0xd800 && codeUnit <= 0xdbff) {
      if (index + 1 >= value.length) return false;
      final low = value.codeUnitAt(index + 1);
      if (low < 0xdc00 || low > 0xdfff) return false;
      index += 1;
    } else if (codeUnit >= 0xdc00 && codeUnit <= 0xdfff) {
      return false;
    }
  }
  return true;
}

String _escapeJsonPointerToken(String token) =>
    token.replaceAll('~', '~0').replaceAll('/', '~1');

Never _invalidStructure(String location) => throw CassetteDecodeException(
      kind: CassetteDecodeFailureKind.invalidStructure,
      location: location,
    );

bool _keysEqual(Iterable<String> actual, List<String> expected) {
  final actualList = actual.toList(growable: false);
  if (actualList.length != expected.length) return false;
  for (var index = 0; index < expected.length; index += 1) {
    if (actualList[index] != expected[index]) return false;
  }
  return true;
}

int? _safeInt(BigInt value) {
  const maximum = 0x7fffffffffffffff;
  const minimum = -0x8000000000000000;
  return value >= BigInt.from(minimum) && value <= BigInt.from(maximum)
      ? value.toInt()
      : null;
}

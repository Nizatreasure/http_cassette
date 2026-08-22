import 'dart:convert';

import '../json/strict_json.dart';
import '../json/value.dart';

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
final class CassetteV1Envelope {
  const CassetteV1Envelope._(this.interactions);

  /// Raw immutable interaction values in persisted order.
  final List<Object?> interactions;
}

/// Decodes UTF-8 [bytes] and validates the exact V1 root envelope.
///
/// Interaction contents are intentionally deferred to later decoder stages.
CassetteV1Envelope decodeCassetteV1Envelope(List<int> bytes) {
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
  return CassetteV1Envelope._(interactions);
}

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

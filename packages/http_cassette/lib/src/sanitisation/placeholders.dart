import '../matching/json.dart';

/// The fixed placeholder for an ordinary sensitive string.
const redactedStringPlaceholder = '[REDACTED]';

/// The fixed placeholder for a sensitive UUID string.
const redactedUuidPlaceholder = '00000000-0000-4000-8000-000000000000';

/// The fixed placeholder for a sensitive email-address string.
const redactedEmailPlaceholder = 'redacted@example.invalid';

final _canonicalUuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
final _ordinaryEmailLocalPart = RegExp(
  r"^[A-Za-z0-9!#$%&'*+/=?^_`{|}~.-]+$",
);
final _ordinaryEmailDomainLabel = RegExp(r'^[A-Za-z0-9-]+$');
final _ordinaryEmailTopLevelDomain = RegExp(r'^[A-Za-z]{2,}$');

/// Returns the fixed type-preserving placeholder for parsed JSON [value].
///
/// [value] must be a JSON scalar produced by the strict JSON parser.
Object? placeholderForJsonScalar(Object? value) => switch (value) {
      String() => _placeholderForString(value),
      bool() => false,
      ParsedJsonNumber() => value.isInteger
          ? ParsedJsonNumber.zeroInteger
          : ParsedJsonNumber.zeroNonInteger,
      null => null,
      _ => throw ArgumentError(
          'A JSON scalar is required for placeholder selection.',
        ),
    };

String _placeholderForString(String value) {
  if (_canonicalUuid.hasMatch(value)) {
    return redactedUuidPlaceholder;
  }
  if (_isOrdinaryEmailAddress(value)) {
    return redactedEmailPlaceholder;
  }
  return redactedStringPlaceholder;
}

bool _isOrdinaryEmailAddress(String value) {
  final at = value.indexOf('@');
  if (at <= 0 || at != value.lastIndexOf('@') || at == value.length - 1) {
    return false;
  }

  final local = value.substring(0, at);
  if (local.length > 64 ||
      local.startsWith('.') ||
      local.endsWith('.') ||
      local.contains('..') ||
      !_ordinaryEmailLocalPart.hasMatch(local)) {
    return false;
  }

  final labels = value.substring(at + 1).split('.');
  if (labels.length < 2 ||
      !_ordinaryEmailTopLevelDomain.hasMatch(labels.last)) {
    return false;
  }
  for (final label in labels) {
    if (label.isEmpty ||
        label.length > 63 ||
        label.startsWith('-') ||
        label.endsWith('-') ||
        !_ordinaryEmailDomainLabel.hasMatch(label)) {
      return false;
    }
  }
  return true;
}

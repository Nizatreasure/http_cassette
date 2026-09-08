/// Validates and returns one safe line of display text.
///
/// [value] must be trimmed and non-empty, contain no control or bidirectional
/// formatting characters, and contain no more than [maximumLength] Unicode
/// code points. [description] identifies the value in any [ArgumentError].
String validateSafeSingleLine(
  String value, {
  required String description,
  int maximumLength = 256,
}) {
  if (value.isEmpty || value.trim() != value) {
    throw ArgumentError(
      '$description must be non-empty with no surrounding whitespace.',
    );
  }

  var length = 0;
  for (final rune in value.runes) {
    length += 1;

    if (length > maximumLength) {
      throw ArgumentError(
        '$description must not exceed $maximumLength characters.',
      );
    }

    if (_isUnsafeRune(rune)) {
      throw ArgumentError(
        '$description must not contain control or formatting characters.',
      );
    }
  }

  return value;
}

bool _isUnsafeRune(int rune) =>
    rune <= 0x1f ||
    (rune >= 0x7f && rune <= 0x9f) ||
    rune == 0x2028 ||
    rune == 0x2029 ||
    (rune >= 0x202a && rune <= 0x202e) ||
    (rune >= 0x2066 && rune <= 0x2069);

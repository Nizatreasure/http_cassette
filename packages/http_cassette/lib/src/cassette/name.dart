/// A validated, cross-platform logical cassette name.
///
/// A name contains one or more slash-separated segments. Segments may contain
/// ASCII letters, digits, `_`, `-` and `.`, but may not be `.` or `..`. The
/// final segment must not end in `.json`, because cassette stores own that
/// suffix.
final class CassetteName {
  /// Creates a validated cassette name from [value].
  ///
  /// Throws an [ArgumentError] when [value] is empty or is not a portable
  /// logical name.
  factory CassetteName(String value) {
    _validate(value);
    return CassetteName._(value);
  }

  const CassetteName._(this.value);

  /// The validated slash-separated logical name.
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is CassetteName && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

void _validate(String value) {
  if (value.isEmpty || value.endsWith('.json')) {
    throw ArgumentError('Cassette name must be a portable logical name.');
  }

  final segments = value.split('/');
  for (final segment in segments) {
    if (segment.isEmpty || segment == '.' || segment == '..') {
      throw ArgumentError('Cassette name must be a portable logical name.');
    }

    for (final codeUnit in segment.codeUnits) {
      if (!_isAllowedCodeUnit(codeUnit)) {
        throw ArgumentError('Cassette name must be a portable logical name.');
      }
    }
  }
}

bool _isAllowedCodeUnit(int codeUnit) =>
    (codeUnit >= 0x41 && codeUnit <= 0x5a) ||
    (codeUnit >= 0x61 && codeUnit <= 0x7a) ||
    (codeUnit >= 0x30 && codeUnit <= 0x39) ||
    codeUnit == 0x5f ||
    codeUnit == 0x2d ||
    codeUnit == 0x2e;

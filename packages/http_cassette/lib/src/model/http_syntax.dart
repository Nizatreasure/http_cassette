bool isHttpToken(String value) {
  if (value.isEmpty) {
    return false;
  }

  for (final codeUnit in value.codeUnits) {
    if (!_isTokenCodeUnit(codeUnit)) {
      return false;
    }
  }
  return true;
}

void validateHttpFieldValue(String value, {required String description}) {
  for (final codeUnit in value.codeUnits) {
    final prohibitedControl = codeUnit < 0x20 && codeUnit != 0x09;
    if (prohibitedControl || codeUnit == 0x7f) {
      throw ArgumentError(
        '$description must not contain prohibited control characters.',
      );
    }
  }
}

bool _isTokenCodeUnit(int codeUnit) =>
    (codeUnit >= 0x30 && codeUnit <= 0x39) ||
    (codeUnit >= 0x41 && codeUnit <= 0x5a) ||
    (codeUnit >= 0x61 && codeUnit <= 0x7a) ||
    switch (codeUnit) {
      0x21 || // !
      0x23 || // #
      0x24 || // $
      0x25 || // %
      0x26 || // &
      0x27 || // '
      0x2a || // *
      0x2b || // +
      0x2d || // -
      0x2e || // .
      0x5e || // ^
      0x5f || // _
      0x60 || // `
      0x7c || // |
      0x7e => // ~
        true,
      _ => false,
    };

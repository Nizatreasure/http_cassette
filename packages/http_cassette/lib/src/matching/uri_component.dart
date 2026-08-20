/// Normalises percent escapes in an encoded URI component conservatively.
///
/// Unreserved ASCII characters are decoded. Other escapes remain encoded with
/// upper-case hexadecimal digits.
String normaliseUriComponent(String value) {
  final result = StringBuffer();
  var index = 0;
  while (index < value.length) {
    final codeUnit = value.codeUnitAt(index);
    if (codeUnit != 0x25) {
      result.writeCharCode(codeUnit);
      index += 1;
      continue;
    }

    if (index + 2 >= value.length) {
      throw ArgumentError('URI component contains a malformed escape.');
    }
    final first = _hexValue(value.codeUnitAt(index + 1));
    final second = _hexValue(value.codeUnitAt(index + 2));
    if (first == null || second == null) {
      throw ArgumentError('URI component contains a malformed escape.');
    }

    final decoded = first * 16 + second;
    if (_isUnreserved(decoded)) {
      result.writeCharCode(decoded);
    } else {
      result
        ..write('%')
        ..write(decoded.toRadixString(16).toUpperCase().padLeft(2, '0'));
    }
    index += 3;
  }
  return result.toString();
}

int? _hexValue(int codeUnit) {
  if (codeUnit >= 0x30 && codeUnit <= 0x39) {
    return codeUnit - 0x30;
  }
  final lower = codeUnit | 0x20;
  if (lower >= 0x61 && lower <= 0x66) {
    return lower - 0x61 + 10;
  }
  return null;
}

bool _isUnreserved(int codeUnit) =>
    (codeUnit >= 0x41 && codeUnit <= 0x5a) ||
    (codeUnit >= 0x61 && codeUnit <= 0x7a) ||
    (codeUnit >= 0x30 && codeUnit <= 0x39) ||
    codeUnit == 0x2d ||
    codeUnit == 0x2e ||
    codeUnit == 0x5f ||
    codeUnit == 0x7e;

/// A validated JSON number retained without binary floating-point conversion.
final class ParsedJsonNumber {
  const ParsedJsonNumber.internal(this.source);

  /// The fixed placeholder for a parsed JSON integer.
  static const zeroInteger = ParsedJsonNumber.internal('0');

  /// The fixed placeholder for a parsed non-integer JSON number.
  static const zeroNonInteger = ParsedJsonNumber.internal('0.0');

  /// The original valid JSON number spelling.
  final String source;

  /// Whether the decoded representation belongs to the integer category.
  bool get isInteger => !source.contains(RegExp(r'[.eE]'));
}

/// Why encoded response content could not be decoded safely.
enum ContentDecodingFailureKind {
  /// Decoding is unavailable on the current platform.
  unsupportedPlatform,

  /// The encoded bytes do not form a valid supported representation.
  invalidContent,

  /// Decoded content would exceed its configured byte limit.
  decodedBodyTooLarge,
}

/// A value-safe failure from bounded content decoding.
final class ContentDecodingException implements Exception {
  /// Creates a failure with its safe [kind] and applicable [maximumBytes].
  const ContentDecodingException({
    required this.kind,
    this.maximumBytes,
  }) : assert(
          kind == ContentDecodingFailureKind.decodedBodyTooLarge
              ? maximumBytes != null && maximumBytes > 0
              : maximumBytes == null,
        );

  /// The safe reason decoding failed.
  final ContentDecodingFailureKind kind;

  /// The configured decoded-byte limit for a size failure.
  final int? maximumBytes;

  @override
  String toString() => switch (kind) {
        ContentDecodingFailureKind.unsupportedPlatform =>
          'Encoded content decoding is unavailable on this platform.',
        ContentDecodingFailureKind.invalidContent =>
          'Encoded content is not a valid supported representation.',
        ContentDecodingFailureKind.decodedBodyTooLarge =>
          'Decoded content exceeded its configured byte limit.',
      };
}

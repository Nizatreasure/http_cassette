/// Why sanitised content could not be recompressed safely.
enum ContentRecompressionFailureKind {
  /// Recompression is unavailable on the current platform.
  unsupportedPlatform,

  /// Recompressed content would exceed its configured byte limit.
  recompressedBodyTooLarge,
}

/// A value-safe failure from bounded content recompression.
final class ContentRecompressionException implements Exception {
  /// Creates a failure with its safe [kind] and applicable [maximumBytes].
  const ContentRecompressionException({
    required this.kind,
    this.maximumBytes,
  }) : assert(
          kind == ContentRecompressionFailureKind.recompressedBodyTooLarge
              ? maximumBytes != null && maximumBytes > 0
              : maximumBytes == null,
        );

  /// The safe reason recompression failed.
  final ContentRecompressionFailureKind kind;

  /// The configured recompressed-byte limit for a size failure.
  final int? maximumBytes;

  @override
  String toString() => switch (kind) {
        ContentRecompressionFailureKind.unsupportedPlatform =>
          'Content recompression is unavailable on this platform.',
        ContentRecompressionFailureKind.recompressedBodyTooLarge =>
          'Recompressed content exceeded its configured byte limit.',
      };
}

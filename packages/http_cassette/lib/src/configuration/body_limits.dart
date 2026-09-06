/// Immutable limits for buffered canonical HTTP bodies.
///
/// Active adapters enforce the request limit before a real attempt and the
/// response limit while capturing its outcome. Content which exceeds a limit
/// fails instead of being truncated.
final class BodyLimits {
  /// Creates validated request and response body limits.
  ///
  /// Both limits are measured in bytes and must be positive.
  factory BodyLimits({
    int requestBytes = defaultRequestBytes,
    int responseBytes = defaultResponseBytes,
  }) {
    if (requestBytes <= 0) {
      throw ArgumentError('Request body limit must be positive.');
    }
    if (responseBytes <= 0) {
      throw ArgumentError('Response body limit must be positive.');
    }
    return BodyLimits._(
      requestBytes: requestBytes,
      responseBytes: responseBytes,
    );
  }

  const BodyLimits._({
    required this.requestBytes,
    required this.responseBytes,
  });

  /// The default request body limit of 2 MiB.
  static const int defaultRequestBytes = 2 * 1024 * 1024;

  /// The default response body limit of 5 MiB.
  static const int defaultResponseBytes = 5 * 1024 * 1024;

  /// The maximum buffered request body size in bytes.
  final int requestBytes;

  /// The maximum buffered response body size in bytes.
  final int responseBytes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BodyLimits &&
          requestBytes == other.requestBytes &&
          responseBytes == other.responseBytes;

  @override
  int get hashCode => Object.hash(requestBytes, responseBytes);
}

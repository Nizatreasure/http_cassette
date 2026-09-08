import '../cassette/name.dart';
import '../model/http_message.dart';

/// Immutable value-free facts identifying an incoming replay request safely.
///
/// URI, header and body values are deliberately absent because their values,
/// names and locations may contain confidential information.
final class ReplayRequestSummary {
  /// Captures bounded facts from [request] at its [arrivalIndex].
  factory ReplayRequestSummary.fromRequest({
    required CassetteRequest request,
    required int arrivalIndex,
  }) {
    if (arrivalIndex < 0) {
      throw ArgumentError('Request arrival index must not be negative.');
    }
    final methodCharacterLength = request.method.runes.length;
    return ReplayRequestSummary._(
      method:
          methodCharacterLength <= _maximumMethodLength ? request.method : null,
      methodCharacterLength: methodCharacterLength,
      bodyByteLength: request.body.length,
      arrivalIndex: arrivalIndex,
    );
  }

  const ReplayRequestSummary._({
    required this.method,
    required this.methodCharacterLength,
    required this.bodyByteLength,
    required this.arrivalIndex,
  });

  /// The canonical upper-case HTTP method, or `null` when it exceeded 64
  /// characters and was omitted rather than truncated.
  final String? method;

  /// The complete character length of the canonical HTTP method.
  final int methodCharacterLength;

  /// The complete request body length without retaining its bytes.
  final int bodyByteLength;

  /// Whether the request has a non-empty body.
  bool get hasBody => bodyByteLength != 0;

  /// The stable request-arrival index assigned by replay.
  final int arrivalIndex;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReplayRequestSummary &&
          method == other.method &&
          methodCharacterLength == other.methodCharacterLength &&
          bodyByteLength == other.bodyByteLength &&
          arrivalIndex == other.arrivalIndex;

  @override
  int get hashCode => Object.hash(
        method,
        methodCharacterLength,
        bodyByteLength,
        arrivalIndex,
      );
}

const _maximumMethodLength = 64;

/// Safe cassette and request context for a replay diagnostic.
final class ReplayDiagnosticContext {
  /// Creates context from a validated logical [cassetteName] and [request].
  const ReplayDiagnosticContext({
    required this.cassetteName,
    required this.request,
  });

  /// The validated logical cassette identity, never a persistence path.
  final CassetteName cassetteName;

  /// The value-free incoming request summary.
  final ReplayRequestSummary request;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReplayDiagnosticContext &&
          cassetteName == other.cassetteName &&
          request == other.request;

  @override
  int get hashCode => Object.hash(cassetteName, request);
}

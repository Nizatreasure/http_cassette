import '../model/http_message.dart';
import 'exclusions.dart';
import 'uri_component.dart';

/// The method, origin and path used by the default request matcher.
///
/// Query data is deliberately excluded and is normalised separately.
final class NormalisedRequestTarget {
  /// Creates a normalised target from a validated canonical [request].
  factory NormalisedRequestTarget.fromRequest(
    CassetteRequest request, {
    MatchingExclusions exclusions = MatchingExclusions.none,
  }) {
    final uri = request.uri;
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();

    return NormalisedRequestTarget._(
      method: request.method,
      scheme: scheme,
      host: host,
      port: _normalisePort(uri, scheme),
      path: uri.path.isEmpty ? '/' : normaliseUriComponent(uri.path),
      userInformation: exclusions.uriUserInformation || uri.userInfo.isEmpty
          ? null
          : normaliseUriComponent(uri.userInfo),
    );
  }

  const NormalisedRequestTarget._({
    required this.method,
    required this.scheme,
    required this.host,
    required this.port,
    required this.path,
    required this.userInformation,
  });

  /// The canonical upper-case HTTP method.
  final String method;

  /// The lower-case URI scheme.
  final String scheme;

  /// The lower-case canonical ASCII host.
  final String host;

  /// The explicit non-default port, or `null` when no port distinguishes it.
  final int? port;

  /// The canonical encoded path, with an empty path represented as `/`.
  final String path;

  /// Normalised URI user information, or `null` when absent or excluded.
  ///
  /// This value is for equality only and must never enter diagnostics.
  final String? userInformation;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NormalisedRequestTarget &&
          method == other.method &&
          scheme == other.scheme &&
          host == other.host &&
          port == other.port &&
          path == other.path &&
          userInformation == other.userInformation;

  @override
  int get hashCode =>
      Object.hash(method, scheme, host, port, path, userInformation);
}

int? _normalisePort(Uri uri, String scheme) {
  if (!uri.hasPort) {
    return null;
  }
  if ((scheme == 'http' && uri.port == 80) ||
      (scheme == 'https' && uri.port == 443)) {
    return null;
  }
  return uri.port;
}

import '../model/http_message.dart';

/// The method, origin and path used by the default request matcher.
///
/// Query data is deliberately excluded and is normalised separately.
final class NormalisedRequestTarget {
  /// Creates a normalised target from a validated canonical [request].
  factory NormalisedRequestTarget.fromRequest(CassetteRequest request) {
    final uri = request.uri;
    final scheme = uri.scheme.toLowerCase();
    final host = _normaliseHost(uri.host);

    return NormalisedRequestTarget._(
      method: request.method,
      scheme: scheme,
      host: host,
      port: _normalisePort(uri, scheme),
      path: _normalisePath(uri.path),
    );
  }

  const NormalisedRequestTarget._({
    required this.method,
    required this.scheme,
    required this.host,
    required this.port,
    required this.path,
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NormalisedRequestTarget &&
          method == other.method &&
          scheme == other.scheme &&
          host == other.host &&
          port == other.port &&
          path == other.path;

  @override
  int get hashCode => Object.hash(method, scheme, host, port, path);
}

String _normaliseHost(String host) {
  for (final codeUnit in host.codeUnits) {
    if (codeUnit > 0x7f || codeUnit == 0x25) {
      throw ArgumentError(
        'HTTP request host must use its canonical ASCII form.',
      );
    }
  }
  return host.toLowerCase();
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

String _normalisePath(String path) {
  if (path.isEmpty) {
    return '/';
  }

  final result = StringBuffer();
  var index = 0;
  while (index < path.length) {
    final codeUnit = path.codeUnitAt(index);
    if (codeUnit != 0x25) {
      result.writeCharCode(codeUnit);
      index += 1;
      continue;
    }

    if (index + 2 >= path.length) {
      throw ArgumentError('HTTP request path contains a malformed escape.');
    }
    final first = _hexValue(path.codeUnitAt(index + 1));
    final second = _hexValue(path.codeUnitAt(index + 2));
    if (first == null || second == null) {
      throw ArgumentError('HTTP request path contains a malformed escape.');
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

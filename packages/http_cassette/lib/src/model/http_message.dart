import 'dart:typed_data';

import 'headers.dart';
import 'http_syntax.dart';

/// An immutable HTTP request in the canonical cassette representation.
abstract final class CassetteRequest {
  /// Creates a validated canonical request.
  ///
  /// [method] must use the HTTP token grammar and is stored in upper-case ASCII
  /// form. [uri] must be absolute and contain a canonical ASCII host without
  /// percent escapes. The body is copied defensively and every element must be
  /// a byte from 0 through 255.
  factory CassetteRequest({
    required String method,
    required Uri uri,
    CassetteHeaders headers = const CassetteHeaders.empty(),
    List<int> body = const <int>[],
  }) =>
      _CassetteRequest(
        method: method,
        uri: uri,
        headers: headers,
        body: body,
      );

  /// The canonical upper-case HTTP method.
  String get method;

  /// The absolute request URI observed at the adapter boundary.
  Uri get uri;

  /// Immutable canonical request headers.
  CassetteHeaders get headers;

  /// Immutable request body bytes as observed by the adapter.
  Uint8List get body;
}

/// An immutable HTTP response in the canonical cassette representation.
abstract final class CassetteResponse {
  /// Creates a validated canonical response.
  ///
  /// [statusCode] must be from 100 through 599. When supplied, [reasonPhrase]
  /// must be non-empty and contain no prohibited control characters. The body
  /// is copied defensively and every element must be a byte from 0 through 255.
  factory CassetteResponse({
    required int statusCode,
    CassetteHeaders headers = const CassetteHeaders.empty(),
    List<int> body = const <int>[],
    String? reasonPhrase,
  }) =>
      _CassetteResponse(
        statusCode: statusCode,
        headers: headers,
        body: body,
        reasonPhrase: reasonPhrase,
      );

  /// The observed HTTP status code.
  int get statusCode;

  /// Immutable canonical response headers.
  CassetteHeaders get headers;

  /// Immutable response body bytes as observed by the adapter.
  Uint8List get body;

  /// The observed reason phrase, or `null` when none was available.
  String? get reasonPhrase;
}

final class _CassetteRequest implements CassetteRequest {
  _CassetteRequest({
    required String method,
    required Uri uri,
    this.headers = const CassetteHeaders.empty(),
    List<int> body = const <int>[],
  })  : method = _canonicalMethod(method),
        uri = _validateUri(uri),
        _body = _copyBody(body);

  @override
  final String method;

  @override
  final Uri uri;

  @override
  final CassetteHeaders headers;

  final Uint8List _body;

  @override
  Uint8List get body => _body;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CassetteRequest &&
          method == other.method &&
          uri == other.uri &&
          headers == other.headers &&
          _bytesEqual(_body, other.body);

  @override
  int get hashCode => Object.hash(method, uri, headers, Object.hashAll(_body));
}

final class _CassetteResponse implements CassetteResponse {
  _CassetteResponse({
    required int statusCode,
    this.headers = const CassetteHeaders.empty(),
    List<int> body = const <int>[],
    String? reasonPhrase,
  })  : statusCode = _validateStatusCode(statusCode),
        reasonPhrase = _validateReasonPhrase(reasonPhrase),
        _body = _copyBody(body);

  @override
  final int statusCode;

  @override
  final CassetteHeaders headers;

  final Uint8List _body;

  @override
  Uint8List get body => _body;

  @override
  final String? reasonPhrase;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CassetteResponse &&
          statusCode == other.statusCode &&
          headers == other.headers &&
          reasonPhrase == other.reasonPhrase &&
          _bytesEqual(_body, other.body);

  @override
  int get hashCode => Object.hash(
        statusCode,
        headers,
        reasonPhrase,
        Object.hashAll(_body),
      );
}

String _canonicalMethod(String method) {
  if (!isHttpToken(method)) {
    throw ArgumentError('HTTP method must use the token grammar.');
  }
  return method.toUpperCase();
}

Uri _validateUri(Uri uri) {
  if (!uri.hasScheme || uri.host.isEmpty) {
    throw ArgumentError(
        'HTTP request URI must be absolute and contain a host.');
  }
  validateCanonicalHttpHost(uri.host);
  return uri;
}

int _validateStatusCode(int statusCode) {
  if (statusCode < 100 || statusCode > 599) {
    throw ArgumentError('HTTP status code must be from 100 through 599.');
  }
  return statusCode;
}

String? _validateReasonPhrase(String? reasonPhrase) {
  if (reasonPhrase == null) {
    return null;
  }
  if (reasonPhrase.isEmpty) {
    throw ArgumentError('HTTP reason phrase must be non-empty when supplied.');
  }
  validateHttpFieldValue(reasonPhrase, description: 'HTTP reason phrase');
  return reasonPhrase;
}

Uint8List _copyBody(List<int> body) {
  for (final byte in body) {
    if (byte < 0 || byte > 255) {
      throw ArgumentError('HTTP body values must be bytes from 0 through 255.');
    }
  }
  return Uint8List.fromList(body).asUnmodifiableView();
}

bool _bytesEqual(Uint8List first, Uint8List second) {
  if (first.length != second.length) {
    return false;
  }
  for (var index = 0; index < first.length; index += 1) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}

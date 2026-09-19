import 'headers.dart';

bool _hasSingleContentEncoding(CassetteHeaders headers, String coding) {
  final values = headers.values('content-encoding');
  return values != null &&
      values.length == 1 &&
      values.single.trim().toLowerCase() == coding;
}

/// Whether [headers] contain exactly one identity content coding.
bool hasIdentityContentEncoding(CassetteHeaders headers) =>
    _hasSingleContentEncoding(headers, 'identity');

/// Whether [headers] contain exactly one gzip content coding.
bool hasGzipContentEncoding(CassetteHeaders headers) =>
    _hasSingleContentEncoding(headers, 'gzip');

/// Whether [headers] identify content transformed by an opaque coding.
bool hasOpaqueContentEncoding(CassetteHeaders headers) =>
    headers.contains('content-encoding') &&
    !hasIdentityContentEncoding(headers);

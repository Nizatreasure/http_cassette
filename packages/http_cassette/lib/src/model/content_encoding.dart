import 'headers.dart';

/// Whether [headers] contain exactly one identity content coding.
bool hasIdentityContentEncoding(CassetteHeaders headers) {
  final values = headers.values('content-encoding');
  return values != null &&
      values.length == 1 &&
      values.single.trim().toLowerCase() == 'identity';
}

/// Whether [headers] identify content transformed by an opaque coding.
bool hasOpaqueContentEncoding(CassetteHeaders headers) =>
    headers.contains('content-encoding') &&
    !hasIdentityContentEncoding(headers);

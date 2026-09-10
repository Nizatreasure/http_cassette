import 'package:dio/dio.dart';
import 'package:http_cassette/http_cassette.dart';

/// Creates a canonical request from `dio` metadata and buffered [body].
CassetteRequest canonicaliseDioRequest(
  RequestOptions options,
  List<int> body,
) =>
    CassetteRequest(
      method: options.method,
      uri: options.uri.removeFragment(),
      headers: CassetteHeaders(_translateDioHeaders(options.headers)),
      body: body,
    );

Map<String, List<String>> _translateDioHeaders(
  Map<String, dynamic> headers,
) {
  final valuesByName = <String, List<String>>{};
  for (final entry in headers.entries) {
    final Object? value = entry.value;
    if (value == null) {
      continue;
    }
    valuesByName[entry.key] = value is List<Object?>
        ? <String>[for (final element in value) '$element']
        : <String>['$value'];
  }
  return valuesByName;
}

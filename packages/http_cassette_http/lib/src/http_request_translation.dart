import 'package:http/http.dart' as http;
import 'package:http_cassette/http_cassette.dart';

/// Creates a canonical request from HTTP [request] metadata and buffered bytes.
///
/// `package:http` exposes request headers as one string per field. This
/// translation preserves each exposed string as one canonical value and does
/// not attempt to infer earlier repeated-field boundaries.
CassetteRequest canonicaliseHttpRequest(
  http.BaseRequest request,
  List<int> body,
) =>
    CassetteRequest(
      method: request.method,
      uri: request.url.removeFragment(),
      headers: CassetteHeaders(<String, Iterable<String>>{
        for (final entry in request.headers.entries)
          entry.key: <String>[entry.value],
      }),
      body: body,
    );

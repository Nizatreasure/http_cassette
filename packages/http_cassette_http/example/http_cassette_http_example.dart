import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette_http/http_cassette_http.dart';

Future<void> main() async {
  final engine = CassetteEngine(store: MemoryCassetteStore());
  final transport = _ExampleClient();
  final client = CassetteHttpClient(engine, inner: transport);

  final response = await client.get(Uri.parse('https://example.test/status'));

  if (response.statusCode != 200 || response.body != 'Available') {
    throw StateError('Inactive HTTP traffic was not preserved.');
  }

  client.close();
  if (transport.closeCount != 1) {
    throw StateError('The wrapped client was not closed exactly once.');
  }
}

final class _ExampleClient extends http.BaseClient {
  var closeCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream<List<int>>.value('Available'.codeUnits),
        200,
        request: request,
        headers: <String, String>{'content-type': 'text/plain'},
      );

  @override
  void close() {
    closeCount += 1;
  }
}

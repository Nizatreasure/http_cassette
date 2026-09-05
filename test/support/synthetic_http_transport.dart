import 'package:http/http.dart' as http;

final class SyntheticHttpTransport extends http.BaseClient {
  SyntheticHttpTransport(this.responseBody);

  String responseBody;
  var sendCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sendCount += 1;
    return http.StreamedResponse(
      Stream<List<int>>.value(responseBody.codeUnits),
      201,
      request: request,
      reasonPhrase: 'Created',
      headers: const <String, String>{'content-type': 'text/plain'},
    );
  }
}

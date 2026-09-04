import 'dart:convert';

import 'package:http_cassette/http_cassette.dart';

final class TransportEquivalenceFixture {
  static final uri = Uri.parse(
    'https://example.test/items?category=book&category=guide',
  );

  static const method = 'POST';
  static const requestBodyText = '{"name":"cassette"}';
  static const responseBodyText = '{"id":1}';

  static const requestHeaders = <String, String>{
    'accept': 'application/json',
    'content-type': 'application/json',
  };

  static const responseHeaders = <String, String>{
    'content-type': 'application/json',
  };

  static List<int> get requestBody => utf8.encode(requestBodyText);

  static List<int> get responseBody => utf8.encode(responseBodyText);

  static Map<String, Object?> recordedRequest(CassetteSnapshot snapshot) {
    final document = jsonDecode(utf8.decode(snapshot.bytes)) as Map;
    final interactions = document['interactions'] as List;
    final interaction = interactions.single as Map;
    return Map<String, Object?>.from(interaction['request'] as Map);
  }
}

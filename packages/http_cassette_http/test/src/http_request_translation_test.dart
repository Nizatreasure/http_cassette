import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_cassette_http/src/http_request_translation.dart';
import 'package:test/test.dart';

void main() {
  test('canonicalises visible request metadata and supplied bytes', () {
    final body = Uint8List.fromList(<int>[0, 127, 255]);
    final request = http.Request(
      'patch',
      Uri.parse('https://example.test/items?tag=one&tag=two'),
    )..headers.addAll(<String, String>{
        'X-Trace': 'first, second',
        'Accept': 'application/json',
      });

    final canonical = canonicaliseHttpRequest(request, body);
    body[0] = 42;
    request.headers['x-trace'] = 'changed';

    expect(canonical.method, 'PATCH');
    expect(
      canonical.uri,
      Uri.parse('https://example.test/items?tag=one&tag=two'),
    );
    expect(canonical.headers.names, <String>['accept', 'x-trace']);
    expect(
      canonical.headers.values('Accept'),
      <String>['application/json'],
    );
    expect(canonical.headers.values('x-trace'), <String>['first, second']);
    expect(canonical.body, <int>[0, 127, 255]);
    expect(request.finalized, isFalse);
  });

  test('removes the request URI fragment', () {
    final request = http.Request(
      'GET',
      Uri.parse('https://example.test/items#private-fragment'),
    );

    final canonical = canonicaliseHttpRequest(request, const <int>[]);

    expect(canonical.uri, Uri.parse('https://example.test/items'));
    expect(canonical.uri.hasFragment, isFalse);
  });

  test('does not invent content-length as a canonical header', () {
    final request = http.StreamedRequest(
      'POST',
      Uri.parse('https://example.test/items'),
    )..contentLength = 3;

    final canonical = canonicaliseHttpRequest(request, <int>[1, 2, 3]);

    expect(canonical.headers.contains('content-length'), isFalse);
  });

  test('rejects invalid canonical request metadata locally', () {
    final relative = http.Request('GET', Uri.parse('/relative'));
    final invalidHeader = http.Request(
      'GET',
      Uri.parse('https://example.test/items'),
    )..headers['invalid header'] = 'value';

    expect(
      () => canonicaliseHttpRequest(relative, const <int>[]),
      throwsArgumentError,
    );
    expect(
      () => canonicaliseHttpRequest(invalidHeader, const <int>[]),
      throwsArgumentError,
    );
  });
}

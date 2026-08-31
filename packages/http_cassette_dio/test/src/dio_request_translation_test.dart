import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http_cassette_dio/src/dio_request_translation.dart';
import 'package:test/test.dart';

void main() {
  test('canonicalises effective request metadata and supplied bytes', () {
    final body = Uint8List.fromList(<int>[0, 127, 255]);
    final repeatedHeaderValues = <String>['first', 'second'];
    final options = RequestOptions(
      baseUrl: 'https://example.test/api/',
      path: 'items',
      method: 'patch',
      queryParameters: <String, Object?>{
        'tag': <String>['one', 'two'],
      },
      headers: <String, Object?>{
        'X-Trace': repeatedHeaderValues,
        'Accept': 'application/json',
        'X-Omitted': null,
      },
    );

    final request = canonicaliseDioRequest(options, body);
    body[0] = 42;
    repeatedHeaderValues[0] = 'changed';

    expect(request.method, 'PATCH');
    expect(
      request.uri,
      Uri.parse('https://example.test/api/items?tag=one&tag=two'),
    );
    expect(request.headers.names, <String>['accept', 'x-trace']);
    expect(request.headers.values('Accept'), <String>['application/json']);
    expect(request.headers.values('x-trace'), <String>['first', 'second']);
    expect(request.headers.contains('x-omitted'), isFalse);
    expect(request.body, <int>[0, 127, 255]);
  });

  test('removes a fragment from the effective request URI', () {
    final options = RequestOptions(
      baseUrl: 'https://example.test/',
      path: 'items#private-fragment',
    );

    final request = canonicaliseDioRequest(options, const <int>[]);

    expect(request.uri, Uri.parse('https://example.test/items'));
    expect(request.uri.hasFragment, isFalse);
  });

  test('rejects invalid canonical request metadata locally', () {
    final options = RequestOptions(
      path: '/relative',
      headers: <String, Object?>{'invalid header': 'value'},
    );

    expect(
      () => canonicaliseDioRequest(options, const <int>[]),
      throwsArgumentError,
    );
  });
}

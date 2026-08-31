import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http_cassette_dio/src/dio_byte_stream_buffer.dart';
import 'package:http_cassette_dio/src/dio_response_translation.dart';
import 'package:test/test.dart';

void main() {
  test('captures canonical and equivalent Dio response forms', () async {
    final redirects = <RedirectRecord>[
      RedirectRecord(
        302,
        'GET',
        Uri.parse('https://example.test/final'),
      ),
    ];
    final headers = <String, List<String>>{
      'X-Trace': <String>['first', 'second'],
    };
    final response = ResponseBody(
      Stream<Uint8List>.fromIterable(<Uint8List>[
        Uint8List.fromList(<int>[1]),
        Uint8List.fromList(<int>[2, 3]),
      ]),
      206,
      statusMessage: 'Partial Content',
      isRedirect: true,
      redirects: redirects,
      headers: headers,
    )..extra = <String, Object?>{'transport': 'metadata'};

    final result = await captureDioResponse(
      response,
      maximumBytes: 3,
    );

    expect(result.canonicalResponse.statusCode, 206);
    expect(result.canonicalResponse.reasonPhrase, 'Partial Content');
    expect(
      result.canonicalResponse.headers.values('x-trace'),
      <String>['first', 'second'],
    );
    expect(result.canonicalResponse.body, <int>[1, 2, 3]);

    final replacement = result.replacementResponse;
    expect(replacement.statusCode, 206);
    expect(replacement.statusMessage, 'Partial Content');
    expect(replacement.isRedirect, isTrue);
    expect(replacement.redirects, same(redirects));
    expect(replacement.headers, same(headers));
    expect(replacement.extra, same(response.extra));
    expect(
      await replacement.stream.expand((chunk) => chunk).toList(),
      <int>[1, 2, 3],
    );
  });

  test('treats an empty status message as an absent canonical reason',
      () async {
    final response = ResponseBody.fromBytes(
      const <int>[],
      204,
      statusMessage: '',
    );

    final result = await captureDioResponse(
      response,
      maximumBytes: 1,
    );

    expect(result.canonicalResponse.reasonPhrase, isNull);
    expect(result.replacementResponse.statusMessage, '');
  });

  test('enforces the response limit while capturing', () async {
    final response = ResponseBody.fromBytes(<int>[1, 2, 3], 200);

    await expectLater(
      captureDioResponse(response, maximumBytes: 2),
      throwsA(isA<DioByteStreamLimitExceeded>()),
    );
  });
}

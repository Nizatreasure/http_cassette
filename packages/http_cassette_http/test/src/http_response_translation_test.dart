import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette_http/src/http_byte_stream_buffer.dart';
import 'package:http_cassette_http/src/http_response_translation.dart';
import 'package:test/test.dart';

void main() {
  final callerRequest = http.Request(
    'GET',
    Uri.parse('https://example.test/items'),
  );

  test('captures canonical and caller-equivalent response forms', () async {
    var listenCount = 0;
    final transportRequest = http.Request(
      'GET',
      Uri.parse('https://example.test/internal'),
    );
    final response = http.StreamedResponse(
      Stream<List<int>>.multi((controller) {
        listenCount += 1;
        controller
          ..add(<int>[1])
          ..add(<int>[2, 3]);
        unawaited(controller.close());
      }, isBroadcast: false),
      206,
      contentLength: 3,
      request: transportRequest,
      headers: <String, String>{
        'x-trace': 'first, second',
        'set-cookie':
            'id=one; Expires=Wed, 21 Oct 2015 07:28:00 GMT,session=two',
      },
      isRedirect: true,
      persistentConnection: false,
      reasonPhrase: 'Partial Content',
    );

    final captured = await captureHttpResponse(
      response,
      request: callerRequest,
      maximumBytes: 3,
    );

    expect(listenCount, 1);
    expect(captured.canonicalResponse.statusCode, 206);
    expect(captured.canonicalResponse.reasonPhrase, 'Partial Content');
    expect(
      captured.canonicalResponse.headers.values('x-trace'),
      <String>['first', 'second'],
    );
    expect(
      captured.canonicalResponse.headers.values('set-cookie'),
      <String>[
        'id=one; Expires=Wed, 21 Oct 2015 07:28:00 GMT',
        'session=two',
      ],
    );
    expect(captured.canonicalResponse.body, <int>[1, 2, 3]);

    final replacement = captured.replacementResponse;
    expect(replacement.statusCode, 206);
    expect(replacement.contentLength, 3);
    expect(replacement.request, same(callerRequest));
    expect(replacement.headers, response.headers);
    expect(replacement.headers, isNot(same(response.headers)));
    expect(replacement.isRedirect, isTrue);
    expect(replacement.persistentConnection, isFalse);
    expect(replacement.reasonPhrase, 'Partial Content');
    expect(await replacement.stream.toBytes(), <int>[1, 2, 3]);
  });

  test('preserves an exposed final URL only on the live replacement', () async {
    final finalUrl = Uri.parse('https://example.test/final');
    final response = _UrlStreamedResponse(
      const Stream<List<int>>.empty(),
      200,
      url: finalUrl,
    );

    final captured = await captureHttpResponse(
      response,
      request: callerRequest,
      maximumBytes: 1,
    );

    expect(captured.replacementResponse, isA<http.BaseResponseWithUrl>());
    expect(
      (captured.replacementResponse as http.BaseResponseWithUrl).url,
      finalUrl,
    );
  });

  test('retains an empty live reason but omits it canonically', () async {
    final response = http.StreamedResponse(
      const Stream<List<int>>.empty(),
      204,
      reasonPhrase: '',
    );

    final captured = await captureHttpResponse(
      response,
      request: callerRequest,
      maximumBytes: 1,
    );

    expect(captured.canonicalResponse.reasonPhrase, isNull);
    expect(captured.replacementResponse.reasonPhrase, '');
  });

  test('rejects an oversized declared response before listening', () async {
    var wasListened = false;
    final response = http.StreamedResponse(
      Stream<List<int>>.multi((controller) {
        wasListened = true;
        unawaited(controller.close());
      }),
      200,
      contentLength: 3,
    );

    await expectLater(
      captureHttpResponse(
        response,
        request: callerRequest,
        maximumBytes: 2,
      ),
      throwsA(isA<HttpByteStreamLimitExceeded>()),
    );
    expect(wasListened, isFalse);
  });

  test('preserves a response stream failure for later safe mapping', () async {
    final failure = StateError('stream failed');
    final response = http.StreamedResponse(
      Stream<List<int>>.error(failure),
      200,
    );

    await expectLater(
      captureHttpResponse(
        response,
        request: callerRequest,
        maximumBytes: 1,
      ),
      throwsA(same(failure)),
    );
  });

  test('reconstructs a canonical response without transport-only metadata',
      () async {
    final canonical = CassetteResponse(
      statusCode: 503,
      reasonPhrase: 'Service Unavailable',
      headers: CassetteHeaders(<String, List<String>>{
        'content-length': <String>['3'],
        'set-cookie': <String>[
          'first=1; Expires=Wed, 21 Oct 2015 07:28:00 GMT',
          'second=2',
        ],
        'x-trace': <String>['first', 'second'],
      }),
      body: <int>[1, 2, 3],
    );

    final reconstructed = reconstructHttpResponse(
      canonical,
      request: callerRequest,
    );
    final chunk = await reconstructed.stream.single;

    expect(reconstructed.statusCode, 503);
    expect(reconstructed.reasonPhrase, 'Service Unavailable');
    expect(reconstructed.contentLength, 3);
    expect(reconstructed.request, same(callerRequest));
    expect(reconstructed.headers['x-trace'], 'first, second');
    expect(
      reconstructed.headersSplitValues['set-cookie'],
      <String>[
        'first=1; Expires=Wed, 21 Oct 2015 07:28:00 GMT',
        'second=2',
      ],
    );
    expect(reconstructed.isRedirect, isFalse);
    expect(reconstructed.persistentConnection, isTrue);
    expect(reconstructed, isNot(isA<http.BaseResponseWithUrl>()));
    expect(chunk, <int>[1, 2, 3]);

    chunk[0] = 9;
    reconstructed.headers['x-trace'] = 'changed';
    expect(canonical.body, <int>[1, 2, 3]);
    expect(canonical.headers.values('x-trace'), <String>['first', 'second']);
  });

  test('does not invent content length from replay body bytes', () {
    final canonical = CassetteResponse(
      statusCode: 200,
      body: <int>[1, 2, 3],
    );

    final reconstructed = reconstructHttpResponse(
      canonical,
      request: callerRequest,
    );

    expect(reconstructed.contentLength, isNull);
  });

  test('ignores an unusable persisted content-length value', () {
    final cases = <List<String>>[
      <String>['invalid'],
      <String>['-1'],
      <String>['1', '2'],
    ];

    for (final values in cases) {
      final canonical = CassetteResponse(
        statusCode: 200,
        headers: CassetteHeaders(<String, List<String>>{
          'content-length': values,
        }),
      );

      final reconstructed = reconstructHttpResponse(
        canonical,
        request: callerRequest,
      );

      expect(reconstructed.contentLength, isNull);
    }
  });
}

final class _UrlStreamedResponse extends http.StreamedResponse
    implements http.BaseResponseWithUrl {
  _UrlStreamedResponse(
    super.stream,
    super.statusCode, {
    required this.url,
  });

  @override
  final Uri url;
}

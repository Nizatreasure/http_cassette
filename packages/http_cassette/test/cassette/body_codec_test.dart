import 'dart:convert';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/body_codec.dart';
import 'package:http_cassette/src/matching/json.dart';
import 'package:test/test.dart';

void main() {
  group('preparePersistedBody', () {
    test('corrects JSON length and removes representation validators', () {
      final prepared = preparePersistedBody(
        CassetteHeaders(<String, Iterable<String>>{
          'content-type': <String>['application/json'],
          'content-length': <String>['999', '1000'],
          'content-md5': <String>['synthetic-md5'],
          'digest': <String>['sha-256=synthetic'],
          'content-digest': <String>['sha-256=:synthetic:'],
          'etag': <String>['W/"synthetic"'],
          'x-retained': <String>['value'],
        }),
        utf8.encode('{ "b" : 2, "a" : 1 }'),
      );

      expect(prepared.body, isA<PersistedJsonBody>());
      expect(utf8.decode(prepared.body.reconstruct()), '{"a":1,"b":2}');
      expect(prepared.headers.values('content-length'), <String>['13']);
      expect(prepared.headers.contains('content-md5'), isFalse);
      expect(prepared.headers.contains('digest'), isFalse);
      expect(prepared.headers.contains('content-digest'), isFalse);
      expect(prepared.headers.contains('etag'), isFalse);
      expect(prepared.headers.values('x-retained'), <String>['value']);
      expect(
        prepared.changedHeaderNames,
        <String>{
          'content-digest',
          'content-length',
          'content-md5',
          'digest',
          'etag',
        },
      );
    });

    test('does not add an absent content-length header', () {
      final headers = _headers(contentType: 'text/plain');

      final prepared = preparePersistedBody(headers, utf8.encode('text'));

      expect(prepared.headers, same(headers));
      expect(prepared.headers.contains('content-length'), isFalse);
      expect(prepared.changedHeaderNames, isEmpty);
    });

    test('retains content encoding with opaque Base64 bytes', () {
      final headers = _headers(
        contentType: 'application/json',
        contentEncoding: 'gzip',
      );

      final prepared = preparePersistedBody(headers, <int>[0x1f, 0x8b]);

      expect(prepared.body, isA<PersistedBase64Body>());
      expect(prepared.headers.values('content-encoding'), <String>['gzip']);
      expect(prepared.changedHeaderNames, isEmpty);
    });

    test('removes content encoding from an empty body', () {
      final prepared = preparePersistedBody(
        CassetteHeaders(<String, Iterable<String>>{
          'content-encoding': <String>['gzip'],
          'content-length': <String>['12'],
        }),
        const <int>[],
      );

      expect(prepared.body, isA<PersistedEmptyBody>());
      expect(prepared.headers.contains('content-encoding'), isFalse);
      expect(prepared.headers.values('content-length'), <String>['0']);
      expect(
        prepared.changedHeaderNames,
        <String>{'content-encoding', 'content-length'},
      );
    });

    test('reports immutable names for request matching exclusions', () {
      final prepared = preparePersistedBody(
        CassetteHeaders(<String, Iterable<String>>{
          'etag': <String>['"strong"'],
        }),
        utf8.encode('body'),
      );

      final exclusions = MatchingExclusions(
        headers: prepared.changedHeaderNames,
      );

      expect(exclusions.headers, <String>{'etag'});
      expect(
        () => prepared.changedHeaderNames.add('another'),
        throwsUnsupportedError,
      );
    });
  });

  group('selectPersistedBody', () {
    test('selects empty before every other representation', () {
      final body = selectPersistedBody(
        _headers(
          contentType: 'application/json',
          contentEncoding: 'gzip',
        ),
        const <int>[],
      );

      expect(body, isA<PersistedEmptyBody>());
    });

    test('forces non-empty content-encoded bytes to Base64', () {
      final source = utf8.encode('{"valid":true}');
      final body = selectPersistedBody(
        _headers(
          contentType: 'application/json',
          contentEncoding: 'gzip',
        ),
        source,
      );

      expect(body, isA<PersistedBase64Body>());
      expect(body.reconstruct(), source);
    });

    test('selects valid media-type JSON before readable text', () {
      final body = selectPersistedBody(
        _headers(contentType: 'application/json'),
        utf8.encode('{ "b" : 2, "a" : 1 }'),
      );

      expect(body, isA<PersistedJsonBody>());
      expect(utf8.decode(body.reconstruct()), '{"a":1,"b":2}');
    });

    test('selects readable UTF-8 independently of media type', () {
      for (final headers in <CassetteHeaders>[
        _headers(contentType: 'text/plain'),
        _headers(contentType: 'application/octet-stream'),
        _headers(contentType: 'application/json'),
      ]) {
        final body = selectPersistedBody(
          headers,
          utf8.encode('readable but not JSON'),
        );

        expect(body, isA<PersistedTextBody>());
        expect(utf8.decode(body.reconstruct()), 'readable but not JSON');
      }
    });

    test('selects Base64 for invalid UTF-8, controls and a byte-order mark',
        () {
      final cases = <List<int>>[
        <int>[0xff],
        utf8.encode('before\u0000after'),
        utf8.encode('\uFEFFtext'),
      ];

      for (final source in cases) {
        final body = selectPersistedBody(const CassetteHeaders.empty(), source);

        expect(body, isA<PersistedBase64Body>());
        expect(body.reconstruct(), source);
      }
    });

    test('validates and defensively copies input bytes', () {
      final source = <int>[0xff, 0x00];
      final body = selectPersistedBody(const CassetteHeaders.empty(), source);

      source[0] = 0;

      expect(body.reconstruct(), <int>[0xff, 0x00]);
      expect(
        () => selectPersistedBody(
          const CassetteHeaders.empty(),
          <int>[256],
        ),
        throwsArgumentError,
      );
    });
  });

  group('PersistedEmptyBody', () {
    test('reconstructs immutable zero bytes', () {
      const body = PersistedEmptyBody();

      expect(body.reconstruct(), isEmpty);
      expect(() => body.reconstruct().add(1), throwsUnsupportedError);
      expect(body, const PersistedEmptyBody());
    });
  });

  group('PersistedJsonBody', () {
    test('reconstructs compact JSON with recursively sorted object keys', () {
      final body = PersistedJsonBody(
        _parseJson('{"z":1,"nested":{"b":2,"a":3},"a":[true,null]}'),
      );

      expect(
        utf8.decode(body.reconstruct()),
        '{"a":[true,null],"nested":{"a":3,"b":2},"z":1}',
      );
      expect(() => body.reconstruct().add(1), throwsUnsupportedError);
    });

    test('supports every JSON root category', () {
      for (final source in <String>[
        '{}',
        '[]',
        '"text"',
        '1.25e2',
        'true',
        'null',
      ]) {
        final body = PersistedJsonBody(_parseJson(source));

        expect(utf8.decode(body.reconstruct()), source);
      }
    });

    test('copies nested collections and exposes immutable content', () {
      final nested = <Object?>['secret'];
      final source = <String, Object?>{'value': nested};
      final body = PersistedJsonBody(source);

      nested[0] = 'changed';
      source['added'] = true;

      expect(utf8.decode(body.reconstruct()), '{"value":["secret"]}');
      final content = body.content! as Map<String, Object?>;
      expect(() => content['other'] = false, throwsUnsupportedError);
      expect(
        () => (content['value']! as List<Object?>).add(false),
        throwsUnsupportedError,
      );
    });

    test('rejects values outside the strict parsed representation', () {
      expect(() => PersistedJsonBody(1), throwsArgumentError);
      expect(
        () => PersistedJsonBody(<String, Object?>{'value': 1.5}),
        throwsArgumentError,
      );
    });

    test('uses canonical structural equality and matching hash codes', () {
      final first = PersistedJsonBody(_parseJson('{"b":2,"a":1}'));
      final second = PersistedJsonBody(_parseJson('{"a":1,"b":2}'));

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });
  });

  group('PersistedTextBody', () {
    test('reconstructs readable text as exact UTF-8', () {
      final body = PersistedTextBody('Hello, café!\tNext line\n');

      expect(body.content, 'Hello, café!\tNext line\n');
      expect(body.reconstruct(), utf8.encode(body.content));
      expect(() => body.reconstruct().add(1), throwsUnsupportedError);
    });

    test('rejects disallowed controls and a leading byte-order mark', () {
      for (final content in <String>['before\u0000after', '\uFEFFtext']) {
        expect(
          () => PersistedTextBody(content),
          throwsArgumentError,
          reason: content.codeUnits.toString(),
        );
      }
    });

    test('rejects unpaired UTF-16 surrogates', () {
      for (final content in <String>['\uD800', '\uDC00', '\uD800x']) {
        expect(
          () => PersistedTextBody(content),
          throwsArgumentError,
          reason: content.codeUnits.toString(),
        );
      }
    });

    test('uses structural equality and matching hash codes', () {
      final first = PersistedTextBody('same');
      final second = PersistedTextBody('same');

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });
  });

  group('PersistedBase64Body', () {
    test('stores canonical padded Base64 and reconstructs exact bytes', () {
      final source = <int>[0, 1, 2, 255];
      final body = PersistedBase64Body.fromBytes(source);

      source[0] = 99;

      expect(body.content, 'AAEC/w==');
      expect(body.reconstruct(), <int>[0, 1, 2, 255]);
      expect(() => body.reconstruct().add(1), throwsUnsupportedError);
    });

    test('rejects values outside the byte range', () {
      for (final bytes in <List<int>>[
        <int>[-1],
        <int>[256],
      ]) {
        expect(
          () => PersistedBase64Body.fromBytes(bytes),
          throwsArgumentError,
        );
      }
    });

    test('uses structural equality and matching hash codes', () {
      final first = PersistedBase64Body.fromBytes(<int>[1, 2, 3]);
      final second = PersistedBase64Body.fromBytes(<int>[1, 2, 3]);

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });
  });
}

Object? _parseJson(String source) {
  final result = parseJsonBody(
    CassetteHeaders(<String, Iterable<String>>{
      'content-type': <String>['application/json'],
    }),
    utf8.encode(source),
  );
  expect(result.status, JsonBodyStatus.valid);
  return result.value;
}

CassetteHeaders _headers({
  String? contentType,
  String? contentEncoding,
}) =>
    CassetteHeaders(<String, Iterable<String>>{
      if (contentType != null) 'content-type': <String>[contentType],
      if (contentEncoding != null)
        'content-encoding': <String>[contentEncoding],
    });

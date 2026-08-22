import 'dart:convert';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/body_codec.dart';
import 'package:http_cassette/src/matching/json.dart';
import 'package:test/test.dart';

void main() {
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

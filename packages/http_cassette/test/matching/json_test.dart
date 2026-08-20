import 'dart:convert';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/matching/json.dart';
import 'package:test/test.dart';

void main() {
  group('parseJsonBody', () {
    test('accepts application/json case-insensitively with parameters', () {
      final result = _parse(
        ' {"answer": 42} ',
        contentType: 'Application/JSON; Charset=UTF-8',
      );

      expect(result.status, JsonBodyStatus.valid);
      final value = result.value! as Map<String, Object?>;
      expect((value['answer']! as ParsedJsonNumber).source, '42');
    });

    test('accepts application subtypes ending in +json', () {
      expect(
        _parse('true', contentType: 'application/problem+json').status,
        JsonBodyStatus.valid,
      );
      expect(
        _parse('true', contentType: 'APPLICATION/VND.API+JSON').status,
        JsonBodyStatus.valid,
      );
      expect(
        _parse('true', contentType: 'image/example+json').status,
        JsonBodyStatus.valid,
      );
    });

    test('does not classify other media types as JSON', () {
      for (final contentType in <String>[
        'text/json',
        'application/+json',
        'application/json-seq',
        'application/problem+xml',
        'not a media type',
      ]) {
        expect(
          _parse('{"valid":true}', contentType: contentType).status,
          JsonBodyStatus.notJsonMediaType,
          reason: contentType,
        );
      }
    });

    test('requires one unambiguous content-type value', () {
      final result = parseJsonBody(
        CassetteHeaders(<String, Iterable<String>>{
          'content-type': <String>['application/json', 'application/json'],
        }),
        utf8.encode('true'),
      );

      expect(result.status, JsonBodyStatus.notJsonMediaType);
    });

    test('accepts every JSON root type', () {
      for (final source in <String>[
        '{}',
        '[]',
        '"value"',
        '42',
        'true',
        'false',
        'null',
      ]) {
        expect(_parse(source).status, JsonBodyStatus.valid, reason: source);
      }
      expect(_parse('null').value, isNull);
    });

    test('retains JSON number spelling without precision loss', () {
      for (final source in <String>[
        '9007199254740993',
        '1.0000000000000000001',
        '-2.5e+9999',
      ]) {
        final result = _parse(source);

        expect(result.status, JsonBodyStatus.valid);
        expect((result.value! as ParsedJsonNumber).source, source);
      }
    });

    test('rejects invalid UTF-8 before parsing', () {
      final result = parseJsonBody(
        _jsonHeaders(),
        <int>[0xc3, 0x28],
      );

      expect(result.status, JsonBodyStatus.invalidUtf8);
      expect(result.value, isNull);
    });

    test('rejects malformed and incomplete JSON', () {
      for (final source in <String>[
        '',
        '{',
        '{"value":}',
        '[1,]',
        'true false',
        '01',
        '"unterminated',
      ]) {
        expect(
          _parse(source).status,
          JsonBodyStatus.malformedJson,
          reason: source,
        );
      }
    });

    test('detects duplicate decoded object members at every depth', () {
      for (final source in <String>[
        '{"name":1,"name":2}',
        '{"name":1,"\\u006eame":2}',
        '{"outer":{"name":1,"name":2}}',
        '[{"name":1,"name":2}]',
      ]) {
        expect(
          _parse(source).status,
          JsonBodyStatus.duplicateObjectMember,
          reason: source,
        );
      }
    });

    test('keeps object names case-sensitive', () {
      expect(
        _parse('{"name":1,"Name":2}').status,
        JsonBodyStatus.valid,
      );
    });

    test('returns deeply immutable arrays and objects', () {
      final result = _parse('{"items":[{"value":1}]}');
      final root = result.value! as Map<String, Object?>;
      final items = root['items']! as List<Object?>;
      final item = items.single! as Map<String, Object?>;

      expect(() => root['other'] = true, throwsUnsupportedError);
      expect(() => items.add(null), throwsUnsupportedError);
      expect(() => item['value'] = 2, throwsUnsupportedError);
    });
  });
}

JsonBodyParseResult _parse(
  String source, {
  String contentType = 'application/json',
}) =>
    parseJsonBody(
      _jsonHeaders(contentType),
      utf8.encode(source),
    );

CassetteHeaders _jsonHeaders([String value = 'application/json']) =>
    CassetteHeaders(<String, Iterable<String>>{
      'content-type': <String>[value],
    });

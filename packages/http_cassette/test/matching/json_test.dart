import 'dart:convert';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/matching/exclusions.dart';
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

  group('compareJsonValues', () {
    test('ignores object member order and formatting whitespace', () {
      final result = _compare(
        '{"first": 1, "nested": {"enabled": true}}',
        '{"nested":{"enabled":true},"first":1.0}',
      );

      expect(result.matches, isTrue);
      expect(result.differences, isEmpty);
    });

    test('compares arbitrary-size numbers by numeric value', () {
      for (final pair in <(String, String)>[
        ('1', '1.0'),
        ('1e0', '0.10e1'),
        ('-0', '0.000e999999999999999999999'),
        ('9007199254740993000', '9.007199254740993e18'),
      ]) {
        expect(_compare(pair.$1, pair.$2).matches, isTrue, reason: '$pair');
      }

      expect(
        _compare('9007199254740992', '9007199254740993').matches,
        isFalse,
      );
      expect(_compare('-1', '1').matches, isFalse);
    });

    test('preserves array order and reports reordered values once', () {
      final result = _compare('[1, {"value": 2}, 3]', '[3, 1, {"value": 2}]');

      _expectDifferences(result, <(String, JsonDifferenceKind)>[
        ('', JsonDifferenceKind.differentOrder),
      ]);
    });

    test('reports deterministic object differences in lexical order', () {
      final result = _compare(
        '{"z":1,"nested":{"kind":"old"},"missing":true,"typed":1}',
        '{"a":2,"nested":{"kind":"new"},"typed":"1"}',
      );

      _expectDifferences(result, <(String, JsonDifferenceKind)>[
        ('/a', JsonDifferenceKind.extra),
        ('/missing', JsonDifferenceKind.missing),
        ('/nested/kind', JsonDifferenceKind.differentValue),
        ('/typed', JsonDifferenceKind.differentType),
        ('/z', JsonDifferenceKind.missing),
      ]);
    });

    test('escapes JSON Pointer tokens', () {
      final result = _compare(
        '{"a/b":{"m~n":true}}',
        '{"a/b":{"m~n":false}}',
      );

      _expectDifferences(result, <(String, JsonDifferenceKind)>[
        ('/a~1b/m~0n', JsonDifferenceKind.differentValue),
      ]);
    });

    test('reports array length and positions in numeric order', () {
      final result = _compare('[0,1,2]', '[0,false,2,3,4]');

      _expectDifferences(result, <(String, JsonDifferenceKind)>[
        ('', JsonDifferenceKind.differentLength),
        ('/1', JsonDifferenceKind.differentType),
        ('/3', JsonDifferenceKind.extra),
        ('/4', JsonDifferenceKind.extra),
      ]);
    });

    test('uses the empty pointer for a root scalar difference', () {
      _expectDifferences(
        _compare('true', 'false'),
        <(String, JsonDifferenceKind)>[
          ('', JsonDifferenceKind.differentValue),
        ],
      );
    });

    test('ignores only the value at an exact JSON Pointer', () {
      final exclusions = MatchingExclusions(
        jsonPointers: <String>{'/customer/email', '/items/0/id'},
      );
      final result = _compare(
        '{"customer":{"email":"first","role":"buyer"},'
            '"items":[{"id":1,"name":"one"}]}',
        '{"customer":{"email":"second","role":"buyer"},'
            '"items":[{"id":"different","name":"one"}]}',
        exclusions: exclusions,
      );

      expect(result.matches, isTrue);
    });

    test('requires an ignored object member to exist on both sides', () {
      final exclusions = MatchingExclusions(
        jsonPointers: <String>{'/customer/email'},
      );

      _expectDifferences(
        _compare(
          '{"customer":{"email":"first"}}',
          '{"customer":{}}',
          exclusions: exclusions,
        ),
        <(String, JsonDifferenceKind)>[
          ('/customer/email', JsonDifferenceKind.missing),
        ],
      );
    });

    test('keeps array length and positions significant when ignored', () {
      final exclusions = MatchingExclusions(jsonPointers: <String>{'/0'});

      expect(
        _compare('["first",1]', '["different",1]', exclusions: exclusions)
            .matches,
        isTrue,
      );
      _expectDifferences(
        _compare('["first"]', '[]', exclusions: exclusions),
        <(String, JsonDifferenceKind)>[
          ('', JsonDifferenceKind.differentLength),
          ('/0', JsonDifferenceKind.missing),
        ],
      );
    });

    test('ignores the complete JSON root through the empty pointer', () {
      final exclusions = MatchingExclusions(jsonPointers: <String>{''});

      expect(_compare('{"value":1}', '[false]', exclusions: exclusions).matches,
          isTrue);
    });

    test('rejects values not produced by the JSON parser', () {
      expect(
        () => compareJsonValues(1, 1),
        throwsArgumentError,
      );
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

JsonComparisonResult _compare(
  String expected,
  String actual, {
  MatchingExclusions exclusions = MatchingExclusions.none,
}) =>
    compareJsonValues(
      _parse(expected).value,
      _parse(actual).value,
      exclusions: exclusions,
    );

void _expectDifferences(
  JsonComparisonResult result,
  List<(String, JsonDifferenceKind)> expected,
) {
  expect(result.matches, isFalse);
  expect(
    result.differences
        .map((difference) => (difference.pointer, difference.kind)),
    orderedEquals(expected),
  );
}

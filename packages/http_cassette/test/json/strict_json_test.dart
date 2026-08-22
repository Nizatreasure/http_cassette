import 'package:http_cassette/src/json/strict_json.dart';
import 'package:http_cassette/src/json/value.dart';
import 'package:test/test.dart';

void main() {
  group('parseStrictJson', () {
    test('preserves object order, array order and number spelling', () {
      final value = parseStrictJson(
        '{"second":[2,1e+02],"first":true}',
      )! as Map<String, Object?>;
      final numbers = value['second']! as List<Object?>;

      expect(value.keys, <String>['second', 'first']);
      expect(
        numbers.map((number) => (number! as ParsedJsonNumber).source),
        <String>['2', '1e+02'],
      );
    });

    test('returns deeply immutable collections', () {
      final root = parseStrictJson('{"items":[{}]}')! as Map<String, Object?>;
      final items = root['items']! as List<Object?>;
      final item = items.single! as Map<String, Object?>;

      expect(() => root['other'] = true, throwsUnsupportedError);
      expect(() => items.add(null), throwsUnsupportedError);
      expect(() => item['other'] = true, throwsUnsupportedError);
    });

    test('reports a duplicate decoded member at its safe position', () {
      const source = '{\n  "name": 1,\n  "\\u006eame": 2\n}';

      expect(
        () => parseStrictJson(source),
        throwsA(
          isA<StrictJsonFormatException>()
              .having(
                (error) => error.kind,
                'kind',
                StrictJsonFailureKind.duplicateObjectMember,
              )
              .having((error) => error.line, 'line', 3)
              .having((error) => error.column, 'column', 3)
              .having(
                (error) => error.toString(),
                'safe text',
                isNot(contains('name')),
              ),
        ),
      );
    });

    test('reports malformed JSON without quoting source text', () {
      const secret = 'private-value';

      expect(
        () => parseStrictJson('{\n  "value": "$secret"\n  false\n}'),
        throwsA(
          isA<StrictJsonFormatException>()
              .having(
                (error) => error.kind,
                'kind',
                StrictJsonFailureKind.malformed,
              )
              .having((error) => error.line, 'line', 3)
              .having((error) => error.column, 'column', 3)
              .having(
                (error) => error.toString(),
                'safe text',
                isNot(contains(secret)),
              ),
        ),
      );
    });
  });
}

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/matching/headers.dart';
import 'package:test/test.dart';

void main() {
  group('NormalisedSelectedHeaders', () {
    test('ignores every header when no names are selected', () {
      final first = _selected(
        <String, Iterable<String>>{
          'accept': <String>['application/json']
        },
      );
      final second = _selected(
        <String, Iterable<String>>{
          'authorization': <String>['secret']
        },
      );

      expect(first.fields, isEmpty);
      expect(first, second);
    });

    test('selects names case-insensitively in deterministic order', () {
      final selected = _selected(
        <String, Iterable<String>>{
          'X-Version': <String>['2'],
          'Accept': <String>['application/json'],
        },
        names: <String>{'x-VERSION', 'ACCEPT'},
      );

      expect(
        selected.fields.map((field) => field.name),
        <String>['accept', 'x-version'],
      );
      expect(selected.fields.first.values, <String>['application/json']);
    });

    test('distinguishes an absent field from a present empty value', () {
      final absent = _selected(
        const <String, Iterable<String>>{},
        names: <String>{'x-value'},
      );
      final empty = _selected(
        <String, Iterable<String>>{
          'x-value': <String>[''],
        },
        names: <String>{'x-value'},
      );

      expect(absent.fields.single.values, isNull);
      expect(empty.fields.single.values, <String>['']);
      expect(absent, isNot(empty));
    });

    test('trims surrounding spaces and horizontal tabs', () {
      expect(
        _selected(
          <String, Iterable<String>>{
            'accept': <String>[' \tapplication/json\t '],
          },
          names: <String>{'accept'},
        ).fields.single.values,
        <String>['application/json'],
      );
    });

    test('preserves internal whitespace and value case', () {
      final first = _selected(
        <String, Iterable<String>>{
          'x-value': <String>['one  two', 'Value'],
        },
        names: <String>{'x-value'},
      );

      expect(first.fields.single.values, <String>['one  two', 'Value']);
      expect(
        first,
        isNot(
          _selected(
            <String, Iterable<String>>{
              'x-value': <String>['one two', 'value'],
            },
            names: <String>{'x-value'},
          ),
        ),
      );
    });

    test('preserves repeated-value order', () {
      final first = _selected(
        <String, Iterable<String>>{
          'accept': <String>['application/json', 'text/plain'],
        },
        names: <String>{'accept'},
      );
      final reversed = _selected(
        <String, Iterable<String>>{
          'accept': <String>['text/plain', 'application/json'],
        },
        names: <String>{'accept'},
      );

      expect(first, isNot(reversed));
    });

    test('does not split comma-separated values', () {
      final combined = _selected(
        <String, Iterable<String>>{
          'accept': <String>['application/json, text/plain'],
        },
        names: <String>{'accept'},
      );
      final repeated = _selected(
        <String, Iterable<String>>{
          'accept': <String>['application/json', 'text/plain'],
        },
        names: <String>{'accept'},
      );

      expect(combined, isNot(repeated));
    });

    test('rejects invalid selected names without echoing them', () {
      const unsafeName = 'x-value\r\nx-secret';

      expect(
        () => _selected(
          const <String, Iterable<String>>{},
          names: <String>{unsafeName},
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.toString(),
            'message',
            isNot(contains('x-secret')),
          ),
        ),
      );
    });

    test('does not expose mutable fields or values', () {
      final selected = _selected(
        <String, Iterable<String>>{
          'accept': <String>['application/json'],
        },
        names: <String>{'accept'},
      );

      expect(
        () => selected.fields.add(selected.fields.single),
        throwsUnsupportedError,
      );
      expect(
        () => selected.fields.single.values!.add('text/plain'),
        throwsUnsupportedError,
      );
    });
  });
}

NormalisedSelectedHeaders _selected(
  Map<String, Iterable<String>> values, {
  Set<String> names = const <String>{},
}) =>
    NormalisedSelectedHeaders.fromHeaders(
      CassetteHeaders(values),
      selectedNames: names,
    );

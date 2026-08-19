import 'package:http_cassette/http_cassette.dart';
import 'package:test/test.dart';

void main() {
  group('CassetteHeaders', () {
    test('creates an empty immutable collection', () {
      const headers = CassetteHeaders.empty();

      expect(headers.names, isEmpty);
      expect(headers.values('accept'), isNull);
      expect(headers.contains('accept'), isFalse);
      expect(headers.toMap(), isEmpty);
    });

    test('canonicalises names and supports case-insensitive lookup', () {
      final headers = CassetteHeaders(<String, Iterable<String>>{
        'Content-Type': <String>['application/json'],
      });

      expect(headers.names, <String>['content-type']);
      expect(headers.contains('CONTENT-TYPE'), isTrue);
      expect(headers.values('content-TYPE'), <String>['application/json']);
    });

    test('sorts names and preserves repeated value order', () {
      final headers = CassetteHeaders(<String, Iterable<String>>{
        'X-Trace': <String>['first'],
        'Accept': <String>['application/json', 'text/plain'],
        'x-trace': <String>['second'],
      });

      expect(headers.names, <String>['accept', 'x-trace']);
      expect(
        headers.values('accept'),
        <String>['application/json', 'text/plain'],
      );
      expect(headers.values('x-trace'), <String>['first', 'second']);
    });

    test('accepts empty values and horizontal tabs', () {
      final headers = CassetteHeaders(<String, Iterable<String>>{
        'x-empty': <String>[''],
        'x-tab': <String>['one\ttwo'],
      });

      expect(headers.values('x-empty'), <String>['']);
      expect(headers.values('x-tab'), <String>['one\ttwo']);
    });

    test('rejects invalid names without echoing them', () {
      for (final name in <String>['', 'bad name', 'bad:name', 'tést']) {
        expect(
          () => CassetteHeaders(<String, Iterable<String>>{
            name: <String>['value'],
          }),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.toString(),
              'message',
              isNot(contains(name.isEmpty ? '<empty>' : name)),
            ),
          ),
        );
      }
    });

    test('rejects fields without values', () {
      expect(
        () => CassetteHeaders(<String, Iterable<String>>{
          'accept': const <String>[],
        }),
        throwsArgumentError,
      );
    });

    test('rejects prohibited value controls without echoing the value', () {
      const unsafeValue = 'secret\r\ninjected: value';

      expect(
        () => CassetteHeaders(<String, Iterable<String>>{
          'x-value': <String>[unsafeValue],
        }),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.toString(),
            'message',
            isNot(contains('secret')),
          ),
        ),
      );
    });

    test('copies source maps and value lists defensively', () {
      final sourceValues = <String>['first'];
      final source = <String, Iterable<String>>{'x-value': sourceValues};
      final headers = CassetteHeaders(source);

      sourceValues.add('second');
      source['other'] = <String>['value'];

      expect(headers.names, <String>['x-value']);
      expect(headers.values('x-value'), <String>['first']);
    });

    test('does not expose mutable maps or lists', () {
      final headers = CassetteHeaders(<String, Iterable<String>>{
        'x-value': <String>['first'],
      });
      final values = headers.values('x-value')!;
      final map = headers.toMap();

      expect(() => values.add('second'), throwsUnsupportedError);
      expect(() => map['other'] = <String>['value'], throwsUnsupportedError);
      expect(() => map['x-value']!.add('second'), throwsUnsupportedError);
    });

    test('uses structural equality and deterministic hash codes', () {
      final first = CassetteHeaders(<String, Iterable<String>>{
        'X-Trace': <String>['one', 'two'],
        'Accept': <String>['application/json'],
      });
      final second = CassetteHeaders(<String, Iterable<String>>{
        'accept': <String>['application/json'],
        'x-trace': <String>['one', 'two'],
      });

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(
        first,
        isNot(
          CassetteHeaders(<String, Iterable<String>>{
            'accept': <String>['application/json'],
            'x-trace': <String>['two', 'one'],
          }),
        ),
      );
    });

    test('treats invalid lookup names as absent', () {
      final headers = CassetteHeaders(<String, Iterable<String>>{
        'accept': <String>['application/json'],
      });

      expect(headers.contains('bad name'), isFalse);
      expect(headers.values('bad name'), isNull);
    });
  });
}

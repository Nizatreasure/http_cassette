import 'package:http_cassette/src/matching/query.dart';
import 'package:test/test.dart';

void main() {
  group('NormalisedQuery', () {
    test('treats reordered names as equivalent', () {
      expect(
        _query('?page=2&tag=dart&tag=http'),
        _query('?tag=dart&tag=http&page=2'),
      );
    });

    test('sorts groups and preserves repeated-value order', () {
      final query = _query('?tag=dart&page=2&tag=http');

      expect(
        query.groups.map((group) => group.name),
        <String>['page', 'tag'],
      );
      expect(
        query.groups.last.values.map((value) => value.value),
        <String>['dart', 'http'],
      );
      expect(
        query,
        isNot(_query('?tag=http&tag=dart&page=2')),
      );
    });

    test('preserves multiplicity', () {
      expect(_query('?tag=dart'), isNot(_query('?tag=dart&tag=dart')));
    });

    test('distinguishes a missing equals sign from an empty value', () {
      final missingEquals = _query('?flag');
      final emptyValue = _query('?flag=');

      expect(missingEquals, isNot(emptyValue));
      expect(missingEquals.groups.single.values.single.value, '');
      expect(missingEquals.groups.single.values.single.hasEquals, isFalse);
      expect(emptyValue.groups.single.values.single.value, '');
      expect(emptyValue.groups.single.values.single.hasEquals, isTrue);
    });

    test('keeps a literal plus distinct from an encoded space', () {
      expect(_query('?value=a+b'), isNot(_query('?value=a%20b')));
      expect(_query('?value=a+b').groups.single.values.single.value, 'a+b');
    });

    test('normalises unreserved and reserved percent escapes', () {
      expect(_query('?%6eame=%7evalue'), _query('?name=~value'));
      expect(
        _query('?name=a%2fvalue').groups.single.values.single.value,
        'a%2Fvalue',
      );
      expect(_query('?name=a%2Fvalue'), isNot(_query('?name=a/value')));
    });

    test('ignores every occurrence of exact normalised names', () {
      expect(
        _query(
          '?keep=one&request%5fid=first&request_id=second&Keep=two',
          ignoredNames: <String>{'request_id'},
        ),
        _query('?keep=one&Keep=two'),
      );
    });

    test('compares ignored names case-sensitively', () {
      final query = _query(
        '?token=one&Token=two',
        ignoredNames: <String>{'token'},
      );

      expect(query.groups.map((group) => group.name), <String>['Token']);
    });

    test('represents an absent or empty query with no groups', () {
      expect(_query('').groups, isEmpty);
      expect(_query('?').groups, isEmpty);
      expect(_query(''), _query('?'));
    });

    test('does not expose mutable groups or values', () {
      final query = _query('?tag=dart');

      expect(
        () => query.groups.add(query.groups.single),
        throwsUnsupportedError,
      );
      expect(
        () => query.groups.single.values.add(
          query.groups.single.values.single,
        ),
        throwsUnsupportedError,
      );
    });
  });
}

NormalisedQuery _query(
  String suffix, {
  Set<String> ignoredNames = const <String>{},
}) =>
    NormalisedQuery.fromUri(
      Uri.parse('https://example.test/$suffix'),
      ignoredNames: ignoredNames,
    );

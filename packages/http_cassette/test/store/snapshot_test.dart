import 'dart:convert';

import 'package:http_cassette/http_cassette.dart';
import 'package:test/test.dart';

void main() {
  group('CassetteRevision', () {
    test('uses opaque identity equality', () {
      final first = CassetteRevision();
      final second = CassetteRevision();

      expect(first, same(first));
      expect(first, isNot(second));
      expect(first.hashCode, 0);
      expect(second.hashCode, 0);
    });

    test('does not print or serialise an underlying value', () {
      final revision = CassetteRevision();

      expect(revision.toString(), 'CassetteRevision(<opaque>)');
      expect(() => jsonEncode(revision),
          throwsA(isA<JsonUnsupportedObjectError>()));
    });
  });

  group('CassetteSnapshot', () {
    test('retains its logical name and exact revision', () {
      final name = CassetteName('checkout/success');
      final revision = CassetteRevision();
      final snapshot = CassetteSnapshot(
        name: name,
        bytes: const <int>[1, 2, 3],
        revision: revision,
      );

      expect(snapshot.name, name);
      expect(snapshot.revision, same(revision));
    });

    test('copies input and exposes immutable bytes', () {
      final input = <int>[1, 2, 3];
      final snapshot = CassetteSnapshot(
        name: CassetteName('checkout'),
        bytes: input,
        revision: CassetteRevision(),
      );

      input[0] = 9;

      expect(snapshot.bytes, <int>[1, 2, 3]);
      expect(() => snapshot.bytes[0] = 9, throwsUnsupportedError);
    });

    test('rejects values outside the byte range', () {
      for (final bytes in <List<int>>[
        <int>[-1],
        <int>[256],
      ]) {
        expect(
          () => CassetteSnapshot(
            name: CassetteName('checkout'),
            bytes: bytes,
            revision: CassetteRevision(),
          ),
          throwsArgumentError,
        );
      }
    });
  });
}

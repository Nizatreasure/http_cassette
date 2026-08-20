import 'package:http_cassette/src/matching/body.dart';
import 'package:test/test.dart';

void main() {
  group('compareExactBodies', () {
    test('matches equal non-empty bodies', () {
      final result = compareExactBodies(
        <int>[0x00, 0x7f, 0xff],
        <int>[0x00, 0x7f, 0xff],
      );

      expect(result.matches, isTrue);
      expect(result.expectedLength, 3);
      expect(result.actualLength, 3);
      expect(result.expectedIsEmpty, isFalse);
      expect(result.actualIsEmpty, isFalse);
      expect(result.firstDifferenceOffset, isNull);
    });

    test('treats two zero-byte bodies as equivalent', () {
      final result = compareExactBodies(const <int>[], const <int>[]);

      expect(result.matches, isTrue);
      expect(result.expectedIsEmpty, isTrue);
      expect(result.actualIsEmpty, isTrue);
      expect(result.firstDifferenceOffset, isNull);
    });

    test('reports the first differing byte offset without byte values', () {
      final result = compareExactBodies(
        <int>[0x10, 0x20, 0x30, 0x40],
        <int>[0x10, 0x21, 0x31, 0x40],
      );

      expect(result.matches, isFalse);
      expect(result.expectedLength, 4);
      expect(result.actualLength, 4);
      expect(result.firstDifferenceOffset, 1);
    });

    test('uses the shorter length when one body is an exact prefix', () {
      final result = compareExactBodies(
        <int>[0x10, 0x20],
        <int>[0x10, 0x20, 0x30],
      );

      expect(result.matches, isFalse);
      expect(result.expectedLength, 2);
      expect(result.actualLength, 3);
      expect(result.firstDifferenceOffset, 2);
    });

    test('distinguishes an empty body from a non-empty body', () {
      final result = compareExactBodies(const <int>[], <int>[0x00]);

      expect(result.matches, isFalse);
      expect(result.expectedIsEmpty, isTrue);
      expect(result.actualIsEmpty, isFalse);
      expect(result.firstDifferenceOffset, 0);
    });

    test('does not retain mutable input lists', () {
      final expected = <int>[0x10];
      final actual = <int>[0x20, 0x30];
      final result = compareExactBodies(expected, actual);

      expected.add(0x40);
      actual.clear();

      expect(result.expectedLength, 1);
      expect(result.actualLength, 2);
      expect(result.firstDifferenceOffset, 0);
    });
  });
}

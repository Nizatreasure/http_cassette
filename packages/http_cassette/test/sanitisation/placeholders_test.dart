import 'package:http_cassette/src/matching/json.dart';
import 'package:http_cassette/src/model/headers.dart';
import 'package:http_cassette/src/sanitisation/placeholders.dart';
import 'package:test/test.dart';

void main() {
  group('placeholderForJsonScalar', () {
    test('uses one fixed placeholder for ordinary strings', () {
      expect(placeholderForJsonScalar('first'), redactedStringPlaceholder);
      expect(placeholderForJsonScalar('second'), redactedStringPlaceholder);
      expect(placeholderForJsonScalar(''), redactedStringPlaceholder);
    });

    test('recognises canonical UUID strings case-insensitively', () {
      for (final value in <String>[
        '123e4567-e89b-12d3-a456-426614174000',
        'ABCDEFAB-CDEF-ABCD-EFAB-ABCDEFABCDEF',
      ]) {
        expect(placeholderForJsonScalar(value), redactedUuidPlaceholder);
      }
      expect(
        placeholderForJsonScalar('{123e4567-e89b-12d3-a456-426614174000}'),
        redactedStringPlaceholder,
      );
    });

    test('recognises only conservative ordinary email addresses', () {
      for (final value in <String>[
        'person@example.test',
        'first.last+tag@sub.example.co.uk',
      ]) {
        expect(placeholderForJsonScalar(value), redactedEmailPlaceholder);
      }
      for (final value in <String>[
        'Person <person@example.test>',
        'person@example',
        '.person@example.test',
        'person..name@example.test',
        'person@example-.test',
      ]) {
        expect(placeholderForJsonScalar(value), redactedStringPlaceholder);
      }
    });

    test('preserves numeric, boolean and null categories', () {
      for (final source in <String>['42', '-0']) {
        final placeholder = placeholderForJsonScalar(_number(source));
        expect(placeholder, same(ParsedJsonNumber.zeroInteger));
        expect((placeholder! as ParsedJsonNumber).source, '0');
      }
      for (final source in <String>['1.5', '1e0', '-2E+3']) {
        final placeholder = placeholderForJsonScalar(_number(source));
        expect(placeholder, same(ParsedJsonNumber.zeroNonInteger));
        expect((placeholder! as ParsedJsonNumber).source, '0.0');
      }
      expect(placeholderForJsonScalar(true), isFalse);
      expect(placeholderForJsonScalar(false), isFalse);
      expect(placeholderForJsonScalar(null), isNull);
    });

    test('rejects objects and arrays', () {
      expect(
        () => placeholderForJsonScalar(<String, Object?>{}),
        throwsArgumentError,
      );
      expect(
        () => placeholderForJsonScalar(<Object?>[]),
        throwsArgumentError,
      );
    });
  });
}

ParsedJsonNumber _number(String source) {
  final result = parseJsonBody(
    CassetteHeaders(<String, Iterable<String>>{
      'content-type': <String>['application/json'],
    }),
    source.codeUnits,
  );
  expect(result.status, JsonBodyStatus.valid);
  return result.value! as ParsedJsonNumber;
}

import 'package:http_cassette/http_cassette.dart';
import 'package:test/test.dart';

void main() {
  group('CassetteName', () {
    test('accepts portable logical names', () {
      for (final value in <String>[
        'checkout_discount_expired',
        'checkout/expired-discount',
        'accounts/user.v2',
        'A-Z/a_z/0-9',
        '.hidden',
      ]) {
        expect(CassetteName(value).value, value);
      }
    });

    test('preserves case-sensitive identity', () {
      expect(CassetteName('Checkout'), isNot(CassetteName('checkout')));
    });

    test('has structural equality and matching hash codes', () {
      final first = CassetteName('checkout/expired-discount');
      final second = CassetteName('checkout/expired-discount');

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    test('rejects empty values and segments', () {
      for (final value in <String>['', '/checkout', 'checkout/', 'a//b']) {
        expect(() => CassetteName(value), throwsArgumentError);
      }
    });

    test('rejects traversal segments', () {
      for (final value in <String>['.', '..', 'a/./b', 'a/../b']) {
        expect(() => CassetteName(value), throwsArgumentError);
      }
    });

    test('rejects POSIX and Windows path forms', () {
      for (final value in <String>[
        '/absolute',
        r'C:\cassettes\checkout',
        r'C:/cassettes/checkout',
        r'\\server\share\checkout',
        r'a\b',
      ]) {
        expect(() => CassetteName(value), throwsArgumentError);
      }
    });

    test('rejects controls, encoded traversal and Unicode lookalikes', () {
      for (final value in <String>[
        'checkout\u0000name',
        'checkout\nname',
        '%2e%2e/checkout',
        'checkout/%2Fname',
        'checkout/\uFF0E\uFF0E',
        'checkout\u2215name',
      ]) {
        expect(
          () => CassetteName(value),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.toString(),
              'message',
              isNot(contains(value)),
            ),
          ),
          reason: value.codeUnits.toString(),
        );
      }
    });

    test('rejects characters outside the portable segment grammar', () {
      for (final value in <String>[
        'checkout name',
        'checkout:name',
        'checkout?name',
        'café',
      ]) {
        expect(() => CassetteName(value), throwsArgumentError);
      }
    });

    test('rejects the store-owned final JSON suffix', () {
      for (final value in <String>[
        'checkout.json',
        'accounts/checkout.json',
      ]) {
        expect(() => CassetteName(value), throwsArgumentError);
      }

      expect(CassetteName('json/checkout').value, 'json/checkout');
      expect(CassetteName('checkout.JSON').value, 'checkout.JSON');
    });
  });
}

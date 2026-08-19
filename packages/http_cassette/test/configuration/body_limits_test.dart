import 'package:http_cassette/http_cassette.dart';
import 'package:test/test.dart';

void main() {
  group('BodyLimits', () {
    test('uses the measured request and response defaults', () {
      final limits = BodyLimits();

      expect(BodyLimits.defaultRequestBytes, 2 * 1024 * 1024);
      expect(BodyLimits.defaultResponseBytes, 5 * 1024 * 1024);
      expect(limits.requestBytes, 2 * 1024 * 1024);
      expect(limits.responseBytes, 5 * 1024 * 1024);
    });

    test('accepts explicit positive overrides independently', () {
      final limits = BodyLimits(
        requestBytes: 1,
        responseBytes: 10 * 1024 * 1024,
      );

      expect(limits.requestBytes, 1);
      expect(limits.responseBytes, 10 * 1024 * 1024);
    });

    test('rejects zero request and response limits', () {
      expect(() => BodyLimits(requestBytes: 0), throwsArgumentError);
      expect(() => BodyLimits(responseBytes: 0), throwsArgumentError);
    });

    test('rejects negative request and response limits', () {
      expect(() => BodyLimits(requestBytes: -1), throwsArgumentError);
      expect(() => BodyLimits(responseBytes: -1), throwsArgumentError);
    });

    test('has structural equality and matching hash codes', () {
      final first = BodyLimits(requestBytes: 1024, responseBytes: 2048);
      final second = BodyLimits(requestBytes: 1024, responseBytes: 2048);

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(
        first,
        isNot(BodyLimits(requestBytes: 2048, responseBytes: 1024)),
      );
    });
  });
}

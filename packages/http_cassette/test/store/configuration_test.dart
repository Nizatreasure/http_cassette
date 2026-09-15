import 'package:http_cassette/http_cassette.dart';
import 'package:test/test.dart';

void main() {
  group('StoreOperationConfiguration', () {
    test('uses a 30 second default timeout', () {
      expect(
        StoreOperationConfiguration().timeout,
        const Duration(seconds: 30),
      );
    });

    test('retains a positive timeout', () {
      const timeout = Duration(milliseconds: 1);

      expect(StoreOperationConfiguration(timeout: timeout).timeout, timeout);
    });

    test('rejects a non-positive timeout', () {
      expect(
        () => StoreOperationConfiguration(timeout: Duration.zero),
        throwsArgumentError,
      );
      expect(
        () => StoreOperationConfiguration(
          timeout: const Duration(microseconds: -1),
        ),
        throwsArgumentError,
      );
    });

    test('has structural equality and matching hash codes', () {
      final first = StoreOperationConfiguration();
      final second = StoreOperationConfiguration();

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(
        first,
        isNot(
          StoreOperationConfiguration(timeout: const Duration(seconds: 31)),
        ),
      );
    });
  });
}

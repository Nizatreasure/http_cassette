import 'package:http_cassette/http_cassette.dart';
import 'package:test/test.dart';

void main() {
  group('RecordingConfiguration', () {
    test('uses a 30-second close grace period by default', () {
      final configuration = RecordingConfiguration();

      expect(
        configuration.closeGracePeriod,
        const Duration(seconds: 30),
      );
      expect(
        RecordingConfiguration.defaultCloseGracePeriod,
        const Duration(seconds: 30),
      );
    });

    test('retains an explicit positive close grace period', () {
      final configuration = RecordingConfiguration(
        closeGracePeriod: const Duration(milliseconds: 1),
      );

      expect(
        configuration.closeGracePeriod,
        const Duration(milliseconds: 1),
      );
    });

    test('rejects zero and negative close grace periods', () {
      for (final duration in <Duration>[
        Duration.zero,
        const Duration(microseconds: -1),
      ]) {
        expect(
          () => RecordingConfiguration(closeGracePeriod: duration),
          throwsArgumentError,
        );
      }
    });

    test('has structural equality and matching hash codes', () {
      final first = RecordingConfiguration(
        closeGracePeriod: const Duration(seconds: 12),
      );
      final second = RecordingConfiguration(
        closeGracePeriod: const Duration(seconds: 12),
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first, isNot(RecordingConfiguration()));
    });
  });

  group('RecordingOptions', () {
    test('rejects an existing cassette by default', () {
      const options = RecordingOptions();

      expect(options.existingCassette, ExistingCassette.fail);
    });

    test('supports explicit replacement and append choices', () {
      expect(
        const RecordingOptions(
          existingCassette: ExistingCassette.replace,
        ).existingCassette,
        ExistingCassette.replace,
      );
      expect(
        const RecordingOptions(
          existingCassette: ExistingCassette.append,
        ).existingCassette,
        ExistingCassette.append,
      );
    });

    test('has structural equality and matching hash codes', () {
      const first = RecordingOptions(
        existingCassette: ExistingCassette.append,
      );
      const second = RecordingOptions(
        existingCassette: ExistingCassette.append,
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(
        first,
        isNot(
          const RecordingOptions(
            existingCassette: ExistingCassette.replace,
          ),
        ),
      );
    });
  });

  test('ExistingCassette contains only the agreed V1 choices', () {
    expect(ExistingCassette.values, <ExistingCassette>[
      ExistingCassette.fail,
      ExistingCassette.replace,
      ExistingCassette.append,
    ]);
  });
}

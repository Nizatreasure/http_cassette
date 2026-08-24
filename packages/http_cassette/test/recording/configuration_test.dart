import 'package:http_cassette/http_cassette.dart';
import 'package:test/test.dart';

void main() {
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

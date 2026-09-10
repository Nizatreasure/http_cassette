import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/recording/active_state.dart';
import 'package:test/test.dart';

void main() {
  group('ActiveRecordingState', () {
    test('retains validated identity and fixed session configuration', () {
      final name = CassetteName('checkout/success');
      final sanitisation = SanitisationConfiguration(
        additionalHeaders: const <String>['x-project-secret'],
      );
      final options = const RecordingOptions(
        existingCassette: ExistingCassette.append,
      );
      final recording = RecordingConfiguration(
        closeGracePeriod: const Duration(seconds: 45),
      );

      final state = ActiveRecordingState(
        cassetteName: name,
        configuration: CassetteConfiguration(
          sanitisation: sanitisation,
          recording: recording,
        ),
        options: options,
      );

      expect(state.cassetteName, same(name));
      expect(state.sanitisation, same(sanitisation));
      expect(state.recording, same(recording));
      expect(state.options, same(options));
    });

    test('assigns monotonic arrival indices from zero', () {
      final state = _state('first');

      expect(state.assignArrivalIndex(), 0);
      expect(state.assignArrivalIndex(), 1);
      expect(state.assignArrivalIndex(), 2);
    });

    test('keeps arrival indices independent between sessions', () {
      final first = _state('first');
      final second = _state('second');

      expect(first.assignArrivalIndex(), 0);
      expect(first.assignArrivalIndex(), 1);
      expect(second.assignArrivalIndex(), 0);
    });
  });
}

ActiveRecordingState _state(String name) => ActiveRecordingState(
      cassetteName: CassetteName(name),
      configuration: CassetteConfiguration(),
      options: const RecordingOptions(),
    );

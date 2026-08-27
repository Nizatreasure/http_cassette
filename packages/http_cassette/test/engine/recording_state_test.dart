import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/engine/cassette_engine.dart';
import 'package:test/test.dart';

void main() {
  group('EngineState recording state', () {
    test('retains recording inputs for the active session', () async {
      final sanitisation = SanitisationConfiguration(
        additionalJsonPointers: const <String>['/credentials/token'],
      );
      final state = EngineState(
        store: MemoryCassetteStore(),
        configuration: CassetteConfiguration(sanitisation: sanitisation),
      );
      final name = CassetteName('checkout/record');
      const options = RecordingOptions();

      final session = await state.startRecording(name, options);

      expect(session.mode, CassetteMode.record);
      expect(state.activeRecording, isNotNull);
      expect(state.activeRecording!.cassetteName, same(name));
      expect(state.activeRecording!.sanitisation, same(sanitisation));
      expect(state.activeRecording!.options, same(options));
    });

    test('clears recording state after successful close', () async {
      final state = _state();
      final session = await state.startRecording(
        CassetteName('recording'),
        const RecordingOptions(),
      );

      await session.close();

      expect(state.activeRecording, isNull);
      expect(state.sessions.isActive, isFalse);
    });

    test('clears recording state after successful discard', () async {
      final state = _state();
      final session = await state.startRecording(
        CassetteName('recording'),
        const RecordingOptions(),
      );

      await session.discard();

      expect(state.activeRecording, isNull);
      expect(state.sessions.isActive, isFalse);
    });
  });
}

EngineState _state() => EngineState(
      store: MemoryCassetteStore(),
      configuration: CassetteConfiguration(),
    );

import 'package:http_cassette/http_cassette.dart';
import 'package:test/test.dart';

void main() {
  group('inactive CassetteInterception', () {
    test('requires no canonical buffering or body limits', () {
      final engine = CassetteEngine(store: MemoryCassetteStore());

      final interception = engine.beginInterception();

      expect(interception.isActive, isFalse);
      expect(interception.bodyLimits, isNull);
      expect(engine.isActive, isFalse);
      expect(engine.activeSession, isNull);
    });

    test('remains inactive when a later session starts', () async {
      final engine = CassetteEngine(store: MemoryCassetteStore());
      final interception = engine.beginInterception();

      final session = await engine.startRecording('later');

      expect(interception.isActive, isFalse);
      expect(interception.bodyLimits, isNull);
      await session.discard();
    });

    test('fails closed while active permits remain unavailable', () async {
      final engine = CassetteEngine(store: MemoryCassetteStore());
      final session = await engine.startRecording('active');

      expect(engine.beginInterception, throwsStateError);

      await session.discard();
    });

    test('is available using only the public package library', () {
      final CassetteInterception interception =
          CassetteEngine(store: MemoryCassetteStore()).beginInterception();

      expect(interception.isActive, isFalse);
    });
  });
}

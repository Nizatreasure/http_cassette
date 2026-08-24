import 'package:http_cassette/http_cassette.dart';
import 'package:test/test.dart';

void main() {
  group('CassetteEngine lifecycle shell', () {
    test('starts inactive', () {
      final engine = _engine();

      expect(engine.isActive, isFalse);
      expect(engine.activeSession, isNull);
    });

    test('starts a lifecycle-only recording session', () async {
      final engine = _engine();

      final session = await engine.startRecording(
        'checkout/declined',
        options: const RecordingOptions(
          existingCassette: ExistingCassette.append,
        ),
      );

      expect(session.name, 'checkout/declined');
      expect(session.mode, CassetteMode.record);
      expect(session.isClosed, isFalse);
      expect(engine.isActive, isTrue);
      expect(engine.activeSession, same(session));
    });

    test('starts a lifecycle-only replay session', () async {
      final engine = _engine();

      final session = await engine.startReplay(
        'checkout/success',
        options: const ReplayOptions(policy: ReplayPolicy.cycle),
      );

      expect(session.name, 'checkout/success');
      expect(session.mode, CassetteMode.replay);
      expect(engine.activeSession, same(session));
    });

    test('rejects invalid logical names without becoming active', () async {
      final engine = _engine();

      await expectLater(
        engine.startReplay('../private'),
        throwsArgumentError,
      );

      expect(engine.isActive, isFalse);
      expect(engine.activeSession, isNull);
    });

    test('rejects a second session while one remains active', () async {
      final engine = _engine();
      final active = await engine.startRecording('first');

      await expectLater(
        engine.startReplay('second'),
        throwsA(
          isA<CassetteException>().having(
            (error) => error.diagnostic.category,
            'category',
            DiagnosticCategory.conflictingSessionOperation,
          ),
        ),
      );

      expect(engine.activeSession, same(active));
    });

    test('becomes inactive after successful close', () async {
      final engine = _engine();
      final session = await engine.startReplay('example');

      await session.close();

      expect(session.isClosed, isTrue);
      expect(engine.isActive, isFalse);
      expect(engine.activeSession, isNull);
    });

    test('becomes inactive after successful discard', () async {
      final engine = _engine();
      final session = await engine.startRecording('example');

      await session.discard();

      expect(session.isClosed, isTrue);
      expect(engine.isActive, isFalse);
    });

    test('separate engines own independent active sessions', () async {
      final firstEngine = _engine();
      final secondEngine = _engine();

      final sessions = await Future.wait(<Future<CassetteSession>>[
        firstEngine.startReplay('first'),
        secondEngine.startRecording('second'),
      ]);

      expect(firstEngine.activeSession, same(sessions[0]));
      expect(secondEngine.activeSession, same(sessions[1]));
    });
  });
}

CassetteEngine _engine() => CassetteEngine(store: MemoryCassetteStore());

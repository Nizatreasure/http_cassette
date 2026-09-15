import 'dart:async';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/cassette.dart';
import 'package:http_cassette/src/cassette/encoder.dart';
import 'package:http_cassette/src/engine/cassette_engine.dart';
import 'package:test/test.dart';

void main() {
  group('CassetteEngine lifecycle shell', () {
    test('starts inactive', () {
      final engine = _engine();

      expect(engine.isActive, isFalse);
      expect(engine.activeSession, isNull);
    });

    test('starts a recording session without transport work', () async {
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

    test('loads a valid cassette before exposing a replay session', () async {
      final engine = _engine();

      final session = await engine.startReplay(
        'checkout/success',
        options: const ReplayOptions(policy: ReplayPolicy.cycle),
      );

      expect(session.name, 'checkout/success');
      expect(session.mode, CassetteMode.replay);
      expect(engine.activeSession, same(session));
    });

    test('leaves the engine inactive when replay loading fails', () async {
      final engine = CassetteEngine(store: MemoryCassetteStore());

      await expectLater(
        engine.startReplay('missing'),
        throwsA(
          isA<CassetteException>().having(
            (error) => error.diagnostic.category,
            'category',
            DiagnosticCategory.cassetteMissing,
          ),
        ),
      );

      expect(engine.isActive, isFalse);
      expect(engine.activeSession, isNull);
    });

    test('releases its reservation after an unexpected loading error',
        () async {
      final error = StateError('unexpected test failure');
      final engine = CassetteEngine(store: _ThrowingReadStore(error));

      await expectLater(engine.startReplay('broken'), throwsA(same(error)));

      expect(engine.isActive, isFalse);
      final recording = await engine.startRecording('available');
      expect(engine.activeSession, same(recording));
    });

    test('clears replay state after an unexpected startup error', () async {
      final error = StateError('unexpected test failure');
      final state = EngineState(
        store: _ThrowingReadStore(error),
        configuration: CassetteConfiguration(),
      );

      await expectLater(
        state.startReplay(CassetteName('broken'), const ReplayOptions()),
        throwsA(same(error)),
      );

      expect(state.sessions.isActive, isFalse);
      expect(state.sessions.activeSession, isNull);
      expect(state.activeReplay, isNull);
    });

    test('reserves ownership without exposing a session while loading',
        () async {
      final read = Completer<CassetteSnapshot>();
      final engine = CassetteEngine(store: _DelayedReadStore(read.future));

      final start = engine.startReplay('pending');

      expect(engine.isActive, isTrue);
      expect(engine.activeSession, isNull);
      await expectLater(
        engine.startRecording('conflict'),
        throwsA(isA<CassetteException>()),
      );

      read.complete(_snapshot(CassetteName('pending')));
      final session = await start;
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

CassetteEngine _engine() => CassetteEngine(store: _ValidReplayStore());

CassetteSnapshot _snapshot(CassetteName name) => CassetteSnapshot(
      name: name,
      bytes: encodeCassetteV1(Cassette()),
      revision: CassetteRevision(),
    );

base class _ValidReplayStore implements CassetteStore {
  @override
  int get maximumBytes => 64 * 1024 * 1024;

  @override
  Future<CassetteSnapshot> read(CassetteName name) async => _snapshot(name);

  @override
  Future<bool> exists(CassetteName name) async => false;

  @override
  Future<void> create(CassetteName name, List<int> bytes) async {}

  @override
  Future<void> replace(CassetteName name, List<int> bytes) async {}

  @override
  Future<void> replaceIfUnchanged(
    CassetteSnapshot snapshot,
    List<int> bytes,
  ) async {}
}

final class _DelayedReadStore extends _ValidReplayStore {
  _DelayedReadStore(this.readResult);

  final Future<CassetteSnapshot> readResult;

  @override
  Future<CassetteSnapshot> read(CassetteName name) => readResult;
}

final class _ThrowingReadStore extends _ValidReplayStore {
  _ThrowingReadStore(this.error);

  final Object error;

  @override
  Future<CassetteSnapshot> read(CassetteName name) async => throw error;
}

import 'package:http_cassette/http_cassette.dart';
import 'package:test/test.dart';

void main() {
  group('CassetteEngine activation policy', () {
    test('defaults to enabled and preserves session startup', () async {
      final engine = CassetteEngine(store: MemoryCassetteStore());

      expect(engine.activationPolicy, CassetteActivationPolicy.enabled);

      final recording = await engine.startRecording('enabled');
      expect(engine.activeSession, same(recording));
      await recording.discard();
    });

    test('retains an explicit enabled policy', () {
      final engine = CassetteEngine(
        store: MemoryCassetteStore(),
        activationPolicy: CassetteActivationPolicy.enabled,
      );

      expect(engine.activationPolicy, CassetteActivationPolicy.enabled);
    });

    test('rejects recording before store access when disabled', () async {
      final store = _ObservingStore();
      final engine = CassetteEngine(
        store: store,
        activationPolicy: CassetteActivationPolicy.disabledWithException,
      );

      await expectLater(
        engine.startRecording('disabled'),
        throwsA(_isActivationDisabled),
      );

      expect(store.operationCount, 0);
      expect(engine.isActive, isFalse);
      expect(engine.activeSession, isNull);
    });

    test('rejects replay before store access when disabled', () async {
      final store = _ObservingStore();
      final engine = CassetteEngine(
        store: store,
        activationPolicy: CassetteActivationPolicy.disabledWithException,
      );

      await expectLater(
        engine.startReplay('disabled'),
        throwsA(_isActivationDisabled),
      );

      expect(store.operationCount, 0);
      expect(engine.isActive, isFalse);
      expect(engine.activeSession, isNull);
      expect(engine.beginInterception().isActive, isFalse);
    });

    test('does not run a scoped callback when activation is disabled',
        () async {
      var callbackRan = false;
      final engine = CassetteEngine(
        store: _ObservingStore(),
        activationPolicy: CassetteActivationPolicy.disabledWithException,
      );

      await expectLater(
        engine.record<void>('disabled', () {
          callbackRan = true;
        }),
        throwsA(_isActivationDisabled),
      );

      expect(callbackRan, isFalse);
    });

    test('returns detached recording and replay sessions for pass-through',
        () async {
      final store = _ObservingStore();
      final engine = _passThroughEngine(store);

      final recording = await engine.startRecording('disabled/recording');
      final replay = await engine.startReplay('disabled/replay');

      expect(recording.name, 'disabled/recording');
      expect(recording.mode, CassetteMode.record);
      expect(replay.name, 'disabled/replay');
      expect(replay.mode, CassetteMode.replay);
      expect(engine.isActive, isFalse);
      expect(engine.activeSession, isNull);
      expect(engine.beginInterception().isActive, isFalse);
      expect(store.operationCount, 0);

      await recording.close();
      await replay.close();
    });

    test('closes and discards inert sessions idempotently', () async {
      final engine = _passThroughEngine(_ObservingStore());
      final recording = await engine.startRecording('disabled/recording');
      final replay = await engine.startReplay('disabled/replay');

      await recording.close();
      await recording.close();
      await replay.discard();
      await replay.discard();

      expect(recording.isClosed, isTrue);
      expect(replay.isClosed, isTrue);
      expect(engine.isActive, isFalse);
    });

    test('allows several detached sessions without engine ownership', () async {
      final engine = _passThroughEngine(_ObservingStore());

      final sessions = await Future.wait(<Future<CassetteSession>>[
        engine.startRecording('disabled/first'),
        engine.startReplay('disabled/second'),
        engine.startRecording('disabled/third'),
      ]);

      expect(sessions.toSet(), hasLength(3));
      expect(engine.isActive, isFalse);
      for (final session in sessions) {
        await session.close();
      }
    });

    test('runs scoped actions while interception stays inactive', () async {
      final store = _ObservingStore();
      final engine = _passThroughEngine(store);
      var actionCount = 0;

      final recorded = await engine.record<int>('disabled/record', () {
        actionCount += 1;
        expect(engine.beginInterception().isActive, isFalse);
        return 1;
      });
      final replayed = await engine.replay<int>('disabled/replay', () {
        actionCount += 1;
        expect(engine.beginInterception().isActive, isFalse);
        return 2;
      });

      expect(recorded, 1);
      expect(replayed, 2);
      expect(actionCount, 2);
      expect(store.operationCount, 0);
      expect(engine.isActive, isFalse);
    });

    test('retains cassette-name validation for inert sessions', () async {
      final engine = _passThroughEngine(_ObservingStore());

      await expectLater(
        engine.startReplay('../invalid'),
        throwsArgumentError,
      );

      expect(engine.isActive, isFalse);
    });
  });
}

CassetteEngine _passThroughEngine(CassetteStore store) => CassetteEngine(
      store: store,
      activationPolicy: CassetteActivationPolicy.disabledWithPassThrough,
    );

final _isActivationDisabled = isA<CassetteException>()
    .having(
      (failure) => failure.diagnostic.category,
      'category',
      DiagnosticCategory.cassetteActivationDisabled,
    )
    .having(
      (failure) => failure.diagnostic.networkAccess,
      'networkAccess',
      NetworkAccess.notAttempted,
    );

final class _ObservingStore implements CassetteStore {
  var operationCount = 0;

  @override
  int get maximumBytes => 64 * 1024 * 1024;

  @override
  Future<void> create(CassetteName name, List<int> bytes) async {
    operationCount += 1;
  }

  @override
  Future<bool> exists(CassetteName name) async {
    operationCount += 1;
    return false;
  }

  @override
  Future<CassetteSnapshot> read(CassetteName name) async {
    operationCount += 1;
    throw StateError('No cassette should be read.');
  }

  @override
  Future<void> replace(CassetteName name, List<int> bytes) async {
    operationCount += 1;
  }

  @override
  Future<void> replaceIfUnchanged(
    CassetteSnapshot snapshot,
    List<int> bytes,
  ) async {
    operationCount += 1;
  }
}

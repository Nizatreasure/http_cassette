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
  });
}

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

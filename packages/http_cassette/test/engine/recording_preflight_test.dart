import 'dart:async';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/configuration/cassette_size_limit.dart';
import 'package:http_cassette/src/engine/cassette_engine.dart';
import 'package:http_cassette/src/recording/active_state.dart';
import 'package:test/test.dart';

void main() {
  group('recording target preflight', () {
    test('starts default recording when the target is absent', () async {
      final state = _state(_ExistsStore(false));

      final session = await state.startRecording(
        CassetteName('recording'),
        const RecordingOptions(),
      );

      expect(session.mode, CassetteMode.record);
      expect(state.activeRecording, isNotNull);
    });

    test('rejects an existing target by default before activation', () async {
      final state = _state(_ExistsStore(true));

      await expectLater(
        state.startRecording(
          CassetteName('recording'),
          const RecordingOptions(),
        ),
        throwsA(
          isA<CassetteException>()
              .having(
                (exception) => exception.diagnostic.category,
                'category',
                DiagnosticCategory.targetCassetteExists,
              )
              .having(
                (exception) => exception.diagnostic.networkAccess,
                'network access',
                NetworkAccess.notAttempted,
              ),
        ),
      );
      expect(state.sessions.isActive, isFalse);
      expect(state.sessions.activeSession, isNull);
      expect(state.activeRecording, isNull);
    });

    test('retains a present replacement target for authoritative close',
        () async {
      final state = _state(_ExistsStore(true));

      final session = await state.startRecording(
        CassetteName('recording'),
        const RecordingOptions(existingCassette: ExistingCassette.replace),
      );

      expect(session.mode, CassetteMode.record);
      expect(state.activeRecording!.options.existingCassette,
          ExistingCassette.replace);
      expect(
        state.activeRecording!.targetPresence,
        RecordingTargetPresence.present,
      );
    });

    test('retains an absent replacement target for create on close', () async {
      final state = _state(_ExistsStore(false));

      final session = await state.startRecording(
        CassetteName('recording'),
        const RecordingOptions(existingCassette: ExistingCassette.replace),
      );

      expect(session.mode, CassetteMode.record);
      expect(
        state.activeRecording!.targetPresence,
        RecordingTargetPresence.absent,
      );
    });

    test('reserves ownership while the existence check is pending', () async {
      final existence = Completer<bool>();
      final state = _state(_DelayedExistsStore(existence.future));

      final start = state.startRecording(
        CassetteName('recording'),
        const RecordingOptions(),
      );

      expect(state.sessions.isActive, isTrue);
      expect(state.sessions.activeSession, isNull);
      await expectLater(
        state.startRecording(
          CassetteName('conflict'),
          const RecordingOptions(),
        ),
        throwsA(isA<CassetteException>()),
      );

      existence.complete(false);
      expect((await start).mode, CassetteMode.record);
    });

    test('maps an expected store check failure and releases ownership',
        () async {
      final name = CassetteName('recording');
      final state = _state(_FailingExistsStore(name));

      await expectLater(
        state.startRecording(name, const RecordingOptions()),
        throwsA(
          isA<CassetteException>()
              .having(
                (exception) => exception.diagnostic.category,
                'category',
                DiagnosticCategory.storeReadFailure,
              )
              .having(
                (exception) => exception.diagnostic.networkAccess,
                'network access',
                NetworkAccess.notAttempted,
              ),
        ),
      );
      expect(state.sessions.isActive, isFalse);
    });

    test('times out a pending store check and releases ownership', () async {
      final state = _state(
        _DelayedExistsStore(Completer<bool>().future),
        timeout: const Duration(milliseconds: 1),
      );

      await expectLater(
        state.startRecording(
          CassetteName('recording'),
          const RecordingOptions(),
        ),
        throwsA(
          isA<CassetteException>().having(
            (exception) => exception.diagnostic.category,
            'category',
            DiagnosticCategory.storeReadFailure,
          ),
        ),
      );
      expect(state.sessions.isActive, isFalse);
      expect(state.activeRecording, isNull);
    });
  });
}

EngineState _state(
  CassetteStore store, {
  Duration timeout = StoreOperationConfiguration.defaultTimeout,
}) =>
    EngineState(
      store: store,
      configuration: CassetteConfiguration(
        storeOperations: StoreOperationConfiguration(timeout: timeout),
      ),
    );

base class _ExistsStore implements CassetteStore {
  _ExistsStore(this.result);

  final bool result;

  @override
  int get maximumBytes => defaultMaximumCassetteBytesV1;

  @override
  Future<bool> exists(CassetteName name) async => result;

  @override
  Future<CassetteSnapshot> read(CassetteName name) =>
      throw UnimplementedError();

  @override
  Future<void> create(CassetteName name, List<int> bytes) =>
      throw UnimplementedError();

  @override
  Future<void> replace(CassetteName name, List<int> bytes) =>
      throw UnimplementedError();

  @override
  Future<void> replaceIfUnchanged(
    CassetteSnapshot snapshot,
    List<int> bytes,
  ) =>
      throw UnimplementedError();
}

final class _DelayedExistsStore extends _ExistsStore {
  _DelayedExistsStore(this.existence) : super(false);

  final Future<bool> existence;

  @override
  Future<bool> exists(CassetteName name) => existence;
}

final class _FailingExistsStore extends _ExistsStore {
  _FailingExistsStore(this.name) : super(false);

  final CassetteName name;

  @override
  Future<bool> exists(CassetteName name) =>
      throw CassetteStoreException.operationFailed(
        name: this.name,
        operation: CassetteStoreOperation.exists,
      );
}

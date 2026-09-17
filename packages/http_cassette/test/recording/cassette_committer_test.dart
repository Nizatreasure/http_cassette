import 'dart:async';
import 'dart:convert';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/cassette.dart';
import 'package:http_cassette/src/cassette/decoder.dart';
import 'package:http_cassette/src/cassette/encoder.dart';
import 'package:http_cassette/src/configuration/cassette_size_limit.dart';
import 'package:http_cassette/src/recording/active_state.dart';
import 'package:http_cassette/src/recording/append_preparation.dart';
import 'package:http_cassette/src/recording/cassette_committer.dart';
import 'package:test/test.dart';

void main() {
  group('RecordingCassetteCommitter', () {
    test('creates a complete deterministically encoded cassette', () async {
      final store = _CommitStore();
      final state = _state();
      await state.recordRequest(
        CassetteRequest(
          method: 'POST',
          uri: Uri.parse('https://example.test/?token=private'),
        ),
        () async => _outcome(201),
      );

      await RecordingCassetteCommitter(store).commit(state);

      expect(store.operation, CassetteStoreOperation.create);
      expect(store.name, state.cassetteName);
      final bytes = store.bytes!;
      expect(utf8.decode(bytes), isNot(contains('private')));
      final cassette = decodeCassetteV1(bytes);
      expect(cassette.interactions, hasLength(1));
      expect(cassette.interactions.single.index, 0);
    });

    test('replaces through the authoritative replace operation', () async {
      final store = _CommitStore();
      final state = _state(existingCassette: ExistingCassette.replace);

      await RecordingCassetteCommitter(store).commit(state);

      expect(store.operation, CassetteStoreOperation.replace);
      expect(decodeCassetteV1(store.bytes!).interactions, isEmpty);
    });

    test('creates when the replacement target was absent at startup', () async {
      final store = _CommitStore();
      final state = _state(
        existingCassette: ExistingCassette.replace,
        targetPresence: RecordingTargetPresence.absent,
      );

      await RecordingCassetteCommitter(store).commit(state);

      expect(store.operation, CassetteStoreOperation.create);
      expect(decodeCassetteV1(store.bytes!).interactions, isEmpty);
    });

    test('finalises before invoking the store', () async {
      final store = _CommitStore();
      final state = _state();
      state.beginRequest(_request('/pending'));

      await expectLater(
        RecordingCassetteCommitter(store).commit(state),
        throwsStateError,
      );

      expect(store.operation, isNull);
      expect(store.bytes, isNull);
    });

    test('conditionally replaces the exact prepared append snapshot', () async {
      final store = _CommitStore();
      final name = CassetteName('recording');
      final preparation = _appendPreparation(name);
      final state = _state(
        name: name,
        existingCassette: ExistingCassette.append,
        appendPreparation: preparation,
      );

      await RecordingCassetteCommitter(store).commit(state);

      expect(store.operation, CassetteStoreOperation.replaceIfUnchanged);
      expect(store.snapshot, same(preparation.snapshot));
      expect(decodeCassetteV1(store.bytes!).interactions, isEmpty);
    });

    test('rejects append state without a prepared snapshot', () async {
      final store = _CommitStore();
      final state = _state(existingCassette: ExistingCassette.append);

      await expectLater(
        RecordingCassetteCommitter(store).commit(state),
        throwsStateError,
      );

      expect(store.operation, isNull);
    });

    test('maps a stale append snapshot safely', () async {
      final name = CassetteName('recording');
      final store = _CommitStore(
        failure: CassetteStoreException.revisionChanged(name),
      );

      await expectLater(
        RecordingCassetteCommitter(store).commit(
          _state(
            name: name,
            existingCassette: ExistingCassette.append,
            appendPreparation: _appendPreparation(name),
          ),
        ),
        throwsA(
          isA<CassetteException>().having(
            (exception) => exception.diagnostic.category,
            'category',
            DiagnosticCategory.appendTargetChanged,
          ),
        ),
      );
    });

    test('maps a disappeared append target safely', () async {
      final name = CassetteName('recording');
      final store = _CommitStore(
        failure: CassetteStoreException.notFound(
          name: name,
          operation: CassetteStoreOperation.replaceIfUnchanged,
        ),
      );

      await expectLater(
        RecordingCassetteCommitter(store).commit(
          _state(
            name: name,
            existingCassette: ExistingCassette.append,
            appendPreparation: _appendPreparation(name),
          ),
        ),
        throwsA(
          isA<CassetteException>().having(
            (exception) => exception.diagnostic.category,
            'category',
            DiagnosticCategory.appendTargetChanged,
          ),
        ),
      );
    });

    test('maps an authoritative create race safely', () async {
      final name = CassetteName('recording');
      final store = _CommitStore(
        failure: CassetteStoreException.alreadyExists(name),
      );

      await expectLater(
        RecordingCassetteCommitter(store).commit(_state(name: name)),
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
    });

    test('maps a replacement-create race safely', () async {
      final name = CassetteName('recording');
      final store = _CommitStore(
        failure: CassetteStoreException.alreadyExists(name),
      );

      await expectLater(
        RecordingCassetteCommitter(store).commit(
          _state(
            name: name,
            existingCassette: ExistingCassette.replace,
            targetPresence: RecordingTargetPresence.absent,
          ),
        ),
        throwsA(
          isA<CassetteException>().having(
            (exception) => exception.diagnostic.category,
            'category',
            DiagnosticCategory.targetCassetteExists,
          ),
        ),
      );

      expect(store.operation, CassetteStoreOperation.create);
    });

    test('maps an authoritative replacement race safely', () async {
      final name = CassetteName('recording');
      final store = _CommitStore(
        failure: CassetteStoreException.notFound(
          name: name,
          operation: CassetteStoreOperation.replace,
        ),
      );

      await expectLater(
        RecordingCassetteCommitter(store).commit(
          _state(name: name, existingCassette: ExistingCassette.replace),
        ),
        throwsA(
          isA<CassetteException>().having(
            (exception) => exception.diagnostic.category,
            'category',
            DiagnosticCategory.cassetteMissing,
          ),
        ),
      );
    });

    test('reports an unconfirmed replacement result safely', () async {
      final name = CassetteName('recording');
      final store = _CommitStore(
        failure: CassetteStoreException.operationFailed(
          name: name,
          operation: CassetteStoreOperation.replace,
        ),
      );

      await expectLater(
        RecordingCassetteCommitter(store).commit(
          _state(name: name, existingCassette: ExistingCassette.replace),
        ),
        throwsA(
          isA<CassetteException>()
              .having(
                (exception) => exception.diagnostic.category,
                'category',
                DiagnosticCategory.storeWriteResultUnconfirmed,
              )
              .having(
                (exception) => exception.diagnostic.networkAccess,
                'network access',
                NetworkAccess.notAttempted,
              ),
        ),
      );
    });

    test('reports an attempted network after captured traffic', () async {
      final name = CassetteName('recording');
      final store = _CommitStore(
        failure: CassetteStoreException.operationFailed(
          name: name,
          operation: CassetteStoreOperation.create,
        ),
      );
      final state = _state(name: name);
      await state.recordRequest(_request('/items'), () async => _outcome(200));

      await expectLater(
        RecordingCassetteCommitter(store).commit(state),
        throwsA(
          isA<CassetteException>()
              .having(
                (exception) => exception.diagnostic.category,
                'category',
                DiagnosticCategory.storeWriteResultUnconfirmed,
              )
              .having(
                (exception) => exception.diagnostic.networkAccess,
                'network access',
                NetworkAccess.attempted,
              ),
        ),
      );
    });

    for (final scenario in <({
      ExistingCassette handling,
      CassetteStoreOperation operation,
    })>[
      (
        handling: ExistingCassette.fail,
        operation: CassetteStoreOperation.create,
      ),
      (
        handling: ExistingCassette.replace,
        operation: CassetteStoreOperation.replace,
      ),
      (
        handling: ExistingCassette.append,
        operation: CassetteStoreOperation.replaceIfUnchanged,
      ),
    ]) {
      test('times out a pending ${scenario.operation.name} safely', () async {
        final name = CassetteName('recording');
        final store = _CommitStore(pending: Completer<void>().future);

        await expectLater(
          RecordingCassetteCommitter(
            store,
            operationTimeout: const Duration(milliseconds: 1),
          ).commit(
            _state(
              name: name,
              existingCassette: scenario.handling,
              appendPreparation: scenario.handling == ExistingCassette.append
                  ? _appendPreparation(name)
                  : null,
            ),
          ),
          throwsA(
            isA<CassetteException>().having(
              (exception) => exception.diagnostic.category,
              'category',
              DiagnosticCategory.storeWriteResultUnconfirmed,
            ),
          ),
        );

        expect(store.operation, scenario.operation);
      });
    }
  });
}

ActiveRecordingState _state({
  CassetteName? name,
  ExistingCassette existingCassette = ExistingCassette.fail,
  RecordingTargetPresence? targetPresence,
  AppendCassettePrepared? appendPreparation,
}) =>
    ActiveRecordingState(
      cassetteName: name ?? CassetteName('recording'),
      configuration: CassetteConfiguration(),
      options: RecordingOptions(existingCassette: existingCassette),
      targetPresence: targetPresence ??
          (existingCassette == ExistingCassette.fail
              ? RecordingTargetPresence.absent
              : RecordingTargetPresence.present),
      appendPreparation: appendPreparation,
    );

AppendCassettePrepared _appendPreparation(CassetteName name) =>
    AppendCassettePreparationResult.prepared(
      snapshot: CassetteSnapshot(
        name: name,
        bytes: encodeCassetteV1(Cassette()),
        revision: CassetteRevision(),
      ),
      cassette: Cassette(),
    ) as AppendCassettePrepared;

CassetteRequest _request(String path) => CassetteRequest(
      method: 'GET',
      uri: Uri.parse('https://example.test$path'),
    );

CassetteOutcome _outcome(int statusCode) => CassetteResponseOutcome(
      CassetteResponse(statusCode: statusCode),
    );

final class _CommitStore implements CassetteStore {
  _CommitStore({this.failure, this.pending});

  final CassetteStoreException? failure;
  final Future<void>? pending;
  CassetteStoreOperation? operation;
  CassetteName? name;
  List<int>? bytes;
  CassetteSnapshot? snapshot;

  @override
  int get maximumBytes => defaultMaximumCassetteBytesV1;

  @override
  Future<void> create(CassetteName name, List<int> bytes) =>
      _write(CassetteStoreOperation.create, name, bytes);

  @override
  Future<void> replace(CassetteName name, List<int> bytes) =>
      _write(CassetteStoreOperation.replace, name, bytes);

  Future<void> _write(
    CassetteStoreOperation operation,
    CassetteName name,
    List<int> bytes,
  ) async {
    this.operation = operation;
    this.name = name;
    this.bytes = List<int>.unmodifiable(bytes);
    if (failure case final failure?) {
      throw failure;
    }
    if (pending case final pending?) {
      await pending;
    }
  }

  @override
  Future<bool> exists(CassetteName name) => throw UnimplementedError();

  @override
  Future<CassetteSnapshot> read(CassetteName name) =>
      throw UnimplementedError();

  @override
  Future<void> replaceIfUnchanged(
    CassetteSnapshot snapshot,
    List<int> bytes,
  ) {
    this.snapshot = snapshot;
    return _write(
      CassetteStoreOperation.replaceIfUnchanged,
      snapshot.name,
      bytes,
    );
  }
}

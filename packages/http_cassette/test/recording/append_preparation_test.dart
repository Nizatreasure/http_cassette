import 'dart:convert';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/cassette.dart';
import 'package:http_cassette/src/cassette/decoder.dart';
import 'package:http_cassette/src/cassette/encoder.dart';
import 'package:http_cassette/src/configuration/cassette_size_limit.dart';
import 'package:http_cassette/src/recording/append_preparation.dart';
import 'package:test/test.dart';

void main() {
  group('AppendCassettePreparer', () {
    test('retains one fully validated snapshot and its cassette', () async {
      final name = CassetteName('recording');
      final snapshot = _snapshot(name, encodeCassetteV1(Cassette()));
      final store = _SnapshotStore(snapshot);

      final result = await AppendCassettePreparer(store).prepare(name);

      expect(result, isA<AppendCassettePrepared>());
      final prepared = result as AppendCassettePrepared;
      expect(prepared.snapshot, same(snapshot));
      expect(prepared.snapshot.revision, same(snapshot.revision));
      expect(prepared.cassette.interactions, isEmpty);
      expect(
        prepared.cassette.schemaVersion,
        currentWritableCassetteSchemaVersion,
      );
      expect(store.readCalls, 1);
    });

    test('reports a missing append target safely', () async {
      final name = CassetteName('missing');
      final store = _FailingReadStore(
        CassetteStoreException.notFound(
          name: name,
          operation: CassetteStoreOperation.read,
        ),
      );

      final failure = await _failure(store, name);

      expect(
        failure.envelope.category,
        DiagnosticCategory.appendTargetMissing,
      );
      expect(failure.storeFailureKind, CassetteStoreFailureKind.notFound);
      expect(failure.envelope.networkAccess, NetworkAccess.notAttempted);
    });

    test('reports an expected append read failure safely', () async {
      final name = CassetteName('unreadable');
      final store = _FailingReadStore(
        CassetteStoreException.operationFailed(
          name: name,
          operation: CassetteStoreOperation.read,
        ),
      );

      final failure = await _failure(store, name);

      expect(failure.envelope.category, DiagnosticCategory.storeReadFailure);
      expect(
        failure.storeFailureKind,
        CassetteStoreFailureKind.operationFailed,
      );
    });

    test('reports invalid append cassette data safely', () async {
      final name = CassetteName('invalid');
      final store = _SnapshotStore(_snapshot(name, utf8.encode('{invalid')));

      final failure = await _failure(store, name);

      expect(
        failure.envelope.category,
        DiagnosticCategory.cassetteDecodeFailure,
      );
      expect(
          failure.decodeFailureKind, CassetteDecodeFailureKind.malformedJson);
    });

    test('compares older and newer targets with the writable version',
        () async {
      for (final observed in <int>[0, 2]) {
        final name = CassetteName('version_$observed');
        final bytes = utf8.encode(
          '{"schemaVersion":$observed,"interactions":[]}',
        );

        final failure = await _failure(
          _SnapshotStore(_snapshot(name, bytes)),
          name,
        );

        expect(
          failure.envelope.category,
          DiagnosticCategory.appendSchemaVersionMismatch,
        );
        expect(failure.observedSchemaVersion, observed);
        expect(
          failure.currentWritableSchemaVersion,
          currentWritableCassetteSchemaVersion,
        );
      }
    });

    test('applies the store byte limit before parsing', () async {
      final name = CassetteName('oversized');
      final bytes = encodeCassetteV1(Cassette());
      final store = _SnapshotStore(
        _snapshot(name, bytes),
        maximumBytes: bytes.length - 1,
      );

      final failure = await _failure(store, name);

      expect(
        failure.envelope.category,
        DiagnosticCategory.cassetteDecodeFailure,
      );
      expect(
          failure.decodeFailureKind, CassetteDecodeFailureKind.inputTooLarge);
    });

    test('rejects a broken store returning a different logical name', () async {
      final requested = CassetteName('requested');
      final store = _SnapshotStore(
        _snapshot(CassetteName('different'), encodeCassetteV1(Cassette())),
      );

      await expectLater(
        AppendCassettePreparer(store).prepare(requested),
        throwsStateError,
      );
      expect(store.readCalls, 1);
    });
  });
}

Future<AppendCassettePreparationFailure> _failure(
  CassetteStore store,
  CassetteName name,
) async {
  final result = await AppendCassettePreparer(store).prepare(name);
  expect(result, isA<AppendCassettePreparationFailed>());
  return (result as AppendCassettePreparationFailed).failure;
}

CassetteSnapshot _snapshot(CassetteName name, List<int> bytes) =>
    CassetteSnapshot(
      name: name,
      bytes: bytes,
      revision: CassetteRevision(),
    );

base class _SnapshotStore implements CassetteStore {
  _SnapshotStore(
    this.snapshot, {
    this.maximumBytes = defaultMaximumCassetteBytesV1,
  });

  final CassetteSnapshot snapshot;
  var readCalls = 0;

  @override
  final int maximumBytes;

  @override
  Future<CassetteSnapshot> read(CassetteName name) async {
    readCalls++;
    return snapshot;
  }

  @override
  Future<bool> exists(CassetteName name) => throw UnimplementedError();

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

final class _FailingReadStore extends _SnapshotStore {
  _FailingReadStore(this.failure)
      : super(
          _snapshot(failure.name, const <int>[]),
        );

  final CassetteStoreException failure;

  @override
  Future<CassetteSnapshot> read(CassetteName name) async {
    readCalls++;
    throw failure;
  }
}

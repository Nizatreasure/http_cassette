import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/cassette.dart';
import 'package:http_cassette/src/cassette/encoder.dart';
import 'package:http_cassette/src/replay/cassette_loader.dart';
import 'package:http_cassette/src/replay/loading_failure.dart';
import 'package:test/test.dart';

void main() {
  group('ReplayCassetteLoader', () {
    test('reads once and returns only the decoded cassette', () async {
      final name = CassetteName('replay/valid');
      final store = _Store(
        snapshot: CassetteSnapshot(
          name: name,
          bytes: encodeCassetteV1(Cassette()),
          revision: CassetteRevision(),
        ),
      );

      final result = await ReplayCassetteLoader(store).load(name);

      expect(result, isA<ReplayCassetteLoaded>());
      expect((result as ReplayCassetteLoaded).cassette, Cassette());
      expect(store.readCount, 1);
      expect(store.existsCount, 0);
    });

    test('maps expected store read failures', () async {
      final name = CassetteName('replay/missing');
      final store = _Store(
        readFailure: CassetteStoreException.notFound(
          name: name,
          operation: CassetteStoreOperation.read,
        ),
      );

      final result = await ReplayCassetteLoader(store).load(name);

      expect(result, isA<ReplayCassetteLoadFailed>());
      final failure = (result as ReplayCassetteLoadFailed).failure;
      expect(failure, isA<ReplayCassetteStoreReadFailure>());
      expect(failure.cassetteName, name);
      expect(
        failure.envelope.category,
        DiagnosticCategory.cassetteMissing,
      );
      expect(store.readCount, 1);
    });

    test('maps decoder failures with the requested cassette name', () async {
      final name = CassetteName('replay/malformed');
      final store = _Store(
        snapshot: CassetteSnapshot(
          name: name,
          bytes: <int>[0x7b],
          revision: CassetteRevision(),
        ),
      );

      final result = await ReplayCassetteLoader(store).load(name);

      final failure = (result as ReplayCassetteLoadFailed).failure;
      expect(failure, isA<ReplayCassetteDecodeFailure>());
      expect(failure.cassetteName, name);
      expect(
        failure.envelope.category,
        DiagnosticCategory.cassetteDecodeFailure,
      );
    });

    test('uses the store maximum when independently decoding', () async {
      final name = CassetteName('replay/oversized');
      final store = _Store(
        maximumBytes: 1,
        snapshot: CassetteSnapshot(
          name: name,
          bytes: encodeCassetteV1(Cassette()),
          revision: CassetteRevision(),
        ),
      );

      final result = await ReplayCassetteLoader(store).load(name);

      final failure = (result as ReplayCassetteLoadFailed).failure
          as ReplayCassetteDecodeFailure;
      expect(failure.diagnostic.maximumBytes, 1);
      expect(failure.diagnostic.failureKind.name, 'inputTooLarge');
    });

    test('rejects a snapshot for a different name', () async {
      final store = _Store(
        snapshot: CassetteSnapshot(
          name: CassetteName('replay/wrong'),
          bytes: encodeCassetteV1(Cassette()),
          revision: CassetteRevision(),
        ),
      );

      await expectLater(
        ReplayCassetteLoader(store).load(CassetteName('replay/requested')),
        throwsStateError,
      );
    });

    test('rejects a store failure for a different name', () async {
      final store = _Store(
        readFailure: CassetteStoreException.notFound(
          name: CassetteName('replay/wrong'),
          operation: CassetteStoreOperation.read,
        ),
      );

      await expectLater(
        ReplayCassetteLoader(store).load(CassetteName('replay/requested')),
        throwsStateError,
      );
    });

    test('does not relabel unexpected store exceptions', () async {
      final store = _Store(unexpectedFailure: StateError('unexpected'));

      await expectLater(
        ReplayCassetteLoader(store).load(CassetteName('replay/unexpected')),
        throwsStateError,
      );
    });
  });
}

final class _Store implements CassetteStore {
  _Store({
    this.maximumBytes = 64 * 1024 * 1024,
    this.snapshot,
    this.readFailure,
    this.unexpectedFailure,
  });

  @override
  final int maximumBytes;
  final CassetteSnapshot? snapshot;
  final CassetteStoreException? readFailure;
  final Object? unexpectedFailure;
  int readCount = 0;
  int existsCount = 0;

  @override
  Future<CassetteSnapshot> read(CassetteName name) async {
    readCount++;
    if (unexpectedFailure case final failure?) {
      throw failure;
    }
    if (readFailure case final failure?) {
      throw failure;
    }
    return snapshot!;
  }

  @override
  Future<bool> exists(CassetteName name) async {
    existsCount++;
    return false;
  }

  @override
  Future<void> create(CassetteName name, List<int> bytes) async =>
      throw UnsupportedError('Not used by this test.');

  @override
  Future<void> replace(CassetteName name, List<int> bytes) async =>
      throw UnsupportedError('Not used by this test.');

  @override
  Future<void> replaceIfUnchanged(
    CassetteSnapshot snapshot,
    List<int> bytes,
  ) async =>
      throw UnsupportedError('Not used by this test.');
}

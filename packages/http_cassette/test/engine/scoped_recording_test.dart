import 'dart:async';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/cassette.dart';
import 'package:http_cassette/src/cassette/decoder.dart';
import 'package:http_cassette/src/cassette/encoder.dart';
import 'package:http_cassette/src/configuration/cassette_size_limit.dart';
import 'package:test/test.dart';

void main() {
  group('CassetteEngine.record', () {
    test('returns a generic value after committing the recording', () async {
      final store = MemoryCassetteStore();
      final engine = CassetteEngine(store: store);
      final value = <int>[1, 2];

      final result = await engine.record<List<int>>(
        'recording',
        () async => value,
      );

      expect(result, same(value));
      expect(engine.isActive, isFalse);
      expect(
        decodeCassetteV1(
          (await store.read(CassetteName('recording'))).bytes,
        ).interactions,
        isEmpty,
      );
    });

    test('passes explicit replace and append options to startup', () async {
      for (final handling in <ExistingCassette>[
        ExistingCassette.replace,
        ExistingCassette.append,
      ]) {
        final store = MemoryCassetteStore();
        final engine = CassetteEngine(store: store);
        final name = CassetteName(handling.name);
        await store.create(name, encodeCassetteV1(Cassette()));

        final result = await engine.record<int>(
          name.value,
          () => 42,
          options: RecordingOptions(existingCassette: handling),
        );

        expect(result, 42);
        expect(engine.isActive, isFalse);
        expect(decodeCassetteV1((await store.read(name)).bytes).interactions,
            isEmpty);
      }
    });

    test('does not invoke the callback when recording startup fails', () async {
      final store = MemoryCassetteStore();
      final engine = CassetteEngine(store: store);
      final name = CassetteName('existing');
      await store.create(name, encodeCassetteV1(Cassette()));
      var invoked = false;

      await expectLater(
        engine.record<void>(name.value, () {
          invoked = true;
        }),
        throwsA(
          isA<CassetteException>().having(
            (exception) => exception.diagnostic.category,
            'category',
            DiagnosticCategory.targetCassetteExists,
          ),
        ),
      );

      expect(invoked, isFalse);
      expect(engine.isActive, isFalse);
    });

    test('discards and rethrows a callback failure with its stack', () async {
      final store = MemoryCassetteStore();
      final engine = CassetteEngine(store: store);
      final error = StateError('callback failed');
      final stackTrace = StackTrace.current;

      try {
        await engine.record<void>(
          'failed',
          () => Future<void>.error(error, stackTrace),
        );
        fail('The callback failure should have been rethrown.');
      } on Object catch (caught, caughtStackTrace) {
        expect(caught, same(error));
        expect(caughtStackTrace, same(stackTrace));
      }

      expect(await store.exists(CassetteName('failed')), isFalse);
      expect(engine.isActive, isFalse);
    });

    test('propagates an unconfirmed commit result and releases ownership',
        () async {
      final engine = CassetteEngine(store: _FailingCreateStore());

      await expectLater(
        engine.record<void>('recording', () {}),
        throwsA(
          isA<CassetteException>().having(
            (exception) => exception.diagnostic.category,
            'category',
            DiagnosticCategory.storeWriteResultUnconfirmed,
          ),
        ),
      );

      expect(engine.isActive, isFalse);
      expect(engine.activeSession, isNull);
    });
  });
}

final class _FailingCreateStore implements CassetteStore {
  @override
  int get maximumBytes => defaultMaximumCassetteBytesV1;

  @override
  Future<bool> exists(CassetteName name) async => false;

  @override
  Future<void> create(CassetteName name, List<int> bytes) async {
    throw CassetteStoreException.operationFailed(
      name: name,
      operation: CassetteStoreOperation.create,
    );
  }

  @override
  Future<CassetteSnapshot> read(CassetteName name) =>
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

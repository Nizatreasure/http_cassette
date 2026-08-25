import 'dart:convert';

import 'package:http_cassette/http_cassette.dart';
import 'package:test/test.dart';

import 'store_contract.dart';

void main() {
  defineCassetteStoreContract(MemoryCassetteStore.new);

  group('MemoryCassetteStore', () {
    test('uses the shared default and accepts a positive override', () {
      expect(MemoryCassetteStore().maximumBytes, 64 * 1024 * 1024);
      expect(MemoryCassetteStore(maximumBytes: 123).maximumBytes, 123);
    });

    test('rejects a non-positive maximum byte count', () {
      expect(
        () => MemoryCassetteStore(maximumBytes: 0),
        throwsArgumentError,
      );
      expect(
        () => MemoryCassetteStore(maximumBytes: -1),
        throwsArgumentError,
      );
    });

    test('rejects oversized creation without storing a cassette', () async {
      final store = MemoryCassetteStore(maximumBytes: 1);
      final name = CassetteName('oversized_create');

      await expectLater(
        store.create(name, const <int>[1, 2]),
        throwsA(
          isA<CassetteStoreException>()
              .having(
                (error) => error.kind,
                'kind',
                CassetteStoreFailureKind.operationFailed,
              )
              .having(
                (error) => error.operation,
                'operation',
                CassetteStoreOperation.create,
              ),
        ),
      );

      expect(await store.exists(name), isFalse);
    });

    test('rejects oversized replacement without changing bytes', () async {
      final store = MemoryCassetteStore(maximumBytes: 1);
      final name = CassetteName('oversized_replace');
      await store.create(name, const <int>[1]);

      await expectLater(
        store.replace(name, const <int>[2, 3]),
        throwsA(isA<CassetteStoreException>()),
      );

      expect((await store.read(name)).bytes, const <int>[1]);
    });

    test('rejects oversized conditional replacement without changing bytes',
        () async {
      final store = MemoryCassetteStore(maximumBytes: 1);
      final name = CassetteName('oversized_conditional');
      await store.create(name, const <int>[1]);
      final snapshot = await store.read(name);

      await expectLater(
        store.replaceIfUnchanged(snapshot, const <int>[2, 3]),
        throwsA(isA<CassetteStoreException>()),
      );

      expect((await store.read(name)).bytes, const <int>[1]);
    });

    test('starts empty and does not share state between instances', () async {
      final first = MemoryCassetteStore();
      final second = MemoryCassetteStore();
      final name = CassetteName('isolate_local');

      await first.create(name, _emptyCassetteBytes());

      expect(await first.exists(name), isTrue);
      expect(await second.exists(name), isFalse);
    });

    test('returns separate snapshots with the same current revision', () async {
      final store = MemoryCassetteStore();
      final name = CassetteName('snapshot_copy');
      await store.create(name, _emptyCassetteBytes());

      final first = await store.read(name);
      final second = await store.read(name);

      expect(first, isNot(same(second)));
      expect(first.revision, same(second.revision));
      expect(first.bytes, second.bytes);
    });
  });
}

List<int> _emptyCassetteBytes() =>
    utf8.encode('{"schemaVersion":1,"interactions":[]}');

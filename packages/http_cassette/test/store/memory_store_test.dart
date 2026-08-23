import 'dart:convert';

import 'package:http_cassette/http_cassette.dart';
import 'package:test/test.dart';

import 'store_contract.dart';

void main() {
  defineCassetteStoreContract(MemoryCassetteStore.new);

  group('MemoryCassetteStore', () {
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

import 'package:http_cassette/http_cassette.dart';
import 'package:test/test.dart';

void main() {
  test('a third-party store can implement the public contract', () async {
    final name = CassetteName('third_party/example');
    final snapshot = CassetteSnapshot(
      name: name,
      bytes: const <int>[1],
      revision: CassetteRevision(),
    );
    final store = _ThirdPartyStore(snapshot);

    expect(await store.exists(name), isTrue);
    expect(await store.read(name), same(snapshot));
    await store.create(name, const <int>[2]);
    await store.replace(name, const <int>[3]);
    await store.replaceIfUnchanged(snapshot, const <int>[4]);

    expect(store.operations, <String>[
      'exists',
      'read',
      'create',
      'replace',
      'replaceIfUnchanged',
    ]);
  });
}

final class _ThirdPartyStore implements CassetteStore {
  _ThirdPartyStore(this.snapshot);

  final CassetteSnapshot snapshot;
  final List<String> operations = <String>[];

  @override
  Future<bool> exists(CassetteName name) {
    operations.add('exists');
    return Future<bool>.value(true);
  }

  @override
  Future<CassetteSnapshot> read(CassetteName name) {
    operations.add('read');
    return Future<CassetteSnapshot>.value(snapshot);
  }

  @override
  Future<void> create(CassetteName name, List<int> bytes) {
    operations.add('create');
    return Future<void>.value();
  }

  @override
  Future<void> replace(CassetteName name, List<int> bytes) {
    operations.add('replace');
    return Future<void>.value();
  }

  @override
  Future<void> replaceIfUnchanged(
    CassetteSnapshot snapshot,
    List<int> bytes,
  ) {
    operations.add('replaceIfUnchanged');
    return Future<void>.value();
  }
}

import 'dart:io';

import 'package:http_cassette/file.dart';
import 'package:http_cassette/http_cassette.dart';
import 'package:test/test.dart';

void main() {
  late Directory sandbox;
  late Directory root;

  setUp(() async {
    sandbox =
        await Directory.systemTemp.createTemp('http_cassette_conditional_');
    root = await Directory('${sandbox.path}/root').create();
  });

  tearDown(() async {
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  test('replaces a cassette whose complete content is unchanged', () async {
    final target = await _write(root, 'current', <int>[1, 2, 3]);
    final store = FileCassetteStore(root);
    final snapshot = await store.read(CassetteName('current'));

    await store.replaceIfUnchanged(snapshot, <int>[4, 5]);

    expect(await target.readAsBytes(), <int>[4, 5]);
    expect(
      await root.list().where((entry) => entry.path.endsWith('.tmp')).toList(),
      isEmpty,
    );
  });

  test('copies input before asynchronous conditional work', () async {
    await _write(root, 'defensive', <int>[1]);
    final store = FileCassetteStore(root);
    final snapshot = await store.read(CassetteName('defensive'));
    final input = <int>[2, 3];

    final replacing = store.replaceIfUnchanged(snapshot, input);
    input[0] = 9;
    await replacing;

    expect((await store.read(snapshot.name)).bytes, <int>[2, 3]);
  });

  test('rejects changed content even when its length is unchanged', () async {
    final target = await _write(root, 'changed', <int>[1, 2, 3]);
    final store = FileCassetteStore(root);
    final snapshot = await store.read(CassetteName('changed'));
    await target.writeAsBytes(<int>[1, 2, 4], flush: true);

    final error = await _capture(
      () => store.replaceIfUnchanged(snapshot, <int>[5]),
    );

    expect(error.kind, CassetteStoreFailureKind.revisionChanged);
    expect(error.operation, CassetteStoreOperation.replaceIfUnchanged);
    expect(await target.readAsBytes(), <int>[1, 2, 4]);
  });

  test('rejects a revision issued by another store', () async {
    final target = await _write(root, 'foreign', <int>[1]);
    final firstStore = FileCassetteStore(root);
    final secondStore = FileCassetteStore(root);
    final snapshot = await firstStore.read(CassetteName('foreign'));

    final error = await _capture(
      () => secondStore.replaceIfUnchanged(snapshot, <int>[2]),
    );

    expect(error.kind, CassetteStoreFailureKind.revisionChanged);
    expect(await target.readAsBytes(), <int>[1]);
  });

  test('rejects a revision associated with another cassette name', () async {
    final first = await _write(root, 'first', <int>[1]);
    final second = await _write(root, 'second', <int>[1]);
    final store = FileCassetteStore(root);
    final firstSnapshot = await store.read(CassetteName('first'));
    final forgedSnapshot = CassetteSnapshot(
      name: CassetteName('second'),
      bytes: firstSnapshot.bytes,
      revision: firstSnapshot.revision,
    );

    final error = await _capture(
      () => store.replaceIfUnchanged(forgedSnapshot, <int>[2]),
    );

    expect(error.kind, CassetteStoreFailureKind.revisionChanged);
    expect(await first.readAsBytes(), <int>[1]);
    expect(await second.readAsBytes(), <int>[1]);
  });

  test('reports a missing current cassette before revision validity', () async {
    final store = FileCassetteStore(root);
    final snapshot = CassetteSnapshot(
      name: CassetteName('missing'),
      bytes: const <int>[],
      revision: CassetteRevision(),
    );

    final error = await _capture(
      () => store.replaceIfUnchanged(snapshot, <int>[1]),
    );

    expect(error.kind, CassetteStoreFailureKind.notFound);
    expect(error.operation, CassetteStoreOperation.replaceIfUnchanged);
  });

  test('observes a preceding same-name replacement before comparing', () async {
    final target = await _write(root, 'ordered', <int>[1]);
    final store = FileCassetteStore(root);
    final snapshot = await store.read(CassetteName('ordered'));

    final replacing = store.replace(snapshot.name, <int>[2]);
    final conditional = _capture(
      () => store.replaceIfUnchanged(snapshot, <int>[3]),
    );
    await replacing;
    final error = await conditional;

    expect(error.kind, CassetteStoreFailureKind.revisionChanged);
    expect(await target.readAsBytes(), <int>[2]);
  });

  test('rejects oversized input before reading the current cassette', () async {
    final target = await _write(root, 'oversized', <int>[1]);
    final store = FileCassetteStore(root, maximumBytes: 1);
    final snapshot = await store.read(CassetteName('oversized'));

    final error = await _capture(
      () => store.replaceIfUnchanged(snapshot, <int>[2, 3]),
    );

    expect(error.kind, CassetteStoreFailureKind.operationFailed);
    expect(error.operation, CassetteStoreOperation.replaceIfUnchanged);
    expect(await target.readAsBytes(), <int>[1]);
  });
}

Future<File> _write(Directory root, String name, List<int> bytes) async {
  final file = File('${root.path}${Platform.pathSeparator}$name.json');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

Future<CassetteStoreException> _capture(
  Future<Object?> Function() operation,
) async {
  try {
    await operation();
  } on CassetteStoreException catch (error) {
    return error;
  }
  fail('Expected a CassetteStoreException.');
}

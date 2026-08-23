import 'dart:io';

import 'package:http_cassette/file.dart';
import 'package:http_cassette/http_cassette.dart';
import 'package:test/test.dart';

void main() {
  late Directory sandbox;
  late Directory root;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('http_cassette_read_');
    root = await Directory('${sandbox.path}/root').create();
  });

  tearDown(() async {
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  test('exposes the measured default and validates overrides', () {
    expect(FileCassetteStore.defaultMaximumBytesV1, 64 * 1024 * 1024);
    expect(FileCassetteStore(root).maximumBytes, 64 * 1024 * 1024);
    expect(FileCassetteStore(root, maximumBytes: 1).maximumBytes, 1);

    for (final maximumBytes in <int>[0, -1]) {
      expect(
        () => FileCassetteStore(root, maximumBytes: maximumBytes),
        throwsArgumentError,
      );
    }
  });

  test('treats a missing root as an empty store for reads', () async {
    final missingRoot = Directory('${sandbox.path}/missing');
    final store = FileCassetteStore(missingRoot);
    final name = CassetteName('checkout');

    expect(await store.exists(name), isFalse);
    final error = await _capture(() => store.read(name));
    expect(error.kind, CassetteStoreFailureKind.notFound);
    expect(error.operation, CassetteStoreOperation.read);
    expect(error.name, name);
  });

  test('reports invalid root entity types safely', () async {
    final rootFile = File('${sandbox.path}/not-a-directory');
    await rootFile.writeAsString('private-root-value');
    final store = FileCassetteStore(Directory(rootFile.path));

    final error = await _capture(
      () => store.exists(CassetteName('checkout')),
    );

    expect(error.kind, CassetteStoreFailureKind.operationFailed);
    expect(error.toString(), isNot(contains(rootFile.path)));
    expect(error.toString(), isNot(contains('private-root-value')));
  });

  test('checks existence and reads nested immutable snapshots', () async {
    final directory = await Directory('${root.path}/checkout').create();
    final file = File('${directory.path}/success.json');
    final bytes = <int>[1, 2, 3];
    await file.writeAsBytes(bytes);
    final store = FileCassetteStore(root);
    final name = CassetteName('checkout/success');

    expect(await store.exists(name), isTrue);
    final snapshot = await store.read(name);
    bytes[0] = 9;

    expect(snapshot.name, name);
    expect(snapshot.bytes, <int>[1, 2, 3]);
    expect(() => snapshot.bytes[0] = 9, throwsUnsupportedError);
  });

  test('returns a new opaque revision for each observed file snapshot',
      () async {
    await File('${root.path}/revision.json').writeAsBytes(<int>[1, 2, 3]);
    final store = FileCassetteStore(root);
    final name = CassetteName('revision');

    final first = await store.read(name);
    final second = await store.read(name);

    expect(first.revision, isNot(second.revision));
    expect(first.revision.toString(), 'CassetteRevision(<opaque>)');
    expect(second.revision.toString(), 'CassetteRevision(<opaque>)');
  });

  test('accepts a file exactly at a custom byte limit', () async {
    await File('${root.path}/boundary.json').writeAsBytes(<int>[1, 2, 3]);
    final store = FileCassetteStore(root, maximumBytes: 3);

    final snapshot = await store.read(CassetteName('boundary'));

    expect(snapshot.bytes, <int>[1, 2, 3]);
  });

  test('rejects a file over the limit without retaining bytes', () async {
    await File('${root.path}/oversized.json').writeAsBytes(<int>[1, 2, 3]);
    final store = FileCassetteStore(root, maximumBytes: 2);

    final error = await _capture(
      () => store.read(CassetteName('oversized')),
    );

    expect(error.kind, CassetteStoreFailureKind.operationFailed);
    expect(error.operation, CassetteStoreOperation.read);
    expect(error.toString(), isNot(contains('[1, 2, 3]')));
  });

  test('preserves format-neutral bytes without decoding them', () async {
    await File('${root.path}/opaque.json').writeAsBytes(<int>[0xff, 0x00]);
    final store = FileCassetteStore(root);

    final snapshot = await store.read(CassetteName('opaque'));

    expect(snapshot.bytes, <int>[0xff, 0x00]);
  });

  test('reports conditional replacement as unsupported', () async {
    final store = FileCassetteStore(root);
    final name = CassetteName('checkout');
    final snapshot = CassetteSnapshot(
      name: name,
      bytes: const <int>[],
      revision: CassetteRevision(),
    );

    final error = await _capture(
      () => store.replaceIfUnchanged(snapshot, const <int>[]),
    );
    expect(error.kind, CassetteStoreFailureKind.unsupportedOperation);
    expect(error.operation, CassetteStoreOperation.replaceIfUnchanged);
    expect(error.name, name);
  });
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

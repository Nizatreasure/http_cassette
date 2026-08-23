import 'dart:convert';
import 'dart:io';

import 'package:http_cassette/file.dart';
import 'package:http_cassette/http_cassette.dart';
import 'package:test/test.dart';

void main() {
  late Directory sandbox;
  late Directory root;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('http_cassette_replace_');
    root = await Directory('${sandbox.path}/root').create();
  });

  tearDown(() async {
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  test('atomically replaces an existing cassette with exact bytes', () async {
    final target = File('${root.path}/checkout.json');
    await target.writeAsBytes(utf8.encode('old-private-value'));
    final store = FileCassetteStore(root);
    final name = CassetteName('checkout');
    final replacement = _cassetteBytes();

    await store.replace(name, replacement);

    expect(await target.readAsBytes(), replacement);
    expect((await store.read(name)).bytes, replacement);
    expect(
      await root.list().where((entry) => entry.path.endsWith('.tmp')).toList(),
      isEmpty,
    );
  });

  test('copies replacement input before asynchronous file work', () async {
    final target = File('${root.path}/defensive.json');
    await target.writeAsBytes(<int>[1]);
    final store = FileCassetteStore(root);
    final name = CassetteName('defensive');
    final input = _cassetteBytes();
    final expected = List<int>.of(input);

    final replacing = store.replace(name, input);
    input[0] = 0x20;
    await replacing;

    expect((await store.read(name)).bytes, expected);
  });

  test('requires an existing cassette without creating the root', () async {
    final missingRoot = Directory('${sandbox.path}/missing');
    final store = FileCassetteStore(missingRoot);
    final name = CassetteName('missing');

    final error = await _capture(() => store.replace(name, _cassetteBytes()));

    expect(error.kind, CassetteStoreFailureKind.notFound);
    expect(error.operation, CassetteStoreOperation.replace);
    expect(await missingRoot.exists(), isFalse);
  });

  test('requires an existing cassette without leaving a candidate', () async {
    final store = FileCassetteStore(root);
    final name = CassetteName('missing');

    final error = await _capture(() => store.replace(name, _cassetteBytes()));

    expect(error.kind, CassetteStoreFailureKind.notFound);
    expect(await root.list().toList(), isEmpty);
  });

  test('rejects oversized input before changing the existing cassette',
      () async {
    final target = File('${root.path}/oversized.json');
    await target.writeAsBytes(<int>[1]);
    final store = FileCassetteStore(root, maximumBytes: 1);
    final name = CassetteName('oversized');

    final error = await _capture(() => store.replace(name, <int>[2, 3]));

    expect(error.kind, CassetteStoreFailureKind.operationFailed);
    expect(error.operation, CassetteStoreOperation.replace);
    expect(await target.readAsBytes(), <int>[1]);
  });

  test('serialises replacements and same-name reads', () async {
    final target = File('${root.path}/ordered.json');
    await target.writeAsBytes(<int>[1]);
    final store = FileCassetteStore(root);
    final name = CassetteName('ordered');
    final first = utf8.encode('first');
    final second = utf8.encode('second');

    final firstReplace = store.replace(name, first);
    final secondReplace = store.replace(name, second);
    final reading = store.read(name);

    await firstReplace;
    await secondReplace;
    expect((await reading).bytes, second);
  });
}

List<int> _cassetteBytes() =>
    utf8.encode('{"schemaVersion":1,"interactions":[]}');

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

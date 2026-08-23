import 'dart:convert';
import 'dart:io';

import 'package:http_cassette/file.dart';
import 'package:http_cassette/http_cassette.dart';
import 'package:test/test.dart';

void main() {
  late Directory sandbox;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('http_cassette_create_');
  });

  tearDown(() async {
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  test('creates a missing root, nested parents and exact file', () async {
    final root = Directory('${sandbox.path}/root');
    final store = FileCassetteStore(root);
    final name = CassetteName('checkout/success');
    final bytes = _cassetteBytes();

    await store.create(name, bytes);

    final file = File(
      '${root.path}${Platform.pathSeparator}checkout'
      '${Platform.pathSeparator}success.json',
    );
    expect(await file.readAsBytes(), bytes);
    expect((await store.read(name)).bytes, bytes);
  });

  test('copies input before asynchronous file work', () async {
    final root = Directory('${sandbox.path}/root');
    final store = FileCassetteStore(root);
    final name = CassetteName('defensive');
    final input = _cassetteBytes();
    final expected = List<int>.of(input);

    final creating = store.create(name, input);
    input[0] = 0x20;
    await creating;

    expect((await store.read(name)).bytes, expected);
  });

  test('never truncates or replaces an existing target', () async {
    final root = await Directory('${sandbox.path}/root').create();
    final target = File('${root.path}/existing.json');
    final original = utf8.encode('existing-private-value');
    await target.writeAsBytes(original);
    final store = FileCassetteStore(root);
    final name = CassetteName('existing');

    final error = await _capture(
      () => store.create(name, _cassetteBytes()),
    );

    expect(error.kind, CassetteStoreFailureKind.alreadyExists);
    expect(error.operation, CassetteStoreOperation.create);
    expect(error.name, name);
    expect(await target.readAsBytes(), original);
    expect(error.toString(), isNot(contains('existing-private-value')));
  });

  test('serialises conflicting creates in invocation order', () async {
    final root = Directory('${sandbox.path}/root');
    final store = FileCassetteStore(root);
    final name = CassetteName('concurrent');
    final firstBytes = _cassetteBytes();
    final secondBytes = utf8.encode(' {"schemaVersion":1,"interactions":[]}');

    final first = store.create(name, firstBytes);
    final second = _capture(() => store.create(name, secondBytes));
    await first;
    final error = await second;

    expect(error.kind, CassetteStoreFailureKind.alreadyExists);
    expect((await store.read(name)).bytes, firstBytes);
  });

  test('makes same-name reads wait for creation to finish', () async {
    final root = Directory('${sandbox.path}/root');
    final store = FileCassetteStore(root);
    final name = CassetteName('ordered_read');
    final bytes = _cassetteBytes();

    final creating = store.create(name, bytes);
    final reading = store.read(name);

    await creating;
    expect((await reading).bytes, bytes);
  });

  test('rejects parent symbolic-link escapes before creating a file', () async {
    final root = await Directory('${sandbox.path}/root').create();
    final outside = await Directory('${sandbox.path}/outside').create();
    final escape = Link('${root.path}/escape');
    if (!await _createLink(escape, outside.path)) {
      markTestSkipped('Symbolic links are unavailable on this platform.');
      return;
    }
    final store = FileCassetteStore(root);
    final name = CassetteName('escape/created');

    final error = await _capture(
      () => store.create(name, _cassetteBytes()),
    );

    expect(error.kind, CassetteStoreFailureKind.operationFailed);
    expect(await File('${outside.path}/created.json').exists(), isFalse);
    expect(error.toString(), isNot(contains(outside.path)));
  });

  test('rejects oversized input before creating the root', () async {
    final root = Directory('${sandbox.path}/root');
    final store = FileCassetteStore(root, maximumBytes: 1);
    final name = CassetteName('oversized');

    final error = await _capture(() => store.create(name, <int>[1, 2]));

    expect(error.kind, CassetteStoreFailureKind.operationFailed);
    expect(error.operation, CassetteStoreOperation.create);
    expect(await root.exists(), isFalse);
  });
}

List<int> _cassetteBytes() =>
    utf8.encode('{"schemaVersion":1,"interactions":[]}');

Future<bool> _createLink(Link link, String target) async {
  try {
    await link.create(target);
    return true;
  } on FileSystemException {
    return false;
  }
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

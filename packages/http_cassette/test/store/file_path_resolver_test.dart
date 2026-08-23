import 'dart:io';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/store/file_path_resolver.dart';
import 'package:test/test.dart';

void main() {
  late Directory sandbox;
  late Directory root;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('http_cassette_path_');
    root = await Directory('${sandbox.path}/root').create();
  });

  tearDown(() async {
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  test('maps nested logical names beneath the canonical root', () async {
    final resolver = FileCassettePathResolver(root);

    final file = await resolver.resolve(
      CassetteName('checkout/expired-discount'),
      operation: CassetteStoreOperation.read,
    );
    final canonicalRoot = await root.resolveSymbolicLinks();

    expect(
      file.path,
      '$canonicalRoot${Platform.pathSeparator}checkout'
      '${Platform.pathSeparator}expired-discount.json',
    );
  });

  test('canonicalises a symbolic-link root', () async {
    final linkedRoot = Link('${sandbox.path}/linked-root');
    if (!await _createLink(linkedRoot, root.path)) {
      markTestSkipped('Symbolic links are unavailable on this platform.');
      return;
    }
    final resolver = FileCassettePathResolver(Directory(linkedRoot.path));

    final file = await resolver.resolve(
      CassetteName('checkout'),
      operation: CassetteStoreOperation.read,
    );
    final canonicalRoot = await root.resolveSymbolicLinks();

    expect(file.path, '$canonicalRoot${Platform.pathSeparator}checkout.json');
  });

  test('allows an existing parent link that remains within the root', () async {
    final actual = await Directory('${root.path}/actual').create();
    final alias = Link('${root.path}/alias');
    if (!await _createLink(alias, actual.path)) {
      markTestSkipped('Symbolic links are unavailable on this platform.');
      return;
    }
    final resolver = FileCassettePathResolver(root);

    final file = await resolver.resolve(
      CassetteName('alias/checkout'),
      operation: CassetteStoreOperation.read,
    );
    final canonicalActual = await actual.resolveSymbolicLinks();

    expect(
      file.path,
      '$canonicalActual${Platform.pathSeparator}checkout.json',
    );
  });

  test('rejects an existing parent link that escapes the root', () async {
    final outside = await Directory('${sandbox.path}/outside').create();
    final escape = Link('${root.path}/escape');
    if (!await _createLink(escape, outside.path)) {
      markTestSkipped('Symbolic links are unavailable on this platform.');
      return;
    }
    final name = CassetteName('escape/checkout');
    final resolver = FileCassettePathResolver(root);

    final error = await _capture(
      () => resolver.resolve(name, operation: CassetteStoreOperation.read),
    );

    expect(error.kind, CassetteStoreFailureKind.operationFailed);
    expect(error.name, name);
    expect(error.operation, CassetteStoreOperation.read);
    expect(error.toString(), isNot(contains(root.path)));
    expect(error.toString(), isNot(contains(outside.path)));
  });

  test('rejects a target link that escapes the root', () async {
    final outside = File('${sandbox.path}/outside.json');
    await outside.writeAsString('{}');
    final target = Link('${root.path}/checkout.json');
    if (!await _createLink(target, outside.path)) {
      markTestSkipped('Symbolic links are unavailable on this platform.');
      return;
    }
    final resolver = FileCassettePathResolver(root);

    final error = await _capture(
      () => resolver.resolve(
        CassetteName('checkout'),
        operation: CassetteStoreOperation.read,
      ),
    );

    expect(error.kind, CassetteStoreFailureKind.operationFailed);
  });

  test('revalidates symbolic links for every operation', () async {
    final parent = await Directory('${root.path}/parent').create();
    final resolver = FileCassettePathResolver(root);
    final name = CassetteName('parent/checkout');

    await resolver.resolve(name, operation: CassetteStoreOperation.read);
    await parent.delete();
    final outside = await Directory('${sandbox.path}/outside').create();
    final replacement = Link(parent.path);
    if (!await _createLink(replacement, outside.path)) {
      markTestSkipped('Symbolic links are unavailable on this platform.');
      return;
    }

    final error = await _capture(
      () => resolver.resolve(name, operation: CassetteStoreOperation.read),
    );

    expect(error.kind, CassetteStoreFailureKind.operationFailed);
  });

  test('maps missing roots to safe operation failures', () async {
    final missingRoot = Directory('${sandbox.path}/missing');
    final resolver = FileCassettePathResolver(missingRoot);

    final error = await _capture(
      () => resolver.resolve(
        CassetteName('checkout'),
        operation: CassetteStoreOperation.exists,
      ),
    );

    expect(error.kind, CassetteStoreFailureKind.operationFailed);
    expect(error.operation, CassetteStoreOperation.exists);
    expect(error.toString(), isNot(contains(missingRoot.path)));
  });
}

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

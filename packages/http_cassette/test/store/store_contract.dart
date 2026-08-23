import 'dart:async';
import 'dart:convert';

import 'package:http_cassette/http_cassette.dart';
import 'package:test/test.dart';

/// Creates one fresh store for a reusable behaviour contract test.
typedef CassetteStoreFactory = FutureOr<CassetteStore> Function();

/// Defines the behaviour required of every complete [CassetteStore].
void defineCassetteStoreContract(CassetteStoreFactory createStore) {
  group('CassetteStore contract', () {
    late CassetteStore store;

    setUp(() async {
      store = await createStore();
    });

    test('reports and reads missing cassettes consistently', () async {
      final name = CassetteName('missing');

      expect(await store.exists(name), isFalse);
      await _expectStoreFailure(
        () => store.read(name),
        kind: CassetteStoreFailureKind.notFound,
        operation: CassetteStoreOperation.read,
        name: name,
      );
    });

    test('creates and reads a defensively copied snapshot', () async {
      final name = CassetteName('created');
      final input = _firstCassetteBytes();
      final creating = store.create(name, input);
      input[0] = 0x20;

      await creating;
      final snapshot = await store.read(name);

      expect(await store.exists(name), isTrue);
      expect(snapshot.name, name);
      expect(snapshot.bytes, _firstCassetteBytes());
      expect(() => snapshot.bytes[0] = 0x20, throwsUnsupportedError);
    });

    test('does not replace an existing cassette during create', () async {
      final name = CassetteName('existing');
      await store.create(name, _firstCassetteBytes());

      await _expectStoreFailure(
        () => store.create(name, _secondCassetteBytes()),
        kind: CassetteStoreFailureKind.alreadyExists,
        operation: CassetteStoreOperation.create,
        name: name,
      );

      expect((await store.read(name)).bytes, _firstCassetteBytes());
    });

    test('requires an existing cassette for explicit replacement', () async {
      final name = CassetteName('replace_missing');

      await _expectStoreFailure(
        () => store.replace(name, _secondCassetteBytes()),
        kind: CassetteStoreFailureKind.notFound,
        operation: CassetteStoreOperation.replace,
        name: name,
      );
    });

    test('replaces bytes defensively and changes the revision', () async {
      final name = CassetteName('replace');
      await store.create(name, _firstCassetteBytes());
      final before = await store.read(name);
      final input = _secondCassetteBytes();
      final replacing = store.replace(name, input);
      input[0] = 0x20;

      await replacing;
      final after = await store.read(name);

      expect(after.bytes, _secondCassetteBytes());
      expect(after.revision, isNot(same(before.revision)));
    });

    test('conditionally replaces a current snapshot', () async {
      final name = CassetteName('conditional');
      await store.create(name, _firstCassetteBytes());
      final before = await store.read(name);
      final input = _secondCassetteBytes();
      final replacing = store.replaceIfUnchanged(before, input);
      input[0] = 0x20;

      await replacing;
      final after = await store.read(name);

      expect(after.bytes, _secondCassetteBytes());
      expect(after.revision, isNot(same(before.revision)));
    });

    test('rejects a stale revision without replacing bytes', () async {
      final name = CassetteName('stale');
      await store.create(name, _firstCassetteBytes());
      final stale = await store.read(name);
      await store.replace(name, _secondCassetteBytes());

      await _expectStoreFailure(
        () => store.replaceIfUnchanged(stale, _thirdCassetteBytes()),
        kind: CassetteStoreFailureKind.revisionChanged,
        operation: CassetteStoreOperation.replaceIfUnchanged,
        name: name,
      );

      expect((await store.read(name)).bytes, _secondCassetteBytes());
    });

    test('serialises conflicting creates in invocation order', () async {
      final name = CassetteName('concurrent');
      final first = store.create(name, _firstCassetteBytes());
      final second = _expectStoreFailure(
        () => store.create(name, _secondCassetteBytes()),
        kind: CassetteStoreFailureKind.alreadyExists,
        operation: CassetteStoreOperation.create,
        name: name,
      );

      await first;
      await second;

      expect((await store.read(name)).bytes, _firstCassetteBytes());
    });
  });
}

Future<void> _expectStoreFailure(
  FutureOr<Object?> Function() action, {
  required CassetteStoreFailureKind kind,
  required CassetteStoreOperation operation,
  required CassetteName name,
}) async {
  try {
    await action();
  } on CassetteStoreException catch (error) {
    expect(error.kind, kind);
    expect(error.operation, operation);
    expect(error.name, name);
    return;
  }
  fail('Expected a CassetteStoreException.');
}

List<int> _firstCassetteBytes() =>
    utf8.encode('{"schemaVersion":1,"interactions":[]}');

List<int> _secondCassetteBytes() =>
    utf8.encode('{"schemaVersion":1,"interactions":[]}\n');

List<int> _thirdCassetteBytes() =>
    utf8.encode(' {"schemaVersion":1,"interactions":[]}');

import 'dart:async';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/adapter/interception.dart';
import 'package:test/test.dart';

void main() {
  group('inactive CassetteInterception', () {
    test('requires no canonical buffering or body limits', () {
      final engine = CassetteEngine(store: MemoryCassetteStore());

      final interception = engine.beginInterception();

      expect(interception.isActive, isFalse);
      expect(interception.bodyLimits, isNull);
      expect(
        () => claimCassetteInterception(interception),
        throwsA(
          isA<CassetteException>().having(
            (exception) => exception.diagnostic.category,
            'category',
            DiagnosticCategory.adapterContractViolation,
          ),
        ),
      );
      expect(engine.isActive, isFalse);
      expect(engine.activeSession, isNull);
    });

    test('remains inactive when a later session starts', () async {
      final engine = CassetteEngine(store: MemoryCassetteStore());
      final interception = engine.beginInterception();

      final session = await engine.startRecording('later');

      expect(interception.isActive, isFalse);
      expect(interception.bodyLimits, isNull);
      await session.discard();
    });

    test('fails closed while session startup is pending', () async {
      final exists = Completer<bool>();
      final engine = CassetteEngine(store: _DelayedExistsStore(exists.future));
      final start = engine.startRecording('pending');

      expect(engine.beginInterception, throwsStateError);

      exists.complete(false);
      final session = await start;
      await session.discard();
    });

    test('is available using only the public package library', () {
      final CassetteInterception interception =
          CassetteEngine(store: MemoryCassetteStore()).beginInterception();

      expect(interception.isActive, isFalse);
    });
  });
}

final class _DelayedExistsStore implements CassetteStore {
  _DelayedExistsStore(this.existsResult);

  final Future<bool> existsResult;

  @override
  int get maximumBytes => 64 * 1024 * 1024;

  @override
  Future<bool> exists(CassetteName name) => existsResult;

  @override
  Future<void> create(CassetteName name, List<int> bytes) =>
      throw UnimplementedError();

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

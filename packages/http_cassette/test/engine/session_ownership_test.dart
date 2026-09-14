import 'dart:async';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/engine/session_ownership.dart';
import 'package:test/test.dart';

void main() {
  group('EngineSessionOwnership', () {
    test('starts inactive and reserves one session', () {
      final ownership = EngineSessionOwnership();

      expect(ownership.isActive, isFalse);
      expect(ownership.activeSession, isNull);

      final session = _acquire(ownership, name: 'checkout/declined');

      expect(ownership.isActive, isTrue);
      expect(ownership.activeSession, same(session));
      expect(session.name, 'checkout/declined');
    });

    test('blocks another start while preparation is reserved', () {
      final ownership = EngineSessionOwnership();
      final reservation = ownership.reserve(CassetteMode.replay);

      expect(ownership.isActive, isTrue);
      expect(ownership.activeSession, isNull);
      expect(
        () => ownership.reserve(CassetteMode.record),
        throwsA(isA<CassetteException>()),
      );

      reservation.cancel();
      expect(ownership.isActive, isFalse);
    });

    test('activates a prepared reservation exactly once', () {
      final ownership = EngineSessionOwnership();
      final reservation = ownership.reserve(CassetteMode.replay);

      final session = reservation.activate(
        name: CassetteName('prepared'),
        mode: CassetteMode.replay,
        closeAction: () async {},
        discardAction: () async {},
      );

      expect(ownership.activeSession, same(session));
      expect(() => reservation.cancel(), throwsStateError);
    });

    test('rejects a conflicting start without replacing the active session',
        () {
      final ownership = EngineSessionOwnership();
      final active = _acquire(ownership, mode: CassetteMode.record);

      expect(
        () => _acquire(ownership),
        throwsA(
          isA<CassetteException>()
              .having(
                (error) => error.diagnostic.category,
                'category',
                DiagnosticCategory.conflictingSessionOperation,
              )
              .having(
                (error) => error.diagnostic.networkAccess,
                'networkAccess',
                NetworkAccess.disabled,
              ),
        ),
      );
      expect(ownership.activeSession, same(active));
    });

    test('reports a requested recording conflict before network access', () {
      final ownership = EngineSessionOwnership();
      _acquire(ownership);

      expect(
        () => _acquire(ownership, mode: CassetteMode.record),
        throwsA(
          isA<CassetteException>().having(
            (error) => error.diagnostic.networkAccess,
            'networkAccess',
            NetworkAccess.notAttempted,
          ),
        ),
      );
    });

    test('releases ownership after successful close', () async {
      final ownership = EngineSessionOwnership();
      final session = _acquire(ownership);

      await session.close();

      expect(session.isClosed, isTrue);
      expect(ownership.isActive, isFalse);
      expect(ownership.activeSession, isNull);
    });

    test('releases ownership after successful discard', () async {
      final ownership = EngineSessionOwnership();
      final session = _acquire(ownership);

      await session.discard();

      expect(session.isClosed, isTrue);
      expect(ownership.isActive, isFalse);
    });

    test('retains ownership while completion is in progress', () async {
      final completion = Completer<void>();
      final ownership = EngineSessionOwnership();
      final session = _acquire(
        ownership,
        closeAction: () => completion.future,
      );

      final closeFuture = session.close();

      expect(ownership.activeSession, same(session));
      expect(() => _acquire(ownership), throwsA(isA<CassetteException>()));

      completion.complete();
      await closeFuture;
      expect(ownership.isActive, isFalse);
    });

    test('retains ownership after a completion failure', () async {
      final ownership = EngineSessionOwnership();
      final failure = StateError('safe test failure');
      final session = _acquire(
        ownership,
        discardAction: () async => throw failure,
      );

      await expectLater(session.discard(), throwsA(same(failure)));

      expect(ownership.activeSession, same(session));
      expect(() => _acquire(ownership), throwsA(isA<CassetteException>()));
    });

    test('releases ownership after any close failure', () async {
      final ownership = EngineSessionOwnership();
      final failure = StateError('safe test failure');
      final session = _acquire(
        ownership,
        mode: CassetteMode.record,
        closeAction: () async => throw failure,
      );

      await expectLater(session.close(), throwsA(same(failure)));

      expect(session.isClosed, isTrue);
      expect(ownership.isActive, isFalse);
      expect(ownership.activeSession, isNull);
      expect(() => _acquire(ownership), returnsNormally);
    });

    test('an old completed session cannot release a newer session', () async {
      final ownership = EngineSessionOwnership();
      final first = _acquire(ownership);
      await first.close();

      final second = _acquire(ownership, name: 'second');
      await first.discard();

      expect(ownership.activeSession, same(second));
    });

    test('separate owners support independent active sessions', () {
      final firstOwner = EngineSessionOwnership();
      final secondOwner = EngineSessionOwnership();

      final first = _acquire(firstOwner, name: 'first');
      final second = _acquire(secondOwner, name: 'second');

      expect(firstOwner.activeSession, same(first));
      expect(secondOwner.activeSession, same(second));
    });
  });
}

CassetteSession _acquire(
  EngineSessionOwnership ownership, {
  String name = 'example',
  CassetteMode mode = CassetteMode.replay,
  Future<void> Function()? closeAction,
  Future<void> Function()? discardAction,
}) =>
    ownership.acquire(
      name: CassetteName(name),
      mode: mode,
      closeAction: closeAction ?? () async {},
      discardAction: discardAction ?? () async {},
    );

import 'dart:convert';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/adapter/interception.dart';
import 'package:test/test.dart';

void main() {
  group('active CassetteInterception', () {
    test('pins the prepared session and exposes exact body limits', () async {
      final bodyLimits = BodyLimits(requestBytes: 12, responseBytes: 34);
      final engine = CassetteEngine(
        store: MemoryCassetteStore(),
        configuration: CassetteConfiguration(bodyLimits: bodyLimits),
      );
      final session = await engine.startRecording('active');

      final interception = engine.beginInterception();

      expect(interception.isActive, isTrue);
      expect(interception.bodyLimits, same(bodyLimits));
      expect(cassetteInterceptionPinsSession(interception, session), isTrue);
      await session.discard();
    });

    test('can be claimed once for its exact pinned session', () async {
      final engine = CassetteEngine(store: MemoryCassetteStore());
      final session = await engine.startRecording('one-claim');
      final interception = engine.beginInterception();

      expect(claimCassetteInterception(interception), same(session));
      expect(
        () => claimCassetteInterception(interception),
        throwsA(
          isA<CassetteException>()
              .having(
                (exception) => exception.diagnostic.category,
                'category',
                DiagnosticCategory.adapterContractViolation,
              )
              .having(
                (exception) => exception.diagnostic.networkAccess,
                'network access',
                NetworkAccess.notAttempted,
              ),
        ),
      );
      await session.discard();
    });

    test('does not drift into a later session', () async {
      final engine = CassetteEngine(store: MemoryCassetteStore());
      final firstSession = await engine.startRecording('first');
      final interception = engine.beginInterception();
      await firstSession.discard();

      final secondSession = await engine.startRecording('second');

      expect(interception.isActive, isTrue);
      expect(
          cassetteInterceptionPinsSession(interception, firstSession), isTrue);
      expect(
        cassetteInterceptionPinsSession(interception, secondSession),
        isFalse,
      );
      await secondSession.discard();
    });

    test('claims the original session after a later session starts', () async {
      final engine = CassetteEngine(store: MemoryCassetteStore());
      final firstSession = await engine.startRecording('first-claim');
      final interception = engine.beginInterception();
      await firstSession.discard();
      final secondSession = await engine.startRecording('second-claim');

      expect(claimCassetteInterception(interception), same(firstSession));

      await secondSession.discard();
    });

    test('pins replay sessions with the same body-limit contract', () async {
      final store = MemoryCassetteStore();
      final name = CassetteName('replay');
      await store.create(
        name,
        utf8.encode('{"schemaVersion":1,"interactions":[]}'),
      );
      final engine = CassetteEngine(store: store);
      final session = await engine.startReplay(name.value);

      final interception = engine.beginInterception();

      expect(interception.isActive, isTrue);
      expect(interception.bodyLimits, isNotNull);
      expect(cassetteInterceptionPinsSession(interception, session), isTrue);
      expect(claimCassetteInterception(interception), same(session));
      await session.discard();
    });
  });
}

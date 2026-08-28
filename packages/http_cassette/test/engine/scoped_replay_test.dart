import 'dart:async';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/cassette.dart';
import 'package:http_cassette/src/cassette/encoder.dart';
import 'package:http_cassette/src/cassette/interaction.dart';
import 'package:test/test.dart';

void main() {
  group('CassetteEngine.replay', () {
    test('loads first and returns a generic value after close', () async {
      final engine = await _engine(Cassette());
      final value = <String>['complete'];
      late CassetteSession callbackSession;

      final result = await engine.replay<List<String>>('recording', () async {
        callbackSession = engine.activeSession!;
        expect(callbackSession.mode, CassetteMode.replay);
        expect(engine.isActive, isTrue);
        return value;
      });

      expect(result, same(value));
      expect(callbackSession.isClosed, isTrue);
      expect(engine.isActive, isFalse);
      expect(engine.activeSession, isNull);
    });

    test('does not invoke the callback when loading fails', () async {
      final engine = CassetteEngine(store: MemoryCassetteStore());
      var invoked = false;

      await expectLater(
        engine.replay<void>('missing', () {
          invoked = true;
        }),
        throwsA(
          isA<CassetteException>().having(
            (exception) => exception.diagnostic.category,
            'category',
            DiagnosticCategory.cassetteMissing,
          ),
        ),
      );

      expect(invoked, isFalse);
      expect(engine.isActive, isFalse);
    });

    test('discards and rethrows a callback failure with its stack', () async {
      final engine = await _engine(_cassetteWithOneInteraction());
      final error = StateError('callback failed');
      final stackTrace = StackTrace.current;

      try {
        await engine.replay<void>(
          'recording',
          () => Future<void>.error(error, stackTrace),
          options: const ReplayOptions(requireAllInteractions: true),
        );
        fail('The callback failure should have been rethrown.');
      } on Object catch (caught, caughtStackTrace) {
        expect(caught, same(error));
        expect(caughtStackTrace, same(stackTrace));
      }

      expect(engine.isActive, isFalse);
      expect(engine.activeSession, isNull);
    });

    test('enforces required usage after a successful callback', () async {
      final engine = await _engine(_cassetteWithOneInteraction());
      var invoked = false;

      await expectLater(
        engine.replay<int>(
          'recording',
          () {
            invoked = true;
            return 42;
          },
          options: const ReplayOptions(requireAllInteractions: true),
        ),
        throwsA(
          isA<CassetteException>().having(
            (exception) => exception.diagnostic.category,
            'category',
            DiagnosticCategory.unusedInteractions,
          ),
        ),
      );

      expect(invoked, isTrue);
      expect(engine.isActive, isTrue);
      expect(engine.activeSession!.isClosed, isFalse);
    });

    test('passes explicit options when required usage is satisfied', () async {
      final engine = await _engine(Cassette());

      final result = await engine.replay<int>(
        'recording',
        () => 42,
        options: const ReplayOptions(
          policy: ReplayPolicy.cycle,
          requireAllInteractions: true,
        ),
      );

      expect(result, 42);
      expect(engine.isActive, isFalse);
    });
  });
}

Future<CassetteEngine> _engine(Cassette cassette) async {
  final store = MemoryCassetteStore();
  await store.create(
    CassetteName('recording'),
    encodeCassetteV1(cassette),
  );
  return CassetteEngine(store: store);
}

Cassette _cassetteWithOneInteraction() => Cassette(
      interactions: <CassetteInteraction>[
        CassetteInteraction(
          index: 0,
          request: CassetteRequest(
            method: 'GET',
            uri: Uri.parse('https://example.test/items'),
          ),
          outcome: CassetteResponseOutcome(
            CassetteResponse(statusCode: 200),
          ),
        ),
      ],
    );

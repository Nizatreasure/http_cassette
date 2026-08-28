import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/cassette.dart';
import 'package:http_cassette/src/cassette/encoder.dart';
import 'package:http_cassette/src/cassette/interaction.dart';
import 'package:http_cassette/src/engine/cassette_engine.dart';
import 'package:http_cassette/src/replay/active_state.dart';
import 'package:test/test.dart';

void main() {
  group('replay session close', () {
    test('skips verification by default and clears replay state', () async {
      final engine = await _engine(_cassetteWithOneInteraction());
      final session = await engine.startReplay('recording');

      await session.close();

      expect(session.isClosed, isTrue);
      expect(engine.isActive, isFalse);
      expect(engine.activeSession, isNull);
    });

    test('passes required verification for an empty cassette', () async {
      final engine = await _engine(Cassette());
      final session = await engine.startReplay(
        'recording',
        options: const ReplayOptions(requireAllInteractions: true),
      );

      await session.close();

      expect(engine.isActive, isFalse);
    });

    test('fails required verification with safe complete usage facts',
        () async {
      final engine = await _engine(_cassetteWithOneInteraction());
      final session = await engine.startReplay(
        'recording',
        options: const ReplayOptions(requireAllInteractions: true),
      );

      late CassetteException exception;
      try {
        await session.close();
        fail('Unused-interaction verification should have failed.');
      } on CassetteException catch (failure) {
        exception = failure;
      }

      expect(
        exception.diagnostic.category,
        DiagnosticCategory.unusedInteractions,
      );
      expect(exception.diagnostic.networkAccess, NetworkAccess.disabled);
      expect(exception.toString(), contains('Unused indices: 0'));
      expect(engine.isActive, isTrue);
      expect(engine.activeSession, same(session));
      expect(session.isClosed, isFalse);
    });

    test('passes required verification after every interaction is used',
        () async {
      final state = EngineState(
        store: MemoryCassetteStore(),
        configuration: CassetteConfiguration(),
      );
      final cassette = _cassetteWithOneInteraction();
      state.activeReplay = ActiveReplayState(
        cassetteName: CassetteName('recording'),
        cassette: cassette,
        configuration: CassetteConfiguration(),
        options: const ReplayOptions(requireAllInteractions: true),
      );
      state.activeReplay!.selectRequest(cassette.interactions.single.request);

      await state.completeActiveReplay();

      expect(state.activeReplay, isNull);
    });

    test('discard skips required verification', () async {
      final engine = await _engine(_cassetteWithOneInteraction());
      final session = await engine.startReplay(
        'recording',
        options: const ReplayOptions(requireAllInteractions: true),
      );

      await session.discard();

      expect(engine.isActive, isFalse);
      expect(session.isClosed, isTrue);
    });
  });
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

Future<CassetteEngine> _engine(Cassette cassette) async {
  final store = MemoryCassetteStore();
  await store.create(CassetteName('recording'), encodeCassetteV1(cassette));
  return CassetteEngine(store: store);
}

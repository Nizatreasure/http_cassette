import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/adapter/interception.dart';
import 'package:test/test.dart';

void main() {
  group('pinned interception execution', () {
    test('records and replays through the exact session mode', () async {
      final store = MemoryCassetteStore();
      final engine = CassetteEngine(store: store);
      final request = _request('/items');
      final liveOutcome = CassetteResponseOutcome(
        CassetteResponse(statusCode: 201),
      );
      final recording = await engine.startRecording('pinned-route');
      final recordingInterception = engine.beginInterception();
      var recordingAttempts = 0;

      final recorded = await executeCassetteInterception(
        recordingInterception,
        request,
        () async {
          recordingAttempts++;
          return liveOutcome;
        },
      );
      await recording.close();

      final replay = await engine.startReplay('pinned-route');
      final replayInterception = engine.beginInterception();
      var replayAttempted = false;
      final replayed = await executeCassetteInterception(
        replayInterception,
        request,
        () async {
          replayAttempted = true;
          return CassetteResponseOutcome(CassetteResponse(statusCode: 500));
        },
      );

      expect(recorded, same(liveOutcome));
      expect(recordingAttempts, 1);
      expect(
        (replayed as CassetteResponseOutcome).response.statusCode,
        201,
      );
      expect(replayAttempted, isFalse);
      await replay.discard();
    });

    test('rejects an old permit instead of routing into a later session',
        () async {
      final engine = CassetteEngine(store: MemoryCassetteStore());
      final first = await engine.startRecording('first');
      final oldInterception = engine.beginInterception();
      await first.discard();
      final second = await engine.startRecording('second');
      var attempted = false;

      await expectLater(
        executeCassetteInterception(
          oldInterception,
          _request('/items'),
          () async {
            attempted = true;
            return CassetteResponseOutcome(CassetteResponse(statusCode: 200));
          },
        ),
        throwsA(
          isA<CassetteException>()
              .having(
                (exception) => exception.diagnostic.category,
                'category',
                DiagnosticCategory.sessionAlreadyClosed,
              )
              .having(
                (exception) => exception.diagnostic.networkAccess,
                'network access',
                NetworkAccess.notAttempted,
              ),
        ),
      );
      expect(attempted, isFalse);

      await second.discard();
    });
  });
}

CassetteRequest _request(String path) => CassetteRequest(
      method: 'GET',
      uri: Uri.parse('https://example.test$path'),
    );

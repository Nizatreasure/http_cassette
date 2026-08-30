import 'package:http_cassette/http_cassette.dart';
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

      final recorded = await recordingInterception.proceed(
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
      final replayed = await replayInterception.proceed(
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
        oldInterception.proceed(
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

    test('rejects inactive and repeated public execution safely', () async {
      final engine = CassetteEngine(store: MemoryCassetteStore());
      final inactive = engine.beginInterception();
      var inactiveAttempted = false;

      await expectLater(
        inactive.proceed(
          _request('/inactive'),
          () async {
            inactiveAttempted = true;
            return CassetteResponseOutcome(CassetteResponse(statusCode: 200));
          },
        ),
        throwsA(
          isA<CassetteException>().having(
            (exception) => exception.diagnostic.category,
            'category',
            DiagnosticCategory.adapterContractViolation,
          ),
        ),
      );
      expect(inactiveAttempted, isFalse);

      final session = await engine.startRecording('one-public-proceed');
      final active = engine.beginInterception();
      await active.proceed(
        _request('/active'),
        () async => CassetteResponseOutcome(CassetteResponse(statusCode: 200)),
      );
      var repeatedAttempted = false;
      await expectLater(
        active.proceed(
          _request('/active'),
          () async {
            repeatedAttempted = true;
            return CassetteResponseOutcome(CassetteResponse(statusCode: 500));
          },
        ),
        throwsA(
          isA<CassetteException>().having(
            (exception) => exception.diagnostic.category,
            'category',
            DiagnosticCategory.adapterContractViolation,
          ),
        ),
      );
      expect(repeatedAttempted, isFalse);
      await session.discard();
    });
  });
}

CassetteRequest _request(String path) => CassetteRequest(
      method: 'GET',
      uri: Uri.parse('https://example.test$path'),
    );

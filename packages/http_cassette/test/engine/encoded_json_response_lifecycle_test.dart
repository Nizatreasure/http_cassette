import 'dart:convert';
import 'dart:io';

import 'package:http_cassette/http_cassette.dart';
import 'package:test/test.dart';

void main() {
  group('encoded JSON response lifecycle', () {
    test('retains captured gzip bytes without sanitisation', () async {
      await _verifyUnsanitisedLifecycle(capturedBodyIsDecompressed: false);
    });

    test('recompresses client-decoded JSON without sanitisation', () async {
      await _verifyUnsanitisedLifecycle(capturedBodyIsDecompressed: true);
    });

    test('persists and replays decoded gzip JSON as plain content', () async {
      await _verifyLifecycle(
        handling: GzipJsonResponseHandling.sanitiseAndStorePlain,
        expectedPersistedEncoding: 'json',
        expectedReplayIsGzip: false,
      );
    });

    test('persists client-decompressed gzip JSON as plain content', () async {
      await _verifyLifecycle(
        handling: GzipJsonResponseHandling.sanitiseAndStorePlain,
        expectedPersistedEncoding: 'json',
        expectedReplayIsGzip: false,
        capturedBodyIsDecompressed: true,
      );
    });

    test('persists and replays sanitised JSON as gzip content', () async {
      await _verifyLifecycle(
        handling: GzipJsonResponseHandling.sanitiseAndStoreCompressed,
        expectedPersistedEncoding: 'base64',
        expectedReplayIsGzip: true,
      );
    });

    test('compresses client-decoded sanitised JSON only for storage', () async {
      await _verifyLifecycle(
        handling: GzipJsonResponseHandling.sanitiseAndStoreCompressed,
        expectedPersistedEncoding: 'gzipBase64',
        expectedReplayIsGzip: false,
        capturedBodyIsDecompressed: true,
      );
    });
  });
}

Future<void> _verifyUnsanitisedLifecycle({
  required bool capturedBodyIsDecompressed,
}) async {
  final store = MemoryCassetteStore();
  final engine = CassetteEngine(store: store);
  const cassetteName = 'opaque-encoded-response';
  final request = CassetteRequest(
    method: 'GET',
    uri: Uri.parse('https://example.test/items'),
  );
  final plainBytes = utf8.encode('{"token":"synthetic-secret","keep":true}');
  final capturedBytes =
      capturedBodyIsDecompressed ? plainBytes : gzip.encode(plainBytes);
  final outcome = CassetteResponseOutcome(
    CassetteResponse(
      statusCode: 200,
      headers: CassetteHeaders(<String, Iterable<String>>{
        'content-type': <String>['application/json'],
        'content-encoding': <String>['gzip'],
      }),
      body: capturedBytes,
    ),
  );

  final recording = await engine.startRecording(cassetteName);
  await engine.beginInterception().proceed(request, () async => outcome);
  await recording.close();

  final snapshot = await store.read(CassetteName(cassetteName));
  final root = jsonDecode(utf8.decode(snapshot.bytes)) as Map<String, Object?>;
  final interaction =
      (root['interactions']! as List<Object?>).single as Map<String, Object?>;
  final storedOutcome = interaction['outcome']! as Map<String, Object?>;
  final storedBody = storedOutcome['body']! as Map<String, Object?>;
  expect(
    storedBody['encoding'],
    capturedBodyIsDecompressed ? 'gzipBase64' : 'base64',
  );
  expect(
    (storedOutcome['headers']! as Map<String, Object?>)['content-encoding'],
    <Object?>['gzip'],
  );

  var networkAttempts = 0;
  final replay = await engine.startReplay(cassetteName);
  final replayed = await engine.beginInterception().proceed(
    request,
    () async {
      networkAttempts += 1;
      return outcome;
    },
  ) as CassetteResponseOutcome;

  expect(networkAttempts, 0);
  expect(
    replayed.response.body,
    capturedBodyIsDecompressed ? plainBytes : capturedBytes,
  );
  expect(
    replayed.response.headers.values('content-encoding'),
    <String>['gzip'],
  );
  final replayedPlainBytes = capturedBodyIsDecompressed
      ? replayed.response.body
      : gzip.decode(replayed.response.body);
  expect(utf8.decode(replayedPlainBytes), contains('synthetic-secret'));
  await replay.close();
}

Future<void> _verifyLifecycle({
  required GzipJsonResponseHandling handling,
  required String expectedPersistedEncoding,
  required bool expectedReplayIsGzip,
  bool capturedBodyIsDecompressed = false,
}) async {
  final store = MemoryCassetteStore();
  final engine = CassetteEngine(
    store: store,
    configuration: CassetteConfiguration(
      sanitisation: SanitisationConfiguration(
        gzipJsonResponses: handling,
      ),
    ),
  );
  const cassetteName = 'encoded-response';
  final request = CassetteRequest(
    method: 'GET',
    uri: Uri.parse('https://example.test/items'),
  );
  final plainBytes = utf8.encode('{"token":"synthetic-secret","keep":true}');
  final originalBytes =
      capturedBodyIsDecompressed ? plainBytes : gzip.encode(plainBytes);
  final liveOutcome = CassetteResponseOutcome(
    CassetteResponse(
      statusCode: 200,
      headers: CassetteHeaders(<String, Iterable<String>>{
        'content-type': <String>['application/json'],
        'content-encoding': <String>['gzip'],
      }),
      body: originalBytes,
    ),
  );
  var recordingNetworkAttempts = 0;

  final recording = await engine.startRecording(cassetteName);
  final liveResult = await engine.beginInterception().proceed(
    request,
    () async {
      recordingNetworkAttempts += 1;
      return liveOutcome;
    },
  );

  expect(liveResult, same(liveOutcome));
  expect(recordingNetworkAttempts, 1);
  expect(
    (liveResult as CassetteResponseOutcome).response.body,
    originalBytes,
  );
  await recording.close();

  final snapshot = await store.read(CassetteName(cassetteName));
  final root = jsonDecode(utf8.decode(snapshot.bytes)) as Map<String, Object?>;
  final interactions = root['interactions']! as List<Object?>;
  final interaction = interactions.single as Map<String, Object?>;
  final storedOutcome = interaction['outcome']! as Map<String, Object?>;
  final storedBody = storedOutcome['body']! as Map<String, Object?>;
  final storedHeaders = storedOutcome['headers']! as Map<String, Object?>;

  expect(storedBody['encoding'], expectedPersistedEncoding);
  expect(storedHeaders['content-encoding'], <Object?>['gzip']);
  if (expectedPersistedEncoding == 'json') {
    expect(storedBody['content'], <String, Object?>{
      'keep': true,
      'token': '[REDACTED]',
    });
  }

  var replayNetworkAttempts = 0;
  final replay = await engine.startReplay(cassetteName);
  final replayed = await engine.beginInterception().proceed(
    request,
    () async {
      replayNetworkAttempts += 1;
      return liveOutcome;
    },
  ) as CassetteResponseOutcome;

  expect(replayNetworkAttempts, 0);
  expect(replayed.response.statusCode, 200);
  expect(
    replayed.response.headers.values('content-encoding'),
    <String>['gzip'],
  );
  final replayedPlainBytes = expectedReplayIsGzip
      ? gzip.decode(replayed.response.body)
      : replayed.response.body;
  expect(utf8.decode(replayedPlainBytes), '{"keep":true,"token":"[REDACTED]"}');
  await replay.close();
}

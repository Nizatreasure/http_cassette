import 'dart:convert';
import 'dart:io';

import 'package:http_cassette/http_cassette.dart';
import 'package:test/test.dart';

void main() {
  group('encoded JSON response lifecycle', () {
    test('persists and replays decoded gzip JSON as plain content', () async {
      await _verifyLifecycle(
        handling: EncodedJsonResponseHandling.decodeAndStorePlain,
        expectedPersistedEncoding: 'json',
        expectRecompressed: false,
      );
    });

    test('persists client-decompressed gzip JSON as plain content', () async {
      await _verifyLifecycle(
        handling: EncodedJsonResponseHandling.decodeAndStorePlain,
        expectedPersistedEncoding: 'json',
        expectRecompressed: false,
        capturedBodyIsDecompressed: true,
      );
    });

    test('persists and replays sanitised JSON as gzip content', () async {
      await _verifyLifecycle(
        handling: EncodedJsonResponseHandling.decodeAndRecompress,
        expectedPersistedEncoding: 'base64',
        expectRecompressed: true,
      );
    });
  });
}

Future<void> _verifyLifecycle({
  required EncodedJsonResponseHandling handling,
  required String expectedPersistedEncoding,
  required bool expectRecompressed,
  bool capturedBodyIsDecompressed = false,
}) async {
  final store = MemoryCassetteStore();
  final engine = CassetteEngine(
    store: store,
    configuration: CassetteConfiguration(
      sanitisation: SanitisationConfiguration(
        encodedJsonResponses: handling,
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
  if (expectRecompressed) {
    expect(storedHeaders['content-encoding'], <Object?>['gzip']);
  } else {
    expect(storedHeaders.containsKey('content-encoding'), isFalse);
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
  if (expectRecompressed) {
    expect(
      replayed.response.headers.values('content-encoding'),
      <String>['gzip'],
    );
    expect(
      utf8.decode(gzip.decode(replayed.response.body)),
      '{"keep":true,"token":"[REDACTED]"}',
    );
  } else {
    expect(replayed.response.headers.contains('content-encoding'), isFalse);
    expect(
      utf8.decode(replayed.response.body),
      '{"keep":true,"token":"[REDACTED]"}',
    );
  }
  await replay.close();
}

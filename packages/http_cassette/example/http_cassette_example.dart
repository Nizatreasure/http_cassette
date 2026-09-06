import 'package:http_cassette/http_cassette.dart';

Future<void> main() async {
  final engine = CassetteEngine(store: MemoryCassetteStore());
  final adapter = ExampleAdapter(engine);
  final request = CassetteRequest(
    method: 'GET',
    uri: Uri.parse('https://api.example.test/profile'),
    headers: CassetteHeaders(<String, Iterable<String>>{
      'accept': <String>['application/json'],
    }),
  );

  final recording = await engine.startRecording('profiles/current-user');
  final liveOutcome = await adapter.send(request);
  await recording.close();

  final replay = await engine.startReplay('profiles/current-user');
  final replayedOutcome = await adapter.send(request);
  await replay.close();

  final liveResponse = (liveOutcome as CassetteResponseOutcome).response;
  final replayedResponse =
      (replayedOutcome as CassetteResponseOutcome).response;

  assert(liveResponse.statusCode == 200);
  assert(replayedResponse.statusCode == 200);
  assert(adapter.realAttemptCount == 1);
}

final class ExampleAdapter {
  ExampleAdapter(this.engine);

  final CassetteEngine engine;
  var realAttemptCount = 0;

  Future<CassetteOutcome> send(CassetteRequest request) {
    final interception = engine.beginInterception();
    if (!interception.isActive) {
      return _sendRealRequest();
    }
    return interception.proceed(request, _sendRealRequest);
  }

  Future<CassetteOutcome> _sendRealRequest() async {
    realAttemptCount += 1;
    return CassetteResponseOutcome(
      CassetteResponse(
        statusCode: 200,
        headers: CassetteHeaders(<String, Iterable<String>>{
          'content-type': <String>['application/json'],
        }),
        body: <int>[123, 125],
      ),
    );
  }
}

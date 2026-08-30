import 'package:http_cassette/http_cassette.dart';

import 'adapter_contract.dart';

final class FakeHttpAdapter implements AdapterContractDriver {
  FakeHttpAdapter(this._engine, this._transport);

  final CassetteEngine _engine;
  final AdapterContractTransport _transport;

  var _canonicalRequestCount = 0;
  var _realAttemptCount = 0;

  @override
  int get canonicalRequestCount => _canonicalRequestCount;

  @override
  int get realAttemptCount => _realAttemptCount;

  @override
  Future<AdapterContractResponse> send(AdapterContractRequest request) async {
    final interception = _engine.beginInterception();
    if (!interception.isActive) {
      _realAttemptCount++;
      return _transport(request);
    }

    _canonicalRequestCount++;
    final outcome = await interception.proceed(
      CassetteRequest(
        method: request.method,
        uri: request.uri,
        headers: CassetteHeaders(request.headers),
        body: request.body,
      ),
      () async {
        _realAttemptCount++;
        final response = await _transport(request);
        return CassetteResponseOutcome(
          CassetteResponse(
            statusCode: response.statusCode,
            headers: CassetteHeaders(response.headers),
            body: response.body,
          ),
        );
      },
    );

    return switch (outcome) {
      CassetteResponseOutcome(:final response) => AdapterContractResponse(
          statusCode: response.statusCode,
          headers: <String, List<String>>{
            for (final name in response.headers.names)
              name: response.headers.values(name)!,
          },
          body: response.body,
        ),
      CassetteTransportFailure() => throw StateError(
          'The basic fake adapter contract covers responses only.',
        ),
    };
  }
}

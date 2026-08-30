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
  Future<AdapterContractOutcome> send(
    AdapterContractRequest request, {
    CassetteCancellation? cancellation,
  }) async {
    final interception = _engine.beginInterception();
    if (!interception.isActive) {
      _realAttemptCount++;
      return _transport(request);
    }
    final bodyLimits = interception.bodyLimits!;
    if (request.body.length > bodyLimits.requestBytes) {
      throw _bodyLimitException(
        summary: 'The request body exceeded its configured limit.',
        networkAccess: NetworkAccess.notAttempted,
      );
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
        final transportOutcome = await _transport(request);
        if (transportOutcome case AdapterContractResponse(:final body)
            when body.length > bodyLimits.responseBytes) {
          throw _bodyLimitException(
            summary: 'The response body exceeded its configured limit.',
            networkAccess: NetworkAccess.attempted,
          );
        }
        return switch (transportOutcome) {
          AdapterContractResponse() => CassetteResponseOutcome(
              CassetteResponse(
                statusCode: transportOutcome.statusCode,
                headers: CassetteHeaders(transportOutcome.headers),
                body: transportOutcome.body,
              ),
            ),
          AdapterContractFailure() => CassetteTransportFailure(
              category: transportOutcome.category,
              message: transportOutcome.message,
            ),
        };
      },
      cancellation: cancellation,
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
      CassetteTransportFailure(:final category, :final message) =>
        AdapterContractFailure(
          category: category,
          message: message,
        ),
    };
  }
}

CassetteException _bodyLimitException({
  required String summary,
  required NetworkAccess networkAccess,
}) =>
    CassetteException(
      CassetteDiagnostic(
        category: DiagnosticCategory.bodyLimitExceeded,
        summary: summary,
        networkAccess: networkAccess,
      ),
    );

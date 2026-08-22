import 'package:http_cassette/http_cassette.dart';
import 'package:test/test.dart';

void main() {
  group('custom sanitiser contracts', () {
    test('request sanitiser returns a request with structured exclusions', () {
      const sanitiser = _RequestSanitiser();
      final request = CassetteRequest(
        method: 'GET',
        uri: Uri.parse('https://example.test/?project=value'),
      );

      final result = sanitiser.sanitise(request);

      expect(result.request, same(request));
      expect(result.exclusions.queryParameters, <String>{'project'});
      expect(
        () => result.exclusions.queryParameters.add('another'),
        throwsUnsupportedError,
      );
    });

    test('response sanitiser returns a canonical response', () {
      const sanitiser = _ResponseSanitiser();
      final response = CassetteResponse(statusCode: 204);

      final result = sanitiser.sanitise(response);

      expect(result, same(response));
    });
  });
}

final class _RequestSanitiser implements RequestSanitiser {
  const _RequestSanitiser();

  @override
  SanitisedRequest sanitise(CassetteRequest request) => SanitisedRequest(
        request: request,
        exclusions: MatchingExclusions(
          queryParameters: <String>{'project'},
        ),
      );
}

final class _ResponseSanitiser implements ResponseSanitiser {
  const _ResponseSanitiser();

  @override
  CassetteResponse sanitise(CassetteResponse response) => response;
}

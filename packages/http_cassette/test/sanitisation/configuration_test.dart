import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/sanitisation/configuration.dart'
    show
        effectiveSensitiveHeaders,
        effectiveSensitiveJsonNames,
        effectiveSensitiveJsonPointers,
        effectiveSensitiveQueryParameters;
import 'package:test/test.dart';

void main() {
  group('SanitisationConfiguration', () {
    test('enables every secure built-in rule by default', () {
      final configuration = SanitisationConfiguration();

      expect(configuration.builtInRulesEnabled, isTrue);
      expect(
        configuration.encodedJsonResponses,
        EncodedJsonResponseHandling.opaque,
      );
      expect(
        effectiveSensitiveHeaders(configuration),
        <String>{
          'api-key',
          'authorization',
          'cookie',
          'proxy-authorization',
          'set-cookie',
          'x-api-key',
          'x-auth-token',
          'x-csrf-token',
          'x-xsrf-token',
        },
      );
      const credentialNames = <String>{
        'access_token',
        'api_key',
        'apikey',
        'auth',
        'authorization',
        'client_secret',
        'id_token',
        'password',
        'passwd',
        'refresh_token',
        'secret',
        'token',
      };
      expect(effectiveSensitiveQueryParameters(configuration), credentialNames);
      expect(effectiveSensitiveJsonNames(configuration), credentialNames);
      expect(effectiveSensitiveJsonPointers(configuration), isEmpty);
    });

    test('disables built-ins only through the conspicuous unsafe constructor',
        () {
      final configuration = SanitisationConfiguration.unsafeWithoutBuiltIns();

      expect(configuration.builtInRulesEnabled, isFalse);
      expect(configuration.additionalHeaders, isEmpty);
      expect(configuration.additionalQueryParameters, isEmpty);
      expect(configuration.additionalJsonNames, isEmpty);
      expect(configuration.additionalJsonPointers, isEmpty);
      expect(configuration.requestSanitisers, isEmpty);
      expect(configuration.responseSanitisers, isEmpty);
      expect(
        configuration.encodedJsonResponses,
        EncodedJsonResponseHandling.opaque,
      );
      expect(effectiveSensitiveHeaders(configuration), isEmpty);
      expect(effectiveSensitiveQueryParameters(configuration), isEmpty);
      expect(effectiveSensitiveJsonNames(configuration), isEmpty);
      expect(effectiveSensitiveJsonPointers(configuration), isEmpty);
      expect(configuration, isNot(SanitisationConfiguration()));
    });

    test('canonicalises, deduplicates and sorts project additions', () {
      final configuration = SanitisationConfiguration(
        additionalHeaders: <String>['X-Project-Secret', 'x-project-secret'],
        additionalQueryParameters: <String>[
          'Account%5fNumber',
          'account_number',
        ],
        additionalJsonNames: <String>['CustomerId', 'customerid'],
        additionalJsonPointers: <String>['/z', '/customer/account~1number'],
      );

      expect(configuration.additionalHeaders, <String>{'x-project-secret'});
      expect(
        configuration.additionalQueryParameters,
        <String>{'account_number'},
      );
      expect(configuration.additionalJsonNames, <String>{'customerid'});
      expect(
        configuration.additionalJsonPointers,
        <String>{'/customer/account~1number', '/z'},
      );
    });

    test('retains explicit encoded JSON response handling', () {
      final plain = SanitisationConfiguration(
        encodedJsonResponses: EncodedJsonResponseHandling.decodeAndStorePlain,
      );
      final recompressed = SanitisationConfiguration.unsafeWithoutBuiltIns(
        encodedJsonResponses: EncodedJsonResponseHandling.decodeAndRecompress,
      );

      expect(
        plain.encodedJsonResponses,
        EncodedJsonResponseHandling.decodeAndStorePlain,
      );
      expect(
        recompressed.encodedJsonResponses,
        EncodedJsonResponseHandling.decodeAndRecompress,
      );
    });

    test('copies inputs and exposes immutable sets', () {
      final source = <String>{'x-project-secret'};
      final configuration = SanitisationConfiguration(
        additionalHeaders: source,
      );
      source.add('x-later-secret');

      expect(configuration.additionalHeaders, <String>{'x-project-secret'});
      expect(
        () => configuration.additionalHeaders.add('x-another-secret'),
        throwsUnsupportedError,
      );
    });

    test('rejects invalid exact rules safely', () {
      expect(
        () => SanitisationConfiguration(
          additionalHeaders: <String>{'not valid'},
        ),
        throwsArgumentError,
      );
      expect(
        () => SanitisationConfiguration(
          additionalQueryParameters: <String>{'bad%'},
        ),
        throwsArgumentError,
      );
      expect(
        () => SanitisationConfiguration(
          additionalJsonPointers: <String>{'/bad~2'},
        ),
        throwsArgumentError,
      );
    });

    test('does not infer broad sensitive names', () {
      final configuration = SanitisationConfiguration();

      for (final name in <String>['id', 'name', 'code', 'value']) {
        expect(effectiveSensitiveQueryParameters(configuration),
            isNot(contains(name)));
        expect(
            effectiveSensitiveJsonNames(configuration), isNot(contains(name)));
      }
    });

    test('has structural equality and deterministic hash codes', () {
      final first = SanitisationConfiguration(
        additionalHeaders: <String>{'X-Secret'},
        additionalJsonPointers: <String>{'/secret'},
      );
      final second = SanitisationConfiguration(
        additionalJsonPointers: <String>{'/secret'},
        additionalHeaders: <String>{'x-secret'},
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    test('copies custom sanitisers and preserves registration order', () {
      const firstRequest = _RequestSanitiser('first');
      const secondRequest = _RequestSanitiser('second');
      const response = _ResponseSanitiser();
      final source = <RequestSanitiser>[firstRequest, secondRequest];

      final configuration = SanitisationConfiguration(
        requestSanitisers: source,
        responseSanitisers: const <ResponseSanitiser>[response],
      );
      source.clear();

      expect(
        configuration.requestSanitisers,
        <RequestSanitiser>[firstRequest, secondRequest],
      );
      expect(configuration.responseSanitisers, <ResponseSanitiser>[response]);
      expect(
        () => configuration.requestSanitisers.add(firstRequest),
        throwsUnsupportedError,
      );
      expect(
        () => configuration.responseSanitisers.clear(),
        throwsUnsupportedError,
      );
    });

    test('unsafe configuration retains explicitly registered sanitisers', () {
      const request = _RequestSanitiser('request');
      const response = _ResponseSanitiser();

      final configuration = SanitisationConfiguration.unsafeWithoutBuiltIns(
        requestSanitisers: const <RequestSanitiser>[request],
        responseSanitisers: const <ResponseSanitiser>[response],
      );

      expect(configuration.builtInRulesEnabled, isFalse);
      expect(configuration.requestSanitisers, <RequestSanitiser>[request]);
      expect(configuration.responseSanitisers, <ResponseSanitiser>[response]);
    });

    test('custom sanitiser order participates in equality', () {
      const first = _RequestSanitiser('first');
      const second = _RequestSanitiser('second');
      final forward = SanitisationConfiguration(
        requestSanitisers: const <RequestSanitiser>[first, second],
      );
      final reverse = SanitisationConfiguration(
        requestSanitisers: const <RequestSanitiser>[second, first],
      );

      expect(forward, isNot(reverse));
    });

    test('encoded JSON response handling participates in equality', () {
      final opaque = SanitisationConfiguration();
      final plain = SanitisationConfiguration(
        encodedJsonResponses: EncodedJsonResponseHandling.decodeAndStorePlain,
      );
      final samePlain = SanitisationConfiguration(
        encodedJsonResponses: EncodedJsonResponseHandling.decodeAndStorePlain,
      );

      expect(opaque, isNot(plain));
      expect(plain, samePlain);
      expect(plain.hashCode, samePlain.hashCode);
    });
  });
}

final class _RequestSanitiser implements RequestSanitiser {
  const _RequestSanitiser(this.id);

  final String id;

  @override
  SanitisedRequest sanitise(CassetteRequest request) => SanitisedRequest(
        request: request,
        exclusions: MatchingExclusions.none,
      );
}

final class _ResponseSanitiser implements ResponseSanitiser {
  const _ResponseSanitiser();

  @override
  CassetteResponse sanitise(CassetteResponse response) => response;
}

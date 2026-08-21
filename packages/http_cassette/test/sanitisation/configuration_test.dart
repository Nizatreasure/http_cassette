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
  });
}

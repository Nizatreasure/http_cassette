import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/sanitisation/placeholders.dart';
import 'package:http_cassette/src/sanitisation/request_fields.dart';
import 'package:test/test.dart';

void main() {
  group('sanitiseHeaders', () {
    test('replaces every value for each built-in sensitive header', () {
      const builtInNames = <String>[
        'authorization',
        'cookie',
        'proxy-authorization',
        'set-cookie',
        'x-api-key',
        'api-key',
        'x-auth-token',
        'x-csrf-token',
        'x-xsrf-token',
      ];
      final headers = CassetteHeaders(<String, Iterable<String>>{
        for (final name in builtInNames)
          name.toUpperCase(): <String>['synthetic-secret', 'another-secret'],
        'accept': <String>['application/json'],
      });

      final result = sanitiseHeaders(headers, SanitisationConfiguration());

      expect(result.sanitisedNames, builtInNames.toSet());
      for (final name in builtInNames) {
        expect(
          result.headers.values(name),
          <String>[redactedStringPlaceholder, redactedStringPlaceholder],
        );
      }
      expect(result.headers.values('accept'), <String>['application/json']);
    });

    test('uses exact case-insensitive project rules without substrings', () {
      final headers = CassetteHeaders(<String, Iterable<String>>{
        'X-Project-Secret': <String>['synthetic-secret'],
        'x-project-secret-suffix': <String>['retained'],
      });
      final configuration = SanitisationConfiguration(
        additionalHeaders: <String>{'x-PROJECT-secret'},
      );

      final result = sanitiseHeaders(headers, configuration);

      expect(result.sanitisedNames, <String>{'x-project-secret'});
      expect(
        result.headers.values('x-project-secret'),
        <String>[redactedStringPlaceholder],
      );
      expect(
        result.headers.values('x-project-secret-suffix'),
        <String>['retained'],
      );
    });

    test('does not mutate or expose sensitive source values', () {
      const sentinel = 'synthetic-credential-sentinel';
      final headers = CassetteHeaders(<String, Iterable<String>>{
        'authorization': <String>[sentinel],
      });

      final result = sanitiseHeaders(headers, SanitisationConfiguration());

      expect(headers.values('authorization'), <String>[sentinel]);
      expect(result.headers.values('authorization'), isNot(contains(sentinel)));
      expect(result.headers.toMap().toString(), isNot(contains(sentinel)));
      expect(
        () => result.sanitisedNames.add('another'),
        throwsUnsupportedError,
      );
    });

    test('leaves headers unchanged when unsafe built-ins are disabled', () {
      final headers = CassetteHeaders(<String, Iterable<String>>{
        'authorization': <String>['synthetic-secret'],
      });

      final result = sanitiseHeaders(
        headers,
        SanitisationConfiguration.unsafeWithoutBuiltIns(),
      );

      expect(result.headers, same(headers));
      expect(result.sanitisedNames, isEmpty);
    });
  });

  group('sanitiseQuery', () {
    test('replaces every present value for built-in sensitive names', () {
      const builtInNames = <String>[
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
      ];
      final query = <String>[
        for (final name in builtInNames)
          '${name.toUpperCase()}=synthetic-secret',
        'token=another-secret',
        'keep=retained',
      ].join('&');
      final uri = Uri.parse('https://example.test/path?$query');

      final result = sanitiseQuery(uri, SanitisationConfiguration());

      expect(result.sanitisedNames, builtInNames.toSet());
      expect(
        result.uri.query.split('&'),
        <String>[
          for (final name in builtInNames)
            '${name.toUpperCase()}=%5BREDACTED%5D',
          'token=%5BREDACTED%5D',
          'keep=retained',
        ],
      );
    });

    test('uses exact case-insensitive project rules without substrings', () {
      final uri = Uri.parse(
        'https://example.test/?Project%5FSecret=value&project_secret_suffix=retained',
      );
      final configuration = SanitisationConfiguration(
        additionalQueryParameters: <String>{'PROJECT_SECRET'},
      );

      final result = sanitiseQuery(uri, configuration);

      expect(result.sanitisedNames, <String>{'project_secret'});
      expect(
        result.uri.query,
        'Project_Secret=%5BREDACTED%5D&project_secret_suffix=retained',
      );
    });

    test('preserves repeated order and missing versus empty values', () {
      final uri = Uri.parse(
        'https://example.test/?token&token=&keep=first&token=third&keep=second',
      );

      final result = sanitiseQuery(uri, SanitisationConfiguration());

      expect(
        result.uri.query,
        'token&token=%5BREDACTED%5D&keep=first&token=%5BREDACTED%5D&keep=second',
      );
      expect(result.sanitisedNames, <String>{'token'});
    });

    test('does not mutate or expose sensitive source values', () {
      const sentinel = 'synthetic-credential-sentinel';
      final uri = Uri.parse('https://example.test/?token=$sentinel');

      final result = sanitiseQuery(uri, SanitisationConfiguration());

      expect(uri.query, 'token=$sentinel');
      expect(result.uri.toString(), isNot(contains(sentinel)));
      expect(
        () => result.sanitisedNames.add('another'),
        throwsUnsupportedError,
      );
    });

    test('leaves the URI unchanged when unsafe built-ins are disabled', () {
      final uri = Uri.parse('https://example.test/?token=synthetic-secret');

      final result = sanitiseQuery(
        uri,
        SanitisationConfiguration.unsafeWithoutBuiltIns(),
      );

      expect(result.uri, same(uri));
      expect(result.sanitisedNames, isEmpty);
    });
  });
}

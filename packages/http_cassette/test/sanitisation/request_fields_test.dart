import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/matching/request_matcher.dart';
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

      expect(
        result.sanitisedNames,
        <String>{...builtInNames.map((name) => name.toUpperCase()), 'token'},
      );
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

      expect(result.sanitisedNames, <String>{'Project_Secret'});
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

  group('sanitiseRequestFields', () {
    test('sanitises URI user information and reports every changed field', () {
      final request = CassetteRequest(
        method: 'post',
        uri: Uri.parse(
          'https://synthetic-user:synthetic-password@example.test/path?TOKEN=secret&keep=value',
        ),
        headers: CassetteHeaders(<String, Iterable<String>>{
          'Authorization': <String>['synthetic-credential'],
          'Accept': <String>['application/json'],
        }),
        body: <int>[1, 2, 3],
      );

      final result = sanitiseRequestFields(
        request,
        SanitisationConfiguration(),
      );

      expect(
        result.request.uri.toString(),
        'https://%5BREDACTED%5D@example.test/path?TOKEN=%5BREDACTED%5D&keep=value',
      );
      expect(
        result.request.headers.values('authorization'),
        <String>[redactedStringPlaceholder],
      );
      expect(result.request.headers.values('accept'),
          <String>['application/json']);
      expect(result.request.method, 'POST');
      expect(result.request.body, <int>[1, 2, 3]);
      expect(result.exclusions.uriUserInformation, isTrue);
      expect(result.exclusions.headers, <String>{'authorization'});
      expect(result.exclusions.queryParameters, <String>{'TOKEN'});
      expect(result.exclusions.jsonPointers, isEmpty);
    });

    test('does not retain source user information in the safe request', () {
      const sentinel = 'synthetic-user-info-sentinel';
      final request = CassetteRequest(
        method: 'GET',
        uri: Uri.parse('https://$sentinel@example.test/'),
      );

      final result = sanitiseRequestFields(
        request,
        SanitisationConfiguration(),
      );

      expect(request.uri.userInfo, sentinel);
      expect(result.request.uri.toString(), isNot(contains(sentinel)));
      expect(result.request.uri.userInfo, '%5BREDACTED%5D');
    });

    test('produces exclusions that ignore only the sanitised values', () {
      final recorded = CassetteRequest(
        method: 'GET',
        uri: Uri.parse('https://user:password@example.test/?TOKEN=first'),
        headers: CassetteHeaders(<String, Iterable<String>>{
          'authorization': <String>['first'],
        }),
      );
      final incoming = CassetteRequest(
        method: 'GET',
        uri: Uri.parse('https://other:credential@example.test/?TOKEN=second'),
        headers: CassetteHeaders(<String, Iterable<String>>{
          'authorization': <String>['second'],
        }),
      );
      final sanitised = sanitiseRequestFields(
        recorded,
        SanitisationConfiguration(),
      );
      final matcher = DefaultRequestMatcher(
        configuration: MatchingConfiguration(
          includedHeaders: <String>{'authorization'},
        ),
      );

      final result = matcher.compare(
        sanitised.request,
        incoming,
        exclusions: sanitised.exclusions,
      );

      expect(result.matches, isTrue);
    });

    test('returns the original request when no field needs sanitisation', () {
      final request = CassetteRequest(
        method: 'GET',
        uri: Uri.parse('https://example.test/?keep=value'),
      );

      final result = sanitiseRequestFields(
        request,
        SanitisationConfiguration(),
      );

      expect(result.request, same(request));
      expect(result.exclusions.headers, isEmpty);
      expect(result.exclusions.queryParameters, isEmpty);
      expect(result.exclusions.uriUserInformation, isFalse);
    });

    test('unsafe opt-out leaves all request fields unchanged', () {
      final request = CassetteRequest(
        method: 'GET',
        uri: Uri.parse('https://user:password@example.test/?token=secret'),
        headers: CassetteHeaders(<String, Iterable<String>>{
          'authorization': <String>['synthetic-credential'],
        }),
      );

      final result = sanitiseRequestFields(
        request,
        SanitisationConfiguration.unsafeWithoutBuiltIns(),
      );

      expect(result.request, same(request));
      expect(result.exclusions.headers, isEmpty);
      expect(result.exclusions.queryParameters, isEmpty);
      expect(result.exclusions.jsonPointers, isEmpty);
      expect(result.exclusions.uriUserInformation, isFalse);
    });
  });
}

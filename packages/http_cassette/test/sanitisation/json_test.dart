import 'dart:convert';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/matching/json.dart';
import 'package:http_cassette/src/sanitisation/json.dart';
import 'package:http_cassette/src/sanitisation/placeholders.dart';
import 'package:test/test.dart';

void main() {
  group('sanitiseJsonNames', () {
    test('sanitises every built-in exact member name case-insensitively', () {
      const names = <String>[
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
      final source = <String, Object?>{
        'nested': <Object?>[
          <String, Object?>{
            for (final name in names) name.toUpperCase(): 'synthetic-secret',
            'token_type': 'retained',
          },
        ],
      };

      final result = sanitiseJsonNames(
        _parse(jsonEncode(source)),
        SanitisationConfiguration(),
      );
      final nested =
          (result.value! as Map<String, Object?>)['nested']! as List<Object?>;
      final values = nested.single! as Map<String, Object?>;

      for (final name in names) {
        expect(values[name.toUpperCase()], redactedStringPlaceholder);
      }
      expect(values['token_type'], 'retained');
      expect(
        result.sanitisedPointers,
        <String>{for (final name in names) '/nested/0/${name.toUpperCase()}'},
      );
    });

    test('uses project names exactly without substring matching', () {
      final parsed = _parse(
        '{"ProjectSecret":"synthetic-secret","ProjectSecretSuffix":"retained"}',
      );
      final configuration = SanitisationConfiguration(
        additionalJsonNames: <String>{'projectsecret'},
      );

      final result = sanitiseJsonNames(parsed, configuration);
      final value = result.value! as Map<String, Object?>;

      expect(value['ProjectSecret'], redactedStringPlaceholder);
      expect(value['ProjectSecretSuffix'], 'retained');
      expect(result.sanitisedPointers, <String>{'/ProjectSecret'});
    });

    test('preserves selected object and array shape while replacing scalars',
        () {
      final parsed = _parse(
        '{"secret":{"email":"person@example.test","uuid":"123e4567-e89b-12d3-a456-426614174000","values":[42,1.5,true,null,[]],"empty":{}}}',
      );

      final result = sanitiseJsonNames(
        parsed,
        SanitisationConfiguration(),
      );
      final expected = _parse(
        '{"secret":{"email":"redacted@example.invalid","uuid":"00000000-0000-4000-8000-000000000000","values":[0,0.0,false,null,[]],"empty":{}}}',
      );

      expect(compareJsonValues(result.value, expected).matches, isTrue);
      expect(
        result.sanitisedPointers,
        <String>{
          '/secret/email',
          '/secret/uuid',
          '/secret/values/0',
          '/secret/values/1',
          '/secret/values/2',
          '/secret/values/3',
        },
      );
    });

    test('escapes affected member names as RFC 6901 pointer tokens', () {
      final parsed = _parse('{"container":{"a/b~c":"synthetic-secret"}}');
      final configuration = SanitisationConfiguration(
        additionalJsonNames: <String>{'a/b~c'},
      );

      final result = sanitiseJsonNames(parsed, configuration);

      expect(result.sanitisedPointers, <String>{'/container/a~1b~0c'});
    });

    test('does not mutate the source and returns immutable output', () {
      const sentinel = 'synthetic-secret-sentinel';
      final parsed = _parse('{"token":"$sentinel","keep":"retained"}')
          as Map<String, Object?>;

      final result = sanitiseJsonNames(parsed, SanitisationConfiguration());
      final value = result.value! as Map<String, Object?>;

      expect(parsed['token'], sentinel);
      expect(value.toString(), isNot(contains(sentinel)));
      expect(() => value['another'] = 'value', throwsUnsupportedError);
      expect(
        () => result.sanitisedPointers.add('/another'),
        throwsUnsupportedError,
      );
    });

    test('returns the original value when no rule selects a member', () {
      final parsed = _parse('{"keep":["retained"]}');

      final result = sanitiseJsonNames(parsed, SanitisationConfiguration());

      expect(result.value, same(parsed));
      expect(result.sanitisedPointers, isEmpty);
    });

    test('unsafe opt-out disables built-in name rules', () {
      final parsed = _parse('{"token":"synthetic-secret"}');

      final result = sanitiseJsonNames(
        parsed,
        SanitisationConfiguration.unsafeWithoutBuiltIns(),
      );

      expect(result.value, same(parsed));
      expect(result.sanitisedPointers, isEmpty);
    });
  });
}

Object? _parse(String source) {
  final result = parseJsonBody(
    CassetteHeaders(<String, Iterable<String>>{
      'content-type': <String>['application/json'],
    }),
    utf8.encode(source),
  );
  expect(result.status, JsonBodyStatus.valid);
  return result.value;
}

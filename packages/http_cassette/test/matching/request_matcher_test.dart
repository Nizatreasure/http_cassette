import 'dart:convert';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/matching/request_matcher.dart';
import 'package:test/test.dart';

void main() {
  group('DefaultRequestMatcher', () {
    test('matches method, origin, path and query by default', () {
      final result = _compare(
        _request('get', 'HTTP://EXAMPLE.TEST:80/items?tag=a&page=1'),
        _request('GET', 'http://example.test/items?page=1&tag=a'),
      );

      expect(result.matches, isTrue);
      _expectStates(result, <RequestMatchComponentState>[
        RequestMatchComponentState.matched,
        RequestMatchComponentState.matched,
        RequestMatchComponentState.matched,
        RequestMatchComponentState.matched,
        RequestMatchComponentState.notConfigured,
        RequestMatchComponentState.notConfigured,
      ]);
    });

    test('keeps every fixed component active', () {
      final pairs = <(CassetteRequest, CassetteRequest)>[
        (
          _request('GET', 'https://a.test/x'),
          _request('POST', 'https://a.test/x')
        ),
        (
          _request('GET', 'https://a.test/x'),
          _request('GET', 'https://b.test/x')
        ),
        (
          _request('GET', 'https://a.test/x'),
          _request('GET', 'https://a.test/y')
        ),
        (
          _request('GET', 'https://a.test/x?a=1'),
          _request('GET', 'https://a.test/x?a=2')
        ),
      ];

      for (final pair in pairs) {
        expect(_compare(pair.$1, pair.$2).matches, isFalse);
      }
    });

    test('ignores headers by default and compares selected headers', () {
      final expected = _request(
        'GET',
        'https://example.test/',
        headers: <String, Iterable<String>>{
          'x-version': <String>['1']
        },
      );
      final actual = _request(
        'GET',
        'https://example.test/',
        headers: <String, Iterable<String>>{
          'x-version': <String>['2']
        },
      );

      expect(_compare(expected, actual).matches, isTrue);
      final configured = _compare(
        expected,
        actual,
        configuration: MatchingConfiguration(
          includedHeaders: <String>{'X-Version'},
        ),
      );
      expect(configured.matches, isFalse);
      expect(
        configured.components[4].state,
        RequestMatchComponentState.different,
      );
    });

    test('requires a body when either request has bytes', () {
      final result = _compare(
        _request('POST', 'https://example.test/'),
        _request('POST', 'https://example.test/', body: <int>[1]),
      );

      expect(result.matches, isFalse);
      expect(result.body.kind, RequestBodyComparisonKind.exactBytes);
      expect(result.body.exactComparison!.firstDifferenceOffset, 0);
    });

    test('compares two valid JSON bodies structurally', () {
      final result = _compare(
        _jsonRequest('{"first":1,"ignored":"old"}'),
        _jsonRequest('{"ignored":"new","first":1.0}'),
        configuration: MatchingConfiguration(
          ignoredJsonPointers: <String>{'/ignored'},
        ),
      );

      expect(result.matches, isTrue);
      expect(result.body.kind, RequestBodyComparisonKind.structuralJson);
      expect(result.body.differences.isEmpty, isTrue);
    });

    test('falls back safely when claimed JSON is invalid', () {
      final expected = _jsonRequest('{invalid');
      final actual = _jsonRequest('{invalid');
      final result = _compare(expected, actual);

      expect(result.matches, isTrue);
      expect(
        result.body.kind,
        RequestBodyComparisonKind.exactBytesJsonUnavailable,
      );
      expect(
        result.components.last.state,
        RequestMatchComponentState.unavailable,
      );
      expect(result.body.exactComparison!.matches, isTrue);
    });

    test('uses exact bytes for non-JSON and content-encoded bodies', () {
      final opaque = _compare(
        _request('POST', 'https://example.test/', body: <int>[1, 2]),
        _request('POST', 'https://example.test/', body: <int>[1, 3]),
      );
      expect(opaque.body.kind, RequestBodyComparisonKind.exactBytes);
      expect(opaque.matches, isFalse);

      final encoded = _compare(
        _jsonRequest('{"value":1}', contentEncoding: 'gzip'),
        _jsonRequest('{ "value": 1 }', contentEncoding: 'gzip'),
      );
      expect(encoded.body.kind, RequestBodyComparisonKind.exactBytes);
      expect(encoded.matches, isFalse);
    });

    test('combines configured and per-request exclusions', () {
      final configuration = MatchingConfiguration(
        includedHeaders: <String>{'x-secret'},
        ignoredQueryParameters: <String>{'token'},
      );
      final exclusions = MatchingExclusions(
        headers: <String>{'x-secret'},
        jsonPointers: <String>{'/volatile'},
      );
      final result = _compare(
        _jsonRequest(
          '{"volatile":1}',
          suffix: '?token=one',
          extraHeaders: <String, Iterable<String>>{
            'x-secret': <String>['first'],
          },
        ),
        _jsonRequest(
          '{"volatile":2}',
          suffix: '?token=two',
          extraHeaders: <String, Iterable<String>>{
            'x-secret': <String>['second'],
          },
        ),
        configuration: configuration,
        exclusions: exclusions,
      );

      expect(result.matches, isTrue);
    });

    test('is deterministic and does not mutate requests', () {
      final expected = _jsonRequest('{"value":1}');
      final actual = _jsonRequest('{"value":2}');
      final matcher = DefaultRequestMatcher();

      final first = matcher.compare(expected, actual);
      final second = matcher.compare(expected, actual);

      expect(
        first.components.map((component) => component.state),
        second.components.map((component) => component.state),
      );
      expect(utf8.decode(expected.body), '{"value":1}');
      expect(utf8.decode(actual.body), '{"value":2}');
      expect(
        () => first.components.add(first.components.first),
        throwsUnsupportedError,
      );
    });

    test('retains bounded differences while preserving the complete count', () {
      final matcher = DefaultRequestMatcher(maximumDifferencesPerComponent: 2);
      final result = matcher.compare(
        _jsonRequest('{"a":1,"b":2,"c":3}'),
        _jsonRequest('{"a":4,"b":5,"c":6}'),
      );
      final body = result.components.last.differences;

      expect(body.totalCount, 3);
      expect(body.differences.length, 2);
      expect(body.omittedCount, 1);
      expect(
        body.differences.map((difference) => difference.location),
        <String>['/a', '/b'],
      );
    });

    test('does not retain differing header, query or body values', () {
      const sentinel = 'credential-sentinel-value';
      final result = _compare(
        _jsonRequest(
          '{"value":"$sentinel"}',
          suffix: '?token=$sentinel',
          extraHeaders: <String, Iterable<String>>{
            'x-version': <String>[sentinel],
          },
        ),
        _jsonRequest(
          '{"value":"different"}',
          suffix: '?token=different',
          extraHeaders: <String, Iterable<String>>{
            'x-version': <String>['different'],
          },
        ),
        configuration: MatchingConfiguration(
          includedHeaders: <String>{'x-version'},
        ),
      );

      expect(result.toString(), isNot(contains(sentinel)));
      for (final component in result.components) {
        for (final difference in component.differences.differences) {
          expect(difference.location, isNot(contains(sentinel)));
        }
      }
    });

    test('evaluates additive custom components in registration order', () {
      final calls = <String>[];
      final first = _TestComponent('first', (
        expected,
        actual,
        context,
      ) {
        calls.add('first');
        expect(context.excludedHeaders, <String>{'x-secret'});
        expect(context.excludedQueryParameters, <String>{'token'});
        expect(context.excludedJsonPointers, <String>{'/secret'});
        expect(context.uriUserInformationExcluded, isTrue);
        return MatchComponentResult(matches: true);
      });
      final second = _TestComponent('second', (
        expected,
        actual,
        context,
      ) {
        calls.add('second');
        return MatchComponentResult(
          matches: false,
          differences: <MatchDifference>[
            MatchDifference(
              kind: MatchDifferenceKind.customComponentDifference,
              location: 'domain-rule',
            ),
          ],
        );
      });
      final matcher = DefaultRequestMatcher(
        configuration: MatchingConfiguration(
          ignoredQueryParameters: <String>{'token'},
          ignoredJsonPointers: <String>{'/secret'},
          customComponents: <RequestMatcherComponent>[first, second],
        ),
      );

      final result = matcher.compare(
        _request('GET', 'https://user@example.test/items?token=one'),
        _request('GET', 'https://other@example.test/items?token=two'),
        exclusions: MatchingExclusions(
          headers: <String>{'x-secret'},
          uriUserInformation: true,
        ),
      );

      expect(calls, <String>['first', 'second']);
      expect(result.components.every((component) => component.matches), isTrue);
      expect(
        result.customComponents.map((component) => component.name),
        <String>['first', 'second'],
      );
      expect(result.customComponents.first.result.matches, isTrue);
      expect(result.customComponents.last.result.matches, isFalse);
      expect(result.matches, isFalse);
    });
  });
}

typedef _CompareCustom = MatchComponentResult Function(
  CassetteRequest expected,
  CassetteRequest actual,
  MatchContext context,
);

final class _TestComponent implements RequestMatcherComponent {
  const _TestComponent(this.name, this._compare);

  @override
  final String name;

  final _CompareCustom _compare;

  @override
  MatchComponentResult compare(
    CassetteRequest expected,
    CassetteRequest actual,
    MatchContext context,
  ) =>
      _compare(expected, actual, context);
}

RequestMatchResult _compare(
  CassetteRequest expected,
  CassetteRequest actual, {
  MatchingConfiguration? configuration,
  MatchingExclusions exclusions = MatchingExclusions.none,
}) =>
    DefaultRequestMatcher(configuration: configuration).compare(
      expected,
      actual,
      exclusions: exclusions,
    );

CassetteRequest _request(
  String method,
  String uri, {
  Map<String, Iterable<String>> headers = const <String, Iterable<String>>{},
  List<int> body = const <int>[],
}) =>
    CassetteRequest(
      method: method,
      uri: Uri.parse(uri),
      headers: CassetteHeaders(headers),
      body: body,
    );

CassetteRequest _jsonRequest(
  String body, {
  String suffix = '',
  String? contentEncoding,
  Map<String, Iterable<String>> extraHeaders =
      const <String, Iterable<String>>{},
}) {
  final headers = <String, Iterable<String>>{
    'content-type': <String>['application/json'],
    ...extraHeaders,
    if (contentEncoding != null) 'content-encoding': <String>[contentEncoding],
  };
  return _request(
    'POST',
    'https://example.test/$suffix',
    headers: headers,
    body: utf8.encode(body),
  );
}

void _expectStates(
  RequestMatchResult result,
  List<RequestMatchComponentState> expected,
) {
  expect(
    result.components.map((component) => component.state),
    orderedEquals(expected),
  );
}

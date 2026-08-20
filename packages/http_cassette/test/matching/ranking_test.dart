import 'dart:convert';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/matching/ranking.dart';
import 'package:http_cassette/src/matching/request_matcher.dart';
import 'package:test/test.dart';

void main() {
  group('rankRequestMatchCandidates', () {
    test('uses the fixed component precedence lexicographically', () {
      final comparisons = <RequestMatchResult>[
        _compare(_request(method: 'POST')),
        _compare(_request(host: 'other.test')),
        _compare(_request(path: '/other')),
        _compare(_request(query: 'a=2')),
        _compare(_request(header: 'other')),
        _compare(_request(body: '{"value":2}')),
        _compare(_request()),
      ];

      for (var index = 0; index < comparisons.length - 1; index++) {
        final earlierDifference = RequestMatchCandidate(
          recordedIndex: 0,
          comparison: comparisons[index],
        );
        final laterDifference = RequestMatchCandidate(
          recordedIndex: 1,
          comparison: comparisons[index + 1],
        );

        expect(
          rankRequestMatchCandidates(<RequestMatchCandidate>[
            earlierDifference,
            laterDifference,
          ]).closestCandidate,
          same(laterDifference),
        );
      }
    });

    test('prefers fewer structural differences within a component', () {
      final oneDifference = RequestMatchCandidate(
        recordedIndex: 1,
        comparison: _compare(_request(query: 'a=1&b=3')),
      );
      final twoDifferences = RequestMatchCandidate(
        recordedIndex: 0,
        comparison: _compare(_request(query: 'a=3&b=4')),
      );

      final ranking = rankRequestMatchCandidates(<RequestMatchCandidate>[
        twoDifferences,
        oneDifference,
      ]);

      expect(ranking.closestCandidate, same(oneDifference));
    });

    test('resolves complete ties to the lowest recorded index', () {
      final higherIndex = RequestMatchCandidate(
        recordedIndex: 8,
        comparison: _compare(_request(path: '/other')),
      );
      final lowerIndex = RequestMatchCandidate(
        recordedIndex: 3,
        comparison: _compare(_request(path: '/other')),
      );

      final ranking = rankRequestMatchCandidates(<RequestMatchCandidate>[
        higherIndex,
        lowerIndex,
      ]);

      expect(ranking.closestCandidate, same(lowerIndex));
    });

    test('reports the number considered and preserves the stored result', () {
      final comparison = _compare(_request(path: '/other'));
      final candidate = RequestMatchCandidate(
        recordedIndex: 4,
        comparison: comparison,
      );

      final ranking = rankRequestMatchCandidates(<RequestMatchCandidate>[
        RequestMatchCandidate(
          recordedIndex: 9,
          comparison: _compare(_request(method: 'POST')),
        ),
        candidate,
      ]);

      expect(ranking.consideredCount, 2);
      expect(ranking.closestCandidate, same(candidate));
      expect(ranking.closestCandidate!.comparison, same(comparison));
    });

    test('returns no candidate for an empty collection', () {
      final ranking = rankRequestMatchCandidates(
        const <RequestMatchCandidate>[],
      );

      expect(ranking.consideredCount, 0);
      expect(ranking.closestCandidate, isNull);
    });

    test('rejects a negative recorded index', () {
      expect(
        () => RequestMatchCandidate(
          recordedIndex: -1,
          comparison: _compare(_request()),
        ),
        throwsArgumentError,
      );
    });

    test('rejects duplicate recorded indices', () {
      expect(
        () => rankRequestMatchCandidates(<RequestMatchCandidate>[
          RequestMatchCandidate(
            recordedIndex: 2,
            comparison: _compare(_request()),
          ),
          RequestMatchCandidate(
            recordedIndex: 2,
            comparison: _compare(_request(path: '/other')),
          ),
        ]),
        throwsArgumentError,
      );
    });
  });
}

final MatchingConfiguration _configuration = MatchingConfiguration(
  includedHeaders: <String>{'x-version'},
);

RequestMatchResult _compare(CassetteRequest expected) => DefaultRequestMatcher(
      configuration: _configuration,
    ).compare(
      expected,
      _request(query: 'a=1&b=2'),
    );

CassetteRequest _request({
  String method = 'GET',
  String host = 'example.test',
  String path = '/items',
  String query = 'a=1&b=2',
  String header = 'current',
  String body = '{"value":1}',
}) =>
    CassetteRequest(
      method: method,
      uri: Uri(scheme: 'https', host: host, path: path, query: query),
      headers: CassetteHeaders(<String, Iterable<String>>{
        'content-type': <String>['application/json'],
        'x-version': <String>[header],
      }),
      body: utf8.encode(body),
    );

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/cassette.dart';
import 'package:http_cassette/src/cassette/interaction.dart';
import 'package:http_cassette/src/matching/request_matcher.dart';
import 'package:http_cassette/src/replay/grouping.dart';
import 'package:test/test.dart';

void main() {
  test('retains matching interactions in recorded-index order', () {
    final cassette = Cassette(
      interactions: <CassetteInteraction>[
        _interaction(0, method: 'POST', path: '/items'),
        _interaction(1, method: 'GET', path: '/items'),
        _interaction(2, method: 'GET', path: '/other'),
        _interaction(3, method: 'GET', path: '/items'),
      ],
    );

    final group = _group(
      cassette,
      CassetteRequest(
        method: 'GET',
        uri: Uri.parse('https://example.test/items'),
      ),
    );

    expect(group.map((interaction) => interaction.index), <int>[1, 3]);
  });

  test('preserves identical recorded interactions without deduplication', () {
    final cassette = Cassette(
      interactions: <CassetteInteraction>[
        _interaction(0, method: 'GET', path: '/items'),
        _interaction(1, method: 'GET', path: '/items'),
        _interaction(2, method: 'GET', path: '/items'),
      ],
    );

    final group = _group(
      cassette,
      CassetteRequest(
        method: 'GET',
        uri: Uri.parse('https://example.test/items'),
      ),
    );

    expect(group, cassette.interactions);
    expect(group.length, 3);
  });

  test('returns an immutable empty group when nothing matches', () {
    final cassette = Cassette(
      interactions: <CassetteInteraction>[
        _interaction(0, method: 'POST', path: '/items'),
      ],
    );

    final group = _group(
      cassette,
      CassetteRequest(
        method: 'GET',
        uri: Uri.parse('https://example.test/items'),
      ),
    );

    expect(group, isEmpty);
    expect(
      () => group.add(_interaction(1, method: 'GET', path: '/items')),
      throwsUnsupportedError,
    );
  });

  test('applies each interaction persisted matching exclusions', () {
    final cassette = Cassette(
      interactions: <CassetteInteraction>[
        _interaction(
          0,
          method: 'GET',
          path: '/items?token=recorded',
          matchingExclusions: MatchingExclusions(
            queryParameters: <String>{'token'},
          ),
        ),
        _interaction(1, method: 'GET', path: '/items?token=recorded'),
      ],
    );

    final group = _group(
      cassette,
      CassetteRequest(
        method: 'GET',
        uri: Uri.parse('https://example.test/items?token=incoming'),
      ),
    );

    expect(group.map((interaction) => interaction.index), <int>[0]);
  });

  test('uses the supplied matcher configuration', () {
    final cassette = Cassette(
      interactions: <CassetteInteraction>[
        _interaction(
          0,
          method: 'GET',
          path: '/items',
          headers: CassetteHeaders(<String, Iterable<String>>{
            'Accept': <String>['application/json'],
          }),
        ),
      ],
    );
    final incoming = CassetteRequest(
      method: 'GET',
      uri: Uri.parse('https://example.test/items'),
      headers: CassetteHeaders(<String, Iterable<String>>{
        'Accept': <String>['text/plain'],
      }),
    );

    final defaultGroup = _group(cassette, incoming);
    final configuredGroup = buildReplayMatchingGroup(
      cassette: cassette,
      incoming: incoming,
      matcher: DefaultRequestMatcher(
        configuration: MatchingConfiguration(
          includedHeaders: <String>{'accept'},
        ),
      ),
    );

    expect(defaultGroup.map((interaction) => interaction.index), <int>[0]);
    expect(configuredGroup, isEmpty);
  });

  test('does not mutate the cassette or incoming request', () {
    final interaction = _interaction(0, method: 'GET', path: '/items');
    final cassette = Cassette(interactions: <CassetteInteraction>[interaction]);
    final incoming = CassetteRequest(
      method: 'GET',
      uri: Uri.parse('https://example.test/items'),
    );

    final group = _group(cassette, incoming);

    expect(cassette.interactions, <CassetteInteraction>[interaction]);
    expect(group.single, same(interaction));
    expect(incoming.uri, Uri.parse('https://example.test/items'));
  });

  test('retains the single comparison used for each candidate', () {
    final cassette = Cassette(
      interactions: <CassetteInteraction>[
        _interaction(0, method: 'GET', path: '/first'),
        _interaction(1, method: 'GET', path: '/second'),
      ],
    );
    final evaluation = evaluateReplayRequest(
      cassette: cassette,
      incoming: CassetteRequest(
        method: 'GET',
        uri: Uri.parse('https://example.test/missing'),
      ),
      matcher: DefaultRequestMatcher(),
    );

    expect(evaluation.matchingInteractions, isEmpty);
    expect(
      evaluation.candidates.map((candidate) => candidate.recordedIndex),
      <int>[0, 1],
    );
    expect(
      evaluation.candidates.every((candidate) => !candidate.comparison.matches),
      isTrue,
    );
    expect(
      () => evaluation.candidates.add(evaluation.candidates.first),
      throwsUnsupportedError,
    );
  });
}

List<CassetteInteraction> _group(
  Cassette cassette,
  CassetteRequest incoming,
) =>
    buildReplayMatchingGroup(
      cassette: cassette,
      incoming: incoming,
      matcher: DefaultRequestMatcher(),
    );

CassetteInteraction _interaction(
  int index, {
  required String method,
  required String path,
  CassetteHeaders? headers,
  MatchingExclusions matchingExclusions = MatchingExclusions.none,
}) =>
    CassetteInteraction(
      index: index,
      request: CassetteRequest(
        method: method,
        uri: Uri.parse('https://example.test$path'),
        headers: headers ?? const CassetteHeaders.empty(),
      ),
      matchingExclusions: matchingExclusions,
      outcome: CassetteResponseOutcome(
        CassetteResponse(statusCode: 200 + index),
      ),
    );

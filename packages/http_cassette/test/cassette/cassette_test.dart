import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/cassette.dart';
import 'package:http_cassette/src/cassette/interaction.dart';
import 'package:test/test.dart';

void main() {
  group('Cassette', () {
    test('creates an empty current-version cassette', () {
      final cassette = Cassette();

      expect(cassette.schemaVersion, 1);
      expect(
        cassette.schemaVersion,
        currentWritableCassetteSchemaVersion,
      );
      expect(cassette.interactions, isEmpty);
    });

    test('retains contiguous interactions in arrival order', () {
      final interactions = <CassetteInteraction>[
        _interaction(0),
        _interaction(1),
      ];

      final cassette = Cassette(interactions: interactions);

      expect(
        cassette.interactions.map((interaction) => interaction.index),
        <int>[0, 1],
      );
    });

    test('rejects indices that do not start at zero', () {
      expect(
        () => Cassette(interactions: <CassetteInteraction>[_interaction(1)]),
        throwsArgumentError,
      );
    });

    test('rejects missing, duplicate and out-of-order indices', () {
      for (final indices in <List<int>>[
        <int>[0, 2],
        <int>[0, 0],
        <int>[0, 2, 1],
      ]) {
        expect(
          () => Cassette(
            interactions: indices.map(_interaction),
          ),
          throwsArgumentError,
          reason: '$indices',
        );
      }
    });

    test('copies the interaction iterable and exposes an immutable list', () {
      final source = <CassetteInteraction>[_interaction(0)];
      final cassette = Cassette(interactions: source);

      source.clear();

      expect(cassette.interactions, hasLength(1));
      expect(
        () => cassette.interactions.add(_interaction(1)),
        throwsUnsupportedError,
      );
    });

    test('uses structural equality and matching hash codes', () {
      Cassette cassette() => Cassette(
            interactions: <CassetteInteraction>[
              _interaction(0),
              _interaction(1),
            ],
          );

      final first = cassette();
      final second = cassette();

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });
  });
}

CassetteInteraction _interaction(int index) => CassetteInteraction(
      index: index,
      request: CassetteRequest(
        method: 'GET',
        uri: Uri.parse('https://example.test/$index'),
      ),
      outcome: CassetteResponseOutcome(
        CassetteResponse(statusCode: 200),
      ),
    );

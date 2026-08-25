import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/cassette.dart';
import 'package:http_cassette/src/replay/active_state.dart';
import 'package:test/test.dart';

void main() {
  group('ActiveReplayState', () {
    test('retains validated identity, cassette and matching configuration', () {
      final name = CassetteName('checkout/success');
      final cassette = Cassette();
      final configuration = CassetteConfiguration(
        matching: MatchingConfiguration(
          includedHeaders: const <String>['accept'],
        ),
      );

      final state = ActiveReplayState(
        cassetteName: name,
        cassette: cassette,
        configuration: configuration,
        options: const ReplayOptions(),
      );

      expect(state.cassetteName, same(name));
      expect(state.cassette, same(cassette));
      expect(state.matcher.configuration, same(configuration.matching));
    });

    test('resolves the engine replay policy once by default', () {
      final state = ActiveReplayState(
        cassetteName: CassetteName('default-policy'),
        cassette: Cassette(),
        configuration: CassetteConfiguration(
          defaultReplayPolicy: ReplayPolicy.last,
        ),
        options: const ReplayOptions(),
      );

      expect(state.replayPolicy, ReplayPolicy.last);
      expect(state.requireAllInteractions, isFalse);
    });

    test('retains the session policy override and verification choice', () {
      final state = ActiveReplayState(
        cassetteName: CassetteName('session-policy'),
        cassette: Cassette(),
        configuration: CassetteConfiguration(
          defaultReplayPolicy: ReplayPolicy.strict,
        ),
        options: const ReplayOptions(
          policy: ReplayPolicy.cycle,
          requireAllInteractions: true,
        ),
      );

      expect(state.replayPolicy, ReplayPolicy.cycle);
      expect(state.requireAllInteractions, isTrue);
    });
  });
}

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/replay/policy_resolution.dart';
import 'package:test/test.dart';

void main() {
  group('ReplayPolicy', () {
    test('provides every agreed policy with stable names', () {
      expect(
        ReplayPolicy.values,
        <ReplayPolicy>[
          ReplayPolicy.strict,
          ReplayPolicy.first,
          ReplayPolicy.last,
          ReplayPolicy.sequence,
          ReplayPolicy.cycle,
        ],
      );
      expect(
        ReplayPolicy.values.map((policy) => policy.name),
        <String>['strict', 'first', 'last', 'sequence', 'cycle'],
      );
    });
  });

  group('ReplayOptions', () {
    test('uses the engine policy and no close verification by default', () {
      const options = ReplayOptions();

      expect(options.policy, isNull);
      expect(options.requireAllInteractions, isFalse);
      expect(
        resolveReplayPolicy(
          defaultPolicy: ReplayPolicy.strict,
          options: options,
        ),
        ReplayPolicy.strict,
      );
    });

    test('preserves every explicit session policy override', () {
      for (final policy in ReplayPolicy.values) {
        final options = ReplayOptions(policy: policy);

        expect(options.policy, policy);
        expect(
          resolveReplayPolicy(
            defaultPolicy: ReplayPolicy.first,
            options: options,
          ),
          policy,
        );
      }
    });

    test('supports explicit successful-close verification', () {
      const options = ReplayOptions(requireAllInteractions: true);

      expect(options.requireAllInteractions, isTrue);
    });

    test('has structural equality and matching hash codes', () {
      const first = ReplayOptions(
        policy: ReplayPolicy.sequence,
        requireAllInteractions: true,
      );
      const second = ReplayOptions(
        policy: ReplayPolicy.sequence,
        requireAllInteractions: true,
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first, isNot(const ReplayOptions(policy: ReplayPolicy.cycle)));
    });
  });
}

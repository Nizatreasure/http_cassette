import 'package:http_cassette/http_cassette.dart';
import 'package:test/test.dart';

void main() {
  group('CassetteConfiguration', () {
    test('uses secure engine defaults', () {
      final configuration = CassetteConfiguration();

      expect(configuration.matching, MatchingConfiguration());
      expect(configuration.sanitisation, SanitisationConfiguration());
      expect(configuration.bodyLimits, BodyLimits());
      expect(configuration.recording, RecordingConfiguration());
      expect(configuration.storeOperations, StoreOperationConfiguration());
      expect(configuration.defaultReplayPolicy, ReplayPolicy.strict);
    });

    test('retains explicit focused configuration values', () {
      final matching = MatchingConfiguration(
        includedHeaders: const <String>{'accept'},
      );
      final sanitisation = SanitisationConfiguration(
        additionalJsonPointers: const <String>{'/account/id'},
      );
      final bodyLimits = BodyLimits(requestBytes: 12, responseBytes: 34);
      final recording = RecordingConfiguration(
        closeGracePeriod: const Duration(seconds: 45),
      );
      final storeOperations = StoreOperationConfiguration(
        timeout: const Duration(seconds: 12),
      );

      final configuration = CassetteConfiguration(
        matching: matching,
        sanitisation: sanitisation,
        bodyLimits: bodyLimits,
        recording: recording,
        storeOperations: storeOperations,
        defaultReplayPolicy: ReplayPolicy.sequence,
      );

      expect(configuration.matching, same(matching));
      expect(configuration.sanitisation, same(sanitisation));
      expect(configuration.bodyLimits, same(bodyLimits));
      expect(configuration.recording, same(recording));
      expect(configuration.storeOperations, same(storeOperations));
      expect(configuration.defaultReplayPolicy, ReplayPolicy.sequence);
    });

    test('has structural equality and matching hash codes', () {
      final first = CassetteConfiguration();
      final second = CassetteConfiguration();

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(
        first,
        isNot(
          CassetteConfiguration(defaultReplayPolicy: ReplayPolicy.first),
        ),
      );
      expect(
        first,
        isNot(
          CassetteConfiguration(
            storeOperations: StoreOperationConfiguration(
              timeout: const Duration(seconds: 31),
            ),
          ),
        ),
      );
      expect(
        first,
        isNot(
          CassetteConfiguration(
            recording: RecordingConfiguration(
              closeGracePeriod: const Duration(seconds: 31),
            ),
          ),
        ),
      );
    });
  });
}

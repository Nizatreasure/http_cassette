import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/decoder.dart';
import 'package:http_cassette/src/diagnostics/exception.dart';
import 'package:http_cassette/src/replay/decode_diagnostic.dart';
import 'package:http_cassette/src/replay/loading_failure.dart';
import 'package:http_cassette/src/replay/loading_failure_formatter.dart';
import 'package:http_cassette/src/replay/store_read_diagnostic.dart';
import 'package:test/test.dart';

void main() {
  group('replayCassetteLoadException', () {
    test('exposes the store failure envelope through CassetteException', () {
      final failure = ReplayCassetteLoadFailure.storeRead(
        ReplayStoreReadDiagnostic.fromStoreFailure(
          CassetteStoreException.notFound(
            name: CassetteName('checkout/missing'),
            operation: CassetteStoreOperation.read,
          ),
        ),
      );

      final exception = replayCassetteLoadException(failure);

      expect(exception, isA<CassetteException>());
      expect(exception.diagnostic, same(failure.envelope));
      expect(exception.toString(), failure.format());
      expect(exception.toString(), contains('Cassette: checkout/missing'));
      expect(exception.toString(), contains('Store failure: notFound'));
    });

    test('preserves safe decoder details in exception formatting', () {
      final failure = ReplayCassetteLoadFailure.decode(
        ReplayCassetteDecodeDiagnostic.fromDecodeFailure(
          cassetteName: CassetteName('checkout/large'),
          failure: const CassetteDecodeException(
            kind: CassetteDecodeFailureKind.inputTooLarge,
            location: '',
            maximumBytes: 4096,
          ),
        ),
      );

      final exception = replayCassetteLoadException(failure);

      expect(exception.diagnostic, same(failure.envelope));
      expect(exception.toString(), failure.format());
      expect(exception.toString(), contains('Decode failure: inputTooLarge'));
      expect(exception.toString(), contains('Cassette limit: 4096 bytes'));
    });

    test('does not change ordinary CassetteException formatting', () {
      final diagnostic = CassetteDiagnostic(
        category: DiagnosticCategory.internalInvariantFailure,
        summary: 'A safe failure occurred.',
        networkAccess: NetworkAccess.notAttempted,
      );

      expect(CassetteException(diagnostic).toString(), diagnostic.format());
    });
  });
}

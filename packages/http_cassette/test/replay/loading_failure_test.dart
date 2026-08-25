import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/decoder.dart';
import 'package:http_cassette/src/replay/decode_diagnostic.dart';
import 'package:http_cassette/src/replay/loading_failure.dart';
import 'package:http_cassette/src/replay/loading_failure_formatter.dart';
import 'package:http_cassette/src/replay/store_read_diagnostic.dart';
import 'package:test/test.dart';

void main() {
  group('ReplayCassetteLoadFailure', () {
    test('wraps store-read details without changing their semantics', () {
      final details = ReplayStoreReadDiagnostic.fromStoreFailure(
        CassetteStoreException.notFound(
          name: CassetteName('missing'),
          operation: CassetteStoreOperation.read,
        ),
      );

      final failure = ReplayCassetteLoadFailure.storeRead(details);

      expect(failure, isA<ReplayCassetteStoreReadFailure>());
      expect(failure.cassetteName, same(details.cassetteName));
      expect(failure.envelope, same(details.envelope));
      expect(
        (failure as ReplayCassetteStoreReadFailure).diagnostic,
        same(details),
      );
    });

    test('wraps decode details without changing their semantics', () {
      final details = _decodeDiagnostic();

      final failure = ReplayCassetteLoadFailure.decode(details);

      expect(failure, isA<ReplayCassetteDecodeFailure>());
      expect(failure.cassetteName, same(details.cassetteName));
      expect(failure.envelope, same(details.envelope));
      expect(
        (failure as ReplayCassetteDecodeFailure).diagnostic,
        same(details),
      );
    });

    test('has structural equality within each exhaustive variant', () {
      ReplayCassetteLoadFailure storeFailure() =>
          ReplayCassetteLoadFailure.storeRead(
            ReplayStoreReadDiagnostic.fromStoreFailure(
              CassetteStoreException.operationFailed(
                name: CassetteName('unreadable'),
                operation: CassetteStoreOperation.read,
              ),
            ),
          );
      final first = storeFailure();
      final second = storeFailure();

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(
          first, isNot(ReplayCassetteLoadFailure.decode(_decodeDiagnostic())));
    });
  });

  group('ReplayCassetteLoadFailureFormatter', () {
    test('formats a store-read failure deterministically', () {
      final failure = ReplayCassetteLoadFailure.storeRead(
        ReplayStoreReadDiagnostic.fromStoreFailure(
          CassetteStoreException.notFound(
            name: CassetteName('checkout/missing'),
            operation: CassetteStoreOperation.read,
          ),
        ),
      );
      const expected = 'HTTP Cassette failure: '
          'The replay cassette does not exist.\n'
          'Category: cassetteMissing\n'
          'Cassette: checkout/missing\n'
          'Loading source: store read\n'
          'Store failure: notFound\n'
          'Network access: disabled; no real request was made';

      expect(failure.format(), expected);
      expect(failure.format(), expected);
    });

    test('formats safe decode position facts without source content', () {
      final failure = ReplayCassetteLoadFailure.decode(
        _decodeDiagnostic(
          failure: const CassetteDecodeException(
            kind: CassetteDecodeFailureKind.malformedJson,
            location: '',
            line: 3,
            column: 9,
          ),
        ),
      );

      expect(
        failure.format(),
        'HTTP Cassette failure: The replay cassette could not be decoded.\n'
        'Category: cassetteDecodeFailure\n'
        'Cassette: checkout/replay\n'
        'Loading source: cassette decoder\n'
        'Decode failure: malformedJson\n'
        'Location: <root>\n'
        'Source position: line=3; column=9\n'
        'Network access: disabled; no real request was made',
      );
    });

    test('formats an oversized input with its configured limit only', () {
      final failure = ReplayCassetteLoadFailure.decode(
        _decodeDiagnostic(
          failure: const CassetteDecodeException(
            kind: CassetteDecodeFailureKind.inputTooLarge,
            location: '',
            maximumBytes: 4096,
          ),
        ),
      );
      final output = failure.format();

      expect(output, contains('Decode failure: inputTooLarge'));
      expect(output, contains('Cassette limit: 4096 bytes'));
      expect(output, isNot(contains('Schema version:')));
    });

    test('formats safely representable and omitted schema versions', () {
      ReplayCassetteLoadFailure failure(int? observed) =>
          ReplayCassetteLoadFailure.decode(
            _decodeDiagnostic(
              failure: CassetteDecodeException(
                kind: CassetteDecodeFailureKind.unsupportedNewerVersion,
                location: '/schemaVersion',
                observedSchemaVersion: observed,
              ),
            ),
          );

      expect(
        failure(2).format(),
        contains('Schema version: observed=2; supported=1'),
      );
      expect(
        failure(null).format(),
        contains(
          'Schema version: observed=<not safely representable>; supported=1',
        ),
      );
    });

    test('uses the shared explicit cassette-name display bound', () {
      final name = List<String>.filled(140, 'a').join();
      final failure = ReplayCassetteLoadFailure.decode(
        _decodeDiagnostic(cassetteName: CassetteName(name)),
      );

      expect(
        failure.format(),
        contains('${List<String>.filled(128, 'a').join()}... (140 characters)'),
      );
      expect(failure.format(), isNot(contains(name)));
    });
  });
}

ReplayCassetteDecodeDiagnostic _decodeDiagnostic({
  CassetteName? cassetteName,
  CassetteDecodeException failure = const CassetteDecodeException(
    kind: CassetteDecodeFailureKind.invalidStructure,
    location: '/interactions/0',
  ),
}) =>
    ReplayCassetteDecodeDiagnostic.fromDecodeFailure(
      cassetteName: cassetteName ?? CassetteName('checkout/replay'),
      failure: failure,
    );

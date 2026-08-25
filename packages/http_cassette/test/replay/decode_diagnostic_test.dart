import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/decoder.dart';
import 'package:http_cassette/src/replay/decode_diagnostic.dart';
import 'package:test/test.dart';

void main() {
  group('ReplayCassetteDecodeDiagnostic', () {
    test('maps byte and syntax failures to cassette decode failure', () {
      final cases = <CassetteDecodeException>[
        const CassetteDecodeException(
          kind: CassetteDecodeFailureKind.inputTooLarge,
          location: '',
          maximumBytes: 1024,
        ),
        const CassetteDecodeException(
          kind: CassetteDecodeFailureKind.invalidUtf8,
          location: '',
        ),
        const CassetteDecodeException(
          kind: CassetteDecodeFailureKind.malformedJson,
          location: '',
          line: 2,
          column: 3,
        ),
        const CassetteDecodeException(
          kind: CassetteDecodeFailureKind.duplicateObjectMember,
          location: '',
          line: 4,
          column: 5,
        ),
      ];

      for (final failure in cases) {
        final diagnostic = _diagnostic(failure);

        expect(
          diagnostic.envelope.category,
          DiagnosticCategory.cassetteDecodeFailure,
        );
        expect(diagnostic.envelope.networkAccess, NetworkAccess.disabled);
      }
    });

    test('retains only the configured limit for oversized input', () {
      final diagnostic = _diagnostic(
        const CassetteDecodeException(
          kind: CassetteDecodeFailureKind.inputTooLarge,
          location: '',
          maximumBytes: 2048,
          observedSchemaVersion: 99,
        ),
      );

      expect(diagnostic.maximumBytes, 2048);
      expect(diagnostic.observedSchemaVersion, isNull);
      expect(
        diagnostic.envelope.summary,
        'The replay cassette exceeds the configured byte limit.',
      );
    });

    test('maps and retains safe syntax positions', () {
      final diagnostic = _diagnostic(
        const CassetteDecodeException(
          kind: CassetteDecodeFailureKind.malformedJson,
          location: '',
          line: 12,
          column: 7,
          maximumBytes: 999,
        ),
      );

      expect(diagnostic.line, 12);
      expect(diagnostic.column, 7);
      expect(diagnostic.maximumBytes, isNull);
      expect(diagnostic.location, isEmpty);
      expect(
        diagnostic.envelope.summary,
        'The replay cassette could not be decoded.',
      );
    });

    test('maps invalid schema structure with its safe location', () {
      final diagnostic = _diagnostic(
        const CassetteDecodeException(
          kind: CassetteDecodeFailureKind.invalidStructure,
          location: '/interactions/3/request/method',
        ),
      );

      expect(
        diagnostic.envelope.category,
        DiagnosticCategory.invalidCassetteStructure,
      );
      expect(diagnostic.location, '/interactions/3/request/method');
      expect(diagnostic.observedSchemaVersion, isNull);
    });

    test('distinguishes older and newer schema versions', () {
      final older = _diagnostic(
        const CassetteDecodeException(
          kind: CassetteDecodeFailureKind.unsupportedOlderVersion,
          location: '/schemaVersion',
          observedSchemaVersion: 0,
        ),
      );
      final newer = _diagnostic(
        const CassetteDecodeException(
          kind: CassetteDecodeFailureKind.unsupportedNewerVersion,
          location: '/schemaVersion',
          observedSchemaVersion: 2,
        ),
      );

      expect(
        older.envelope.category,
        DiagnosticCategory.unsupportedOlderSchemaVersion,
      );
      expect(older.observedSchemaVersion, 0);
      expect(older.supportedSchemaVersion, 1);
      expect(
        newer.envelope.category,
        DiagnosticCategory.unsupportedNewerSchemaVersion,
      );
      expect(newer.observedSchemaVersion, 2);
      expect(newer.supportedSchemaVersion, 1);
    });

    test('allows an unrepresentable unsupported schema version to be omitted',
        () {
      final diagnostic = _diagnostic(
        const CassetteDecodeException(
          kind: CassetteDecodeFailureKind.unsupportedNewerVersion,
          location: '/schemaVersion',
        ),
      );

      expect(diagnostic.observedSchemaVersion, isNull);
      expect(diagnostic.supportedSchemaVersion, 1);
    });

    test('rejects incomplete, non-positive and invalid limit facts', () {
      final failures = <CassetteDecodeException>[
        const CassetteDecodeException(
          kind: CassetteDecodeFailureKind.malformedJson,
          location: '',
          line: 1,
        ),
        const CassetteDecodeException(
          kind: CassetteDecodeFailureKind.malformedJson,
          location: '',
          line: 0,
          column: 1,
        ),
        const CassetteDecodeException(
          kind: CassetteDecodeFailureKind.inputTooLarge,
          location: '',
        ),
        const CassetteDecodeException(
          kind: CassetteDecodeFailureKind.inputTooLarge,
          location: '',
          maximumBytes: 0,
        ),
      ];

      for (final failure in failures) {
        expect(() => _diagnostic(failure), throwsArgumentError);
      }
    });

    test('has structural equality and matching hash codes', () {
      const failure = CassetteDecodeException(
        kind: CassetteDecodeFailureKind.invalidStructure,
        location: '/interactions/0',
      );

      final first = _diagnostic(failure);
      final second = _diagnostic(failure);

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(
        first,
        isNot(
          ReplayCassetteDecodeDiagnostic.fromDecodeFailure(
            cassetteName: CassetteName('other'),
            failure: failure,
          ),
        ),
      );
    });
  });
}

ReplayCassetteDecodeDiagnostic _diagnostic(
  CassetteDecodeException failure,
) =>
    ReplayCassetteDecodeDiagnostic.fromDecodeFailure(
      cassetteName: CassetteName('checkout/replay'),
      failure: failure,
    );

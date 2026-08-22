import 'dart:convert';

import 'package:http_cassette/src/cassette/decoder.dart';
import 'package:test/test.dart';

void main() {
  group('decodeCassetteV1Envelope', () {
    test('accepts the exact root and exposes immutable interactions', () {
      final envelope = _decode(
        '{"schemaVersion":1,"interactions":[{"pending":true}]}',
      );

      expect(envelope.interactions, hasLength(1));
      expect(() => envelope.interactions.add(null), throwsUnsupportedError);
    });

    test('rejects invalid UTF-8 without a source position', () {
      _expectFailure(
        () => decodeCassetteV1Envelope(<int>[0xc3, 0x28]),
        CassetteDecodeFailureKind.invalidUtf8,
        location: '',
      );
    });

    test('maps malformed JSON to a safe positional failure', () {
      const secret = 'private-value';

      _expectFailure(
        () => _decode('{\n"schemaVersion": 1,\n"$secret"\n}'),
        CassetteDecodeFailureKind.malformedJson,
        location: '',
        line: 4,
        column: 1,
        absentText: secret,
      );
    });

    test('distinguishes duplicate object members', () {
      _expectFailure(
        () => _decode(
          '{"schemaVersion":1,"schemaVersion":1,"interactions":[]}',
        ),
        CassetteDecodeFailureKind.duplicateObjectMember,
        location: '',
        line: 1,
        column: 20,
      );
    });

    test('requires a root object with exact ordered fields', () {
      for (final source in <String>[
        '[]',
        '{"schemaVersion":1}',
        '{"schemaVersion":1,"unknown":false,"interactions":[]}',
        '{"interactions":[],"schemaVersion":1}',
      ]) {
        _expectFailure(
          () => _decode(source),
          CassetteDecodeFailureKind.invalidStructure,
          location: '',
        );
      }
    });

    test('requires schemaVersion to be a JSON integer', () {
      for (final version in <String>['null', '"1"', '1.0', '1e0']) {
        _expectFailure(
          () => _decode(
            '{"schemaVersion":$version,"interactions":[]}',
          ),
          CassetteDecodeFailureKind.invalidStructure,
          location: '/schemaVersion',
        );
      }
    });

    test('distinguishes unsupported older and newer versions', () {
      _expectVersionFailure(
        0,
        CassetteDecodeFailureKind.unsupportedOlderVersion,
      );
      _expectVersionFailure(
        2,
        CassetteDecodeFailureKind.unsupportedNewerVersion,
      );
    });

    test('does not retain an impractically large version in the failure', () {
      final exception = _captureFailure(
        () => _decode(
          '{"schemaVersion":999999999999999999999999,"interactions":[]}',
        ),
      );

      expect(exception.kind, CassetteDecodeFailureKind.unsupportedNewerVersion);
      expect(exception.observedSchemaVersion, isNull);
      expect(exception.toString(), isNot(contains('999999')));
    });

    test('requires interactions to be an array', () {
      _expectFailure(
        () => _decode('{"schemaVersion":1,"interactions":{}}'),
        CassetteDecodeFailureKind.invalidStructure,
        location: '/interactions',
      );
    });
  });
}

CassetteV1Envelope _decode(String source) =>
    decodeCassetteV1Envelope(utf8.encode(source));

void _expectVersionFailure(int version, CassetteDecodeFailureKind kind) {
  final exception = _captureFailure(
    () => _decode('{"schemaVersion":$version,"interactions":[]}'),
  );
  expect(exception.kind, kind);
  expect(exception.location, '/schemaVersion');
  expect(exception.observedSchemaVersion, version);
  expect(exception.supportedSchemaVersion, 1);
}

void _expectFailure(
  void Function() operation,
  CassetteDecodeFailureKind kind, {
  required String location,
  int? line,
  int? column,
  String? absentText,
}) {
  final exception = _captureFailure(operation);
  expect(exception.kind, kind);
  expect(exception.location, location);
  expect(exception.line, line);
  expect(exception.column, column);
  if (absentText != null) {
    expect(exception.toString(), isNot(contains(absentText)));
  }
}

CassetteDecodeException _captureFailure(void Function() operation) {
  try {
    operation();
  } on CassetteDecodeException catch (error) {
    return error;
  }
  fail('Expected a CassetteDecodeException.');
}

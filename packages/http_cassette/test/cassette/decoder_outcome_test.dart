import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/decoder.dart';
import 'package:http_cassette/src/json/strict_json.dart';
import 'package:test/test.dart';

void main() {
  group('decodeCassetteOutcomeV1', () {
    test('reconstructs a response with an optional reason phrase', () {
      final outcome = _decode(
        '{"type":"response","statusCode":201,"reasonPhrase":"Created",'
        '"headers":{"content-length":["5"]},'
        '"body":{"encoding":"text","content":"saved"}}',
      ) as CassetteResponseOutcome;

      expect(outcome.response.statusCode, 201);
      expect(outcome.response.reasonPhrase, 'Created');
      expect(outcome.response.body, <int>[115, 97, 118, 101, 100]);
    });

    test('preserves an absent response reason phrase', () {
      final outcome = _decode(
        '{"type":"response","statusCode":204,"headers":{},'
        '"body":{"encoding":"empty"}}',
      ) as CassetteResponseOutcome;

      expect(outcome.response.reasonPhrase, isNull);
    });

    test('requires exact response fields in exact order', () {
      _expectInvalid(
        '{"statusCode":200,"type":"response","headers":{},'
            '"body":{"encoding":"empty"}}',
        '/outcome',
      );
      _expectInvalid(
        '{"type":"response","statusCode":200,"headers":{},'
            '"reasonPhrase":"OK","body":{"encoding":"empty"}}',
        '/outcome',
      );
    });

    test('requires an integer response status from 100 through 599', () {
      for (final status in <String>['null', '200.0', '99', '600']) {
        _expectInvalid(
          '{"type":"response","statusCode":$status,"headers":{},'
              '"body":{"encoding":"empty"}}',
          '/outcome/statusCode',
        );
      }
    });

    test('validates response reason phrases without retaining values', () {
      const phrase = 'private\nphrase';
      final error = _capture(
        () => decodeCassetteOutcomeV1(
          <String, Object?>{
            'type': 'response',
            'statusCode': parseStrictJson('200'),
            'reasonPhrase': phrase,
            'headers': <String, Object?>{},
            'body': <String, Object?>{'encoding': 'empty'},
          },
          location: '/outcome',
        ),
      );

      expect(error.location, '/outcome/reasonPhrase');
      expect(error.toString(), isNot(contains('private')));
    });

    test('validates response body selection and payload headers', () {
      _expectInvalid(
        '{"type":"response","statusCode":200,'
            '"headers":{"content-length":["99"]},'
            '"body":{"encoding":"text","content":"hello"}}',
        '/outcome/headers',
      );
      _expectInvalid(
        '{"type":"response","statusCode":200,"headers":{},'
            '"body":{"encoding":"base64","content":"aGVsbG8="}}',
        '/outcome/body',
      );
    });

    test('reconstructs every portable transport-failure category', () {
      for (final category in TransportFailureCategory.values) {
        final outcome = _decode(
          '{"type":"transportFailure","category":"${category.name}",'
          '"message":"The operation failed safely."}',
        ) as CassetteTransportFailure;

        expect(outcome.category, category);
      }
    });

    test('requires exact transport-failure fields and known category', () {
      _expectInvalid(
        '{"type":"transportFailure","message":"Safe.",'
            '"category":"other"}',
        '/outcome',
      );
      const category = 'private-category';
      final error = _capture(
        () => _decode(
          '{"type":"transportFailure","category":"$category",'
          '"message":"Safe."}',
        ),
      );
      expect(error.location, '/outcome/category');
      expect(error.toString(), isNot(contains(category)));
    });

    test('requires a safe transport-failure message', () {
      for (final message in <Object?>[null, '', ' unsafe ']) {
        final error = _capture(
          () => decodeCassetteOutcomeV1(
            <String, Object?>{
              'type': 'transportFailure',
              'category': 'other',
              'message': message,
            },
            location: '/outcome',
          ),
        );
        expect(error.location, '/outcome/message');
      }
    });

    test('rejects an unknown discriminator without retaining it', () {
      const type = 'private-outcome';
      final error = _capture(
        () => _decode('{"type":"$type"}'),
      );

      expect(error.location, '/outcome/type');
      expect(error.toString(), isNot(contains(type)));
    });
  });
}

CassetteOutcome _decode(String source) => decodeCassetteOutcomeV1(
      parseStrictJson(source),
      location: '/outcome',
    );

void _expectInvalid(String source, String location) {
  final error = _capture(() => _decode(source));
  expect(error.kind, CassetteDecodeFailureKind.invalidStructure);
  expect(error.location, location);
}

CassetteDecodeException _capture(void Function() operation) {
  try {
    operation();
  } on CassetteDecodeException catch (error) {
    return error;
  }
  fail('Expected a CassetteDecodeException.');
}

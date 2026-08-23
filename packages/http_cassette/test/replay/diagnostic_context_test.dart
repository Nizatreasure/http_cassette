import 'package:http_cassette/src/cassette/name.dart';
import 'package:http_cassette/src/model/http_message.dart';
import 'package:http_cassette/src/replay/diagnostic_context.dart';
import 'package:test/test.dart';

void main() {
  group('ReplayRequestSummary', () {
    test('retains only bounded value-free request facts', () {
      final summary = ReplayRequestSummary.fromRequest(
        request: CassetteRequest(
          method: 'post',
          uri: Uri.parse(
            'https://user@example.test/private?field=private-value',
          ),
          body: const <int>[1, 2, 3],
        ),
        arrivalIndex: 7,
      );

      expect(summary.method, 'POST');
      expect(summary.methodCharacterLength, 4);
      expect(summary.bodyByteLength, 3);
      expect(summary.hasBody, isTrue);
      expect(summary.arrivalIndex, 7);
      expect(summary.toString(), isNot(contains('example.test')));
      expect(summary.toString(), isNot(contains('private-value')));
    });

    test('omits an unusually long method instead of truncating its value', () {
      final summary = ReplayRequestSummary.fromRequest(
        request: CassetteRequest(
          method: List<String>.filled(65, 'A').join(),
          uri: Uri.parse('https://example.test'),
        ),
        arrivalIndex: 0,
      );

      expect(summary.method, isNull);
      expect(summary.methodCharacterLength, 65);
    });

    test('reports an empty body without retaining body data', () {
      final summary = ReplayRequestSummary.fromRequest(
        request: CassetteRequest(
          method: 'GET',
          uri: Uri.parse('https://example.test'),
        ),
        arrivalIndex: 0,
      );

      expect(summary.bodyByteLength, 0);
      expect(summary.hasBody, isFalse);
    });

    test('rejects a negative arrival index', () {
      expect(
        () => ReplayRequestSummary.fromRequest(
          request: CassetteRequest(
            method: 'GET',
            uri: Uri.parse('https://example.test'),
          ),
          arrivalIndex: -1,
        ),
        throwsArgumentError,
      );
    });

    test('has structural equality and matching hash codes', () {
      ReplayRequestSummary summary() => ReplayRequestSummary.fromRequest(
            request: CassetteRequest(
              method: 'POST',
              uri: Uri.parse('https://example.test'),
              body: const <int>[1],
            ),
            arrivalIndex: 2,
          );

      expect(summary(), summary());
      expect(summary().hashCode, summary().hashCode);
    });
  });

  test('ReplayDiagnosticContext retains validated value-safe context', () {
    ReplayDiagnosticContext context() => ReplayDiagnosticContext(
          cassetteName: CassetteName('checkout/declined'),
          request: ReplayRequestSummary.fromRequest(
            request: CassetteRequest(
              method: 'POST',
              uri: Uri.parse('https://example.test'),
            ),
            arrivalIndex: 4,
          ),
        );

    expect(context().cassetteName.value, 'checkout/declined');
    expect(context(), context());
    expect(context().hashCode, context().hashCode);
  });
}

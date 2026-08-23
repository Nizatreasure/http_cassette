import 'dart:typed_data';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/cassette.dart';
import 'package:http_cassette/src/cassette/encoder.dart';
import 'package:http_cassette/src/cassette/interaction.dart';

const _emptyInteractionCountV1 = 10000;

void main() {
  _measureMaximumBodyPairV1(
    label: 'opaque-binary',
    requestByte: 0xff,
    responseByte: 0xff,
  );
  _measureMaximumBodyPairV1(
    label: 'escaped-text',
    requestByte: 0x09,
    responseByte: 0x09,
  );
  _measureEmptyInteractionsV1();
}

void _measureMaximumBodyPairV1({
  required String label,
  required int requestByte,
  required int responseByte,
}) {
  final request = Uint8List(BodyLimits.defaultRequestBytes)
    ..fillRange(0, BodyLimits.defaultRequestBytes, requestByte);
  final response = Uint8List(BodyLimits.defaultResponseBytes)
    ..fillRange(0, BodyLimits.defaultResponseBytes, responseByte);
  final cassette = Cassette(
    interactions: <CassetteInteraction>[
      _interactionV1(index: 0, requestBody: request, responseBody: response),
    ],
  );
  final encodedBytes = encodeCassetteV1(cassette).length;
  final bodyBytes = request.length + response.length;

  print(
    '$label: bodyBytes=$bodyBytes encodedBytes=$encodedBytes '
    'overheadBytes=${encodedBytes - bodyBytes} '
    'expansion=${(encodedBytes / bodyBytes).toStringAsFixed(3)}',
  );
}

void _measureEmptyInteractionsV1() {
  final cassette = Cassette(
    interactions: List<CassetteInteraction>.generate(
      _emptyInteractionCountV1,
      (index) => _interactionV1(
        index: index,
        requestBody: Uint8List(0),
        responseBody: Uint8List(0),
      ),
      growable: false,
    ),
  );
  final encodedBytes = encodeCassetteV1(cassette).length;

  print(
    'empty-interactions: count=$_emptyInteractionCountV1 '
    'encodedBytes=$encodedBytes '
    'bytesPerInteraction='
    '${(encodedBytes / _emptyInteractionCountV1).toStringAsFixed(1)}',
  );
}

CassetteInteraction _interactionV1({
  required int index,
  required Uint8List requestBody,
  required Uint8List responseBody,
}) {
  return CassetteInteraction(
    index: index,
    request: CassetteRequest(
      method: 'POST',
      uri: Uri.parse('https://example.test/resource'),
      body: requestBody,
    ),
    outcome: CassetteResponseOutcome(
      CassetteResponse(statusCode: 200, body: responseBody),
    ),
  );
}

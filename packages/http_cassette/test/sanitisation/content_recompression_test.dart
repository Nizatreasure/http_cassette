import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http_cassette/src/sanitisation/content_recompression.dart';
import 'package:http_cassette/src/sanitisation/content_recompression_stub.dart'
    as unsupported_platform;
import 'package:test/test.dart';

void main() {
  group('recompressGzipContent', () {
    test('recompresses valid content within the limit', () {
      final source = utf8.encode('{"value":true}');

      final encoded = recompressGzipContent(source, maximumBytes: 1024);

      expect(gzip.decode(encoded), source);
      expect(() => encoded[0] = 0, throwsUnsupportedError);
    });

    test('accepts recompressed content at the exact limit', () {
      final source = List<int>.generate(1024, (index) => index % 256);
      final expectedLength = gzip.encode(source).length;

      final encoded = recompressGzipContent(
        source,
        maximumBytes: expectedLength,
      );

      expect(encoded.length, expectedLength);
      expect(gzip.decode(encoded), source);
    });

    test('stops when recompressed content would exceed the limit', () {
      final source = utf8.encode('{}');
      final maximumBytes = gzip.encode(source).length - 1;

      expect(
        () => recompressGzipContent(source, maximumBytes: maximumBytes),
        throwsA(
          isA<ContentRecompressionException>()
              .having(
                (failure) => failure.kind,
                'kind',
                ContentRecompressionFailureKind.recompressedBodyTooLarge,
              )
              .having(
                (failure) => failure.maximumBytes,
                'maximum bytes',
                maximumBytes,
              ),
        ),
      );
    });

    test('rejects invalid limits and byte values before recompression', () {
      expect(
        () => recompressGzipContent(const <int>[], maximumBytes: 0),
        throwsArgumentError,
      );
      expect(
        () => recompressGzipContent(const <int>[256], maximumBytes: 1),
        throwsArgumentError,
      );
    });
  });

  test('unsupported implementation reports a value-safe platform failure', () {
    expect(
      () => unsupported_platform.recompressGzipContent(
        Uint8List(0),
        maximumBytes: 1,
      ),
      throwsA(
        isA<ContentRecompressionException>().having(
          (failure) => failure.kind,
          'kind',
          ContentRecompressionFailureKind.unsupportedPlatform,
        ),
      ),
    );
  });
}

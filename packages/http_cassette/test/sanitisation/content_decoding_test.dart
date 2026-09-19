import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http_cassette/src/sanitisation/content_decoding.dart';
import 'package:http_cassette/src/sanitisation/content_decoding_stub.dart'
    as unsupported_platform;
import 'package:test/test.dart';

void main() {
  group('decodeGzipContent', () {
    test('decodes valid content within the limit', () {
      final source = utf8.encode('{"value":true}');

      final decoded = decodeGzipContent(
        gzip.encode(source),
        maximumBytes: source.length,
      );

      expect(decoded, source);
      expect(() => decoded[0] = 0, throwsUnsupportedError);
    });

    test('accepts decoded content at the exact limit', () {
      final source = List<int>.generate(1024, (index) => index % 256);

      expect(
        decodeGzipContent(
          gzip.encode(source),
          maximumBytes: source.length,
        ),
        source,
      );
    });

    test('stops when decoded content would exceed the limit', () {
      final source = List<int>.filled(4096, 0);

      expect(
        () => decodeGzipContent(
          gzip.encode(source),
          maximumBytes: source.length - 1,
        ),
        throwsA(
          isA<ContentDecodingException>()
              .having(
                (failure) => failure.kind,
                'kind',
                ContentDecodingFailureKind.decodedBodyTooLarge,
              )
              .having(
                (failure) => failure.maximumBytes,
                'maximum bytes',
                source.length - 1,
              ),
        ),
      );
    });

    test('maps malformed gzip without retaining input values', () {
      const sentinel = 'private compressed content';

      expect(
        () => decodeGzipContent(
          utf8.encode(sentinel),
          maximumBytes: 1024,
        ),
        throwsA(
          isA<ContentDecodingException>()
              .having(
                (failure) => failure.kind,
                'kind',
                ContentDecodingFailureKind.invalidContent,
              )
              .having(
                (failure) => failure.toString(),
                'description',
                isNot(contains(sentinel)),
              ),
        ),
      );
    });

    test('rejects invalid limits and byte values before decoding', () {
      expect(
        () => decodeGzipContent(const <int>[], maximumBytes: 0),
        throwsArgumentError,
      );
      expect(
        () => decodeGzipContent(const <int>[256], maximumBytes: 1),
        throwsArgumentError,
      );
    });
  });

  test('unsupported implementation reports a value-safe platform failure', () {
    expect(
      () => unsupported_platform.decodeGzipContent(
        Uint8List(0),
        maximumBytes: 1,
      ),
      throwsA(
        isA<ContentDecodingException>().having(
          (failure) => failure.kind,
          'kind',
          ContentDecodingFailureKind.unsupportedPlatform,
        ),
      ),
    );
  });
}

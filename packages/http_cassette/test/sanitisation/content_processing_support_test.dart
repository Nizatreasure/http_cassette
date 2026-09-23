import 'package:http_cassette/src/sanitisation/content_processing_support.dart';
import 'package:http_cassette/src/sanitisation/content_processing_support_io.dart'
    as io_platform;
import 'package:http_cassette/src/sanitisation/content_processing_support_stub.dart'
    as unsupported_platform;
import 'package:test/test.dart';

void main() {
  test('reports gzip processing support for each platform implementation', () {
    expect(supportsGzipContentProcessing, isTrue);
    expect(io_platform.supportsGzipContentProcessing, isTrue);
    expect(unsupported_platform.supportsGzipContentProcessing, isFalse);
  });
}

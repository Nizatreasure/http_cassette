import 'dart:typed_data';

/// Collects complete transformed content without exceeding a byte limit.
final class BoundedByteSink implements Sink<List<int>> {
  BoundedByteSink(this.maximumBytes);

  final int maximumBytes;
  final BytesBuilder _bytes = BytesBuilder(copy: false);
  var _isClosed = false;

  @override
  void add(List<int> chunk) {
    if (_isClosed) {
      throw StateError('Transformed content sink is closed.');
    }
    if (chunk.length > maximumBytes - _bytes.length) {
      throw const ByteLimitExceeded();
    }
    _bytes.add(chunk);
  }

  @override
  void close() {
    _isClosed = true;
  }

  Uint8List takeBytes() {
    if (!_isClosed) {
      throw StateError('Transformed content is not complete.');
    }
    return _bytes.takeBytes().asUnmodifiableView();
  }
}

/// Internal signal that transformed output crossed its byte limit.
final class ByteLimitExceeded implements Exception {
  const ByteLimitExceeded();
}

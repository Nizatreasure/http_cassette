import 'dart:io';
import 'dart:math';

import 'temporary_file_io.dart';

/// Prepares complete same-directory files for a later atomic replacement.
///
/// A successful caller owns the returned file. A failed write attempts to
/// close and delete its candidate while preserving the original failure.
final class SameDirectoryTemporaryFileWriter {
  /// Creates a temporary-file writer.
  ///
  /// Production callers should retain the secure random default. [io] and
  /// [random] allow deterministic failure and collision testing.
  SameDirectoryTemporaryFileWriter({
    TemporaryFileIo io = const DartTemporaryFileIo(),
    Random? random,
  })  : _io = io,
        _random = random ?? Random.secure();

  static const int _maximumCreateAttempts = 16;
  static const int _randomWordLimit = 0x10000;

  final TemporaryFileIo _io;
  final Random _random;

  /// Writes [bytes] to a new unpredictable file beside [target].
  ///
  /// The file is flushed and closed before it is returned. Name collisions
  /// are retried a bounded number of times. This method never replaces or
  /// otherwise modifies [target].
  Future<File> write(File target, List<int> bytes) async {
    for (var attempt = 0; attempt < _maximumCreateAttempts; attempt++) {
      final candidate = File(
        '${target.parent.path}${Platform.pathSeparator}'
        '.http_cassette-${_randomSuffix()}.tmp',
      );
      try {
        await _io.createExclusive(candidate);
      } on Object catch (error, stackTrace) {
        FileSystemEntityType type;
        try {
          type = await _io.type(candidate.path);
        } on Object {
          Error.throwWithStackTrace(error, stackTrace);
        }
        if (type == FileSystemEntityType.notFound) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        if (attempt + 1 == _maximumCreateAttempts) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        continue;
      }

      RandomAccessFile? handle;
      try {
        handle = await _io.openWrite(candidate);
        await _io.write(handle, bytes);
        await _io.flush(handle);
        await _io.close(handle);
        handle = null;
        return candidate;
      } on Object catch (error, stackTrace) {
        await _closeQuietly(handle);
        await _deleteQuietly(candidate);
        Error.throwWithStackTrace(error, stackTrace);
      }
    }

    throw StateError('Temporary-file creation attempts were exhausted.');
  }

  String _randomSuffix() {
    final buffer = StringBuffer();
    for (var index = 0; index < 8; index++) {
      buffer.write(
        _random.nextInt(_randomWordLimit).toRadixString(16).padLeft(4, '0'),
      );
    }
    return buffer.toString();
  }

  Future<void> _closeQuietly(RandomAccessFile? handle) async {
    if (handle == null) {
      return;
    }
    try {
      await _io.close(handle);
    } on Object {
      // Cleanup must not replace the write failure.
    }
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await _io.type(file.path) != FileSystemEntityType.notFound) {
        await _io.delete(file);
      }
    } on Object {
      // Cleanup must not replace the write failure.
    }
  }
}

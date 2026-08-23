import 'dart:io';

/// The file operations needed to prepare an atomic-replacement candidate.
abstract interface class TemporaryFileIo {
  /// Creates [file] only when its path does not already exist.
  Future<void> createExclusive(File file);

  /// Opens [file] for writing without creating it.
  Future<RandomAccessFile> openWrite(File file);

  /// Writes all [bytes] to [handle].
  Future<void> write(RandomAccessFile handle, List<int> bytes);

  /// Flushes buffered output for [handle].
  Future<void> flush(RandomAccessFile handle);

  /// Closes [handle].
  Future<void> close(RandomAccessFile handle);

  /// Deletes [file].
  Future<void> delete(File file);

  /// Returns the kind of entry at [path] without following symbolic links.
  Future<FileSystemEntityType> type(String path);
}

/// Implements temporary-file operations with `dart:io`.
final class DartTemporaryFileIo implements TemporaryFileIo {
  /// Creates a `dart:io` temporary-file boundary.
  const DartTemporaryFileIo();

  @override
  Future<void> createExclusive(File file) => file.create(exclusive: true);

  @override
  Future<RandomAccessFile> openWrite(File file) =>
      file.open(mode: FileMode.writeOnly);

  @override
  Future<void> write(RandomAccessFile handle, List<int> bytes) =>
      handle.writeFrom(bytes);

  @override
  Future<void> flush(RandomAccessFile handle) => handle.flush();

  @override
  Future<void> close(RandomAccessFile handle) => handle.close();

  @override
  Future<void> delete(File file) => file.delete();

  @override
  Future<FileSystemEntityType> type(String path) =>
      FileSystemEntity.type(path, followLinks: false);
}

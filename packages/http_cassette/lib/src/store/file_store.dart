import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../cassette/name.dart';
import '../configuration/cassette_size_limit.dart';
import 'exception.dart';
import 'file_path_resolver.dart';
import 'snapshot.dart';
import 'store.dart';
import 'temporary_file_writer.dart';

/// A file-backed store for encoded cassette bytes.
///
/// The store is format-neutral: reads enforce [maximumBytes] but do not decode
/// UTF-8, parse JSON or validate a cassette schema. Creation is exclusive and
/// explicit replacement is atomic where the file system supports replacement
/// rename. Conditional replacement is not implemented yet.
final class FileCassetteStore implements CassetteStore {
  /// Creates a file store rooted at [root].
  ///
  /// A missing root behaves as an empty store for reads. [maximumBytes] must be
  /// positive and defaults to the measured V1 total-file limit.
  factory FileCassetteStore(
    Directory root, {
    int maximumBytes = defaultMaximumCassetteBytesV1,
  }) {
    if (maximumBytes <= 0) {
      throw ArgumentError('Maximum cassette byte count must be positive.');
    }
    return FileCassetteStore._(
      root: root.absolute,
      maximumBytes: maximumBytes,
    );
  }

  FileCassetteStore._({
    required Directory root,
    required this.maximumBytes,
  })  : _root = root,
        _resolver = FileCassettePathResolver(root);

  /// The default maximum encoded V1 cassette size of 64 MiB.
  static const int defaultMaximumBytesV1 = defaultMaximumCassetteBytesV1;

  final Directory _root;
  final FileCassettePathResolver _resolver;
  final SameDirectoryTemporaryFileWriter _temporaryFileWriter =
      SameDirectoryTemporaryFileWriter();
  final Map<CassetteName, Future<void>> _writeTails =
      <CassetteName, Future<void>>{};

  /// The maximum encoded cassette bytes accepted by one read.
  final int maximumBytes;

  @override
  Future<bool> exists(CassetteName name) async {
    await _waitForWrites(name);
    if (!await _rootExists(name, CassetteStoreOperation.exists)) {
      return false;
    }
    final file = await _resolver.resolve(
      name,
      operation: CassetteStoreOperation.exists,
    );
    return file.exists();
  }

  @override
  Future<CassetteSnapshot> read(CassetteName name) async {
    await _waitForWrites(name);
    if (!await _rootExists(name, CassetteStoreOperation.read)) {
      throw CassetteStoreException.notFound(
        name: name,
        operation: CassetteStoreOperation.read,
      );
    }
    final file = await _resolver.resolve(
      name,
      operation: CassetteStoreOperation.read,
    );
    if (!await file.exists()) {
      throw CassetteStoreException.notFound(
        name: name,
        operation: CassetteStoreOperation.read,
      );
    }

    try {
      final bytes = await _readBounded(file, name);
      return CassetteSnapshot(
        name: name,
        bytes: bytes,
        revision: CassetteRevision(),
      );
    } on CassetteStoreException {
      rethrow;
    } on FileSystemException {
      if (!await file.exists()) {
        throw CassetteStoreException.notFound(
          name: name,
          operation: CassetteStoreOperation.read,
        );
      }
      throw CassetteStoreException.operationFailed(
        name: name,
        operation: CassetteStoreOperation.read,
      );
    }
  }

  @override
  Future<void> create(CassetteName name, List<int> bytes) {
    final copied = _copyWriteBytes(
      name,
      bytes,
      operation: CassetteStoreOperation.create,
    );
    return _serialiseWrite(name, () => _create(name, copied));
  }

  @override
  Future<void> replace(CassetteName name, List<int> bytes) {
    final copied = _copyWriteBytes(
      name,
      bytes,
      operation: CassetteStoreOperation.replace,
    );
    return _serialiseWrite(name, () => _replace(name, copied));
  }

  @override
  Future<void> replaceIfUnchanged(
    CassetteSnapshot snapshot,
    List<int> bytes,
  ) =>
      Future<void>.error(
        CassetteStoreException.unsupported(
          name: snapshot.name,
          operation: CassetteStoreOperation.replaceIfUnchanged,
        ),
      );

  Future<bool> _rootExists(
    CassetteName name,
    CassetteStoreOperation operation,
  ) async {
    final type = await FileSystemEntity.type(_root.path);
    if (type == FileSystemEntityType.notFound) {
      return false;
    }
    if (type != FileSystemEntityType.directory) {
      throw CassetteStoreException.operationFailed(
        name: name,
        operation: operation,
      );
    }
    return true;
  }

  Future<Uint8List> _readBounded(File file, CassetteName name) async {
    final builder = BytesBuilder(copy: false);
    var observedBytes = 0;
    await for (final chunk in file.openRead()) {
      observedBytes += chunk.length;
      if (observedBytes > maximumBytes) {
        throw CassetteStoreException.operationFailed(
          name: name,
          operation: CassetteStoreOperation.read,
        );
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Uint8List _copyWriteBytes(
    CassetteName name,
    List<int> bytes, {
    required CassetteStoreOperation operation,
  }) {
    if (bytes.length > maximumBytes) {
      throw CassetteStoreException.operationFailed(
        name: name,
        operation: operation,
      );
    }
    for (final byte in bytes) {
      if (byte < 0 || byte > 255) {
        throw ArgumentError(
          'Cassette store values must be bytes from 0 through 255.',
        );
      }
    }
    return Uint8List.fromList(bytes);
  }

  Future<void> _create(CassetteName name, Uint8List bytes) async {
    await _ensureRoot(name, CassetteStoreOperation.create);
    var target = await _resolver.resolve(
      name,
      operation: CassetteStoreOperation.create,
    );

    try {
      await target.parent.create(recursive: true);
      target = await _resolver.resolve(
        name,
        operation: CassetteStoreOperation.create,
      );
    } on CassetteStoreException {
      rethrow;
    } on FileSystemException {
      throw CassetteStoreException.operationFailed(
        name: name,
        operation: CassetteStoreOperation.create,
      );
    }

    var created = false;
    RandomAccessFile? handle;
    try {
      await target.create(exclusive: true);
      created = true;
      handle = await target.open(mode: FileMode.writeOnly);
      await handle.writeFrom(bytes);
      await handle.flush();
      await handle.close();
      handle = null;
    } on FileSystemException {
      await _closeQuietly(handle);
      if (created) {
        await _deleteQuietly(target);
        throw CassetteStoreException.operationFailed(
          name: name,
          operation: CassetteStoreOperation.create,
        );
      }
      final type = await FileSystemEntity.type(
        target.path,
        followLinks: false,
      );
      if (type != FileSystemEntityType.notFound) {
        throw CassetteStoreException.alreadyExists(name);
      }
      throw CassetteStoreException.operationFailed(
        name: name,
        operation: CassetteStoreOperation.create,
      );
    } catch (_) {
      await _closeQuietly(handle);
      if (created) {
        await _deleteQuietly(target);
      }
      rethrow;
    }
  }

  Future<void> _replace(CassetteName name, Uint8List bytes) async {
    if (!await _rootExists(name, CassetteStoreOperation.replace)) {
      throw CassetteStoreException.notFound(
        name: name,
        operation: CassetteStoreOperation.replace,
      );
    }
    var target = await _resolver.resolve(
      name,
      operation: CassetteStoreOperation.replace,
    );
    await _requireReplaceableTarget(target, name);

    File? candidate;
    try {
      candidate = await _temporaryFileWriter.write(target, bytes);
      target = await _resolver.resolve(
        name,
        operation: CassetteStoreOperation.replace,
      );
      await _requireReplaceableTarget(target, name);
      await _temporaryFileWriter.replaceTarget(candidate, target);
      candidate = null;
    } on CassetteStoreException {
      if (candidate != null) {
        await _temporaryFileWriter.discard(candidate);
      }
      rethrow;
    } on Object {
      if (candidate != null) {
        await _temporaryFileWriter.discard(candidate);
      }
      throw CassetteStoreException.operationFailed(
        name: name,
        operation: CassetteStoreOperation.replace,
      );
    }
  }

  Future<void> _requireReplaceableTarget(
    File target,
    CassetteName name,
  ) async {
    FileSystemEntityType type;
    try {
      type = await FileSystemEntity.type(target.path, followLinks: false);
    } on FileSystemException {
      throw CassetteStoreException.operationFailed(
        name: name,
        operation: CassetteStoreOperation.replace,
      );
    }
    if (type == FileSystemEntityType.notFound) {
      throw CassetteStoreException.notFound(
        name: name,
        operation: CassetteStoreOperation.replace,
      );
    }
    if (type != FileSystemEntityType.file) {
      throw CassetteStoreException.operationFailed(
        name: name,
        operation: CassetteStoreOperation.replace,
      );
    }
  }

  Future<void> _ensureRoot(
    CassetteName name,
    CassetteStoreOperation operation,
  ) async {
    final type = await FileSystemEntity.type(_root.path);
    if (type == FileSystemEntityType.notFound) {
      try {
        await _root.create(recursive: true);
      } on FileSystemException {
        throw CassetteStoreException.operationFailed(
          name: name,
          operation: operation,
        );
      }
      return;
    }
    if (type != FileSystemEntityType.directory) {
      throw CassetteStoreException.operationFailed(
        name: name,
        operation: operation,
      );
    }
  }

  Future<void> _waitForWrites(CassetteName name) async {
    final pending = _writeTails[name];
    if (pending == null) {
      return;
    }
    try {
      await pending;
    } on Object {
      // A later operation must observe the resulting file-system state even
      // when the preceding write failed.
    }
  }

  Future<void> _serialiseWrite(
    CassetteName name,
    Future<void> Function() operation,
  ) {
    final previous = _writeTails[name] ?? Future<void>.value();
    final next = previous.catchError((Object _) {}).then((_) => operation());
    _writeTails[name] = next;
    return next.whenComplete(() {
      if (identical(_writeTails[name], next)) {
        final completed = _writeTails.remove(name);
        if (completed != null) {
          unawaited(completed);
        }
      }
    });
  }
}

Future<void> _closeQuietly(RandomAccessFile? handle) async {
  if (handle == null) {
    return;
  }
  try {
    await handle.close();
  } on FileSystemException {
    // The original write failure remains authoritative.
  }
}

Future<void> _deleteQuietly(File file) async {
  try {
    if (await file.exists()) {
      await file.delete();
    }
  } on FileSystemException {
    // Cleanup is best effort after a failed create.
  }
}

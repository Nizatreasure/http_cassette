import 'dart:io';
import 'dart:typed_data';

import '../cassette/name.dart';
import '../configuration/cassette_size_limit.dart';
import 'exception.dart';
import 'file_path_resolver.dart';
import 'snapshot.dart';
import 'store.dart';

/// A read-capable file-backed store for encoded cassette bytes.
///
/// The store is format-neutral: reads enforce [maximumBytes] but do not decode
/// UTF-8, parse JSON or validate a cassette schema. Write operations remain
/// unsupported until atomic file writes are implemented.
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

  /// The maximum encoded cassette bytes accepted by one read.
  final int maximumBytes;

  @override
  Future<bool> exists(CassetteName name) async {
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
  Future<void> create(CassetteName name, List<int> bytes) => Future<void>.error(
        CassetteStoreException.unsupported(
          name: name,
          operation: CassetteStoreOperation.create,
        ),
      );

  @override
  Future<void> replace(CassetteName name, List<int> bytes) =>
      Future<void>.error(
        CassetteStoreException.unsupported(
          name: name,
          operation: CassetteStoreOperation.replace,
        ),
      );

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
}

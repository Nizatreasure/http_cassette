import 'dart:io';

import '../cassette/name.dart';
import 'exception.dart';

/// Resolves logical cassette names beneath one existing file-store root.
///
/// Resolution canonicalises the root and every existing path component on
/// each call. This prevents a symbolic-link change from relying on validation
/// performed by an earlier operation.
final class FileCassettePathResolver {
  /// Creates a resolver for [root].
  FileCassettePathResolver(Directory root) : _root = root.absolute;

  final Directory _root;

  /// Resolves [name] to its store-owned JSON file for [operation].
  ///
  /// The root must exist. Existing symbolic links may resolve within the root
  /// but any escape or invalid path state produces a safe operation failure.
  Future<File> resolve(
    CassetteName name, {
    required CassetteStoreOperation operation,
  }) async {
    try {
      final canonicalRoot = Directory(await _root.resolveSymbolicLinks());
      final rootType = await FileSystemEntity.type(canonicalRoot.path);
      if (rootType != FileSystemEntityType.directory) {
        throw CassetteStoreException.operationFailed(
          name: name,
          operation: operation,
        );
      }
      var current = canonicalRoot;
      final segments = name.value.split('/');

      for (var index = 0; index < segments.length - 1; index++) {
        final candidate = Directory.fromUri(
          current.uri.resolve('${segments[index]}/'),
        );
        final type = await FileSystemEntity.type(
          candidate.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.notFound) {
          final remaining = segments.skip(index).join('/');
          return File.fromUri(current.uri.resolve('$remaining.json'));
        }
        if (type != FileSystemEntityType.directory &&
            type != FileSystemEntityType.link) {
          throw CassetteStoreException.operationFailed(
            name: name,
            operation: operation,
          );
        }

        final resolved = Directory(await candidate.resolveSymbolicLinks());
        if (!_isWithin(canonicalRoot, resolved.path)) {
          throw CassetteStoreException.operationFailed(
            name: name,
            operation: operation,
          );
        }
        current = resolved;
      }

      final target = File.fromUri(
        current.uri.resolve('${segments.last}.json'),
      );
      final targetType = await FileSystemEntity.type(
        target.path,
        followLinks: false,
      );
      if (targetType == FileSystemEntityType.notFound) {
        return target;
      }
      if (targetType != FileSystemEntityType.file &&
          targetType != FileSystemEntityType.link) {
        throw CassetteStoreException.operationFailed(
          name: name,
          operation: operation,
        );
      }

      final resolvedTarget = await target.resolveSymbolicLinks();
      if (!_isWithin(canonicalRoot, resolvedTarget)) {
        throw CassetteStoreException.operationFailed(
          name: name,
          operation: operation,
        );
      }
      return File(resolvedTarget);
    } on CassetteStoreException {
      rethrow;
    } on FileSystemException {
      throw CassetteStoreException.operationFailed(
        name: name,
        operation: operation,
      );
    }
  }
}

bool _isWithin(Directory root, String candidate) {
  final rootPath = _comparisonPath(root.path);
  final candidatePath = _comparisonPath(candidate);
  final rootPrefix = rootPath.endsWith(Platform.pathSeparator)
      ? rootPath
      : '$rootPath${Platform.pathSeparator}';
  return candidatePath == rootPath || candidatePath.startsWith(rootPrefix);
}

String _comparisonPath(String path) =>
    Platform.isWindows ? path.toLowerCase() : path;

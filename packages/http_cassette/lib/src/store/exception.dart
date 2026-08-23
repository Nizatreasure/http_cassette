import '../cassette/name.dart';

/// The store operation that failed.
enum CassetteStoreOperation {
  /// Checking whether a cassette exists.
  exists,

  /// Reading a cassette snapshot.
  read,

  /// Creating a cassette only when absent.
  create,

  /// Explicitly replacing a cassette.
  replace,

  /// Replacing a cassette only when its revision is unchanged.
  replaceIfUnchanged,
}

/// A stable category for a cassette-store failure.
enum CassetteStoreFailureKind {
  /// The requested cassette does not exist.
  notFound,

  /// Creation found an existing cassette.
  alreadyExists,

  /// Conditional replacement found a different current revision.
  revisionChanged,

  /// The store cannot perform the requested operation.
  unsupportedOperation,

  /// The store could not complete the requested operation.
  operationFailed,
}

/// A safe structured failure reported by a cassette store.
///
/// This exception retains only a logical cassette name, operation and stable
/// category. It does not retain paths, cassette bytes, revisions or underlying
/// platform exceptions.
final class CassetteStoreException implements Exception {
  /// Creates a missing-cassette failure for [operation].
  factory CassetteStoreException.notFound({
    required CassetteName name,
    required CassetteStoreOperation operation,
  }) {
    if (operation != CassetteStoreOperation.read &&
        operation != CassetteStoreOperation.replace &&
        operation != CassetteStoreOperation.replaceIfUnchanged) {
      throw ArgumentError(
        'A missing cassette can fail read or replacement operations only.',
      );
    }
    return CassetteStoreException._(
      kind: CassetteStoreFailureKind.notFound,
      name: name,
      operation: operation,
    );
  }

  /// Creates a failure for creation when [name] already exists.
  factory CassetteStoreException.alreadyExists(CassetteName name) =>
      CassetteStoreException._(
        kind: CassetteStoreFailureKind.alreadyExists,
        name: name,
        operation: CassetteStoreOperation.create,
      );

  /// Creates a stale-revision failure for conditional replacement of [name].
  factory CassetteStoreException.revisionChanged(CassetteName name) =>
      CassetteStoreException._(
        kind: CassetteStoreFailureKind.revisionChanged,
        name: name,
        operation: CassetteStoreOperation.replaceIfUnchanged,
      );

  /// Creates an unsupported [operation] failure for [name].
  factory CassetteStoreException.unsupported({
    required CassetteName name,
    required CassetteStoreOperation operation,
  }) =>
      CassetteStoreException._(
        kind: CassetteStoreFailureKind.unsupportedOperation,
        name: name,
        operation: operation,
      );

  /// Creates a general failure for [operation] on [name].
  factory CassetteStoreException.operationFailed({
    required CassetteName name,
    required CassetteStoreOperation operation,
  }) =>
      CassetteStoreException._(
        kind: CassetteStoreFailureKind.operationFailed,
        name: name,
        operation: operation,
      );

  const CassetteStoreException._({
    required this.kind,
    required this.name,
    required this.operation,
  });

  /// The stable machine-readable failure category.
  final CassetteStoreFailureKind kind;

  /// The logical cassette involved in the failure.
  final CassetteName name;

  /// The operation that failed.
  final CassetteStoreOperation operation;

  @override
  String toString() => 'CassetteStoreException('
      '${kind.name}, ${operation.name}, ${name.value})';
}

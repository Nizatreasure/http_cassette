import '../cassette/name.dart';
import '../configuration/cassette_size_limit.dart';
import 'exception.dart';
import 'snapshot.dart';
import 'store.dart';

/// An isolate-local in-memory cassette store.
///
/// Each instance owns private state. Operations mutate that state synchronously
/// in invocation order before their returned futures complete. No state is
/// shared across instances or Dart isolates.
final class MemoryCassetteStore implements CassetteStore {
  /// Creates an empty in-memory store with a positive [maximumBytes].
  factory MemoryCassetteStore({
    int maximumBytes = defaultMaximumCassetteBytesV1,
  }) {
    if (maximumBytes <= 0) {
      throw ArgumentError('Maximum cassette byte count must be positive.');
    }
    return MemoryCassetteStore._(maximumBytes);
  }

  MemoryCassetteStore._(this.maximumBytes);

  /// The default maximum encoded V1 cassette size of 64 MiB.
  static const int defaultMaximumBytesV1 = defaultMaximumCassetteBytesV1;

  @override
  final int maximumBytes;

  final Map<CassetteName, CassetteSnapshot> _snapshots =
      <CassetteName, CassetteSnapshot>{};

  @override
  Future<bool> exists(CassetteName name) =>
      Future<bool>.value(_snapshots.containsKey(name));

  @override
  Future<CassetteSnapshot> read(CassetteName name) {
    final snapshot = _snapshots[name];
    if (snapshot == null) {
      return Future<CassetteSnapshot>.error(
        CassetteStoreException.notFound(
          name: name,
          operation: CassetteStoreOperation.read,
        ),
      );
    }
    return Future<CassetteSnapshot>.value(_copySnapshot(snapshot));
  }

  @override
  Future<void> create(CassetteName name, List<int> bytes) {
    final limitFailure = _validateBytes(
      name,
      bytes,
      CassetteStoreOperation.create,
    );
    if (limitFailure != null) {
      return limitFailure;
    }
    if (_snapshots.containsKey(name)) {
      return Future<void>.error(CassetteStoreException.alreadyExists(name));
    }
    _snapshots[name] = _newSnapshot(name, bytes);
    return Future<void>.value();
  }

  @override
  Future<void> replace(CassetteName name, List<int> bytes) {
    final limitFailure = _validateBytes(
      name,
      bytes,
      CassetteStoreOperation.replace,
    );
    if (limitFailure != null) {
      return limitFailure;
    }
    if (!_snapshots.containsKey(name)) {
      return Future<void>.error(
        CassetteStoreException.notFound(
          name: name,
          operation: CassetteStoreOperation.replace,
        ),
      );
    }
    _snapshots[name] = _newSnapshot(name, bytes);
    return Future<void>.value();
  }

  @override
  Future<void> replaceIfUnchanged(
    CassetteSnapshot snapshot,
    List<int> bytes,
  ) {
    final limitFailure = _validateBytes(
      snapshot.name,
      bytes,
      CassetteStoreOperation.replaceIfUnchanged,
    );
    if (limitFailure != null) {
      return limitFailure;
    }
    final current = _snapshots[snapshot.name];
    if (current == null) {
      return Future<void>.error(
        CassetteStoreException.notFound(
          name: snapshot.name,
          operation: CassetteStoreOperation.replaceIfUnchanged,
        ),
      );
    }
    if (!identical(current.revision, snapshot.revision)) {
      return Future<void>.error(
        CassetteStoreException.revisionChanged(snapshot.name),
      );
    }
    _snapshots[snapshot.name] = _newSnapshot(snapshot.name, bytes);
    return Future<void>.value();
  }

  Future<void>? _validateBytes(
    CassetteName name,
    List<int> bytes,
    CassetteStoreOperation operation,
  ) {
    if (bytes.length <= maximumBytes) {
      return null;
    }
    return Future<void>.error(
      CassetteStoreException.operationFailed(
        name: name,
        operation: operation,
      ),
    );
  }
}

CassetteSnapshot _newSnapshot(CassetteName name, List<int> bytes) =>
    CassetteSnapshot(
      name: name,
      bytes: bytes,
      revision: CassetteRevision(),
    );

CassetteSnapshot _copySnapshot(CassetteSnapshot snapshot) => CassetteSnapshot(
      name: snapshot.name,
      bytes: snapshot.bytes,
      revision: snapshot.revision,
    );

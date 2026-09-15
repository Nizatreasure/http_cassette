import '../cassette/encoder.dart';
import '../diagnostics/diagnostic.dart';
import '../diagnostics/exception.dart';
import '../store/configuration.dart';
import '../store/exception.dart';
import '../store/operation_timeout.dart';
import '../store/store.dart';
import 'active_state.dart';
import 'configuration.dart';

/// Finalises, encodes and writes one complete recording cassette.
final class RecordingCassetteCommitter {
  /// Creates a committer backed by [store].
  const RecordingCassetteCommitter(
    this.store, {
    this.operationTimeout = StoreOperationConfiguration.defaultTimeout,
  });

  /// The store receiving the complete encoded cassette.
  final CassetteStore store;

  /// The maximum wait for the cassette write.
  final Duration operationTimeout;

  /// Commits the complete recording retained by [state].
  ///
  /// Create and replace modes use their corresponding authoritative store
  /// operation. Append conditionally replaces its exact prepared snapshot.
  Future<void> commit(ActiveRecordingState state) async {
    final cassette = state.finaliseCassette();
    final bytes = encodeCassetteV1(cassette);
    final operation = switch (state.options.existingCassette) {
      ExistingCassette.fail => CassetteStoreOperation.create,
      ExistingCassette.replace => CassetteStoreOperation.replace,
      ExistingCassette.append => CassetteStoreOperation.replaceIfUnchanged,
    };

    try {
      switch (operation) {
        case CassetteStoreOperation.create:
          await runStoreOperation(
            action: () => store.create(state.cassetteName, bytes),
            timeout: operationTimeout,
            name: state.cassetteName,
            operation: operation,
          );
        case CassetteStoreOperation.replace:
          await runStoreOperation(
            action: () => store.replace(state.cassetteName, bytes),
            timeout: operationTimeout,
            name: state.cassetteName,
            operation: operation,
          );
        case CassetteStoreOperation.replaceIfUnchanged:
          final snapshot = state.appendSnapshot;
          if (snapshot == null) {
            throw StateError(
              'Append recording requires a prepared cassette snapshot.',
            );
          }
          await runStoreOperation(
            action: () => store.replaceIfUnchanged(snapshot, bytes),
            timeout: operationTimeout,
            name: state.cassetteName,
            operation: operation,
          );
        case CassetteStoreOperation.exists || CassetteStoreOperation.read:
          throw StateError('Invalid recording commit store operation.');
      }
    } on CassetteStoreException catch (failure) {
      if (failure.name != state.cassetteName ||
          failure.operation != operation) {
        throw StateError(
          'A cassette store reported an invalid recording-write failure.',
        );
      }
      throw _commitException(
        failure,
        networkAccess: cassette.interactions.isEmpty
            ? NetworkAccess.notAttempted
            : NetworkAccess.attempted,
      );
    }
  }
}

CassetteException _commitException(
  CassetteStoreException failure, {
  required NetworkAccess networkAccess,
}) {
  final category = switch ((failure.operation, failure.kind)) {
    (_, CassetteStoreFailureKind.operationFailed) =>
      DiagnosticCategory.storeWriteResultUnconfirmed,
    (CassetteStoreOperation.create, CassetteStoreFailureKind.alreadyExists) =>
      DiagnosticCategory.targetCassetteExists,
    (CassetteStoreOperation.replace, CassetteStoreFailureKind.notFound) =>
      DiagnosticCategory.cassetteMissing,
    (CassetteStoreOperation.replace, _) =>
      DiagnosticCategory.atomicReplacementFailure,
    (
      CassetteStoreOperation.replaceIfUnchanged,
      CassetteStoreFailureKind.notFound ||
          CassetteStoreFailureKind.revisionChanged,
    ) =>
      DiagnosticCategory.appendTargetChanged,
    (CassetteStoreOperation.replaceIfUnchanged, _) =>
      DiagnosticCategory.atomicReplacementFailure,
    (CassetteStoreOperation.create, _) => DiagnosticCategory.storeWriteFailure,
    _ => throw StateError('Invalid recording commit failure operation.'),
  };
  return CassetteException(
    CassetteDiagnostic(
      category: category,
      summary: switch (category) {
        DiagnosticCategory.targetCassetteExists =>
          'The recording target appeared before it could be created.',
        DiagnosticCategory.cassetteMissing =>
          'The recording replacement target no longer exists.',
        DiagnosticCategory.atomicReplacementFailure =>
          'The recording target could not be replaced atomically.',
        DiagnosticCategory.appendTargetChanged =>
          'The append target changed before the recording could be committed; '
              'no append was written.',
        DiagnosticCategory.storeWriteFailure =>
          'The recording cassette could not be written.',
        DiagnosticCategory.storeWriteResultUnconfirmed =>
          'The store reported a write failure and its final result could not '
              'be confirmed.',
        _ => throw StateError('Invalid recording commit category.'),
      },
      networkAccess: networkAccess,
    ),
  );
}

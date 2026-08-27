import '../cassette/encoder.dart';
import '../diagnostics/diagnostic.dart';
import '../diagnostics/exception.dart';
import '../store/exception.dart';
import '../store/store.dart';
import 'active_state.dart';
import 'configuration.dart';

/// Finalises, encodes and authoritatively writes one recording cassette.
final class RecordingCassetteCommitter {
  /// Creates a committer backed by [store].
  const RecordingCassetteCommitter(this.store);

  /// The store receiving the complete encoded cassette.
  final CassetteStore store;

  /// Commits the complete recording retained by [state].
  ///
  /// Create and replace modes use their corresponding authoritative store
  /// operation. Append has a separate loading and conditional-write contract.
  Future<void> commit(ActiveRecordingState state) async {
    final cassette = state.finaliseCassette();
    final bytes = encodeCassetteV1(cassette);
    final operation = switch (state.options.existingCassette) {
      ExistingCassette.fail => CassetteStoreOperation.create,
      ExistingCassette.replace => CassetteStoreOperation.replace,
      ExistingCassette.append => throw StateError(
          'Append recording requires its dedicated conditional commit.',
        ),
    };

    try {
      switch (operation) {
        case CassetteStoreOperation.create:
          await store.create(state.cassetteName, bytes);
        case CassetteStoreOperation.replace:
          await store.replace(state.cassetteName, bytes);
        case CassetteStoreOperation.exists ||
              CassetteStoreOperation.read ||
              CassetteStoreOperation.replaceIfUnchanged:
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
    (CassetteStoreOperation.create, CassetteStoreFailureKind.alreadyExists) =>
      DiagnosticCategory.targetCassetteExists,
    (CassetteStoreOperation.replace, CassetteStoreFailureKind.notFound) =>
      DiagnosticCategory.cassetteMissing,
    (CassetteStoreOperation.replace, _) =>
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
        DiagnosticCategory.storeWriteFailure =>
          'The recording cassette could not be written.',
        _ => throw StateError('Invalid recording commit category.'),
      },
      networkAccess: networkAccess,
    ),
  );
}

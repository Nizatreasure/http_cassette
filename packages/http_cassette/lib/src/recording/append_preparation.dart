import '../cassette/cassette.dart';
import '../cassette/decoder.dart';
import '../cassette/name.dart';
import '../configuration/body_limits.dart';
import '../diagnostics/diagnostic.dart';
import '../store/configuration.dart';
import '../store/exception.dart';
import '../store/operation_timeout.dart';
import '../store/snapshot.dart';
import '../store/store.dart';

/// The result of preparing one existing cassette for append recording.
sealed class AppendCassettePreparationResult {
  const AppendCassettePreparationResult._();

  /// Creates a successful preparation retaining [snapshot] and [cassette].
  const factory AppendCassettePreparationResult.prepared({
    required CassetteSnapshot snapshot,
    required Cassette cassette,
  }) = AppendCassettePrepared._;

  /// Creates a failed preparation containing only safe [failure] details.
  const factory AppendCassettePreparationResult.failed(
    AppendCassettePreparationFailure failure,
  ) = AppendCassettePreparationFailed._;
}

/// One valid, fully decoded append target and its exact store snapshot.
final class AppendCassettePrepared extends AppendCassettePreparationResult {
  const AppendCassettePrepared._({
    required this.snapshot,
    required this.cassette,
  }) : super._();

  /// The immutable encoded snapshot whose revision must remain current.
  final CassetteSnapshot snapshot;

  /// The fully validated cassette reconstructed from [snapshot].
  final Cassette cassette;
}

/// An expected append preparation failure.
final class AppendCassettePreparationFailed
    extends AppendCassettePreparationResult {
  const AppendCassettePreparationFailed._(this.failure) : super._();

  /// Safe structured details of the failure.
  final AppendCassettePreparationFailure failure;
}

/// Safe structured details of an append preparation failure.
final class AppendCassettePreparationFailure {
  AppendCassettePreparationFailure._({
    required this.cassetteName,
    required this.envelope,
    this.storeFailureKind,
    this.decodeFailureKind,
    this.observedSchemaVersion,
  });

  /// The validated logical cassette identity, never a persistence path.
  final CassetteName cassetteName;

  /// The expected store failure kind, when reading failed.
  final CassetteStoreFailureKind? storeFailureKind;

  /// The value-free decoder failure kind, when decoding failed.
  final CassetteDecodeFailureKind? decodeFailureKind;

  /// The safely representable persisted version when versions differed.
  final int? observedSchemaVersion;

  /// The writable schema version required for append recording.
  int get currentWritableSchemaVersion => currentWritableCassetteSchemaVersion;

  /// The common safe diagnostic envelope.
  final CassetteDiagnostic envelope;
}

/// Reads and fully validates an existing cassette for append recording.
final class AppendCassettePreparer {
  /// Creates a preparer backed by [store].
  const AppendCassettePreparer(
    this.store, {
    this.operationTimeout = StoreOperationConfiguration.defaultTimeout,
    this.maximumRequestBodyBytes = BodyLimits.defaultRequestBytes,
    this.maximumResponseBodyBytes = BodyLimits.defaultResponseBytes,
  })  : assert(maximumRequestBodyBytes > 0),
        assert(maximumResponseBodyBytes > 0);

  /// The store supplying one immutable append-target snapshot.
  final CassetteStore store;

  /// The maximum wait for the append-target read.
  final Duration operationTimeout;

  /// Maximum reconstructed request body size.
  final int maximumRequestBodyBytes;

  /// Maximum reconstructed response body size.
  final int maximumResponseBodyBytes;

  /// Reads and prepares the cassette identified by [cassetteName].
  ///
  /// Exactly one store snapshot is read. No store mutation occurs.
  Future<AppendCassettePreparationResult> prepare(
    CassetteName cassetteName,
  ) async {
    late final CassetteSnapshot snapshot;
    try {
      snapshot = await runStoreOperation(
        action: () => store.read(cassetteName),
        timeout: operationTimeout,
        name: cassetteName,
        operation: CassetteStoreOperation.read,
      );
    } on CassetteStoreException catch (failure) {
      if (failure.name != cassetteName ||
          failure.operation != CassetteStoreOperation.read ||
          failure.kind == CassetteStoreFailureKind.alreadyExists ||
          failure.kind == CassetteStoreFailureKind.revisionChanged) {
        throw StateError(
          'A cassette store reported an invalid append-read failure.',
        );
      }
      return AppendCassettePreparationResult.failed(
        _storeFailure(cassetteName, failure.kind),
      );
    }
    if (snapshot.name != cassetteName) {
      throw StateError(
        'A cassette store returned an append snapshot for a different name.',
      );
    }

    try {
      final cassette = decodeCassetteV1(
        snapshot.bytes,
        maximumBytes: store.maximumBytes,
        maximumRequestBodyBytes: maximumRequestBodyBytes,
        maximumResponseBodyBytes: maximumResponseBodyBytes,
      );
      if (cassette.schemaVersion != currentWritableCassetteSchemaVersion) {
        throw StateError(
          'The decoded append cassette did not use the writable version.',
        );
      }
      return AppendCassettePreparationResult.prepared(
        snapshot: snapshot,
        cassette: cassette,
      );
    } on CassetteDecodeException catch (failure) {
      return AppendCassettePreparationResult.failed(
        _decodeFailure(cassetteName, failure),
      );
    }
  }
}

AppendCassettePreparationFailure _storeFailure(
  CassetteName cassetteName,
  CassetteStoreFailureKind kind,
) {
  final category = kind == CassetteStoreFailureKind.notFound
      ? DiagnosticCategory.appendTargetMissing
      : DiagnosticCategory.storeReadFailure;
  return AppendCassettePreparationFailure._(
    cassetteName: cassetteName,
    storeFailureKind: kind,
    envelope: CassetteDiagnostic(
      category: category,
      summary: category == DiagnosticCategory.appendTargetMissing
          ? 'The append target does not exist.'
          : 'The append target could not be read.',
      networkAccess: NetworkAccess.notAttempted,
    ),
  );
}

AppendCassettePreparationFailure _decodeFailure(
  CassetteName cassetteName,
  CassetteDecodeException failure,
) {
  final category = switch (failure.kind) {
    CassetteDecodeFailureKind.unsupportedOlderVersion ||
    CassetteDecodeFailureKind.unsupportedNewerVersion =>
      DiagnosticCategory.appendSchemaVersionMismatch,
    CassetteDecodeFailureKind.invalidStructure =>
      DiagnosticCategory.invalidCassetteStructure,
    CassetteDecodeFailureKind.bodyTooLarge =>
      DiagnosticCategory.bodyLimitExceeded,
    CassetteDecodeFailureKind.inputTooLarge ||
    CassetteDecodeFailureKind.invalidUtf8 ||
    CassetteDecodeFailureKind.malformedJson ||
    CassetteDecodeFailureKind.duplicateObjectMember ||
    CassetteDecodeFailureKind.unsupportedBodyDecoding =>
      DiagnosticCategory.cassetteDecodeFailure,
  };
  return AppendCassettePreparationFailure._(
    cassetteName: cassetteName,
    decodeFailureKind: failure.kind,
    observedSchemaVersion:
        category == DiagnosticCategory.appendSchemaVersionMismatch
            ? failure.observedSchemaVersion
            : null,
    envelope: CassetteDiagnostic(
      category: category,
      summary: switch (category) {
        DiagnosticCategory.appendSchemaVersionMismatch =>
          'The append target schema version does not match the current '
              'writable version.',
        DiagnosticCategory.invalidCassetteStructure =>
          'The append target has an invalid cassette structure.',
        DiagnosticCategory.cassetteDecodeFailure =>
          'The append target could not be decoded.',
        DiagnosticCategory.bodyLimitExceeded =>
          'An append target body exceeds its configured byte limit.',
        _ => throw StateError('Invalid append preparation category.'),
      },
      networkAccess: NetworkAccess.notAttempted,
    ),
  );
}

import '../cassette/name.dart';
import '../diagnostics/diagnostic.dart';
import '../store/exception.dart';

/// Safe structured information for a replay cassette store-read failure.
final class ReplayStoreReadDiagnostic {
  /// Maps an expected store [failure] from a replay read.
  factory ReplayStoreReadDiagnostic.fromStoreFailure(
    CassetteStoreException failure,
  ) {
    if (failure.operation != CassetteStoreOperation.read) {
      throw ArgumentError(
        'A replay store-read diagnostic requires a read failure.',
      );
    }

    final category = switch (failure.kind) {
      CassetteStoreFailureKind.notFound => DiagnosticCategory.cassetteMissing,
      CassetteStoreFailureKind.unsupportedOperation ||
      CassetteStoreFailureKind.operationFailed =>
        DiagnosticCategory.cassetteUnreadable,
      CassetteStoreFailureKind.alreadyExists ||
      CassetteStoreFailureKind.revisionChanged =>
        throw StateError('The store reported an invalid read failure kind.'),
    };
    return ReplayStoreReadDiagnostic._(
      cassetteName: failure.name,
      storeFailureKind: failure.kind,
      category: category,
    );
  }

  ReplayStoreReadDiagnostic._({
    required this.cassetteName,
    required this.storeFailureKind,
    required DiagnosticCategory category,
  }) : envelope = CassetteDiagnostic(
          category: category,
          summary: switch (category) {
            DiagnosticCategory.cassetteMissing =>
              'The replay cassette does not exist.',
            DiagnosticCategory.cassetteUnreadable =>
              'The replay cassette could not be read.',
            _ => throw StateError('Invalid replay store-read category.'),
          },
          networkAccess: NetworkAccess.disabled,
        );

  /// The validated logical cassette identity, never a persistence path.
  final CassetteName cassetteName;

  /// The safe store failure kind that caused this loading failure.
  final CassetteStoreFailureKind storeFailureKind;

  /// The common diagnostic envelope with fixed replay-loading semantics.
  final CassetteDiagnostic envelope;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReplayStoreReadDiagnostic &&
          cassetteName == other.cassetteName &&
          storeFailureKind == other.storeFailureKind;

  @override
  int get hashCode => Object.hash(cassetteName, storeFailureKind);
}

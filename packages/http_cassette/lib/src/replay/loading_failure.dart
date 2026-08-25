import '../cassette/name.dart';
import '../diagnostics/diagnostic.dart';
import 'decode_diagnostic.dart';
import 'store_read_diagnostic.dart';

/// One safe structured failure from replay cassette loading.
sealed class ReplayCassetteLoadFailure {
  const ReplayCassetteLoadFailure._();

  /// Wraps an already safe store-read [diagnostic].
  factory ReplayCassetteLoadFailure.storeRead(
    ReplayStoreReadDiagnostic diagnostic,
  ) = ReplayCassetteStoreReadFailure._;

  /// Wraps an already safe decode [diagnostic].
  factory ReplayCassetteLoadFailure.decode(
    ReplayCassetteDecodeDiagnostic diagnostic,
  ) = ReplayCassetteDecodeFailure._;

  /// The validated logical cassette identity, never a persistence path.
  CassetteName get cassetteName;

  /// The common diagnostic envelope for this loading failure.
  CassetteDiagnostic get envelope;
}

/// A replay loading failure produced by a store read.
final class ReplayCassetteStoreReadFailure extends ReplayCassetteLoadFailure {
  const ReplayCassetteStoreReadFailure._(this.diagnostic) : super._();

  /// The safe store-read diagnostic details.
  final ReplayStoreReadDiagnostic diagnostic;

  @override
  CassetteName get cassetteName => diagnostic.cassetteName;

  @override
  CassetteDiagnostic get envelope => diagnostic.envelope;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReplayCassetteStoreReadFailure && diagnostic == other.diagnostic;

  @override
  int get hashCode => diagnostic.hashCode;
}

/// A replay loading failure produced by cassette decoding.
final class ReplayCassetteDecodeFailure extends ReplayCassetteLoadFailure {
  const ReplayCassetteDecodeFailure._(this.diagnostic) : super._();

  /// The safe cassette-decode diagnostic details.
  final ReplayCassetteDecodeDiagnostic diagnostic;

  @override
  CassetteName get cassetteName => diagnostic.cassetteName;

  @override
  CassetteDiagnostic get envelope => diagnostic.envelope;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReplayCassetteDecodeFailure && diagnostic == other.diagnostic;

  @override
  int get hashCode => diagnostic.hashCode;
}

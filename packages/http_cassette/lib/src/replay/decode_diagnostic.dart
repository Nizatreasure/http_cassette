import '../cassette/decoder.dart';
import '../cassette/name.dart';
import '../diagnostics/diagnostic.dart';

/// Safe structured information for a replay cassette decode failure.
final class ReplayCassetteDecodeDiagnostic {
  /// Projects a value-free decoder [failure] for [cassetteName].
  factory ReplayCassetteDecodeDiagnostic.fromDecodeFailure({
    required CassetteName cassetteName,
    required CassetteDecodeException failure,
  }) {
    if ((failure.line == null) != (failure.column == null) ||
        (failure.line != null && failure.line! <= 0) ||
        (failure.column != null && failure.column! <= 0)) {
      throw ArgumentError(
        'Decode source positions must be positive and complete.',
      );
    }
    if (failure.kind == CassetteDecodeFailureKind.inputTooLarge &&
        (failure.maximumBytes == null || failure.maximumBytes! <= 0)) {
      throw ArgumentError(
        'An oversized cassette failure requires a positive byte limit.',
      );
    }

    final category = switch (failure.kind) {
      CassetteDecodeFailureKind.inputTooLarge ||
      CassetteDecodeFailureKind.invalidUtf8 ||
      CassetteDecodeFailureKind.malformedJson ||
      CassetteDecodeFailureKind.duplicateObjectMember =>
        DiagnosticCategory.cassetteDecodeFailure,
      CassetteDecodeFailureKind.invalidStructure =>
        DiagnosticCategory.invalidCassetteStructure,
      CassetteDecodeFailureKind.unsupportedOlderVersion =>
        DiagnosticCategory.unsupportedOlderSchemaVersion,
      CassetteDecodeFailureKind.unsupportedNewerVersion =>
        DiagnosticCategory.unsupportedNewerSchemaVersion,
    };
    return ReplayCassetteDecodeDiagnostic._(
      cassetteName: cassetteName,
      failureKind: failure.kind,
      location: failure.location,
      line: failure.line,
      column: failure.column,
      observedSchemaVersion: switch (failure.kind) {
        CassetteDecodeFailureKind.unsupportedOlderVersion ||
        CassetteDecodeFailureKind.unsupportedNewerVersion =>
          failure.observedSchemaVersion,
        _ => null,
      },
      supportedSchemaVersion: failure.supportedSchemaVersion,
      maximumBytes: failure.kind == CassetteDecodeFailureKind.inputTooLarge
          ? failure.maximumBytes
          : null,
      category: category,
    );
  }

  ReplayCassetteDecodeDiagnostic._({
    required this.cassetteName,
    required this.failureKind,
    required this.location,
    required this.line,
    required this.column,
    required this.observedSchemaVersion,
    required this.supportedSchemaVersion,
    required this.maximumBytes,
    required DiagnosticCategory category,
  }) : envelope = CassetteDiagnostic(
          category: category,
          summary: switch (category) {
            DiagnosticCategory.cassetteDecodeFailure =>
              failureKind == CassetteDecodeFailureKind.inputTooLarge
                  ? 'The replay cassette exceeds the configured byte limit.'
                  : 'The replay cassette could not be decoded.',
            DiagnosticCategory.invalidCassetteStructure =>
              'The replay cassette has an invalid structure.',
            DiagnosticCategory.unsupportedOlderSchemaVersion =>
              'The replay cassette uses an unsupported older schema version.',
            DiagnosticCategory.unsupportedNewerSchemaVersion =>
              'The replay cassette uses an unsupported newer schema version.',
            _ => throw StateError('Invalid replay decode category.'),
          },
          networkAccess: NetworkAccess.disabled,
        );

  /// The validated logical cassette identity, never a persistence path.
  final CassetteName cassetteName;

  /// The value-free decoder failure kind.
  final CassetteDecodeFailureKind failureKind;

  /// The decoder-produced structural JSON Pointer, or the root empty string.
  final String location;

  /// The one-based syntax-error line when safely available.
  final int? line;

  /// The one-based syntax-error column when safely available.
  final int? column;

  /// The safely representable unsupported schema version, when available.
  final int? observedSchemaVersion;

  /// The schema version supported by the current decoder.
  final int supportedSchemaVersion;

  /// The configured total cassette byte limit for oversized input.
  final int? maximumBytes;

  /// The common diagnostic envelope with fixed replay-loading semantics.
  final CassetteDiagnostic envelope;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReplayCassetteDecodeDiagnostic &&
          cassetteName == other.cassetteName &&
          failureKind == other.failureKind &&
          location == other.location &&
          line == other.line &&
          column == other.column &&
          observedSchemaVersion == other.observedSchemaVersion &&
          supportedSchemaVersion == other.supportedSchemaVersion &&
          maximumBytes == other.maximumBytes;

  @override
  int get hashCode => Object.hash(
        cassetteName,
        failureKind,
        location,
        line,
        column,
        observedSchemaVersion,
        supportedSchemaVersion,
        maximumBytes,
      );
}

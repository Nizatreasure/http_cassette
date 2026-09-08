import '../safety/safe_text.dart';

/// Identifies a cassette-system failure without requiring message parsing.
enum DiagnosticCategory {
  /// A logical cassette name is invalid.
  invalidCassetteName,

  /// Request-matcher configuration is invalid.
  invalidMatcherConfiguration,

  /// Sanitisation configuration is invalid.
  invalidSanitisationConfiguration,

  /// Replay-policy configuration is invalid.
  invalidReplayPolicyConfiguration,

  /// A session operation conflicts with the current lifecycle state.
  conflictingSessionOperation,

  /// This engine's policy does not permit cassette session activation.
  cassetteActivationDisabled,

  /// An operation requires an active cassette session, but none exists.
  noActiveSession,

  /// An operation attempted to use a cassette session after it closed.
  sessionAlreadyClosed,

  /// A deliberately unsafe operation was rejected.
  unsafeOperationRejected,

  /// The requested capability is unavailable on the current platform.
  unsupportedPlatform,

  /// The requested cassette does not exist.
  cassetteMissing,

  /// The requested cassette could not be read.
  cassetteUnreadable,

  /// Cassette bytes could not be decoded.
  cassetteDecodeFailure,

  /// Decoded cassette data has an invalid structure.
  invalidCassetteStructure,

  /// The cassette uses a newer schema than this package supports.
  unsupportedNewerSchemaVersion,

  /// The cassette uses an older schema that this operation cannot use.
  unsupportedOlderSchemaVersion,

  /// Cassette integrity could not be established.
  cassetteIntegrityFailure,

  /// No recorded interaction matched the incoming request.
  noMatchingInteraction,

  /// Matching interactions exist but are exhausted under the replay policy.
  interactionsExhausted,

  /// A persisted interaction is invalid.
  invalidPersistedInteraction,

  /// Required replay verification found interactions that were not used.
  unusedInteractions,

  /// Internal replay state violated a required invariant.
  replayStateInvariantFailure,

  /// Recording cannot create a cassette because the target already exists.
  targetCassetteExists,

  /// Append requires an existing cassette, but the target is missing.
  appendTargetMissing,

  /// Append found a cassette with a different writable schema version.
  appendSchemaVersionMismatch,

  /// An append target changed after it was read.
  appendTargetChanged,

  /// A request or response body exceeded its configured limit.
  bodyLimitExceeded,

  /// A request or response body uses an unsupported representation.
  unsupportedBody,

  /// Built-in sanitisation failed.
  sanitisationFailure,

  /// A custom sanitiser failed.
  customSanitiserFailure,

  /// Sanitisation produced invalid canonical data.
  invalidSanitisedResult,

  /// A cassette store could not complete a read.
  storeReadFailure,

  /// A cassette store could not complete a write.
  storeWriteFailure,

  /// Atomic cassette replacement failed.
  atomicReplacementFailure,

  /// A recording session was discarded after its callback failed.
  sessionDiscarded,

  /// Session cleanup also failed after a scoped callback failure.
  sessionCleanupFailure,

  /// An adapter supplied an invalid canonical request.
  invalidCanonicalRequest,

  /// An adapter supplied an invalid canonical response.
  invalidCanonicalResponse,

  /// An adapter did not follow the public integration contract.
  adapterContractViolation,

  /// An adapter attempted the real transport more than once.
  realTransportAttemptRepeated,

  /// An adapter did not map a transport failure safely.
  unmappedAdapterFailure,

  /// An adapter could not reconstruct a transport-specific response.
  responseReconstructionFailure,

  /// The caller cancelled the operation.
  cancelled,

  /// The core encountered an unexpected invariant failure.
  internalInvariantFailure,
}

/// Describes whether a real network attempt was possible for a failure.
enum NetworkAccess {
  /// Replay disabled network access, so no real request could occur.
  disabled,

  /// Network access was permitted but no real request was attempted.
  notAttempted,

  /// A real transport attempt began before the failure occurred.
  attempted,
}

/// Safe, structured information about an HTTP Cassette failure.
///
/// A diagnostic is the authoritative failure representation. Consumers should
/// inspect its fields rather than parse exception text.
///
/// The [summary] must be a trimmed, non-empty single line containing no more
/// than 256 Unicode code points. Control and bidirectional formatting
/// characters are rejected so the summary can be displayed safely. Values
/// removed by sanitisation must never be supplied to this constructor.
abstract final class CassetteDiagnostic {
  /// Creates a validated diagnostic.
  factory CassetteDiagnostic({
    required DiagnosticCategory category,
    required String summary,
    required NetworkAccess networkAccess,
  }) = _CassetteDiagnostic;

  /// The stable machine-readable failure category.
  DiagnosticCategory get category;

  /// A concise, safe description of the failure.
  String get summary;

  /// Whether a real network attempt was possible or occurred.
  NetworkAccess get networkAccess;
}

final class _CassetteDiagnostic implements CassetteDiagnostic {
  _CassetteDiagnostic({
    required this.category,
    required String summary,
    required this.networkAccess,
  }) : summary = validateSafeSingleLine(
          summary,
          description: 'Diagnostic summary',
        );

  @override
  final DiagnosticCategory category;

  @override
  final String summary;

  @override
  final NetworkAccess networkAccess;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CassetteDiagnostic &&
          category == other.category &&
          summary == other.summary &&
          networkAccess == other.networkAccess;

  @override
  int get hashCode => Object.hash(category, summary, networkAccess);
}

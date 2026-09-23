/// Transport-neutral HTTP recording and replay.
///
/// Provides cassette sessions, canonical HTTP models, matching, sanitisation,
/// replay policies, diagnostics, in-memory storage and the public contract used
/// by HTTP client adapters.
library;

export 'src/adapter/cancellation.dart' show CassetteCancellation;
export 'src/adapter/interception.dart' show CassetteInterception;
export 'src/adapter/real_http_attempt.dart' show RealHttpAttempt;
export 'src/cassette/name.dart';
export 'src/configuration/activation_policy.dart' show CassetteActivationPolicy;
export 'src/configuration/body_limits.dart';
export 'src/configuration/cassette_configuration.dart';
export 'src/configuration/matching_configuration.dart';
export 'src/diagnostics/diagnostic.dart';
export 'src/diagnostics/exception.dart'
    show CassetteException, ScopedCassetteException;
export 'src/diagnostics/formatter.dart';
export 'src/engine/cassette_engine.dart' show CassetteEngine;
export 'src/matching/custom.dart';
export 'src/matching/difference.dart'
    show BoundedMatchDifferences, MatchDifference, MatchDifferenceKind;
export 'src/matching/exclusions.dart' show MatchingExclusions;
export 'src/model/headers.dart';
export 'src/model/http_message.dart';
export 'src/model/outcome.dart';
export 'src/recording/configuration.dart'
    show ExistingCassette, RecordingConfiguration, RecordingOptions;
export 'src/replay/configuration.dart' show ReplayOptions, ReplayPolicy;
export 'src/sanitisation/configuration.dart'
    show GzipJsonResponseHandling, SanitisationConfiguration;
export 'src/sanitisation/custom.dart'
    show RequestSanitiser, ResponseSanitiser, SanitisedRequest;
export 'src/session/cassette_mode.dart';
export 'src/session/cassette_session.dart' show CassetteSession;
export 'src/store/configuration.dart' show StoreOperationConfiguration;
export 'src/store/exception.dart'
    show
        CassetteStoreException,
        CassetteStoreFailureKind,
        CassetteStoreOperation;
export 'src/store/memory_store.dart' show MemoryCassetteStore;
export 'src/store/snapshot.dart' show CassetteRevision, CassetteSnapshot;
export 'src/store/store.dart' show CassetteStore;

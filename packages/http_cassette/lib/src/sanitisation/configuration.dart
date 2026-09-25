import '../matching/exclusions.dart';
import '../matching/header_names.dart';
import '../matching/uri_component.dart';
import 'custom.dart';

const _builtInHeaders = <String>{
  'api-key',
  'authorization',
  'cookie',
  'proxy-authorization',
  'set-cookie',
  'x-api-key',
  'x-auth-token',
  'x-csrf-token',
  'x-xsrf-token',
};

const _builtInCredentialNames = <String>{
  'access_token',
  'api_key',
  'apikey',
  'auth',
  'authorization',
  'client_secret',
  'id_token',
  'password',
  'passwd',
  'refresh_token',
  'secret',
  'token',
};

/// How eligible gzip-coded JSON response bodies are sanitised and stored.
///
/// A response is eligible when it has a non-empty body, a supported JSON media
/// type and exactly one gzip content coding. The HTTP client may expose either
/// gzip bytes or bytes which it has already decompressed while retaining the
/// gzip header.
enum GzipJsonResponseHandling {
  /// Store the captured body state without built-in body sanitisation.
  ///
  /// Captured gzip bytes remain ordinary Base64. Already-decompressed strict
  /// JSON is recompressed only for `gzipBase64` cassette storage and is
  /// decompressed back to plain bytes during replay. That recompression
  /// requires a platform with gzip processing support.
  storeWithoutSanitisation,

  /// Sanitise and store structured JSON which replays as plain bytes.
  ///
  /// This mode requires a platform with gzip processing support, including
  /// when the HTTP client has already decompressed the captured body.
  sanitiseAndStorePlain,

  /// Sanitise and compress while preserving the captured body state.
  ///
  /// Captured gzip bytes are recompressed into ordinary Base64 and replay as
  /// gzip bytes. Already-decompressed bytes use `gzipBase64` storage and replay
  /// as plain bytes. This mode requires gzip processing support.
  sanitiseAndStoreCompressed,
}

/// Configures secure sanitisation before a recording is persisted.
///
/// Built-in rules replace common credential-shaped header, query and JSON
/// values. Project rules and custom sanitisers extend that protection.
abstract final class SanitisationConfiguration {
  /// Creates configuration with built-in rules and project additions.
  ///
  /// Header rules apply to requests and responses. Query rules apply to request
  /// URIs. JSON name and pointer rules apply to JSON request and response
  /// bodies. A JSON name matches that member at every object depth; use an exact
  /// pointer when only one path is sensitive.
  ///
  /// Header names use the HTTP token grammar. Query names are URI-normalised.
  /// Header, query and JSON member names compare case-insensitively. JSON
  /// Pointers use exact case-sensitive RFC 6901 syntax. Custom sanitisers run in
  /// registration order before the built-in rules.
  factory SanitisationConfiguration({
    Iterable<String> additionalHeaders = const <String>[],
    Iterable<String> additionalQueryParameters = const <String>[],
    Iterable<String> additionalJsonNames = const <String>[],
    Iterable<String> additionalJsonPointers = const <String>[],
    Iterable<RequestSanitiser> requestSanitisers = const <RequestSanitiser>[],
    Iterable<ResponseSanitiser> responseSanitisers =
        const <ResponseSanitiser>[],
    GzipJsonResponseHandling gzipJsonResponses =
        GzipJsonResponseHandling.storeWithoutSanitisation,
  }) {
    final pointers = MatchingExclusions(
      jsonPointers: additionalJsonPointers,
    ).jsonPointers;
    return _SanitisationConfiguration(
      builtInRulesEnabled: true,
      additionalHeaders: canonicaliseHeaderNames(
        additionalHeaders,
        invalidMessage:
            'Additional sensitive header name must use the HTTP token grammar.',
      ),
      additionalQueryParameters: _canonicalQueryNames(
        additionalQueryParameters,
      ),
      additionalJsonNames: _canonicalNames(additionalJsonNames),
      additionalJsonPointers: pointers,
      requestSanitisers: List<RequestSanitiser>.unmodifiable(
        requestSanitisers,
      ),
      responseSanitisers: List<ResponseSanitiser>.unmodifiable(
        responseSanitisers,
      ),
      gzipJsonResponses: gzipJsonResponses,
    );
  }

  /// Creates explicitly unsafe configuration without built-in rules.
  ///
  /// Recording with this configuration may persist raw credentials and
  /// personal data. The supplied custom sanitisers still run in registration
  /// order, but they alone are responsible for protecting the interaction.
  factory SanitisationConfiguration.unsafeWithoutBuiltIns({
    Iterable<RequestSanitiser> requestSanitisers = const <RequestSanitiser>[],
    Iterable<ResponseSanitiser> responseSanitisers =
        const <ResponseSanitiser>[],
    GzipJsonResponseHandling gzipJsonResponses =
        GzipJsonResponseHandling.storeWithoutSanitisation,
  }) =>
      _SanitisationConfiguration(
        builtInRulesEnabled: false,
        additionalHeaders: const <String>{},
        additionalQueryParameters: const <String>{},
        additionalJsonNames: const <String>{},
        additionalJsonPointers: const <String>{},
        requestSanitisers: List<RequestSanitiser>.unmodifiable(
          requestSanitisers,
        ),
        responseSanitisers: List<ResponseSanitiser>.unmodifiable(
          responseSanitisers,
        ),
        gzipJsonResponses: gzipJsonResponses,
      );

  /// Secure defaults with no project-specific additions.
  static final defaults = SanitisationConfiguration();

  /// Whether common sensitive-name rules are enabled.
  bool get builtInRulesEnabled;

  /// Project-added canonical lower-case sensitive header names.
  Set<String> get additionalHeaders;

  /// Project-added normalised lower-case sensitive query names.
  Set<String> get additionalQueryParameters;

  /// Project-added lower-case JSON member names matched at every object depth.
  Set<String> get additionalJsonNames;

  /// Project-added exact case-sensitive RFC 6901 JSON Pointers.
  Set<String> get additionalJsonPointers;

  /// Custom request sanitisers in explicit execution order.
  List<RequestSanitiser> get requestSanitisers;

  /// Custom response sanitisers in explicit execution order.
  List<ResponseSanitiser> get responseSanitisers;

  /// How gzip-coded JSON response bodies are sanitised and stored.
  GzipJsonResponseHandling get gzipJsonResponses;
}

final class _SanitisationConfiguration implements SanitisationConfiguration {
  const _SanitisationConfiguration({
    required this.builtInRulesEnabled,
    required this.additionalHeaders,
    required this.additionalQueryParameters,
    required this.additionalJsonNames,
    required this.additionalJsonPointers,
    required this.requestSanitisers,
    required this.responseSanitisers,
    required this.gzipJsonResponses,
  });

  @override
  final bool builtInRulesEnabled;

  @override
  final Set<String> additionalHeaders;

  @override
  final Set<String> additionalQueryParameters;

  @override
  final Set<String> additionalJsonNames;

  @override
  final Set<String> additionalJsonPointers;

  @override
  final List<RequestSanitiser> requestSanitisers;

  @override
  final List<ResponseSanitiser> responseSanitisers;

  @override
  final GzipJsonResponseHandling gzipJsonResponses;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SanitisationConfiguration &&
          builtInRulesEnabled == other.builtInRulesEnabled &&
          _setsEqual(additionalHeaders, other.additionalHeaders) &&
          _setsEqual(
            additionalQueryParameters,
            other.additionalQueryParameters,
          ) &&
          _setsEqual(additionalJsonNames, other.additionalJsonNames) &&
          _setsEqual(additionalJsonPointers, other.additionalJsonPointers) &&
          _listsEqual(requestSanitisers, other.requestSanitisers) &&
          _listsEqual(responseSanitisers, other.responseSanitisers) &&
          gzipJsonResponses == other.gzipJsonResponses;

  @override
  int get hashCode => Object.hash(
        builtInRulesEnabled,
        Object.hashAll(additionalHeaders),
        Object.hashAll(additionalQueryParameters),
        Object.hashAll(additionalJsonNames),
        Object.hashAll(additionalJsonPointers),
        Object.hashAll(requestSanitisers),
        Object.hashAll(responseSanitisers),
        gzipJsonResponses,
      );
}

Set<String> effectiveSensitiveHeaders(
        SanitisationConfiguration configuration) =>
    _effectiveRules(
      configuration,
      _builtInHeaders,
      configuration.additionalHeaders,
    );

Set<String> effectiveSensitiveQueryParameters(
  SanitisationConfiguration configuration,
) =>
    _effectiveRules(
      configuration,
      _builtInCredentialNames,
      configuration.additionalQueryParameters,
    );

Set<String> effectiveSensitiveJsonNames(
  SanitisationConfiguration configuration,
) =>
    _effectiveRules(
      configuration,
      _builtInCredentialNames,
      configuration.additionalJsonNames,
    );

Set<String> effectiveSensitiveJsonPointers(
  SanitisationConfiguration configuration,
) =>
    configuration.additionalJsonPointers;

Set<String> _canonicalQueryNames(Iterable<String> names) => _sortedSet(
      names.map((name) => normaliseUriComponent(name).toLowerCase()),
    );

Set<String> _canonicalNames(Iterable<String> names) =>
    _sortedSet(names.map((name) => name.toLowerCase()));

Set<String> _effectiveRules(
  SanitisationConfiguration configuration,
  Set<String> builtIns,
  Set<String> additions,
) =>
    _sortedSet(<String>{
      if (configuration.builtInRulesEnabled) ...builtIns,
      ...additions,
    });

Set<String> _sortedSet(Iterable<String> values) {
  final sorted = values.toSet().toList()..sort();
  return Set<String>.unmodifiable(sorted);
}

bool _setsEqual<T>(Set<T> first, Set<T> second) =>
    first.length == second.length && first.containsAll(second);

bool _listsEqual<T>(List<T> first, List<T> second) {
  if (first.length != second.length) {
    return false;
  }
  for (var index = 0; index < first.length; index += 1) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}

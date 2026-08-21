import '../matching/exclusions.dart';
import '../matching/header_names.dart';
import '../matching/uri_component.dart';

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

/// Immutable secure-default sanitisation rule configuration.
abstract final class SanitisationConfiguration {
  /// Creates configuration with mandatory built-in rules and project additions.
  ///
  /// Header names use the HTTP token grammar. Query names are URI-normalised.
  /// Header, query and JSON member names are canonicalised to lower case for
  /// exact case-insensitive rule matching. JSON Pointers use exact RFC 6901
  /// syntax and remain case-sensitive.
  factory SanitisationConfiguration({
    Iterable<String> additionalHeaders = const <String>[],
    Iterable<String> additionalQueryParameters = const <String>[],
    Iterable<String> additionalJsonNames = const <String>[],
    Iterable<String> additionalJsonPointers = const <String>[],
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
    );
  }

  /// Creates explicitly unsafe configuration without built-in rules.
  ///
  /// Recording with this configuration may persist raw credentials and
  /// personal data. Project custom sanitisers added by later configuration
  /// stages will remain independent of this built-in policy.
  factory SanitisationConfiguration.unsafeWithoutBuiltIns() =>
      const _SanitisationConfiguration(
        builtInRulesEnabled: false,
        additionalHeaders: <String>{},
        additionalQueryParameters: <String>{},
        additionalJsonNames: <String>{},
        additionalJsonPointers: <String>{},
      );

  /// Secure defaults with no project-specific additions.
  static final defaults = SanitisationConfiguration();

  /// Whether mandatory built-in sensitive-name rules are enabled.
  bool get builtInRulesEnabled;

  /// Project-added canonical lower-case sensitive header names.
  Set<String> get additionalHeaders;

  /// Project-added normalised lower-case sensitive query names.
  Set<String> get additionalQueryParameters;

  /// Project-added lower-case sensitive JSON member names.
  Set<String> get additionalJsonNames;

  /// Project-added exact RFC 6901 sensitive JSON Pointers.
  Set<String> get additionalJsonPointers;
}

final class _SanitisationConfiguration implements SanitisationConfiguration {
  const _SanitisationConfiguration({
    required this.builtInRulesEnabled,
    required this.additionalHeaders,
    required this.additionalQueryParameters,
    required this.additionalJsonNames,
    required this.additionalJsonPointers,
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
          _setsEqual(additionalJsonPointers, other.additionalJsonPointers);

  @override
  int get hashCode => Object.hash(
        builtInRulesEnabled,
        Object.hashAll(additionalHeaders),
        Object.hashAll(additionalQueryParameters),
        Object.hashAll(additionalJsonNames),
        Object.hashAll(additionalJsonPointers),
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

import '../matching/exclusions.dart';
import '../matching/header_names.dart';

/// Immutable configuration for built-in request matching.
abstract final class MatchingConfiguration {
  /// Creates validated matching configuration.
  ///
  /// Method, URI and non-empty-body matching cannot be disabled. Header names
  /// use the HTTP token grammar. Query names and JSON Pointers follow the
  /// validation rules described by [MatchingExclusions].
  factory MatchingConfiguration({
    Iterable<String> includedHeaders = const <String>[],
    Iterable<String> ignoredQueryParameters = const <String>[],
    Iterable<String> ignoredJsonPointers = const <String>[],
  }) {
    final exclusions = MatchingExclusions(
      queryParameters: ignoredQueryParameters,
      jsonPointers: ignoredJsonPointers,
    );
    return _MatchingConfiguration(
      includedHeaders: canonicaliseHeaderNames(
        includedHeaders,
        invalidMessage: 'Included header name must use the HTTP token grammar.',
      ),
      ignoredQueryParameters: exclusions.queryParameters,
      ignoredJsonPointers: exclusions.jsonPointers,
    );
  }

  /// An empty configuration using only the fixed default matcher components.
  static final defaults = MatchingConfiguration();

  /// Canonical lower-case header names included in matching.
  Set<String> get includedHeaders;

  /// Query parameter names whose values are ignored.
  Set<String> get ignoredQueryParameters;

  /// Exact RFC 6901 JSON Pointers whose values are ignored.
  Set<String> get ignoredJsonPointers;
}

final class _MatchingConfiguration implements MatchingConfiguration {
  const _MatchingConfiguration({
    required this.includedHeaders,
    required this.ignoredQueryParameters,
    required this.ignoredJsonPointers,
  });

  @override
  final Set<String> includedHeaders;

  @override
  final Set<String> ignoredQueryParameters;

  @override
  final Set<String> ignoredJsonPointers;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatchingConfiguration &&
          _setsEqual(includedHeaders, other.includedHeaders) &&
          _setsEqual(
            ignoredQueryParameters,
            other.ignoredQueryParameters,
          ) &&
          _setsEqual(ignoredJsonPointers, other.ignoredJsonPointers);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(includedHeaders),
        Object.hashAll(ignoredQueryParameters),
        Object.hashAll(ignoredJsonPointers),
      );
}

bool _setsEqual<T>(Set<T> first, Set<T> second) =>
    first.length == second.length && first.containsAll(second);

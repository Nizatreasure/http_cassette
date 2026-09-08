import '../model/http_message.dart';
import 'difference.dart';
import 'exclusions.dart';

/// Adds one domain-specific comparison to the configured request matcher.
///
/// The component runs after the built-in comparisons. It must compare
/// deterministically, respect every exclusion in [MatchContext], and return
/// only safe value-free differences.
abstract interface class RequestMatcherComponent {
  /// A stable safe name identifying this component in diagnostics.
  String get name;

  /// Compares recorded [expected] data with the incoming [actual] request.
  ///
  /// [context] identifies values which sanitisation or configuration excludes
  /// from matching. The method must not log or retain request values.
  MatchComponentResult compare(
    CassetteRequest expected,
    CassetteRequest actual,
    MatchContext context,
  );
}

/// The effective matching exclusions supplied to a custom matcher component.
abstract final class MatchContext {
  /// Creates a validated context for direct component use or testing.
  factory MatchContext({
    Iterable<String> excludedHeaders = const <String>[],
    Iterable<String> excludedQueryParameters = const <String>[],
    Iterable<String> excludedJsonPointers = const <String>[],
    bool uriUserInformationExcluded = false,
    bool bodyExcluded = false,
  }) {
    final exclusions = MatchingExclusions(
      headers: excludedHeaders,
      queryParameters: excludedQueryParameters,
      jsonPointers: excludedJsonPointers,
      uriUserInformation: uriUserInformationExcluded,
      body: bodyExcluded,
    );
    return _MatchContext(exclusions);
  }

  /// Canonical lower-case header names excluded from value matching.
  Set<String> get excludedHeaders;

  /// Normalised query names whose values are excluded from matching.
  Set<String> get excludedQueryParameters;

  /// Exact RFC 6901 JSON Pointers excluded from value matching.
  Set<String> get excludedJsonPointers;

  /// Whether URI user information is excluded from value matching.
  bool get uriUserInformationExcluded;

  /// Whether the complete request body value is excluded from matching.
  ///
  /// Body presence remains significant.
  bool get bodyExcluded;
}

/// The safe result returned by one custom matcher comparison.
abstract final class MatchComponentResult {
  /// Creates a result from [matches] and value-free [differences].
  ///
  /// A matching result must have no differences. A non-matching result must
  /// provide at least one difference. Retained details use the library's fixed
  /// diagnostic bound while the complete count remains available.
  factory MatchComponentResult({
    required bool matches,
    Iterable<MatchDifference> differences = const <MatchDifference>[],
  }) {
    final collector = MatchDifferenceCollector();
    for (final difference in differences) {
      collector.add(difference);
    }
    final boundedDifferences = collector.build();
    if (matches != boundedDifferences.isEmpty) {
      throw ArgumentError(
        matches
            ? 'A matching component result must not contain differences.'
            : 'A non-matching component result must contain a difference.',
      );
    }
    return _MatchComponentResult(
      matches: matches,
      differences: boundedDifferences,
    );
  }

  /// Whether the component considered the requests equivalent.
  bool get matches;

  /// Safe bounded differences and their complete count.
  BoundedMatchDifferences get differences;
}

final class _MatchContext implements MatchContext {
  const _MatchContext(this._exclusions);

  final MatchingExclusions _exclusions;

  @override
  Set<String> get excludedHeaders => _exclusions.headers;

  @override
  Set<String> get excludedQueryParameters => _exclusions.queryParameters;

  @override
  Set<String> get excludedJsonPointers => _exclusions.jsonPointers;

  @override
  bool get uriUserInformationExcluded => _exclusions.uriUserInformation;

  @override
  bool get bodyExcluded => _exclusions.body;
}

final class _MatchComponentResult implements MatchComponentResult {
  const _MatchComponentResult({
    required this.matches,
    required this.differences,
  });

  @override
  final bool matches;

  @override
  final BoundedMatchDifferences differences;
}

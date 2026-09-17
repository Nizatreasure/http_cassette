import '../configuration/matching_configuration.dart';
import '../model/http_message.dart';
import 'body.dart';
import 'custom.dart';
import 'difference.dart';
import 'exclusions.dart';
import 'headers.dart';
import 'json.dart';
import 'normalisation.dart';
import 'query.dart';

/// A built-in component in deterministic comparison order.
enum RequestMatchComponent {
  method,
  origin,
  path,
  query,
  selectedHeaders,
  body
}

/// The comparison state of one built-in matcher component.
enum RequestMatchComponentState {
  matched,
  different,
  excluded,
  unavailable,
  notConfigured
}

/// An immutable, value-free result for one matcher component.
final class RequestMatchComponentResult {
  const RequestMatchComponentResult({
    required this.component,
    required this.state,
    required this.matches,
    required this.differences,
  });

  /// The component that was compared.
  final RequestMatchComponent component;

  /// The component's diagnostic state.
  final RequestMatchComponentState state;

  /// Whether this component permits the request to match.
  ///
  /// An unavailable semantic body comparison may still match through exact
  /// byte fallback.
  final bool matches;

  /// Safe bounded differences and the complete count used for ranking.
  final BoundedMatchDifferences differences;
}

/// One evaluated custom component in registration order.
final class CustomComponentMatchResult {
  const CustomComponentMatchResult({
    required this.name,
    required this.result,
  });

  /// The component's validated registration name.
  final String name;

  /// The safe result returned by the component.
  final MatchComponentResult result;
}

/// The comparison strategy used for the request body.
enum RequestBodyComparisonKind {
  notConfigured,
  valueExcluded,
  structuralJson,
  exactBytes,
  exactBytesJsonUnavailable,
}

/// Safe comparison details for the request body component.
final class RequestBodyMatchResult {
  const RequestBodyMatchResult._({
    required this.kind,
    required this.matches,
    this.exactComparison,
    this.expectedJsonStatus,
    this.actualJsonStatus,
    required this.differences,
  });

  /// The comparison strategy selected from the two canonical requests.
  final RequestBodyComparisonKind kind;

  /// Whether the body component matched.
  final bool matches;

  /// Value-free byte facts when exact comparison was used.
  final ExactBodyComparisonResult? exactComparison;

  /// The expected body's JSON classification when parsing was attempted.
  final JsonBodyStatus? expectedJsonStatus;

  /// The actual body's JSON classification when parsing was attempted.
  final JsonBodyStatus? actualJsonStatus;

  /// Safe bounded body differences and their complete count.
  final BoundedMatchDifferences differences;
}

/// The immutable result of comparing one expected and actual request.
final class RequestMatchResult {
  RequestMatchResult._({
    required Iterable<RequestMatchComponentResult> components,
    required Iterable<CustomComponentMatchResult> customComponents,
    required this.body,
  })  : components = List<RequestMatchComponentResult>.unmodifiable(components),
        customComponents =
            List<CustomComponentMatchResult>.unmodifiable(customComponents);

  /// Component results in deterministic matcher order.
  final List<RequestMatchComponentResult> components;

  /// Custom component results in deterministic registration order.
  final List<CustomComponentMatchResult> customComponents;

  /// Safe details from the body component.
  final RequestBodyMatchResult body;

  /// Whether every configured component matched.
  bool get matches =>
      components.every((component) => component.matches) &&
      customComponents.every((component) => component.result.matches);
}

/// Stateless composition of the built-in V1 request matcher components.
final class DefaultRequestMatcher {
  /// Creates a matcher using [configuration].
  DefaultRequestMatcher({
    MatchingConfiguration? configuration,
    this.maximumDifferencesPerComponent =
        MatchDifferenceCollector.defaultMaximumRetained,
  }) : configuration = configuration ?? MatchingConfiguration.defaults {
    if (maximumDifferencesPerComponent < 0) {
      throw ArgumentError(
        'Maximum differences per component must not be negative.',
      );
    }
  }

  /// Immutable built-in matching configuration.
  final MatchingConfiguration configuration;

  /// Maximum safe difference records retained for each component.
  final int maximumDifferencesPerComponent;

  /// Compares [expected] with [actual] without mutating either request.
  RequestMatchResult compare(
    CassetteRequest expected,
    CassetteRequest actual, {
    MatchingExclusions exclusions = MatchingExclusions.none,
  }) {
    final configuredExclusions = MatchingExclusions(
      queryParameters: configuration.ignoredQueryParameters,
      jsonPointers: configuration.ignoredJsonPointers,
    );
    final effectiveExclusions = exclusions.mergedWith(configuredExclusions);
    final expectedTarget = NormalisedRequestTarget.fromRequest(
      expected,
      exclusions: effectiveExclusions,
    );
    final actualTarget = NormalisedRequestTarget.fromRequest(
      actual,
      exclusions: effectiveExclusions,
    );

    final methodMatches = expectedTarget.method == actualTarget.method;
    final originMatches = expectedTarget.scheme == actualTarget.scheme &&
        expectedTarget.host == actualTarget.host &&
        expectedTarget.port == actualTarget.port &&
        expectedTarget.userInformation == actualTarget.userInformation;
    final pathMatches = expectedTarget.path == actualTarget.path;
    final expectedQuery = NormalisedQuery.fromUri(
      expected.uri,
      exclusions: effectiveExclusions,
    );
    final actualQuery = NormalisedQuery.fromUri(
      actual.uri,
      exclusions: effectiveExclusions,
    );
    final queryDifferences = compareNormalisedQueries(
      expectedQuery,
      actualQuery,
      maximumRetained: maximumDifferencesPerComponent,
    );
    final queryMatches = queryDifferences.isEmpty;

    final hasSelectedHeaders = configuration.includedHeaders.isNotEmpty;
    final expectedHeaders = NormalisedSelectedHeaders.fromHeaders(
      expected.headers,
      selectedNames: configuration.includedHeaders,
      exclusions: effectiveExclusions,
    );
    final actualHeaders = NormalisedSelectedHeaders.fromHeaders(
      actual.headers,
      selectedNames: configuration.includedHeaders,
      exclusions: effectiveExclusions,
    );
    final headerDifferences = compareSelectedHeaders(
      expectedHeaders,
      actualHeaders,
      maximumRetained: maximumDifferencesPerComponent,
    );
    final headersMatch = !hasSelectedHeaders || headerDifferences.isEmpty;
    final body = _compareRequestBodies(
      expected,
      actual,
      effectiveExclusions,
      maximumDifferencesPerComponent,
    );
    final customContext = MatchContext(
      excludedHeaders: effectiveExclusions.headers,
      excludedQueryParameters: effectiveExclusions.queryParameters,
      excludedJsonPointers: effectiveExclusions.jsonPointers,
      uriUserInformationExcluded: effectiveExclusions.uriUserInformation,
      bodyExcluded: effectiveExclusions.body,
    );
    final customComponents = <CustomComponentMatchResult>[];
    for (final component in configuration.customComponents) {
      customComponents.add(
        CustomComponentMatchResult(
          name: component.name,
          result: component.compare(expected, actual, customContext),
        ),
      );
    }

    return RequestMatchResult._(
      components: <RequestMatchComponentResult>[
        _component(
          RequestMatchComponent.method,
          methodMatches,
          _singleDifference(
            matches: methodMatches,
            kind: MatchDifferenceKind.differentValue,
            location: 'method',
            maximumRetained: maximumDifferencesPerComponent,
          ),
        ),
        _component(
          RequestMatchComponent.origin,
          originMatches,
          _originDifferences(
            expectedTarget,
            actualTarget,
            maximumDifferencesPerComponent,
          ),
        ),
        _component(
          RequestMatchComponent.path,
          pathMatches,
          _singleDifference(
            matches: pathMatches,
            kind: MatchDifferenceKind.differentValue,
            location: 'path',
            maximumRetained: maximumDifferencesPerComponent,
          ),
        ),
        _component(RequestMatchComponent.query, queryMatches, queryDifferences),
        RequestMatchComponentResult(
          component: RequestMatchComponent.selectedHeaders,
          state: hasSelectedHeaders
              ? _state(headersMatch)
              : RequestMatchComponentState.notConfigured,
          matches: headersMatch,
          differences: headerDifferences,
        ),
        RequestMatchComponentResult(
          component: RequestMatchComponent.body,
          state: switch (body.kind) {
            RequestBodyComparisonKind.notConfigured =>
              RequestMatchComponentState.notConfigured,
            RequestBodyComparisonKind.valueExcluded when body.matches =>
              RequestMatchComponentState.excluded,
            RequestBodyComparisonKind.exactBytesJsonUnavailable =>
              RequestMatchComponentState.unavailable,
            _ => _state(body.matches),
          },
          matches: body.matches,
          differences: body.differences,
        ),
      ],
      customComponents: customComponents,
      body: body,
    );
  }
}

RequestMatchComponentResult _component(
  RequestMatchComponent component,
  bool matches,
  BoundedMatchDifferences differences,
) =>
    RequestMatchComponentResult(
      component: component,
      state: _state(matches),
      matches: matches,
      differences: differences,
    );

RequestMatchComponentState _state(bool matches) => matches
    ? RequestMatchComponentState.matched
    : RequestMatchComponentState.different;

RequestBodyMatchResult _compareRequestBodies(
  CassetteRequest expected,
  CassetteRequest actual,
  MatchingExclusions exclusions,
  int maximumRetained,
) {
  if (expected.body.isEmpty && actual.body.isEmpty) {
    return RequestBodyMatchResult._(
      kind: RequestBodyComparisonKind.notConfigured,
      matches: true,
      differences: _emptyDifferences(),
    );
  }

  if (exclusions.body) {
    final presenceMatches = expected.body.isEmpty == actual.body.isEmpty;
    return RequestBodyMatchResult._(
      kind: RequestBodyComparisonKind.valueExcluded,
      matches: presenceMatches,
      differences: _singleDifference(
        matches: presenceMatches,
        kind: MatchDifferenceKind.differentMultiplicity,
        location: 'body',
        maximumRetained: maximumRetained,
      ),
    );
  }

  if (!_hasContentEncoding(expected) && !_hasContentEncoding(actual)) {
    final expectedJson = parseJsonBody(expected.headers, expected.body);
    final actualJson = parseJsonBody(actual.headers, actual.body);
    if (expectedJson.status == JsonBodyStatus.valid &&
        actualJson.status == JsonBodyStatus.valid) {
      final comparison = compareJsonValues(
        expectedJson.value,
        actualJson.value,
        exclusions: exclusions,
        maximumRetained: maximumRetained,
      );
      final differences = MatchDifferenceCollector(
        maximumRetained: maximumRetained,
      );
      for (final difference in comparison.differences) {
        differences.add(
          MatchDifference(
            kind: _jsonDifferenceKind(difference.kind),
            location: difference.pointer,
          ),
        );
      }
      differences.addOmitted(comparison.omittedCount);
      return RequestBodyMatchResult._(
        kind: RequestBodyComparisonKind.structuralJson,
        matches: comparison.matches,
        expectedJsonStatus: expectedJson.status,
        actualJsonStatus: actualJson.status,
        differences: differences.build(),
      );
    }

    final unavailable = _isInvalidJson(expectedJson.status) ||
        _isInvalidJson(actualJson.status);
    final exact = compareExactBodies(expected.body, actual.body);
    final differences = MatchDifferenceCollector(
      maximumRetained: maximumRetained,
    );
    if (unavailable) {
      differences.add(
        MatchDifference(kind: MatchDifferenceKind.unavailableComparison),
      );
    }
    if (!exact.matches) {
      differences.add(
        MatchDifference(
          kind: expected.body.length == actual.body.length
              ? MatchDifferenceKind.differentValue
              : MatchDifferenceKind.differentMultiplicity,
          location: 'body',
        ),
      );
    }
    return RequestBodyMatchResult._(
      kind: unavailable
          ? RequestBodyComparisonKind.exactBytesJsonUnavailable
          : RequestBodyComparisonKind.exactBytes,
      matches: exact.matches,
      exactComparison: exact,
      expectedJsonStatus: expectedJson.status,
      actualJsonStatus: actualJson.status,
      differences: differences.build(),
    );
  }

  final exact = compareExactBodies(expected.body, actual.body);
  final differences = _singleDifference(
    matches: exact.matches,
    kind: expected.body.length == actual.body.length
        ? MatchDifferenceKind.differentValue
        : MatchDifferenceKind.differentMultiplicity,
    location: 'body',
    maximumRetained: maximumRetained,
  );
  return RequestBodyMatchResult._(
    kind: RequestBodyComparisonKind.exactBytes,
    matches: exact.matches,
    exactComparison: exact,
    differences: differences,
  );
}

BoundedMatchDifferences _originDifferences(
  NormalisedRequestTarget expected,
  NormalisedRequestTarget actual,
  int maximumRetained,
) {
  final collector = MatchDifferenceCollector(maximumRetained: maximumRetained);
  if (expected.scheme != actual.scheme) {
    collector.add(
      MatchDifference(
        kind: MatchDifferenceKind.differentValue,
        location: 'scheme',
      ),
    );
  }
  if (expected.host != actual.host) {
    collector.add(
      MatchDifference(
        kind: MatchDifferenceKind.differentValue,
        location: 'host',
      ),
    );
  }
  if (expected.port != actual.port) {
    collector.add(
      MatchDifference(
        kind: MatchDifferenceKind.differentValue,
        location: 'port',
      ),
    );
  }
  if (expected.userInformation != actual.userInformation) {
    collector.add(
      MatchDifference(
        kind: MatchDifferenceKind.differentValue,
        location: 'user-information',
      ),
    );
  }
  return collector.build();
}

BoundedMatchDifferences _singleDifference({
  required bool matches,
  required MatchDifferenceKind kind,
  required String location,
  required int maximumRetained,
}) {
  final collector = MatchDifferenceCollector(maximumRetained: maximumRetained);
  if (!matches) {
    collector.add(MatchDifference(kind: kind, location: location));
  }
  return collector.build();
}

BoundedMatchDifferences _emptyDifferences() =>
    MatchDifferenceCollector(maximumRetained: 0).build();

MatchDifferenceKind _jsonDifferenceKind(JsonDifferenceKind kind) =>
    switch (kind) {
      JsonDifferenceKind.missing => MatchDifferenceKind.missing,
      JsonDifferenceKind.extra => MatchDifferenceKind.extra,
      JsonDifferenceKind.differentType => MatchDifferenceKind.differentType,
      JsonDifferenceKind.differentValue => MatchDifferenceKind.differentValue,
      JsonDifferenceKind.differentOrder => MatchDifferenceKind.differentOrder,
      JsonDifferenceKind.differentLength =>
        MatchDifferenceKind.differentMultiplicity,
    };

bool _hasContentEncoding(CassetteRequest request) =>
    request.headers.values('content-encoding') != null;

bool _isInvalidJson(JsonBodyStatus status) => switch (status) {
      JsonBodyStatus.invalidUtf8 ||
      JsonBodyStatus.malformedJson ||
      JsonBodyStatus.duplicateObjectMember =>
        true,
      JsonBodyStatus.notJsonMediaType || JsonBodyStatus.valid => false,
    };

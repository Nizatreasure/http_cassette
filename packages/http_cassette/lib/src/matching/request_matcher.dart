import '../configuration/matching_configuration.dart';
import '../model/http_message.dart';
import 'body.dart';
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
  unavailable,
  notConfigured
}

/// An immutable, value-free result for one matcher component.
final class RequestMatchComponentResult {
  const RequestMatchComponentResult({
    required this.component,
    required this.state,
    required this.matches,
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
}

/// The comparison strategy used for the request body.
enum RequestBodyComparisonKind {
  notConfigured,
  structuralJson,
  exactBytes,
  exactBytesJsonUnavailable,
}

/// Safe comparison details for the request body component.
final class RequestBodyMatchResult {
  const RequestBodyMatchResult._({
    required this.kind,
    required this.matches,
    this.jsonComparison,
    this.exactComparison,
    this.expectedJsonStatus,
    this.actualJsonStatus,
  });

  /// The comparison strategy selected from the two canonical requests.
  final RequestBodyComparisonKind kind;

  /// Whether the body component matched.
  final bool matches;

  /// Structural differences when [kind] is structural JSON.
  final JsonComparisonResult? jsonComparison;

  /// Value-free byte facts when exact comparison was used.
  final ExactBodyComparisonResult? exactComparison;

  /// The expected body's JSON classification when parsing was attempted.
  final JsonBodyStatus? expectedJsonStatus;

  /// The actual body's JSON classification when parsing was attempted.
  final JsonBodyStatus? actualJsonStatus;
}

/// The immutable result of comparing one expected and actual request.
final class RequestMatchResult {
  RequestMatchResult._({
    required Iterable<RequestMatchComponentResult> components,
    required this.body,
  }) : components = List<RequestMatchComponentResult>.unmodifiable(components);

  /// Component results in deterministic matcher order.
  final List<RequestMatchComponentResult> components;

  /// Safe details from the body component.
  final RequestBodyMatchResult body;

  /// Whether every configured component matched.
  bool get matches => components.every((component) => component.matches);
}

/// Stateless composition of the built-in V1 request matcher components.
final class DefaultRequestMatcher {
  /// Creates a matcher using [configuration].
  DefaultRequestMatcher({
    MatchingConfiguration? configuration,
  }) : configuration = configuration ?? MatchingConfiguration.defaults;

  /// Immutable built-in matching configuration.
  final MatchingConfiguration configuration;

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
    final queryMatches = NormalisedQuery.fromUri(
          expected.uri,
          exclusions: effectiveExclusions,
        ) ==
        NormalisedQuery.fromUri(
          actual.uri,
          exclusions: effectiveExclusions,
        );

    final hasSelectedHeaders = configuration.includedHeaders.isNotEmpty;
    final headersMatch = !hasSelectedHeaders ||
        NormalisedSelectedHeaders.fromHeaders(
              expected.headers,
              selectedNames: configuration.includedHeaders,
              exclusions: effectiveExclusions,
            ) ==
            NormalisedSelectedHeaders.fromHeaders(
              actual.headers,
              selectedNames: configuration.includedHeaders,
              exclusions: effectiveExclusions,
            );
    final body = _compareRequestBodies(
      expected,
      actual,
      effectiveExclusions,
    );

    return RequestMatchResult._(
      components: <RequestMatchComponentResult>[
        _component(RequestMatchComponent.method, methodMatches),
        _component(RequestMatchComponent.origin, originMatches),
        _component(RequestMatchComponent.path, pathMatches),
        _component(RequestMatchComponent.query, queryMatches),
        RequestMatchComponentResult(
          component: RequestMatchComponent.selectedHeaders,
          state: hasSelectedHeaders
              ? _state(headersMatch)
              : RequestMatchComponentState.notConfigured,
          matches: headersMatch,
        ),
        RequestMatchComponentResult(
          component: RequestMatchComponent.body,
          state: switch (body.kind) {
            RequestBodyComparisonKind.notConfigured =>
              RequestMatchComponentState.notConfigured,
            RequestBodyComparisonKind.exactBytesJsonUnavailable =>
              RequestMatchComponentState.unavailable,
            _ => _state(body.matches),
          },
          matches: body.matches,
        ),
      ],
      body: body,
    );
  }
}

RequestMatchComponentResult _component(
  RequestMatchComponent component,
  bool matches,
) =>
    RequestMatchComponentResult(
      component: component,
      state: _state(matches),
      matches: matches,
    );

RequestMatchComponentState _state(bool matches) => matches
    ? RequestMatchComponentState.matched
    : RequestMatchComponentState.different;

RequestBodyMatchResult _compareRequestBodies(
  CassetteRequest expected,
  CassetteRequest actual,
  MatchingExclusions exclusions,
) {
  if (expected.body.isEmpty && actual.body.isEmpty) {
    return const RequestBodyMatchResult._(
      kind: RequestBodyComparisonKind.notConfigured,
      matches: true,
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
      );
      return RequestBodyMatchResult._(
        kind: RequestBodyComparisonKind.structuralJson,
        matches: comparison.matches,
        jsonComparison: comparison,
        expectedJsonStatus: expectedJson.status,
        actualJsonStatus: actualJson.status,
      );
    }

    final unavailable = _isInvalidJson(expectedJson.status) ||
        _isInvalidJson(actualJson.status);
    final exact = compareExactBodies(expected.body, actual.body);
    return RequestBodyMatchResult._(
      kind: unavailable
          ? RequestBodyComparisonKind.exactBytesJsonUnavailable
          : RequestBodyComparisonKind.exactBytes,
      matches: exact.matches,
      exactComparison: exact,
      expectedJsonStatus: expectedJson.status,
      actualJsonStatus: actualJson.status,
    );
  }

  final exact = compareExactBodies(expected.body, actual.body);
  return RequestBodyMatchResult._(
    kind: RequestBodyComparisonKind.exactBytes,
    matches: exact.matches,
    exactComparison: exact,
  );
}

bool _hasContentEncoding(CassetteRequest request) =>
    request.headers.values('content-encoding') != null;

bool _isInvalidJson(JsonBodyStatus status) => switch (status) {
      JsonBodyStatus.invalidUtf8 ||
      JsonBodyStatus.malformedJson ||
      JsonBodyStatus.duplicateObjectMember =>
        true,
      JsonBodyStatus.notJsonMediaType || JsonBodyStatus.valid => false,
    };

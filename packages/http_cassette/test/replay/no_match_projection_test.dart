import 'package:http_cassette/src/configuration/matching_configuration.dart';
import 'package:http_cassette/src/matching/custom.dart';
import 'package:http_cassette/src/matching/difference.dart';
import 'package:http_cassette/src/matching/request_matcher.dart';
import 'package:http_cassette/src/model/headers.dart';
import 'package:http_cassette/src/model/http_message.dart';
import 'package:http_cassette/src/replay/no_match_projection.dart';
import 'package:test/test.dart';

void main() {
  test('suppresses locations and custom names while preserving safe facts', () {
    final projection = _projection();

    expect(
      projection.builtInComponents.map((fact) => fact.component),
      RequestMatchComponent.values,
    );
    final path = projection.builtInComponents[RequestMatchComponent.path.index];
    expect(path.matches, isFalse);
    expect(path.differences.totalCount, 1);
    expect(path.differences.differences.single.locationSuppressed, isTrue);
    expect(projection.customComponents, hasLength(1));
    expect(projection.customComponents.single.registrationIndex, 0);
    expect(
      projection.customComponents.single.differences.differences.single.kind,
      MatchDifferenceKind.customComponentDifference,
    );
    expect(
      projection.customComponents.single.differences.differences.single
          .locationSuppressed,
      isTrue,
    );
    expect(projection.toString(), isNot(contains('private')));
  });

  test('copies value-free exact body facts without retaining bytes', () {
    final body = _projection().body;

    expect(body.kind, RequestBodyComparisonKind.exactBytes);
    expect(body.expectedLength, 3);
    expect(body.actualLength, 2);
    expect(body.firstDifferenceOffset, 1);
  });

  test('is deeply immutable with structural equality', () {
    final first = _projection();
    final second = _projection();

    expect(first, second);
    expect(first.hashCode, second.hashCode);
    expect(
      () => first.builtInComponents.add(first.builtInComponents.first),
      throwsUnsupportedError,
    );
    expect(
      () => first.customComponents.add(first.customComponents.first),
      throwsUnsupportedError,
    );
    expect(
      first.builtInComponents.first.differences.differences.clear,
      throwsUnsupportedError,
    );
  });

  test('rejects a matching comparison', () {
    final request = CassetteRequest(
      method: 'GET',
      uri: Uri.parse('https://example.test/items'),
    );

    expect(
      () => ReplayNoMatchComparisonProjection.fromComparison(
        DefaultRequestMatcher().compare(request, request),
      ),
      throwsArgumentError,
    );
  });
}

ReplayNoMatchComparisonProjection _projection() {
  final matcher = DefaultRequestMatcher(
    configuration: MatchingConfiguration(
      includedHeaders: const <String>['x-private-header'],
      customComponents: const <RequestMatcherComponent>[
        _PrivateComponent(),
      ],
    ),
  );
  final comparison = matcher.compare(
    CassetteRequest(
      method: 'POST',
      uri: Uri.parse('https://example.test/private-path?private-query=one'),
      headers: CassetteHeaders(
        const <String, Iterable<String>>{
          'x-private-header': <String>['one'],
        },
      ),
      body: const <int>[1, 2, 3],
    ),
    CassetteRequest(
      method: 'GET',
      uri: Uri.parse('https://example.test/other?private-query=two'),
      headers: CassetteHeaders(
        const <String, Iterable<String>>{
          'x-private-header': <String>['two'],
        },
      ),
      body: const <int>[1, 4],
    ),
  );
  return ReplayNoMatchComparisonProjection.fromComparison(comparison);
}

final class _PrivateComponent implements RequestMatcherComponent {
  const _PrivateComponent();

  @override
  String get name => 'private-component-name';

  @override
  MatchComponentResult compare(
    CassetteRequest expected,
    CassetteRequest actual,
    MatchContext context,
  ) =>
      MatchComponentResult(
        matches: false,
        differences: <MatchDifference>[
          MatchDifference(
            kind: MatchDifferenceKind.customComponentDifference,
            location: 'private-custom-location',
          ),
        ],
      );
}

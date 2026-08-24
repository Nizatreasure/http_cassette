import 'package:http_cassette/src/cassette/name.dart';
import 'package:http_cassette/src/configuration/matching_configuration.dart';
import 'package:http_cassette/src/diagnostics/diagnostic.dart';
import 'package:http_cassette/src/matching/custom.dart';
import 'package:http_cassette/src/matching/difference.dart';
import 'package:http_cassette/src/matching/ranking.dart';
import 'package:http_cassette/src/matching/request_matcher.dart';
import 'package:http_cassette/src/model/http_message.dart';
import 'package:http_cassette/src/replay/configuration.dart';
import 'package:http_cassette/src/replay/diagnostic_context.dart';
import 'package:http_cassette/src/replay/matcher_description.dart';
import 'package:http_cassette/src/replay/no_match.dart';
import 'package:http_cassette/src/replay/no_match_diagnostic.dart';
import 'package:test/test.dart';

void main() {
  test('assembles complete fixed no-match semantics', () {
    final diagnostic = _diagnostic();

    expect(
      diagnostic.envelope.category,
      DiagnosticCategory.noMatchingInteraction,
    );
    expect(
      diagnostic.envelope.summary,
      'No recorded interaction matched the request.',
    );
    expect(diagnostic.envelope.networkAccess, NetworkAccess.disabled);
    expect(diagnostic.context.cassetteName.value, 'checkout/declined');
    expect(diagnostic.context.request.method, 'GET');
    expect(diagnostic.replayPolicy, ReplayPolicy.strict);
    expect(diagnostic.matcher.customComponentCount, 1);
    expect(diagnostic.consideredInteractionCount, 1);
    expect(diagnostic.closestRecordedIndex, 3);
    expect(diagnostic.closestComparison, isNotNull);
    expect(
      diagnostic.closestComparison!.customComponents.single.registrationIndex,
      0,
    );
  });

  test('assembles an empty-cassette failure without a closest candidate', () {
    final request = _request('/incoming');
    final diagnostic = ReplayNoMatchDiagnostic(
      context: _context(request),
      replayPolicy: ReplayPolicy.strict,
      matcher: ReplayMatcherDescription.fromConfiguration(
        MatchingConfiguration.defaults,
      ),
      details: ReplayNoMatchDetails.fromRanking(
        rankRequestMatchCandidates(const <RequestMatchCandidate>[]),
      ),
    );

    expect(diagnostic.consideredInteractionCount, 0);
    expect(diagnostic.closestRecordedIndex, isNull);
    expect(diagnostic.closestComparison, isNull);
  });

  test('rejects a matcher description inconsistent with the comparison', () {
    final configuration = MatchingConfiguration(
      customComponents: const <RequestMatcherComponent>[_PrivateComponent()],
    );
    final request = _request('/incoming');
    final comparison = DefaultRequestMatcher(
      configuration: configuration,
    ).compare(_request('/recorded'), request);

    expect(
      () => ReplayNoMatchDiagnostic(
        context: _context(request),
        replayPolicy: ReplayPolicy.strict,
        matcher: ReplayMatcherDescription.fromConfiguration(
          MatchingConfiguration.defaults,
        ),
        details: ReplayNoMatchDetails.fromRanking(
          rankRequestMatchCandidates(<RequestMatchCandidate>[
            RequestMatchCandidate(
              recordedIndex: 0,
              comparison: comparison,
            ),
          ]),
        ),
      ),
      throwsArgumentError,
    );
  });

  test('retains no original comparison or confidential locations', () {
    final diagnostic = _diagnostic();

    expect(diagnostic.toString(), isNot(contains('private')));
    final custom = diagnostic.closestComparison!.customComponents.single;
    expect(custom.differences.differences.single.locationSuppressed, isTrue);
  });

  test('has structural equality and matching hash codes', () {
    expect(_diagnostic(), _diagnostic());
    expect(_diagnostic().hashCode, _diagnostic().hashCode);
  });
}

ReplayNoMatchDiagnostic _diagnostic() {
  final configuration = MatchingConfiguration(
    customComponents: const <RequestMatcherComponent>[_PrivateComponent()],
  );
  final incoming = _request('/incoming');
  final comparison = DefaultRequestMatcher(
    configuration: configuration,
  ).compare(_request('/recorded'), incoming);
  final details = ReplayNoMatchDetails.fromRanking(
    rankRequestMatchCandidates(<RequestMatchCandidate>[
      RequestMatchCandidate(recordedIndex: 3, comparison: comparison),
    ]),
  );
  return ReplayNoMatchDiagnostic(
    context: _context(incoming),
    replayPolicy: ReplayPolicy.strict,
    matcher: ReplayMatcherDescription.fromConfiguration(configuration),
    details: details,
  );
}

ReplayDiagnosticContext _context(CassetteRequest request) =>
    ReplayDiagnosticContext(
      cassetteName: CassetteName('checkout/declined'),
      request: ReplayRequestSummary.fromRequest(
        request: request,
        arrivalIndex: 5,
      ),
    );

CassetteRequest _request(String path) => CassetteRequest(
      method: 'GET',
      uri: Uri(scheme: 'https', host: 'example.test', path: path),
    );

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

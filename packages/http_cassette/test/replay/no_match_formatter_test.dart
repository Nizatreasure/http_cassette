import 'package:http_cassette/src/cassette/name.dart';
import 'package:http_cassette/src/configuration/matching_configuration.dart';
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
import 'package:http_cassette/src/replay/no_match_formatter.dart';
import 'package:test/test.dart';

void main() {
  test('renders complete no-match information in stable order', () {
    final diagnostic = _diagnostic();

    expect(
      diagnostic.format(),
      '''HTTP Cassette failure: No recorded interaction matched the request.
Category: noMatchingInteraction
Cassette: checkout/declined
Request: method=GET; arrival=5; body=3 bytes
Interactions considered: 1
Closest interaction: #2
Built-in components:
  method: matched
  origin: matched
  path: different; differences=differentValue (location suppressed)
  query: matched
  selectedHeaders: notConfigured
  body: different; differences=differentMultiplicity (location suppressed)
Body comparison: strategy=exactBytes; expected bytes=2; actual bytes=3; first difference=1; expected JSON=notJsonMediaType; actual JSON=notJsonMediaType
Matcher: method + URI + non-empty body; selected headers=0; ignored query parameters=0; ignored JSON locations=0; custom components=0
Replay policy: strict
Network access: disabled; no real request was made''',
    );
    expect(diagnostic.format(), diagnostic.format());
    expect(diagnostic.format(), isNot(endsWith('\n')));
  });

  test('renders an empty cassette without a closest candidate', () {
    final request = _request('/incoming', const <int>[]);
    final diagnostic = ReplayNoMatchDiagnostic(
      context: _context(request),
      replayPolicy: ReplayPolicy.first,
      matcher: ReplayMatcherDescription.fromConfiguration(
        MatchingConfiguration.defaults,
      ),
      details: ReplayNoMatchDetails.fromRanking(
        rankRequestMatchCandidates(const <RequestMatchCandidate>[]),
      ),
    );
    final text = diagnostic.format();

    expect(
      text,
      contains('Closest interaction: none; cassette contains no interactions'),
    );
    expect(text, isNot(contains('Built-in components:')));
  });

  test('bounds custom components and per-component differences', () {
    final components = List<RequestMatcherComponent>.generate(
      10,
      (index) => _ManyDifferencesComponent(index),
    );
    final configuration = MatchingConfiguration(customComponents: components);
    final incoming = _request('/incoming', const <int>[]);
    final comparison = DefaultRequestMatcher(
      configuration: configuration,
    ).compare(_request('/recorded', const <int>[]), incoming);
    final diagnostic = ReplayNoMatchDiagnostic(
      context: _context(incoming),
      replayPolicy: ReplayPolicy.strict,
      matcher: ReplayMatcherDescription.fromConfiguration(configuration),
      details: ReplayNoMatchDetails.fromRanking(
        rankRequestMatchCandidates(<RequestMatchCandidate>[
          RequestMatchCandidate(recordedIndex: 0, comparison: comparison),
        ]),
      ),
    );
    final text = diagnostic.format();

    expect(text, contains('... (2 custom components omitted)'));
    expect(text, contains('... (2 omitted)'));
    expect(text, contains('[7]: different'));
    expect(text, isNot(contains('[8]:')));
    expect(text, isNot(contains('private-location')));
    expect(text, isNot(contains('private-component')));
  });
}

ReplayNoMatchDiagnostic _diagnostic() {
  final expected = _request('/recorded', const <int>[1, 2]);
  final incoming = _request('/incoming', const <int>[1, 4, 5]);
  final comparison = DefaultRequestMatcher().compare(expected, incoming);
  return ReplayNoMatchDiagnostic(
    context: _context(incoming),
    replayPolicy: ReplayPolicy.strict,
    matcher: ReplayMatcherDescription.fromConfiguration(
      MatchingConfiguration.defaults,
    ),
    details: ReplayNoMatchDetails.fromRanking(
      rankRequestMatchCandidates(<RequestMatchCandidate>[
        RequestMatchCandidate(recordedIndex: 2, comparison: comparison),
      ]),
    ),
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

CassetteRequest _request(String path, List<int> body) => CassetteRequest(
      method: 'GET',
      uri: Uri(scheme: 'https', host: 'example.test', path: path),
      body: body,
    );

final class _ManyDifferencesComponent implements RequestMatcherComponent {
  const _ManyDifferencesComponent(this.index);

  final int index;

  @override
  String get name => 'private-component-$index';

  @override
  MatchComponentResult compare(
    CassetteRequest expected,
    CassetteRequest actual,
    MatchContext context,
  ) =>
      MatchComponentResult(
        matches: false,
        differences: List<MatchDifference>.generate(
          10,
          (differenceIndex) => MatchDifference(
            kind: MatchDifferenceKind.customComponentDifference,
            location: 'private-location-$differenceIndex',
          ),
        ),
      );
}

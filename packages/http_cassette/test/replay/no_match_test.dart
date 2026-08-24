import 'package:http_cassette/src/diagnostics/diagnostic.dart';
import 'package:http_cassette/src/matching/ranking.dart';
import 'package:http_cassette/src/matching/request_matcher.dart';
import 'package:http_cassette/src/model/http_message.dart';
import 'package:http_cassette/src/replay/no_match.dart';
import 'package:test/test.dart';

void main() {
  test('retains the original closest safe comparison without recomputing', () {
    final farther = _candidate(index: 4, method: 'POST');
    final closest = _candidate(index: 2, method: 'GET', path: '/other');
    final details = ReplayNoMatchDetails.fromRanking(
      rankRequestMatchCandidates(<RequestMatchCandidate>[farther, closest]),
    );

    expect(details.consideredInteractionCount, 2);
    expect(details.closestRecordedIndex, 2);
    expect(details.closestComparison, same(closest.comparison));
    expect(details.closestComparison!.matches, isFalse);
    expect(details.networkAccess, NetworkAccess.disabled);
  });

  test('represents an empty cassette without a closest candidate', () {
    final details = ReplayNoMatchDetails.fromRanking(
      rankRequestMatchCandidates(const <RequestMatchCandidate>[]),
    );

    expect(details.consideredInteractionCount, 0);
    expect(details.closestRecordedIndex, isNull);
    expect(details.closestComparison, isNull);
  });

  test('rejects a ranking whose closest candidate matches', () {
    final matching = _candidate(index: 0, method: 'GET');

    expect(
      () => ReplayNoMatchDetails.fromRanking(
        rankRequestMatchCandidates(<RequestMatchCandidate>[matching]),
      ),
      throwsArgumentError,
    );
  });

  test('does not retain compared request values in its object rendering', () {
    final details = ReplayNoMatchDetails.fromRanking(
      rankRequestMatchCandidates(<RequestMatchCandidate>[
        _candidate(index: 0, method: 'GET', path: '/private-value'),
      ]),
    );

    expect(details.toString(), isNot(contains('private-value')));
  });
}

RequestMatchCandidate _candidate({
  required int index,
  required String method,
  String path = '/items',
}) =>
    RequestMatchCandidate(
      recordedIndex: index,
      comparison: DefaultRequestMatcher().compare(
        CassetteRequest(
          method: method,
          uri: Uri(scheme: 'https', host: 'example.test', path: path),
        ),
        CassetteRequest(
          method: 'GET',
          uri: Uri.parse('https://example.test/items'),
        ),
      ),
    );

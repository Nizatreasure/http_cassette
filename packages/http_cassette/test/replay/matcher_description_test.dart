import 'package:http_cassette/src/configuration/matching_configuration.dart';
import 'package:http_cassette/src/matching/custom.dart';
import 'package:http_cassette/src/model/http_message.dart';
import 'package:http_cassette/src/replay/matcher_description.dart';
import 'package:test/test.dart';

void main() {
  test('retains fixed matcher behaviour and configured counts only', () {
    final description = ReplayMatcherDescription.fromConfiguration(
      MatchingConfiguration(
        includedHeaders: const <String>['x-private-header'],
        ignoredQueryParameters: const <String>['private-query-name'],
        ignoredJsonPointers: const <String>['/private/location'],
        customComponents: const <RequestMatcherComponent>[
          _MatcherComponent('private-component-name'),
        ],
      ),
    );

    expect(description.matchesMethod, isTrue);
    expect(description.matchesUri, isTrue);
    expect(description.matchesNonEmptyBody, isTrue);
    expect(description.selectedHeaderCount, 1);
    expect(description.ignoredQueryParameterCount, 1);
    expect(description.ignoredJsonLocationCount, 1);
    expect(description.customComponentCount, 1);
    expect(description.toString(), isNot(contains('private')));
  });

  test('describes the default matcher with zero optional counts', () {
    final description = ReplayMatcherDescription.fromConfiguration(
      MatchingConfiguration.defaults,
    );

    expect(description.selectedHeaderCount, 0);
    expect(description.ignoredQueryParameterCount, 0);
    expect(description.ignoredJsonLocationCount, 0);
    expect(description.customComponentCount, 0);
  });

  test('has structural equality based on value-safe facts', () {
    ReplayMatcherDescription description(String header) =>
        ReplayMatcherDescription.fromConfiguration(
          MatchingConfiguration(includedHeaders: <String>[header]),
        );

    expect(description('x-first'), description('x-second'));
    expect(
      description('x-first').hashCode,
      description('x-second').hashCode,
    );
  });
}

final class _MatcherComponent implements RequestMatcherComponent {
  const _MatcherComponent(this.name);

  @override
  final String name;

  @override
  MatchComponentResult compare(
    CassetteRequest expected,
    CassetteRequest actual,
    MatchContext context,
  ) =>
      MatchComponentResult(matches: true);
}

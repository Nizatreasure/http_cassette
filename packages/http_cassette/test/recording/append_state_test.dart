import 'dart:async';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/cassette.dart';
import 'package:http_cassette/src/cassette/interaction.dart';
import 'package:http_cassette/src/recording/active_state.dart';
import 'package:http_cassette/src/recording/append_preparation.dart';
import 'package:test/test.dart';

void main() {
  group('append recording state', () {
    test('retains the exact prepared snapshot and existing interactions', () {
      final name = CassetteName('recording');
      final existing = <CassetteInteraction>[
        _interaction(0, '/first', MatchingExclusions.none),
        _interaction(
          1,
          '/second',
          MatchingExclusions(queryParameters: const <String>['token']),
        ),
      ];
      final preparation = _preparation(name, existing);

      final state = _state(name, preparation);

      expect(state.appendSnapshot, same(preparation.snapshot));
      expect(
        state.appendSnapshot!.revision,
        same(preparation.snapshot.revision),
      );
      expect(state.interactions[0], same(preparation.cassette.interactions[0]));
      expect(state.interactions[1], same(preparation.cassette.interactions[1]));
      expect(
        state.interactions[1].matchingExclusions.queryParameters,
        <String>{'token'},
      );
    });

    test('continues arrival indices after every existing interaction', () {
      final name = CassetteName('recording');
      final state = _state(
        name,
        _preparation(name, <CassetteInteraction>[
          _interaction(0, '/first', MatchingExclusions.none),
          _interaction(1, '/second', MatchingExclusions.none),
        ]),
      );

      expect(state.assignArrivalIndex(), 2);
      expect(state.assignArrivalIndex(), 3);
    });

    test('finalises existing and new duplicates without reordering', () async {
      final name = CassetteName('recording');
      final request = _request('/duplicate');
      final state = _state(
        name,
        _preparation(name, <CassetteInteraction>[
          CassetteInteraction(
            index: 0,
            request: request,
            outcome: _outcome(200),
          ),
        ]),
      );

      await state.recordRequest(request, () async => _outcome(201));
      final cassette = state.finaliseCassette();

      expect(cassette.interactions.map((value) => value.index), <int>[0, 1]);
      expect(
        cassette.interactions.map(
          (value) =>
              (value.outcome as CassetteResponseOutcome).response.statusCode,
        ),
        <int>[200, 201],
      );
      expect(cassette.interactions[0], same(state.interactions[0]));
    });

    test('orders reverse new completions after existing interactions',
        () async {
      final name = CassetteName('recording');
      final state = _state(
        name,
        _preparation(name, <CassetteInteraction>[
          _interaction(0, '/existing', MatchingExclusions.none),
        ]),
      );
      final firstCompletion = Completer<CassetteOutcome>();
      final secondCompletion = Completer<CassetteOutcome>();
      final first = state.recordRequest(
        _request('/first-new'),
        () => firstCompletion.future,
      );
      final second = state.recordRequest(
        _request('/second-new'),
        () => secondCompletion.future,
      );

      secondCompletion.complete(_outcome(203));
      await second;
      firstCompletion.complete(_outcome(202));
      await first;

      expect(
        state.finaliseCassette().interactions.map((value) => value.index),
        <int>[0, 1, 2],
      );
    });

    test('rejects append preparation with non-append options', () {
      final name = CassetteName('recording');
      final preparation = _preparation(name, const <CassetteInteraction>[]);

      expect(
        () => ActiveRecordingState(
          cassetteName: name,
          configuration: CassetteConfiguration(),
          options: const RecordingOptions(),
          appendPreparation: preparation,
        ),
        throwsArgumentError,
      );
    });

    test('rejects append preparation for another cassette name', () {
      final preparation = _preparation(
        CassetteName('prepared'),
        const <CassetteInteraction>[],
      );

      expect(
        () => _state(CassetteName('requested'), preparation),
        throwsArgumentError,
      );
    });
  });
}

ActiveRecordingState _state(
  CassetteName name,
  AppendCassettePrepared preparation,
) =>
    ActiveRecordingState(
      cassetteName: name,
      configuration: CassetteConfiguration(),
      options: const RecordingOptions(
        existingCassette: ExistingCassette.append,
      ),
      appendPreparation: preparation,
    );

AppendCassettePrepared _preparation(
  CassetteName name,
  List<CassetteInteraction> interactions,
) =>
    AppendCassettePreparationResult.prepared(
      snapshot: CassetteSnapshot(
        name: name,
        bytes: const <int>[],
        revision: CassetteRevision(),
      ),
      cassette: Cassette(interactions: interactions),
    ) as AppendCassettePrepared;

CassetteInteraction _interaction(
  int index,
  String path,
  MatchingExclusions exclusions,
) =>
    CassetteInteraction(
      index: index,
      request: _request(path),
      outcome: _outcome(200 + index),
      matchingExclusions: exclusions,
    );

CassetteRequest _request(String path) => CassetteRequest(
      method: 'GET',
      uri: Uri.parse('https://example.test$path'),
    );

CassetteOutcome _outcome(int statusCode) => CassetteResponseOutcome(
      CassetteResponse(statusCode: statusCode),
    );

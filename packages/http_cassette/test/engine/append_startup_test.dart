import 'dart:async';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/cassette.dart';
import 'package:http_cassette/src/cassette/encoder.dart';
import 'package:http_cassette/src/cassette/interaction.dart';
import 'package:http_cassette/src/configuration/cassette_size_limit.dart';
import 'package:http_cassette/src/engine/cassette_engine.dart';
import 'package:test/test.dart';

void main() {
  group('append recording startup', () {
    test('initialises active state from one validated snapshot', () async {
      final name = CassetteName('recording');
      final snapshot = _snapshot(name, _cassetteWithTwoInteractions());
      final store = _AppendStore(snapshot);
      final state = _state(store);

      final session = await state.startRecording(name, _appendOptions);

      expect(session.mode, CassetteMode.record);
      expect(store.readCalls, 1);
      expect(store.existsCalls, 0);
      expect(state.activeRecording!.appendSnapshot, same(snapshot));
      expect(
        state.activeRecording!.interactions.map((value) => value.index),
        <int>[0, 1],
      );
      expect(state.activeRecording!.assignArrivalIndex(), 2);
    });

    test('delivers a safe missing-target failure and releases ownership',
        () async {
      final name = CassetteName('missing');
      final store = _AppendStore(
        _snapshot(name, Cassette()),
        readFailure: CassetteStoreException.notFound(
          name: name,
          operation: CassetteStoreOperation.read,
        ),
      );
      final state = _state(store);

      await expectLater(
        state.startRecording(name, _appendOptions),
        throwsA(
          isA<CassetteException>().having(
            (exception) => exception.diagnostic.category,
            'category',
            DiagnosticCategory.appendTargetMissing,
          ),
        ),
      );

      expect(state.sessions.isActive, isFalse);
      expect(state.activeRecording, isNull);
    });

    test('retains pending ownership without exposing a session', () async {
      final name = CassetteName('recording');
      final read = Completer<CassetteSnapshot>();
      final store = _DelayedAppendStore(read.future);
      final state = _state(store);

      final start = state.startRecording(name, _appendOptions);

      expect(state.sessions.isActive, isTrue);
      expect(state.sessions.activeSession, isNull);
      expect(state.activeRecording, isNull);
      await expectLater(
        state.startRecording(
            CassetteName('conflict'), const RecordingOptions()),
        throwsA(isA<CassetteException>()),
      );

      read.complete(_snapshot(name, Cassette()));
      final session = await start;
      expect(state.sessions.activeSession, same(session));
    });

    test('releases ownership after an unexpected preparation error', () async {
      final error = StateError('broken append store');
      final state = _state(_ThrowingAppendStore(error));

      await expectLater(
        state.startRecording(CassetteName('recording'), _appendOptions),
        throwsA(same(error)),
      );

      expect(state.sessions.isActive, isFalse);
      expect(state.activeRecording, isNull);
    });
  });
}

const _appendOptions = RecordingOptions(
  existingCassette: ExistingCassette.append,
);

EngineState _state(CassetteStore store) => EngineState(
      store: store,
      configuration: CassetteConfiguration(),
    );

Cassette _cassetteWithTwoInteractions() => Cassette(
      interactions: <CassetteInteraction>[
        _interaction(0, '/first'),
        _interaction(1, '/second'),
      ],
    );

CassetteInteraction _interaction(int index, String path) => CassetteInteraction(
      index: index,
      request: CassetteRequest(
        method: 'GET',
        uri: Uri.parse('https://example.test$path'),
      ),
      outcome: CassetteResponseOutcome(CassetteResponse(statusCode: 200)),
    );

CassetteSnapshot _snapshot(CassetteName name, Cassette cassette) =>
    CassetteSnapshot(
      name: name,
      bytes: encodeCassetteV1(cassette),
      revision: CassetteRevision(),
    );

base class _AppendStore implements CassetteStore {
  _AppendStore(this.snapshot, {this.readFailure});

  final CassetteSnapshot snapshot;
  final CassetteStoreException? readFailure;
  var readCalls = 0;
  var existsCalls = 0;

  @override
  int get maximumBytes => defaultMaximumCassetteBytesV1;

  @override
  Future<CassetteSnapshot> read(CassetteName name) async {
    readCalls++;
    final failure = readFailure;
    if (failure != null) {
      throw failure;
    }
    return snapshot;
  }

  @override
  Future<bool> exists(CassetteName name) async {
    existsCalls++;
    return false;
  }

  @override
  Future<void> create(CassetteName name, List<int> bytes) async {}

  @override
  Future<void> replace(CassetteName name, List<int> bytes) async {}

  @override
  Future<void> replaceIfUnchanged(
    CassetteSnapshot snapshot,
    List<int> bytes,
  ) async {}
}

final class _DelayedAppendStore extends _AppendStore {
  _DelayedAppendStore(this.readResult)
      : super(_snapshot(CassetteName('unused'), Cassette()));

  final Future<CassetteSnapshot> readResult;

  @override
  Future<CassetteSnapshot> read(CassetteName name) {
    readCalls++;
    return readResult;
  }
}

final class _ThrowingAppendStore extends _AppendStore {
  _ThrowingAppendStore(this.error)
      : super(_snapshot(CassetteName('unused'), Cassette()));

  final Object error;

  @override
  Future<CassetteSnapshot> read(CassetteName name) async => throw error;
}

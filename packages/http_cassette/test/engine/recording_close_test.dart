import 'dart:async';
import 'dart:convert';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/cassette.dart';
import 'package:http_cassette/src/cassette/decoder.dart';
import 'package:http_cassette/src/cassette/encoder.dart';
import 'package:http_cassette/src/configuration/cassette_size_limit.dart';
import 'package:http_cassette/src/engine/cassette_engine.dart';
import 'package:test/test.dart';

void main() {
  group('recording session close', () {
    test('commits a complete sanitised create recording', () async {
      final store = MemoryCassetteStore();
      final state = _state(store);
      final name = CassetteName('recording');
      final session = await state.startRecording(
        name,
        const RecordingOptions(),
      );
      await state.executeActiveRecordingRequest(
        CassetteRequest(
          method: 'GET',
          uri: Uri.parse('https://example.test/?token=private'),
        ),
        () async => CassetteResponseOutcome(
          CassetteResponse(
            statusCode: 200,
            headers: CassetteHeaders(<String, List<String>>{
              'content-type': <String>['application/json'],
            }),
            body: utf8.encode('{"token":"private-response"}'),
          ),
        ),
      );

      await session.close();

      final cassette = decodeCassetteV1((await store.read(name)).bytes);
      expect(cassette.interactions, hasLength(1));
      expect(
        cassette.interactions.single.request.uri.queryParameters['token'],
        '[REDACTED]',
      );
      expect(state.activeRecording, isNull);
      expect(state.sessions.isActive, isFalse);
    });

    test('commits an explicit replacement on close', () async {
      final store = MemoryCassetteStore();
      final state = _state(store);
      final name = CassetteName('recording');
      await store.create(name, encodeCassetteV1(Cassette()));
      final session = await state.startRecording(
        name,
        const RecordingOptions(existingCassette: ExistingCassette.replace),
      );
      await state.executeActiveRecordingRequest(
        _request('/replacement'),
        () async => _outcome(204),
      );

      await session.close();

      final cassette = decodeCassetteV1((await store.read(name)).bytes);
      expect(cassette.interactions, hasLength(1));
      expect(cassette.interactions.single.request.uri.path, '/replacement');
    });

    test('discard performs no create write', () async {
      final store = MemoryCassetteStore();
      final state = _state(store);
      final name = CassetteName('recording');
      final session = await state.startRecording(
        name,
        const RecordingOptions(),
      );
      await state.executeActiveRecordingRequest(
        _request('/discarded'),
        () async => _outcome(200),
      );

      await session.discard();

      expect(await store.exists(name), isFalse);
      expect(state.activeRecording, isNull);
      expect(state.sessions.isActive, isFalse);
    });

    test('seals capture while the create write is pending', () async {
      final store = _DelayedCreateStore();
      final state = _state(store);
      final session = await state.startRecording(
        CassetteName('recording'),
        const RecordingOptions(),
      );
      var attempted = false;

      final close = session.close();
      await store.started.future;

      await expectLater(
        state.executeActiveRecordingRequest(_request('/late'), () async {
          attempted = true;
          return _outcome(200);
        }),
        throwsA(
          isA<CassetteException>().having(
            (exception) => exception.diagnostic.category,
            'category',
            DiagnosticCategory.conflictingSessionOperation,
          ),
        ),
      );
      expect(attempted, isFalse);

      store.release.complete();
      await close;
      expect(state.sessions.isActive, isFalse);
    });

    test('retains sealed state after a commit failure', () async {
      final name = CassetteName('recording');
      final state = _state(_FailingCreateStore(name));
      final session = await state.startRecording(
        name,
        const RecordingOptions(),
      );
      var attempted = false;

      await expectLater(
        session.close(),
        throwsA(
          isA<CassetteException>().having(
            (exception) => exception.diagnostic.category,
            'category',
            DiagnosticCategory.storeWriteFailure,
          ),
        ),
      );

      expect(session.isClosed, isFalse);
      expect(state.sessions.isActive, isTrue);
      expect(state.activeRecording!.isFinalised, isTrue);
      await expectLater(
        state.executeActiveRecordingRequest(_request('/late'), () async {
          attempted = true;
          return _outcome(200);
        }),
        throwsA(isA<CassetteException>()),
      );
      expect(attempted, isFalse);
    });

    test('seals admission when close finds a pending request', () async {
      final store = MemoryCassetteStore();
      final state = _state(store);
      final name = CassetteName('recording');
      final session = await state.startRecording(
        name,
        const RecordingOptions(),
      );
      final pending = Completer<CassetteOutcome>();
      final capture = state.executeActiveRecordingRequest(
        _request('/pending'),
        () => pending.future,
      );
      var lateAttempted = false;

      await expectLater(session.close(), throwsStateError);

      expect(state.activeRecording!.acceptsRequests, isFalse);
      expect(state.activeRecording!.isFinalised, isFalse);
      await expectLater(
        state.executeActiveRecordingRequest(_request('/late'), () async {
          lateAttempted = true;
          return _outcome(200);
        }),
        throwsA(isA<CassetteException>()),
      );
      expect(lateAttempted, isFalse);

      pending.complete(_outcome(200));
      await capture;
      expect(await store.exists(name), isFalse);
    });

    test('leaves append close write-free until append is implemented',
        () async {
      final store = _CountingStore();
      final state = _state(store);
      final session = await state.startRecording(
        CassetteName('recording'),
        const RecordingOptions(existingCassette: ExistingCassette.append),
      );

      await session.close();

      expect(store.writeCalls, 0);
      expect(state.sessions.isActive, isFalse);
    });
  });
}

EngineState _state(CassetteStore store) => EngineState(
      store: store,
      configuration: CassetteConfiguration(),
    );

CassetteRequest _request(String path) => CassetteRequest(
      method: 'GET',
      uri: Uri.parse('https://example.test$path'),
    );

CassetteOutcome _outcome(int statusCode) => CassetteResponseOutcome(
      CassetteResponse(statusCode: statusCode),
    );

base class _CountingStore implements CassetteStore {
  var writeCalls = 0;

  @override
  int get maximumBytes => defaultMaximumCassetteBytesV1;

  @override
  Future<bool> exists(CassetteName name) async => false;

  @override
  Future<void> create(CassetteName name, List<int> bytes) async {
    writeCalls++;
  }

  @override
  Future<void> replace(CassetteName name, List<int> bytes) async {
    writeCalls++;
  }

  @override
  Future<CassetteSnapshot> read(CassetteName name) async => CassetteSnapshot(
        name: name,
        bytes: encodeCassetteV1(Cassette()),
        revision: CassetteRevision(),
      );

  @override
  Future<void> replaceIfUnchanged(
    CassetteSnapshot snapshot,
    List<int> bytes,
  ) =>
      throw UnimplementedError();
}

final class _DelayedCreateStore extends _CountingStore {
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<void> create(CassetteName name, List<int> bytes) async {
    writeCalls++;
    started.complete();
    await release.future;
  }
}

final class _FailingCreateStore extends _CountingStore {
  _FailingCreateStore(this.name);

  final CassetteName name;

  @override
  Future<void> create(CassetteName name, List<int> bytes) async {
    writeCalls++;
    throw CassetteStoreException.operationFailed(
      name: this.name,
      operation: CassetteStoreOperation.create,
    );
  }
}

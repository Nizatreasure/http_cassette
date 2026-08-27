import 'dart:convert';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/cassette/decoder.dart';
import 'package:http_cassette/src/configuration/cassette_size_limit.dart';
import 'package:http_cassette/src/recording/active_state.dart';
import 'package:http_cassette/src/recording/cassette_committer.dart';
import 'package:test/test.dart';

void main() {
  group('RecordingCassetteCommitter', () {
    test('creates a complete deterministically encoded cassette', () async {
      final store = _CommitStore();
      final state = _state();
      await state.recordRequest(
        CassetteRequest(
          method: 'POST',
          uri: Uri.parse('https://example.test/?token=private'),
        ),
        () async => _outcome(201),
      );

      await RecordingCassetteCommitter(store).commit(state);

      expect(store.operation, CassetteStoreOperation.create);
      expect(store.name, state.cassetteName);
      final bytes = store.bytes!;
      expect(utf8.decode(bytes), isNot(contains('private')));
      final cassette = decodeCassetteV1(bytes);
      expect(cassette.interactions, hasLength(1));
      expect(cassette.interactions.single.index, 0);
    });

    test('replaces through the authoritative replace operation', () async {
      final store = _CommitStore();
      final state = _state(existingCassette: ExistingCassette.replace);

      await RecordingCassetteCommitter(store).commit(state);

      expect(store.operation, CassetteStoreOperation.replace);
      expect(decodeCassetteV1(store.bytes!).interactions, isEmpty);
    });

    test('finalises before invoking the store', () async {
      final store = _CommitStore();
      final state = _state();
      state.beginRequest(_request('/pending'));

      await expectLater(
        RecordingCassetteCommitter(store).commit(state),
        throwsStateError,
      );

      expect(store.operation, isNull);
      expect(store.bytes, isNull);
    });

    test('rejects append without invoking the store', () async {
      final store = _CommitStore();
      final state = _state(existingCassette: ExistingCassette.append);

      await expectLater(
        RecordingCassetteCommitter(store).commit(state),
        throwsStateError,
      );

      expect(store.operation, isNull);
    });

    test('maps an authoritative create race safely', () async {
      final name = CassetteName('recording');
      final store = _CommitStore(
        failure: CassetteStoreException.alreadyExists(name),
      );

      await expectLater(
        RecordingCassetteCommitter(store).commit(_state(name: name)),
        throwsA(
          isA<CassetteException>()
              .having(
                (exception) => exception.diagnostic.category,
                'category',
                DiagnosticCategory.targetCassetteExists,
              )
              .having(
                (exception) => exception.diagnostic.networkAccess,
                'network access',
                NetworkAccess.notAttempted,
              ),
        ),
      );
    });

    test('maps an authoritative replacement race safely', () async {
      final name = CassetteName('recording');
      final store = _CommitStore(
        failure: CassetteStoreException.notFound(
          name: name,
          operation: CassetteStoreOperation.replace,
        ),
      );

      await expectLater(
        RecordingCassetteCommitter(store).commit(
          _state(name: name, existingCassette: ExistingCassette.replace),
        ),
        throwsA(
          isA<CassetteException>().having(
            (exception) => exception.diagnostic.category,
            'category',
            DiagnosticCategory.cassetteMissing,
          ),
        ),
      );
    });

    test('maps an atomic replacement failure safely', () async {
      final name = CassetteName('recording');
      final store = _CommitStore(
        failure: CassetteStoreException.operationFailed(
          name: name,
          operation: CassetteStoreOperation.replace,
        ),
      );

      await expectLater(
        RecordingCassetteCommitter(store).commit(
          _state(name: name, existingCassette: ExistingCassette.replace),
        ),
        throwsA(
          isA<CassetteException>()
              .having(
                (exception) => exception.diagnostic.category,
                'category',
                DiagnosticCategory.atomicReplacementFailure,
              )
              .having(
                (exception) => exception.diagnostic.networkAccess,
                'network access',
                NetworkAccess.notAttempted,
              ),
        ),
      );
    });

    test('reports an attempted network after captured traffic', () async {
      final name = CassetteName('recording');
      final store = _CommitStore(
        failure: CassetteStoreException.operationFailed(
          name: name,
          operation: CassetteStoreOperation.create,
        ),
      );
      final state = _state(name: name);
      await state.recordRequest(_request('/items'), () async => _outcome(200));

      await expectLater(
        RecordingCassetteCommitter(store).commit(state),
        throwsA(
          isA<CassetteException>()
              .having(
                (exception) => exception.diagnostic.category,
                'category',
                DiagnosticCategory.storeWriteFailure,
              )
              .having(
                (exception) => exception.diagnostic.networkAccess,
                'network access',
                NetworkAccess.attempted,
              ),
        ),
      );
    });
  });
}

ActiveRecordingState _state({
  CassetteName? name,
  ExistingCassette existingCassette = ExistingCassette.fail,
}) =>
    ActiveRecordingState(
      cassetteName: name ?? CassetteName('recording'),
      configuration: CassetteConfiguration(),
      options: RecordingOptions(existingCassette: existingCassette),
    );

CassetteRequest _request(String path) => CassetteRequest(
      method: 'GET',
      uri: Uri.parse('https://example.test$path'),
    );

CassetteOutcome _outcome(int statusCode) => CassetteResponseOutcome(
      CassetteResponse(statusCode: statusCode),
    );

final class _CommitStore implements CassetteStore {
  _CommitStore({this.failure});

  final CassetteStoreException? failure;
  CassetteStoreOperation? operation;
  CassetteName? name;
  List<int>? bytes;

  @override
  int get maximumBytes => defaultMaximumCassetteBytesV1;

  @override
  Future<void> create(CassetteName name, List<int> bytes) =>
      _write(CassetteStoreOperation.create, name, bytes);

  @override
  Future<void> replace(CassetteName name, List<int> bytes) =>
      _write(CassetteStoreOperation.replace, name, bytes);

  Future<void> _write(
    CassetteStoreOperation operation,
    CassetteName name,
    List<int> bytes,
  ) async {
    this.operation = operation;
    this.name = name;
    this.bytes = List<int>.unmodifiable(bytes);
    if (failure case final failure?) {
      throw failure;
    }
  }

  @override
  Future<bool> exists(CassetteName name) => throw UnimplementedError();

  @override
  Future<CassetteSnapshot> read(CassetteName name) =>
      throw UnimplementedError();

  @override
  Future<void> replaceIfUnchanged(
    CassetteSnapshot snapshot,
    List<int> bytes,
  ) =>
      throw UnimplementedError();
}

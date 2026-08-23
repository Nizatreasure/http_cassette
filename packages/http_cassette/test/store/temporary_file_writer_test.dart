import 'dart:io';
import 'dart:math';

import 'package:http_cassette/src/store/temporary_file_io.dart';
import 'package:http_cassette/src/store/temporary_file_writer.dart';
import 'package:test/test.dart';

void main() {
  late Directory sandbox;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp(
      'http_cassette_temporary_writer_',
    );
  });

  tearDown(() async {
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  test('writes a complete closed candidate beside the target', () async {
    final target = File('${sandbox.path}${Platform.pathSeparator}example.json');
    final writer = SameDirectoryTemporaryFileWriter(random: Random(1));

    final candidate = await writer.write(target, <int>[0, 1, 2, 255]);

    expect(candidate.parent.path, target.parent.path);
    expect(candidate.path, isNot(target.path));
    expect(candidate.path, endsWith('.tmp'));
    expect(await candidate.readAsBytes(), <int>[0, 1, 2, 255]);
    expect(await target.exists(), isFalse);
    await candidate.delete();
  });

  test('uses a new unpredictable candidate name for each write', () async {
    final target = File('${sandbox.path}${Platform.pathSeparator}example.json');
    final writer = SameDirectoryTemporaryFileWriter(random: Random(2));

    final first = await writer.write(target, <int>[1]);
    final second = await writer.write(target, <int>[2]);

    expect(second.path, isNot(first.path));
  });

  test('retries an exclusive-create collision', () async {
    final target = File('${sandbox.path}${Platform.pathSeparator}example.json');
    final io = _ControlledTemporaryFileIo(collideOnce: true);
    final writer = SameDirectoryTemporaryFileWriter(io: io, random: Random(3));

    final candidate = await writer.write(target, <int>[7]);

    expect(io.createCalls, 2);
    expect(await candidate.readAsBytes(), <int>[7]);
    expect(await sandbox.list().length, 2);
  });

  for (final failurePoint in _FailurePoint.values) {
    test('removes the candidate after ${failurePoint.name} fails', () async {
      final target =
          File('${sandbox.path}${Platform.pathSeparator}example.json');
      final io = _ControlledTemporaryFileIo(failurePoint: failurePoint);
      final writer =
          SameDirectoryTemporaryFileWriter(io: io, random: Random(4));

      await expectLater(
        writer.write(target, <int>[8, 9]),
        throwsA(isA<StateError>()),
      );

      expect(await sandbox.list().toList(), isEmpty);
      expect(await target.exists(), isFalse);
    });
  }

  test('preserves the write failure when cleanup also fails', () async {
    final target = File('${sandbox.path}${Platform.pathSeparator}example.json');
    final io = _ControlledTemporaryFileIo(
      failurePoint: _FailurePoint.write,
      failCleanup: true,
    );
    final writer = SameDirectoryTemporaryFileWriter(io: io, random: Random(5));

    await expectLater(
      writer.write(target, <int>[10]),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'write failed',
        ),
      ),
    );
  });

  test('replaces a target with a prepared candidate', () async {
    final target = File('${sandbox.path}${Platform.pathSeparator}example.json');
    await target.writeAsBytes(<int>[1]);
    final writer = SameDirectoryTemporaryFileWriter(random: Random(6));
    final candidate = await writer.write(target, <int>[2, 3]);

    await writer.replaceTarget(candidate, target);

    expect(await target.readAsBytes(), <int>[2, 3]);
    expect(await candidate.exists(), isFalse);
  });

  test('removes a candidate and preserves a rename failure', () async {
    final target = File('${sandbox.path}${Platform.pathSeparator}example.json');
    await target.writeAsBytes(<int>[1]);
    final io = _ControlledTemporaryFileIo(failRename: true);
    final writer = SameDirectoryTemporaryFileWriter(io: io, random: Random(7));
    final candidate = await writer.write(target, <int>[2]);

    await expectLater(
      writer.replaceTarget(candidate, target),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'rename failed',
        ),
      ),
    );

    expect(await target.readAsBytes(), <int>[1]);
    expect(await candidate.exists(), isFalse);
  });
}

enum _FailurePoint { open, write, flush, close }

final class _ControlledTemporaryFileIo implements TemporaryFileIo {
  _ControlledTemporaryFileIo({
    this.collideOnce = false,
    this.failurePoint,
    this.failCleanup = false,
    this.failRename = false,
  });

  final bool collideOnce;
  final _FailurePoint? failurePoint;
  final bool failCleanup;
  final bool failRename;
  final DartTemporaryFileIo _delegate = const DartTemporaryFileIo();
  var createCalls = 0;

  @override
  Future<void> createExclusive(File file) async {
    createCalls++;
    if (collideOnce && createCalls == 1) {
      await _delegate.createExclusive(file);
      throw FileSystemException('collision');
    }
    await _delegate.createExclusive(file);
  }

  @override
  Future<RandomAccessFile> openWrite(File file) async {
    if (failurePoint == _FailurePoint.open) {
      throw StateError('open failed');
    }
    return _delegate.openWrite(file);
  }

  @override
  Future<void> write(RandomAccessFile handle, List<int> bytes) async {
    if (failurePoint == _FailurePoint.write) {
      throw StateError('write failed');
    }
    await _delegate.write(handle, bytes);
  }

  @override
  Future<void> flush(RandomAccessFile handle) async {
    if (failurePoint == _FailurePoint.flush) {
      throw StateError('flush failed');
    }
    await _delegate.flush(handle);
  }

  @override
  Future<void> close(RandomAccessFile handle) async {
    if (failurePoint == _FailurePoint.close || failCleanup) {
      throw StateError('close failed');
    }
    await _delegate.close(handle);
  }

  @override
  Future<void> delete(File file) async {
    if (failCleanup) {
      throw StateError('delete failed');
    }
    await _delegate.delete(file);
  }

  @override
  Future<void> rename(File source, String targetPath) async {
    if (failRename) {
      throw StateError('rename failed');
    }
    await _delegate.rename(source, targetPath);
  }

  @override
  Future<FileSystemEntityType> type(String path) => _delegate.type(path);
}

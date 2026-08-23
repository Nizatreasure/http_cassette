import 'dart:typed_data';

import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette/src/store/file_revision.dart';
import 'package:test/test.dart';

void main() {
  test('matches only exact captured content', () {
    final revision = FileCassetteRevision.takeOwnership(
      CassetteName('exact'),
      Uint8List.fromList(<int>[1, 2, 3]),
    );

    expect(revision.matches(<int>[1, 2, 3]), isTrue);
    expect(revision.matches(<int>[1, 2, 4]), isFalse);
    expect(revision.matches(<int>[1, 2]), isFalse);
    expect(revision.matches(<int>[1, 2, 3, 4]), isFalse);
  });

  test('matches boundary byte values exactly', () {
    final revision = FileCassetteRevision.takeOwnership(
      CassetteName('boundary'),
      Uint8List.fromList(<int>[0, 255]),
    );

    expect(revision.matches(<int>[0, 255]), isTrue);
    expect(revision.matches(<int>[0, 254]), isFalse);
  });

  test('uses a separate opaque identity for each content snapshot', () {
    final name = CassetteName('empty');
    final first = FileCassetteRevision.takeOwnership(name, Uint8List(0));
    final second = FileCassetteRevision.takeOwnership(name, Uint8List(0));

    expect(first.opaque, isNot(second.opaque));
    expect(first.opaque.toString(), 'CassetteRevision(<opaque>)');
  });

  test('retains the logical cassette associated with the revision', () {
    final name = CassetteName('checkout/success');
    final revision = FileCassetteRevision.takeOwnership(name, Uint8List(0));

    expect(revision.name, name);
  });
}

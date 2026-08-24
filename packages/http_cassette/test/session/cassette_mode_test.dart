import 'package:http_cassette/http_cassette.dart';
import 'package:test/test.dart';

void main() {
  test('CassetteMode contains only explicit record and replay modes', () {
    expect(CassetteMode.values, <CassetteMode>[
      CassetteMode.record,
      CassetteMode.replay,
    ]);
  });
}

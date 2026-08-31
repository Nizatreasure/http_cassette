import 'package:dio/dio.dart';
import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette_dio/http_cassette_dio.dart';

void main() {
  final engine = CassetteEngine(store: MemoryCassetteStore());
  final dio = Dio()..installHttpCassette(engine);

  dio.close();
}

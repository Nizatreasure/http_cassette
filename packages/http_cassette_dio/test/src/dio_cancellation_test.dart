import 'dart:async';

import 'package:dio/dio.dart';
import 'package:http_cassette_dio/src/dio_cancellation.dart';
import 'package:test/test.dart';

void main() {
  test('returns no core signal when Dio supplied no cancellation', () {
    final options = RequestOptions(path: 'https://example.test/items');

    expect(createDioCassetteCancellation(options, null), isNull);
  });

  test('exposes an already-cancelled token synchronously', () async {
    final token = CancelToken()..cancel('caller reason');
    final options = RequestOptions(
      path: 'https://example.test/items',
      cancelToken: token,
    );

    final cancellation = createDioCassetteCancellation(
      options,
      token.whenCancel,
    )!;

    expect(cancellation.isCancelled, isTrue);
    await cancellation.whenCancelled;
    expect(cancellation.isCancelled, isTrue);
  });

  test('becomes cancelled before its future completes', () async {
    final source = Completer<void>();
    final options = RequestOptions(path: 'https://example.test/items');
    final cancellation = createDioCassetteCancellation(
      options,
      source.future,
    )!;

    expect(cancellation.isCancelled, isFalse);

    source.complete();
    await cancellation.whenCancelled;

    expect(cancellation.isCancelled, isTrue);
  });

  test('observes a token future when fetch did not supply one', () async {
    final token = CancelToken();
    final options = RequestOptions(
      path: 'https://example.test/items',
      cancelToken: token,
    );
    final cancellation = createDioCassetteCancellation(options, null)!;

    token.cancel();
    await cancellation.whenCancelled;

    expect(cancellation.isCancelled, isTrue);
  });
}

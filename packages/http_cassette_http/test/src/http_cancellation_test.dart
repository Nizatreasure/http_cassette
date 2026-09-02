import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http_cassette_http/src/http_cancellation.dart';
import 'package:test/test.dart';

void main() {
  final uri = Uri.parse('https://example.test/items');

  test('returns no core signal for an ordinary request', () {
    final request = http.Request('GET', uri);

    expect(createHttpCassetteCancellation(request), isNull);
  });

  test('returns no core signal when an abortable request has no trigger', () {
    final request = http.AbortableStreamedRequest('GET', uri);

    expect(createHttpCassetteCancellation(request), isNull);
  });

  test('retains the exact trigger and becomes monotonically cancelled',
      () async {
    final trigger = Completer<void>();
    final request = http.AbortableStreamedRequest(
      'GET',
      uri,
      abortTrigger: trigger.future,
    );

    final cancellation = createHttpCassetteCancellation(request)!;

    expect(cancellation.abortTrigger, same(trigger.future));
    expect(cancellation.isCancelled, isFalse);

    trigger.complete();
    await cancellation.whenCancelled;

    expect(cancellation.isCancelled, isTrue);
    await cancellation.whenCancelled;
    expect(cancellation.isCancelled, isTrue);
  });

  test('replaces an invalid trigger error without retaining its value',
      () async {
    const secret = 'private abort reason';
    final trigger = Completer<void>();
    final request = http.AbortableStreamedRequest(
      'GET',
      uri,
      abortTrigger: trigger.future,
    );
    final cancellation = createHttpCassetteCancellation(request)!;

    trigger.completeError(StateError(secret));

    Object? caught;
    try {
      await cancellation.whenCancelled;
    } on Object catch (error) {
      caught = error;
    }

    expect(caught, isA<HttpAbortTriggerFailure>());
    expect(caught, isNot(isA<StateError>()));
    expect(caught.toString(), isNot(contains(secret)));
    expect(cancellation.isCancelled, isFalse);
  });
}

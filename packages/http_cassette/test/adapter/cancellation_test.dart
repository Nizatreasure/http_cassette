import 'dart:async';

import 'package:http_cassette/http_cassette.dart';
import 'package:test/test.dart';

void main() {
  test('CassetteCancellation supports a monotonic completion signal', () async {
    final cancellation = _ManualCancellation();
    var completed = false;
    unawaited(cancellation.whenCancelled.then((_) => completed = true));

    expect(cancellation.isCancelled, isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);

    cancellation.cancel();

    await cancellation.whenCancelled;
    expect(cancellation.isCancelled, isTrue);
    expect(completed, isTrue);
  });
}

final class _ManualCancellation implements CassetteCancellation {
  final _completion = Completer<void>();

  var _isCancelled = false;

  @override
  bool get isCancelled => _isCancelled;

  @override
  Future<void> get whenCancelled => _completion.future;

  void cancel() {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    _completion.complete();
  }
}

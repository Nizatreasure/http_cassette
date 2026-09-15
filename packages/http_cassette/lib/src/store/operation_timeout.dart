import 'dart:async';

import '../cassette/name.dart';
import 'exception.dart';

/// Waits at most [timeout] for one cassette-store [operation].
Future<T> runStoreOperation<T>({
  required Future<T> Function() action,
  required Duration timeout,
  required CassetteName name,
  required CassetteStoreOperation operation,
}) async {
  try {
    return await action().timeout(timeout);
  } on TimeoutException {
    throw CassetteStoreException.operationFailed(
      name: name,
      operation: operation,
    );
  }
}

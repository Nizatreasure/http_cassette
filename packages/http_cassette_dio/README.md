# http_cassette_dio

`http_cassette_dio` connects Dio to the transport-neutral `http_cassette`
package.

The package wraps Dio's transport adapter and passes requests through unchanged
while its cassette engine is inactive. It does not buffer request bodies on
this path.

Active requests are read once from Dio's final encoded request stream, bounded
by the engine's request-body limit and translated into the canonical core
request. Recording permits one real transport attempt, captures its response or
portable transport failure and returns the equivalent live Dio result. Replay
returns the recorded outcome without calling the wrapped transport adapter.

A null request stream remains an empty canonical body. Non-null streams,
including single-subscription and empty streams, are consumed exactly once and
prepared as equivalent replacement streams for later recording. Declared or
measured bodies over the configured limit fail without truncation or network
access. Cancellation and stream errors retain no partial request.

While a cassette session is active, Dio send progress may advance as the
wrapper buffers the request rather than as bytes reach the network. Original
stream chunk boundaries, timing and back-pressure are not preserved. Inactive
requests retain Dio's ordinary streaming and progress behaviour.

## Recordable outcomes

HTTP Cassette distinguishes an outcome of the remote attempt from a local or
caller-controlled failure:

- Every completed HTTP response is recordable, including redirects and 4xx or
  5xx responses.
- A genuine transport failure is recordable when no complete response was
  received. Examples include a timeout, connection failure or secure connection
  failure. Recording these outcomes makes offline, retry and error-handling
  scenarios reproducible during replay.
- Caller cancellation is not recordable because it is a decision made for one
  particular request.
- Cassette failures, such as a body-limit, sanitisation, matching or storage
  failure, are not remote outcomes and are not recorded.

The Dio adapter uses fixed safe descriptions for recordable transport failures.
It never copies raw Dio messages, causes, response values or stack traces into a
cassette. A transport failure encountered while recording an intended success
scenario would become that request's outcome once active execution is
connected. The developer should discard that recording rather than commit it.
The current implementation defines and applies this mapping during recording
and replay.

Dio applies `validateStatus` after the transport adapter returns. HTTP Cassette
therefore records a completed 4xx or 5xx response before Dio may expose it as a
`badResponse`, and replay follows the same Dio status policy. A directly
observed redirect preserves its status, reason, headers and body. V1 does not
persist Dio's `isRedirect` flag, redirect history or transport `extra`, so those
values are available on the live response but not reconstructed during replay.
When Dio's transport follows redirects itself, HTTP Cassette records the final
response observed at the adapter boundary.

## Cassette system failures

HTTP Cassette system failures travel through Dio as `DioException` values so
they follow Dio's ordinary error pipeline. The exact safe `CassetteException`
is retained in `DioException.error` and is available through the extension
getter:

```dart
try {
  await dio.get<void>('/users');
} on DioException catch (error) {
  final cassetteFailure = error.cassetteException;
  if (cassetteFailure != null) {
    // Inspect cassetteFailure.diagnostic.
  }
}
```

The getter returns `null` for ordinary Dio failures and for replayed portable
transport failures.

## Recording and replay

Start and complete sessions through the same engine installed on Dio:

```dart
final recording = await engine.startRecording('account/details');
await dio.get<void>('https://api.example.test/account');
await recording.close();

final replay = await engine.startReplay('account/details');
await dio.get<void>('https://api.example.test/account'); // No network access.
await replay.close();
```

Recording calls the wrapped Dio adapter at most once for each admitted request.
Replay never calls it, including when the cassette is missing, unmatched or
exhausted. Discard a recording instead of closing it when its captured outcome
is not the scenario you intended to keep.

Caller cancellation is never stored as a reusable interaction. Cancellation
before replay selection consumes nothing. During recording, Dio's original
cancellation future still reaches the wrapped adapter; if cancellation wins the
race with the complete captured outcome, the later outcome is ignored and the
recording cannot retain that request.

## Installation

The package is not ready for publication. During development in this workspace,
it can be resolved with `dart pub get` from the repository root.

Create one engine and install that same instance on Dio. Configure any custom
Dio transport adapter before installation:

```dart
import 'package:dio/dio.dart';
import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette_dio/http_cassette_dio.dart';

final engine = CassetteEngine(store: MemoryCassetteStore());
final dio = Dio();

// Configure dio.httpClientAdapter here when required.
dio.installHttpCassette(engine);
```

`CassetteEngine` is not a singleton. Creating another engine creates separate
session state, so it will not control a Dio adapter that holds the first engine.
Several Dio instances may install the same engine when they should participate
in one cassette session.

Installing HTTP Cassette twice on one Dio instance throws a `StateError`.
Assigning another `httpClientAdapter` after installation replaces and disables
the cassette integration. Closing Dio closes the wrapped transport adapter at
most once; cassette sessions remain controlled explicitly through the engine.

## Example

The example is a compile check that installs the adapter without making a
network request.

```sh
dart run example/http_cassette_dio_example.dart
```

## Licence

This package is licensed under the BSD 3-Clause License.

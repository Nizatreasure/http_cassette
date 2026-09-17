# http_cassette_dio

`http_cassette_dio` connects `dio` to the transport-neutral [`http_cassette`](https://pub.dev/packages/http_cassette) engine. It records real HTTP interactions through `dio` and later replays them without contacting the network.

The package wraps `dio`'s final transport adapter. Request interceptors and transformers run before HTTP Cassette, so active sessions capture the final encoded request-body bytes. Response transformation, status validation, and response interceptors continue to run normally after a live or replayed raw response is returned.

## Features

- One-call installation on an existing `dio` client.
- Exact pass-through while no cassette session is active.
- Bounded capture of final encoded request and response bodies.
- Recording through the configured underlying transport adapter.
- Replay without calling the underlying adapter.
- Portable response and transport-failure mapping.
- `DioException` access to structured cassette-system failures.
- Shared cassette sessions across several `dio` clients when they use the same engine.

## Installation

Add both the integration package and the core package used to configure the engine:

```sh
dart pub add http_cassette http_cassette_dio
```

Import `dio`, the core package, and this adapter:

```dart
import 'package:dio/dio.dart';
import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette_dio/http_cassette_dio.dart';
```

## Set up `dio`

Create one engine and install that same instance on `dio`. Configure any custom `HttpClientAdapter` before installation because HTTP Cassette wraps the adapter currently assigned to `dio.httpClientAdapter`.

```dart
final engine = CassetteEngine(
  store: MemoryCassetteStore(),
);

final dio = Dio();

// Configure dio.httpClientAdapter here when required.
dio.installHttpCassette(engine);
```

`CassetteEngine` is not a singleton. A different engine has separate session state and cannot control an adapter installed with the first engine. Several `dio` clients may install the same engine when their requests should participate in the same cassette session.

Installing HTTP Cassette twice on one `dio` client throws a `StateError`. Assigning another `httpClientAdapter` after installation replaces and disables the cassette integration. Closing `dio` closes the wrapped adapter at most once; cassette sessions remain controlled explicitly through the shared engine.

Matching, sanitisation, replay policies, recording lifecycle, activation, body limits, cassette limits, and storage are configured on the core engine. See the [`http_cassette` documentation](https://pub.dev/packages/http_cassette) for those settings.

## Record and replay

Run requests within recording and replay sessions through the engine installed on `dio`:

```dart
final live = await engine.record(
  'account/details',
  () => dio.get<void>('https://api.example.test/account'),
);

final recorded = await engine.replay(
  'account/details',
  () => dio.get<void>('https://api.example.test/account'),
); // No network access.
```

The scoped methods close a successful session and discard it when the callback fails. Manual `startRecording` and `startReplay` sessions are also available for interactive or multi-step scenarios. Recording calls the wrapped adapter at most once for each admitted request. Replay never calls it, including when a request is unmatched or its matching interactions are exhausted. A missing or invalid cassette prevents the replay session from starting. Discard a recording instead of closing it when its captured outcome is not the scenario you intended to keep.

When no cassette session is active, requests pass directly to the wrapped adapter without body buffering or reconstruction. This includes an engine configured for disabled pass-through.

Closing a recording immediately stops new requests from joining it. A request which reaches HTTP Cassette after that point passes through to the wrapped adapter without being recorded, while requests already admitted may finish within the engine's configured close grace period. If close fails, the session still ends and releases the shared engine for another session.

## Request and response bodies

Active requests are consumed once from `dio`'s final encoded request stream, checked against the engine's request-body limit, and translated into a canonical request. A null request stream represents an empty body. Every non-null stream, including an empty or single-subscription stream, is replaced with an equivalent stream for an authorised recording attempt.

Active responses are also completely buffered before they are recorded or returned to `dio`. The engine's response-body limit applies to this capture. Declared or measured bodies over their configured limit fail without truncation. Cancellation and stream errors retain no partial body.

Original stream chunks, timing, and back-pressure are not preserved. During an active session, `dio` send progress may advance while HTTP Cassette buffers the encoded request rather than while bytes reach the network. Response delivery waits for complete bounded capture. Inactive requests retain `dio`'s ordinary streaming and progress behaviour.

These limits apply to individual HTTP bodies. Configure them on the shared core engine. The store's separate `maximumBytes` value limits one complete encoded cassette.

## Recordable outcomes

HTTP Cassette distinguishes a remote attempt outcome from a local or caller-controlled failure:

- Every completed final HTTP response is recordable, including ordinary 2xx responses, directly observed 3xx redirects, and 4xx or 5xx error responses.
- A transport failure is recordable when no complete response was received, including timeouts, connection failures, and secure connection failures.
- Caller cancellation is not recordable because it belongs to one particular request.
- Cassette-system failures, including body-limit, sanitisation, matching, and storage failures, are not remote outcomes and are not recorded.

The canonical cassette model accepts status codes from 100 through 599. A 1xx response can therefore be recorded if the wrapped adapter exposes it as the completed response. Informational responses handled internally by the transport are not visible to HTTP Cassette; it records only the final response returned at the adapter boundary.

The adapter uses fixed safe descriptions for recordable transport failures. It never copies raw `dio` messages, causes, response values, or stack traces into a cassette. A transport failure encountered while recording an intended success scenario becomes that request's recorded outcome, so discard the recording if that is not the scenario you intended to keep.

`dio` applies `validateStatus` after the transport adapter returns. HTTP Cassette therefore records the completed response before `dio` applies that policy, even when the policy later exposes its status as a `badResponse`. Replay follows the same status policy.

A directly observed redirect preserves its status, reason phrase, headers, and body. HTTP Cassette does not persist `dio`'s `isRedirect` flag, redirect history, or transport `extra`, so those values are available on the live response but are not reconstructed during replay. When the wrapped transport follows redirects itself, HTTP Cassette records only the final response observed at the adapter boundary.

## Cassette-system failures

Cassette-system failures travel through `dio` as `DioException` values so they follow its ordinary error pipeline. The exact safe `CassetteException` is retained in `DioException.error` and is available through `cassetteException`:

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

The getter returns `null` for ordinary `dio` failures and replayed portable transport failures.

## Cancellation

Cancellation before replay selection consumes no recorded interaction. During recording, `dio`'s cancellation future is passed to the wrapped adapter. If cancellation wins the race with the complete captured outcome, the later outcome is ignored and that request is not retained in the recording.

## Portability

The official `dio` and `http` adapters use the same canonical cassette format. Equivalent basic requests, successful responses, and common portable transport failures can be recorded through either adapter and replayed through the other without contacting the receiving transport.

A cassette preserves canonical HTTP values, not every client-specific value. It does not store progress, stream chunks, timing, redirect history, connection state, request `extra`, or other transport-specific options. Portability is also limited by the receiving client; for example, `http` cannot represent repeated request-header field lines separately. Transport-failure categories remain portable, but each adapter reconstructs the closest failure its client supports.

## Composition and limitations

- A request interceptor which resolves or rejects without dispatching to the transport never reaches HTTP Cassette and is not recorded.
- Each retry that independently reaches `HttpClientAdapter.fetch` is a separate cassette observation. A retry layer above that boundary may expose only its final attempt.
- SSE, endless streams, and bodies exceeding the configured limits are unsupported.
- Replay does not reproduce original stream chunks, timing, progress, or back-pressure.
- Redirect history and other `dio`-specific transport state are not persisted.

A custom wrapped adapter must return every completed HTTP status as a `ResponseBody`. Throwing a `badResponse` from this transport boundary, throwing a raw non-`dio` error, or emitting a raw response-stream error is treated as an adapter contract violation and is not recorded. Raw error values and messages are not retained in the diagnostic.

## Example

The example records and replays one response through a local fake transport. It does not make a network request.

```sh
dart run example/http_cassette_dio_example.dart
```

## Licence

This package is available under the BSD 3-Clause License. See [`LICENSE`](LICENSE).

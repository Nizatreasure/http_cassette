# http_cassette_http

`http_cassette_http` connects `http` to the transport-neutral [`http_cassette`](https://pub.dev/packages/http_cassette) engine. It records real HTTP interactions through an `http.Client` and later replays them without contacting the wrapped client.

`CassetteHttpClient` is an `http.BaseClient`, so it works with standard `http` convenience methods and can be composed with other clients and middleware.

## Features

- Drop-in `http.Client` wrapper.
- Exact request and response pass-through while no cassette session is active.
- Bounded capture of final request and response bytes.
- Recording through one authorised call to the wrapped client.
- Replay without calling the wrapped client.
- Portable response and transport-failure mapping.
- Cancellation support for `http.Abortable` requests.
- Safe `ClientException` access to cassette-system and replayed transport failures.

## Installation

Add `http`, the core package, and this integration package:

```sh
dart pub add http http_cassette http_cassette_http
```

Import the three packages:

```dart
import 'package:http/http.dart' as http;
import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette_http/http_cassette_http.dart';
```

## Create a client

Create and retain one core engine, then wrap the `http` client which should use it:

```dart
final engine = CassetteEngine(
  store: MemoryCassetteStore(),
);

final client = CassetteHttpClient(
  engine,
  inner: http.Client(),
);
```

When `inner` is omitted, `CassetteHttpClient` creates a normal `http.Client`. The wrapper owns its inner client, including one supplied by the caller. Calling `close` closes that client at most once. It does not close or discard a cassette session on the shared engine.

`CassetteEngine` is not a singleton. Code which starts sessions and every cassette client participating in those sessions must share the same engine instance.

## Record and replay

Run requests within recording and replay sessions through the shared engine:

```dart
final uri = Uri.parse('https://example.test/policies');

final live = await engine.record(
  'policies/list',
  () => client.get(uri),
);

final recorded = await engine.replay(
  'policies/list',
  () => client.get(uri),
); // No network access.
```

The scoped methods close a successful session and discard it when the callback fails. Manual `startRecording` and `startReplay` sessions are also available for interactive or multi-step scenarios.

When no cassette session is active, `send` delegates the exact request to the wrapped client without inspecting or finalising it. The exact response or failure is returned unchanged. During recording, the client finalises and buffers the request once, then the core may authorise one wrapped-client call. During replay, the request is buffered for deterministic matching but the wrapped client is never called.

Replay failures never fall back to the wrapped client. A missing or invalid cassette prevents replay startup, while an unmatched or exhausted request fails without network access.

## Activation policy

The cassette client does not need to be removed when cassette commands must be disabled. Configure the shared engine once:

```dart
final engine = CassetteEngine(
  store: store,
  activationPolicy: CassetteActivationPolicy.disabledWithPassThrough,
);
```

`disabledWithException` rejects recording and replay commands before store or transport work. `disabledWithPassThrough` returns inert sessions and leaves the engine inactive, so requests reach the wrapped client normally and no cassette is read or changed.

`disabledWithPassThrough` permits ordinary network access even when code calls a replay command because no active replay session is created. An active replay session never accesses the network.

## Request and response bodies

Active requests and responses are completely buffered. The defaults are 2 MiB for requests and 5 MiB for responses. Configure them through the core `BodyLimits`:

```dart
final engine = CassetteEngine(
  store: MemoryCassetteStore(),
  configuration: CassetteConfiguration(
    bodyLimits: BodyLimits(
      requestBytes: 4 * 1024 * 1024,
      responseBytes: 10 * 1024 * 1024,
    ),
  ),
);
```

A request over its limit fails before the wrapped client is called. A response over its limit fails after one authorised attempt. Content is never truncated, and empty streams remain empty. These limits apply to individual HTTP bodies; the store's separate `maximumBytes` value limits one complete encoded cassette.

Buffering delays a live attempt until the complete active request is available and delays delivery until the complete response is available. Replay does not preserve original chunk boundaries, timing, or back-pressure. Endless streams, server-sent events, and bodies above the configured limits are unsupported. Inactive requests retain the wrapped client's normal streaming behaviour.

Ordinary requests, streamed requests, and multipart requests are supported from their final encoded bytes. The active replacement request preserves the standard public `BaseRequest` properties but cannot preserve a custom request subclass's identity or private fields. A custom inner client which requires such a subtype is incompatible inside the active cassette boundary; inactive pass-through still receives the exact original request.

## Response behaviour

Every completed final HTTP response is recordable, including ordinary 2xx responses, directly observed 3xx redirects, and 4xx or 5xx error responses. Convenience methods such as `get` return these status responses normally. Higher-level methods such as `read` may reject a status after `send` returns; that client policy does not turn the recorded response into a transport failure.

A directly observed redirect records and replays its status, reason phrase, headers, and body. The live response retains its exposed final URL, redirect flag, and connection-persistence value. Those transport-only values are not cassette data and are not invented during replay. If the wrapped client follows a redirect, HTTP Cassette records only the final response it observes.

## Cancellation

Cancellation is supported for requests implementing `http.Abortable` with a non-null `abortTrigger`. The same trigger controls active request buffering, the authorised live request, response capture, and core selection. Cancellation is returned as `RequestAbortedException` and is never recorded as a reusable transport outcome.

An ordinary `BaseRequest` has no cancellation signal. Cancellation before replay selection consumes no recorded interaction. If cancellation wins during recording, a later response is ignored and that request is not retained.

## Client composition

Place request-changing middleware outside `CassetteHttpClient` when its changes must be recorded and matched:

```text
application -> request middleware -> CassetteHttpClient -> transport
```

The cassette client then sees the effective request produced by that middleware. Middleware which returns a response without calling the cassette client is not observed. Middleware inside the cassette boundary receives the rebuilt active request, so later changes are not part of the canonical request used for matching.

The same boundary matters for retries. A retry client outside `CassetteHttpClient` presents every attempt as a separate cassette interaction. A retry client inside it can make several transport attempts within one authorised call, while HTTP Cassette sees only the final result returned by that client. Place retries outside when each attempt must be recorded and replayed separately.

## Header representation

`http` exposes request headers as one string per case-insensitive name. If repeated field lines were combined before the adapter sees them, it cannot tell whether a comma belongs to one value or separates earlier values. It therefore records the exposed string as one canonical value and cannot reconstruct the original field-line count during replay.

Response capture uses `headersSplitValues` to preserve the values exposed by `http`. Replay joins canonical repeated response values because `http` again requires one string per name. Exact wire casing and field-line multiplicity are not preserved beyond the public values exposed by the client.

## Custom clients and contract failures

A custom wrapped client must follow the public `http` contract: return a valid `StreamedResponse`, use `ClientException` for transport failures, emit valid byte values, and make abort triggers complete normally. Raw errors, failing response streams, and invalid abort triggers become safe `adapterContractViolation` failures. They are not recorded, and their original values are not retained in diagnostics.

## Failure inspection

The package adds safe inspection getters to `http.ClientException`:

```dart
try {
  await client.get(uri);
} on http.ClientException catch (failure) {
  final cassetteFailure = failure.cassetteException;
  final replayedTransportFailure = failure.cassetteTransportFailure;
}
```

Ordinary client failures and `RequestAbortedException` return `null` from both getters. A cassette-system exception carries its exact safe `CassetteException`. A reconstructed transport failure carries its exact `CassetteTransportFailure`, including the portable category and safe message. The two values are mutually exclusive.

HTTP Cassette-created client exceptions omit `ClientException.uri` because an incoming URL may contain credentials or sensitive query values.

## Portability

The official `http` and `dio` adapters use the same canonical cassette format. Equivalent basic requests, successful responses, and common portable transport failures can be recorded through either adapter and replayed through the other without contacting the receiving transport.

A cassette preserves canonical HTTP values, not every client-specific value. It does not store stream chunks, timing, redirect history, connection state, `dio` request `extra`, or custom `BaseRequest` state. Transport-failure categories remain portable, but each adapter reconstructs the closest failure its client supports.

## Limitations

- Active request and response bodies are completely buffered.
- Endless streams and server-sent events are unsupported.
- Replay does not reproduce stream chunks, timing, or back-pressure.
- Custom request-subclass identity and private state are not preserved during active sessions.
- Exact header casing and repeated wire field lines may be lost through `http`'s public header representation.
- Redirect and connection-specific response state are not persisted.

## Example

The example records and replays one response through a local fake client. It does not contact the network.

```sh
dart run example/http_cassette_http_example.dart
```

## Licence

This package is available under the BSD 3-Clause License. See [`LICENSE`](LICENSE).

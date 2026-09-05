# http_cassette_http

`http_cassette_http` provides the `package:http` integration for
HTTP Cassette. `CassetteHttpClient` supports inactive pass-through, explicit
recording and network-free replay, and owns the client it wraps.

## Installation

The package is not ready for publication. During development in this workspace,
it can be resolved with `dart pub get` from the repository root.

## Client setup

Create and retain the core engine, then wrap the `package:http` client which
should use it:

```dart
final engine = CassetteEngine(store: MemoryCassetteStore());
final client = CassetteHttpClient(
  engine,
  inner: http.Client(),
);
```

When the engine has no active session, `send` delegates the exact request to
the wrapped client. It does not inspect or finalise the request. The exact
response or failure is passed back unchanged.

During recording, the client finalises and buffers the request once, then lets
the core authorise one call to the wrapped client. The complete response or a
portable `ClientException` failure is captured before the result is returned.
During replay, the request is buffered for deterministic matching but the
wrapped client is never called.

The wrapper owns the inner client, including one supplied by the caller.
Closing `CassetteHttpClient` closes that client at most once. It does not close
or discard a cassette session on the shared engine.

```dart
final recording = await engine.startRecording('policies/list');
final live = await client.get(Uri.parse('https://example.test/policies'));
await recording.close();

final replay = await engine.startReplay('policies/list');
final recorded = await client.get(Uri.parse('https://example.test/policies'));
await replay.close();
```

Replay failures never fall back to the wrapped client. A missing cassette,
mismatch or exhausted interaction therefore cannot access the network.

## Cassette portability

`package:http` and Dio use the same canonical cassette format. Contract tests
verify equivalent basic requests, successful responses and common portable
transport failures. A successful recording made through either official
adapter can replay through the other without contacting its wrapped transport.

The cassette preserves canonical HTTP values, not every client-specific value.
It does not store stream chunks or timing, redirect history, connection state,
Dio `extra` or custom `BaseRequest` state. Transport failure categories remain
available as portable cassette data, but each adapter reconstructs the closest
failure its client supports. Because `package:http` exposes one string per
request header, it cannot preserve earlier repeated request-header field lines
as separate canonical values.

## Client composition

Place request-changing middleware outside `CassetteHttpClient` when its changes
must be recorded and matched:

```text
application -> request middleware -> CassetteHttpClient -> transport
```

The cassette client then sees the effective request produced by that
middleware. Middleware which returns a response without calling the cassette
client is not observed. Middleware inside the cassette boundary receives the
rebuilt active request, so any later changes are not part of the canonical
request used for matching.

The same boundary matters for retries. A retry client outside
`CassetteHttpClient` presents every attempt as a separate cassette interaction.
A retry client inside it can make several transport attempts within the one
authorised call, while HTTP Cassette sees only the final result returned by that
client. Choose the order deliberately; place retries outside when each attempt
must be recorded and replayed separately.

## Cancellation

Cancellation is supported for requests implementing `http.Abortable` with a
non-null `abortTrigger`. The same trigger controls active request buffering,
the authorised live request, response capture and core selection. Cancellation
is returned as `RequestAbortedException` and is never recorded as a reusable
transport outcome.

An ordinary `BaseRequest` has no cancellation signal. Cancelling before replay
selection consumes no interaction. If cancellation wins during recording, a
later response is ignored and no interaction is retained.

## Response behaviour

Every completed HTTP exchange is a response, including 3xx, 4xx and 5xx status
codes. `package:http` convenience operations such as `get` return those status
responses normally. Higher-level operations such as `read` may reject a status
after `send` returns; that client policy does not turn the recorded exchange
into a transport failure.

A directly observed redirect records and replays its status, reason phrase,
headers and body. The live response retains its exposed final URL, redirect
flag and connection-persistence value. Those transport-only values are not in
the cassette schema, so replay does not invent them. If the inner client follows
a redirect, HTTP Cassette records only the final response it observes.

## Bodies and custom clients

Active requests and responses are completely buffered. The defaults are 2 MiB
for requests and 5 MiB for responses, configured through the core
`BodyLimits`. A request over its limit fails before the inner client is called.
A response over its limit fails after one authorised attempt. Content is never
truncated, and empty streams remain empty.

Buffering delays the live network attempt until the whole active request is
available, and delays delivery to the caller until the whole response is
available. It does not preserve chunk boundaries, timing or back-pressure.
Endless streams, server-sent events and bodies above the configured limits are
unsupported. Inactive requests retain the inner client's normal streaming
behaviour.

Ordinary requests, streamed requests and multipart requests are supported from
their final encoded bytes. In active mode the replacement request preserves
the standard public `BaseRequest` properties. It cannot preserve a custom
request subclass's identity or private fields. A custom inner client which
requires such a subtype is therefore incompatible inside the cassette
boundary; inactive pass-through still receives the exact original request.

`package:http` exposes request headers as one string per case-insensitive name,
so the adapter cannot recover earlier repeated fields or infer that a comma
separates values. Response capture uses `headersSplitValues`; replay joins
canonical repeated values because `package:http` again requires one string per
name. Exact wire casing and field-line multiplicity are not preserved beyond
the public values exposed by `package:http`.

A custom inner client must follow the public `package:http` contract: return a
valid `StreamedResponse`, use `ClientException` for transport failures, emit
valid byte values and make abort triggers complete normally. Raw errors,
failing response streams and invalid abort triggers become safe
`adapterContractViolation` failures. They are not recorded, and their original
values are not retained in cassette diagnostics.

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

An ordinary client failure and `RequestAbortedException` return `null` from
both getters. A cassette-system exception carries its exact safe
`CassetteException`. A reconstructed transport failure carries its exact
`CassetteTransportFailure`, including the portable category and safe message.
The two values are mutually exclusive.

HTTP Cassette-created client exceptions deliberately omit `ClientException.uri`
because an incoming URL may contain credentials or sensitive query values.

## Example

The example records and replays one response using a local fake client. It does
not contact the network.

```sh
dart run example/http_cassette_http_example.dart
```

## Licence

This package is licensed under the BSD 3-Clause License.

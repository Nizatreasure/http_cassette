# http_cassette_http

`http_cassette_http` provides the developing `package:http` integration for
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

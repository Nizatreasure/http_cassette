# http_cassette_http

`http_cassette_http` provides the developing `package:http` integration for
HTTP Cassette. `CassetteHttpClient` currently provides exact inactive
pass-through and owns the client it wraps.

Active recording and replay translation are not implemented yet. An active
session fails locally without calling the wrapped client.

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

The wrapper owns the inner client, including one supplied by the caller.
Closing `CassetteHttpClient` closes that client at most once. It does not close
or discard a cassette session on the shared engine.

Do not start recording or replay with this adapter yet. Until active request
and response translation is implemented, an active call fails locally and
does not access the network.

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
The currently disconnected active client path does not produce these wrapped
failures yet.

## Example

The example demonstrates construction, inactive pass-through and ownership
using a local fake client. It does not contact the network.

```sh
dart run example/http_cassette_http_example.dart
```

## Licence

This package is licensed under the BSD 3-Clause License.

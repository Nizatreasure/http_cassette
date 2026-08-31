# http_cassette_dio

`http_cassette_dio` connects Dio to the transport-neutral `http_cassette`
package.

The current implementation wraps Dio's transport adapter and passes requests
through unchanged while its cassette engine is inactive. It does not buffer
request bodies on this path.

Active requests are now read once from Dio's final encoded request stream,
bounded by the engine's request-body limit and translated into the canonical
core request. Recording and replay execution are not connected yet, so the
wrapper then rejects the request before Dio can access the network. This
fail-closed boundary prevents an incomplete replay path from silently reaching
the network.

A null request stream remains an empty canonical body. Non-null streams,
including single-subscription and empty streams, are consumed exactly once and
prepared as equivalent replacement streams for later recording. Declared or
measured bodies over the configured limit fail without truncation or network
access. Cancellation and stream errors retain no partial request.

While a cassette session is active, Dio send progress may advance as the
wrapper buffers the request rather than as bytes reach the network. Original
stream chunk boundaries, timing and back-pressure are not preserved. Inactive
requests retain Dio's ordinary streaming and progress behaviour.

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

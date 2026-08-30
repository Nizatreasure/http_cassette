# http_cassette_dio

`http_cassette_dio` connects Dio to the transport-neutral `http_cassette`
package.

The current implementation installs the adapter and passes requests through
unchanged while its cassette engine is inactive. It does not buffer request
bodies on this path.

Active recording and replay translation are not implemented yet. If the shared
engine has an active session, the interceptor rejects the request before Dio
can access the network. This fail-closed boundary prevents an incomplete replay
path from silently reaching the network.

## Installation

The package is not ready for publication. During development in this workspace,
it can be resolved with `dart pub get` from the repository root.

Create one engine and pass that same instance to the interceptor and to the
code that will control cassette sessions:

```dart
import 'package:dio/dio.dart';
import 'package:http_cassette/http_cassette.dart';
import 'package:http_cassette_dio/http_cassette_dio.dart';

final engine = CassetteEngine(store: MemoryCassetteStore());
final dio = Dio()..interceptors.add(CassetteDioInterceptor(engine));
```

`CassetteEngine` is not a singleton. Creating another engine creates separate
session state, so it will not control an interceptor that holds the first
engine.

## Example

The example is a compile check that installs the interceptor without making a
network request.

```sh
dart run example/http_cassette_dio_example.dart
```

## Licence

This package is licensed under the BSD 3-Clause License.

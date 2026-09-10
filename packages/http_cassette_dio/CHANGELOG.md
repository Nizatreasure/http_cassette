# Changelog

## 0.1.0

- Added `CassetteHttpClientAdapter` and `installHttpCassette` for connecting a `Dio` instance to an HTTP Cassette engine.
- Added recording and network-free replay of bounded request and response bodies through the core interception contract.
- Added canonical translation of `dio` requests, completed responses, redirects, and portable transport failures.
- Added cancellation handling that prevents caller cancellation from becoming a recorded transport outcome.
- Added structured cassette-failure inspection through `DioException` extensions.
- Added inactive and explicitly disabled pass-through behaviour without changing the wrapped transport request.
- Added cassette portability with the official `http` adapter for equivalent requests, responses, and transport failures.

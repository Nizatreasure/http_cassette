# Changelog

## 0.1.0

- Added `CassetteHttpClient` for connecting an `http` client to an HTTP Cassette engine.
- Added recording and network-free replay of bounded request and response bodies through the core interception contract.
- Added canonical translation of `http` requests, completed responses, redirects, and portable transport failures.
- Added request-abort handling that prevents caller cancellation from becoming a recorded transport outcome.
- Added structured cassette and replayed transport-failure inspection through `ClientException` extensions.
- Added inactive and explicitly disabled pass-through behaviour without changing the inner-client request.
- Added pass-through for new requests while recording close waits for already admitted requests to settle.
- Added cassette portability with the official `dio` adapter for equivalent requests, responses, and transport failures.

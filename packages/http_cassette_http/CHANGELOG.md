# Changelog

## 0.1.0

- Created the initial `package:http` integration package scaffold.
- Added `CassetteHttpClient` with exact inactive pass-through, fail-closed
  active behaviour and single ownership of its inner client.
- Added bounded, cancellation-aware internal buffering for active HTTP byte
  streams.
- Added an internal monotonic bridge from `package:http` abort triggers to the
  transport-neutral cancellation contract.
- Added internal canonical translation of effective `package:http` request
  metadata and already-buffered body bytes.
- Added one-time active request finalisation, bounded buffering and equivalent
  replacement of standard `package:http` request behaviour.

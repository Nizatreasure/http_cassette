# Changelog

## 0.1.0

- Added repository contract coverage proving basic canonical request
  equivalence with the official Dio adapter.
- Verified that equivalent successful responses produce the same canonical
  persisted outcome through both official adapters.
- Verified common portable transport-failure equivalence without retaining
  private client failure details.
- Verified that cassettes recorded through either official adapter replay
  through the other without transport access.
- Documented the portable cassette contract and transport-specific boundaries.
- Verified and documented explicit disabled command pass-through to the inner
  `package:http` client.
- Added end-to-end file-backed create and replay coverage through the public
  HTTP client wrapper.
- Added end-to-end file-backed replacement coverage through the public HTTP
  client wrapper.
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
- Added bounded live response capture with canonical translation and an
  equivalent fresh response stream for the caller.
- Added conservative, value-free translation from `package:http` client
  failures to portable transport outcomes while excluding cancellation.
- Added replay reconstruction of canonical responses as fresh
  `package:http` response streams without invented transport metadata.
- Added safe public inspection of cassette-system and replayed transport
  failures carried by `ClientException`, without retaining request URIs.
- Connected active recording and replay through the public core interception
  contract, with one authorised inner-client call and no replay network access.
- Verified abort ordering before request buffering, replay selection and live
  response completion, including non-retention of late outcomes.
- Verified completed error statuses, direct redirect metadata boundaries and
  bodyless JSON-labelled requests across recording and replay.
- Verified body limits, empty streams and value-free failure handling for
  invalid abort triggers, custom-client errors and response-stream errors.
- Documented middleware and retry ordering, active buffering, custom request
  boundaries and the header representation exposed by `package:http`.

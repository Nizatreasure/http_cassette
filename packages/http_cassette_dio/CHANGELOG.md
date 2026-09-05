# Changelog

## Unreleased

- Added repository contract coverage proving basic canonical request
  equivalence with the official `package:http` adapter.
- Verified that equivalent successful responses produce the same canonical
  persisted outcome through both official adapters.
- Verified common portable transport-failure equivalence without retaining
  private client failure details.
- Verified that cassettes recorded through either official adapter replay
  through the other without transport access.
- Documented the portable cassette contract and transport-specific boundaries.
- Verified and documented explicit disabled command pass-through to Dio's
  wrapped transport.
- Supported recording bodyless requests that carry a JSON content type.
- Added the public Dio transport-adapter wrapper, one-call installation and
  inactive request pass-through.
- Added a fail-closed boundary until active recording and replay translation is
  implemented.
- Added internal translation from effective Dio request metadata and supplied
  bytes to the transport-neutral request model.
- Added bounded single-use buffering and canonicalisation of active Dio request
  streams, including safe limit and cancellation failures.
- Added shared bounded Dio byte-stream capture and internal canonical response
  translation with an equivalent raw Dio response.
- Added safe internal translation from Dio transport failure types to portable
  failure outcomes without retaining raw exception values.
- Added internal reconstruction of canonical replay responses as independent
  raw Dio responses.
- Added internal reconstruction of portable replay failures as the closest Dio
  exception while retaining their safe core category.
- Added public access to structured cassette-system failures carried by Dio
  exceptions and used it for active request body-limit failures.
- Added an internal monotonic bridge from Dio cancellation state to the
  transport-neutral core cancellation contract.
- Connected active Dio recording and replay through the public core
  interception contract, with one authorised live attempt and no replay
  network access.
- Completed adapter-level cancellation ordering tests for live recording and
  replay selection, including non-retention of late outcomes.
- Verified that Dio status validation remains outside cassette capture and
  documented direct and followed redirect behaviour.
- Verified value-free adapter-contract failures for unmapped adapter errors,
  failing response streams and invalid transport-level `badResponse` errors.
- Documented interceptor, retry, buffering, progress and streaming limitations.

## 0.1.0

- Created the initial Dio integration package scaffold.
- No adapter or public API is available yet.

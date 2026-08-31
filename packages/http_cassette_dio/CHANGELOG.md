# Changelog

## Unreleased

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

## 0.1.0

- Created the initial Dio integration package scaffold.
- No adapter or public API is available yet.

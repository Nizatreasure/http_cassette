# Changelog

## 0.1.0

- Created the initial package scaffold.
- Added structured diagnostic categories, network-access status and the base
  cassette exception.
- Added safe deterministic diagnostic formatting.
- Added immutable canonical HTTP headers with ordered repeated values.
- Added immutable canonical HTTP requests and responses with protected bodies.
- Added canonical response outcomes and portable transport failures.
- Added validated, cross-platform logical cassette names.
- Added measured, configurable request and response body limits.
- Added conservative method and URI normalisation for matching.
- Added deterministic query normalisation with ordered repeated values.
- Added case-insensitive selected-header matching foundations.
- Added strict JSON body classification and duplicate-member detection.
- Added deterministic structural JSON comparison with lossless numeric matching.
- Added exact byte-body comparison with value-free difference facts.
- Added validated request matching exclusions with structure-preserving query
  and JSON behaviour.
- Added immutable matching configuration and composed the default request
  matcher.
- Added deterministic, value-free and bounded matcher component differences.
- Added deterministic closest-candidate ranking from stored match results.
- Added the safe transport-neutral custom matcher component contract.
- Added validated ordered custom matcher registration to matching
  configuration.
- Added custom matcher execution, eligibility and closest-candidate ranking.
- Added deterministic type-preserving scalar sanitisation placeholders.
- Added immutable secure-default sanitisation rule configuration.
- Added a conspicuous unsafe opt-out from built-in sanitisation rules.
- Added exact sensitive-header value sanitisation with affected-name reporting.
- Added exact sensitive query-value sanitisation with affected-name reporting.
- Added URI user-information sanitisation and composed request-field matching
  exclusions.
- Added recursive, type-preserving JSON member-name sanitisation.
- Added exact RFC 6901 JSON Pointer sanitisation.
- Added deterministic UTF-8 encoding for strictly parsed JSON values.
- Added safe JSON body classification, sanitisation and invalid-body failure.
- Added composed built-in request and response sanitisation.
- Added public transport-neutral custom sanitiser contracts.
- Added immutable ordered custom sanitiser registration.
- Added whole-request-body matching exclusions that retain empty versus
  non-empty body presence.
- Added ordered custom request-sanitiser execution with value-free exclusion
  coverage validation.
- Added ordered custom response-sanitiser execution.
- Composed complete custom-then-built-in request and response sanitisation
  pipelines.
- Added immutable sanitised cassette interaction values with validated arrival
  indices and persisted matching exclusions.
- Added immutable current-version cassettes with contiguous ordered interaction
  validation.
- Added immutable empty, readable-text and canonical-Base64 persisted body
  representations with exact byte reconstruction.
- Added deeply immutable structured JSON bodies with deterministic compact
  reconstruction.
- Treated content-encoded bodies as opaque bytes during built-in JSON
  sanitisation.
- Added deterministic core selection of empty, JSON, text and Base64 persisted
  body encodings.
- Added payload-derived header correction with changed-name reporting for
  request matching exclusions.
- Added deterministic canonical URI construction for persisted requests.
- Added immutable, exactly ordered projection into the V1 cassette schema.
- Added deterministic pretty-printed V1 cassette encoding with golden coverage.
- Added a shared strict JSON parser with safe positional failures.
- Added strict V1 root-envelope and schema-version decoding.
- Added strict decoding for every V1 persisted body representation.
- Added strict V1 header and request matching-exclusion decoding.
- Added strict reconstruction of complete canonical V1 requests.
- Standardised internal V1-specific identifiers with a `V1` suffix.
- Added strict reconstruction of V1 response and transport-failure outcomes.
- Added strict reconstruction of complete immutable V1 cassettes.
- Added reviewed invalid V1 fixtures and complete-cassette round-trip coverage.
- Added a reproducible cassette-size probe and selected a 64 MiB default
  total-file limit.
- Enforced the configurable cassette byte limit before UTF-8 decoding and JSON
  parsing.
- Added immutable encoded cassette snapshots with opaque identity-only
  revisions.
- Added safe structured cassette-store failure and operation categories.
- Added the public transport-neutral cassette-store contract.
- Added isolate-local in-memory cassette storage with conditional replacement.
- Added the internal file-store path resolver with per-operation symbolic-link
  containment checks.
- Added the `dart:io` file-store library with safe existence checks and bounded,
  format-neutral reads.
- Added exclusive create-only file writes with defensive input copying,
  same-instance ordering and best-effort failed-write cleanup.
- Added the internal failure-safe same-directory temporary-file writer needed
  for atomic file replacement.
- Added explicit atomic file replacement on supported file systems, including
  same-instance ordering and safe missing-target behaviour.
- Added private content snapshots behind opaque file-store revisions.
- Added content-checked conditional file replacement with stale and foreign
  revision rejection.
- Added immutable replay policy and session-option configuration.
- Added deterministic immutable replay matching-group construction.
- Added synchronous strict replay selection with distinct no-match and
  exhausted results.
- Added deterministic reusable first- and last-match replay selection.
- Added progressive sequence replay selection with final-match reuse.
- Added wrapping cycle replay selection with stable distinct-use tracking.
- Added immutable replay usage snapshots and optional cassette-wide unused
  interaction verification.
- Added immutable value-free replay exhaustion facts for later diagnostics.
- Added immutable value-free replay request and cassette diagnostic context.
- Added internal structured replay exhaustion diagnostic assembly.
- Added bounded deterministic formatting for replay exhaustion diagnostics.
- Added structured diagnostics for failed unused-interaction verification.
- Added bounded deterministic formatting for unused-interaction diagnostics.
- Added immutable no-match facts from existing candidate rankings.
- Added value-safe matcher descriptions containing configuration counts only.
- Added location-suppressed projections of closest no-match comparisons.
- Added internal structured replay no-match diagnostic assembly.
- Added bounded deterministic formatting for replay no-match diagnostics.
- Connected actual strict replay exhaustion to its safe structured diagnostic.
- Added internal replay outcome delivery with safe no-match and exhaustion
  exceptions.
- Connected internal replay execution to the engine's active replay session.
- Completed internal engine-route coverage for matched, mismatched and
  exhausted replay requests.
- Added active recording-session configuration and request-arrival state.
- Added an internal one-shot recording transport-attempt guard.
- Added indexed transient recording request attempts before session retention.
- Added sanitised recording interaction projection with matching exclusions.
- Added ordered in-memory retention for sanitised recording interactions.
- Composed recording admission, one real attempt, sanitisation and retention.
- Connected internal recording execution to the engine's active session.
- Added complete in-memory recording cassette finalisation.
- Added recording-start target preflight for create and replace modes.
- Added authoritative internal recording commits for create and replace modes.
- Connected create and replacement recording commits to successful close.
- Added immutable engine configuration and explicit cassette session modes.
- Added internal cassette session lifecycle state control.
- Added the public asynchronous cassette session lifecycle handle.
- Added immutable recording options for existing cassette handling.
- Added internal one-active-session engine ownership control.
- Added the public lifecycle-only cassette engine shell.
- Added safe replay store-read diagnostic mapping.
- Added safe replay cassette-decode diagnostic mapping.
- Added a unified, safely formatted replay-loading failure boundary.
- Unified the store and decoder total cassette byte-limit contract.
- Added internal single-read replay cassette loading and strict decoding.
- Connected replay-loading failures to the public cassette exception boundary.
- Loaded and validated cassettes before activating replay sessions.
- Added immutable resolved configuration for active replay sessions.
- Added session-local monotonic replay request-arrival indices.
- Combined internal replay arrival assignment, matching and policy selection.
- Assembled safe no-match diagnostics from actual replay selection.
- Record/replay behaviour is not available yet.

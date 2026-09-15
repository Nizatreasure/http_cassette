# Changelog

## 0.1.0

- Added the transport-neutral cassette engine with explicit recording and network-free replay sessions.
- Added file-backed and in-memory cassette stores with bounded reads, safe writes, atomic replacement, and validated append support.
- Added immutable canonical HTTP requests, responses, headers, interactions, and portable transport failures.
- Added deterministic request matching for methods, URIs, selected headers, JSON bodies, and binary bodies, with configurable exclusions and custom matcher components.
- Added strict, first, last, sequence, and cycle replay policies, optional unused-interaction verification, and deterministic concurrent request ordering.
- Added secure built-in request and response sanitisation, type-preserving JSON redaction, RFC 6901 JSON Pointer rules, and custom sanitiser support.
- Added configurable request, response, and total cassette size limits.
- Added strict versioned cassette encoding and decoding with readable JSON, text, and Base64 body representations.
- Added structured, value-safe diagnostics for loading, matching, exhaustion, storage, cancellation, and lifecycle failures.
- Added the public interception and cancellation contracts used by official and third-party transport adapters.
- Added configurable engine activation policies for enabled, fail-closed, and silent pass-through operation.
- Added a configurable recording-close grace period with all-or-nothing persistence and safe failure diagnostics.
- Added pass-through for new transport interceptions while a recording is closing.
- Made close and discard failures terminal, including explicit diagnostics for unconfirmed store-write results.
- Added a configurable timeout for cassette-store existence checks, reads, and writes.

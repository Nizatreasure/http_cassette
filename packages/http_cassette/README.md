# http_cassette

`http_cassette` is the transport-neutral core of HTTP Cassette. It records canonical HTTP interactions, stores them as deterministic JSON, and replays them without network access.

The package owns cassette sessions, matching, replay policy, sanitisation, diagnostics, and storage. It does not depend on `dio`, `http`, Flutter, or any application framework.

Most applications should use this package with [`http_cassette_dio`](https://pub.dev/packages/http_cassette_dio) or [`http_cassette_http`](https://pub.dev/packages/http_cassette_http). Use the core directly when implementing a custom transport adapter or custom cassette store.

## Features

- Explicit recording and replay sessions.
- Deterministic request matching and replay selection.
- Secure-default request and response sanitisation.
- Human-readable, versioned JSON cassettes.
- In-memory and file-backed storage.
- Structured, value-safe diagnostics.
- Portable canonical requests, responses, and transport failures.
- Public contracts for custom HTTP adapters, matchers, sanitisers, and stores.

## Installation

```sh
dart pub add http_cassette
```

Import the main library for the engine, configuration, models, diagnostics, and in-memory storage:

```dart
import 'package:http_cassette/http_cassette.dart';
```

File-backed storage has a separate `dart:io` entry point:

```dart
import 'package:http_cassette/file.dart';
```

## Create an engine

Every engine has one store and one immutable configuration. An engine is not a singleton. The adapter and the code which starts sessions must share the same engine instance.

Use `MemoryCassetteStore` for temporary, isolate-local recordings:

```dart
final engine = CassetteEngine(
  store: MemoryCassetteStore(),
);
```

Use `FileCassetteStore` when recordings must survive between runs:

```dart
import 'dart:io';

import 'package:http_cassette/file.dart';
import 'package:http_cassette/http_cassette.dart';

final engine = CassetteEngine(
  store: FileCassetteStore(Directory('test/cassettes')),
);
```

The file store is available only on platforms which support `dart:io`. It maps a logical name such as `checkout/declined-card` to a JSON file below the configured root. Absolute paths, traversal segments, and symbolic-link escapes are rejected.

## Record a cassette

Start recording before the application sends the requests that belong to the scenario. Close the session only when every intended request has completed.

```dart
final recording = await engine.startRecording('account/details');

try {
  await runAccountDetailsScenario();
  await recording.close();
} catch (_) {
  await recording.discard();
  rethrow;
}
```

Closing a recording sanitises and writes the complete cassette. Discarding releases the session without writing it. Recording is explicit; installing an adapter alone does not create cassettes.

The scoped form handles close and discard automatically:

```dart
final result = await engine.record(
  'account/details',
  () => runAccountDetailsScenario(),
);
```

### Existing cassettes

Recording fails by default if the target already exists. Choose replacement or append explicitly:

```dart
final replacement = await engine.startRecording(
  'account/details',
  options: const RecordingOptions(
    existingCassette: ExistingCassette.replace,
  ),
);

final append = await engine.startRecording(
  'account/details',
  options: const RecordingOptions(
    existingCassette: ExistingCassette.append,
  ),
);
```

Append requires an existing, valid cassette whose schema version equals the engine's current writable schema version. Existing interactions are kept and new indices continue from the previous highest index. A detected concurrent change rejects the append without replacing the existing file.

## Replay a cassette

Replay loads and validates the complete cassette before the session becomes active:

```dart
final replay = await engine.startReplay('account/details');

try {
  await runAccountDetailsScenario();
  await replay.close();
} catch (_) {
  await replay.discard();
  rethrow;
}
```

An active replay never calls the real transport. A missing cassette, invalid cassette, unmatched request, or exhausted interaction throws a `CassetteException` without network fallback.

The scoped form is also available:

```dart
final result = await engine.replay(
  'account/details',
  () => runAccountDetailsScenario(),
);
```

Set `requireAllInteractions` when successful close must confirm that every recorded interaction was used:

```dart
final replay = await engine.startReplay(
  'account/details',
  options: const ReplayOptions(requireAllInteractions: true),
);
```

## Matching

The default matcher compares:

- the HTTP method;
- the normalised URI, including query values;
- every non-empty request body.

Headers are ignored by default because credentials, dates, traces, and other volatile values commonly appear there. JSON bodies are compared structurally: object member order is ignored, array order is preserved, and scalar types and values must match. Other bodies use exact byte comparison.

Add selected headers or exclusions through `MatchingConfiguration`:

```dart
final configuration = CassetteConfiguration(
  matching: MatchingConfiguration(
    includedHeaders: {'accept', 'x-api-version'},
    ignoredQueryParameters: {'request_id'},
    ignoredJsonPointers: {'/metadata/generated_at'},
  ),
);
```

Ignored JSON paths use exact RFC 6901 JSON Pointer syntax. A missing ignored query parameter or JSON path needs no special handling; matching simply has no value to exclude at that location.

Custom `RequestMatcherComponent` implementations can add domain-specific comparisons. They receive canonical requests and the effective exclusions, and must return bounded, value-safe differences.

## Replay policies

`ReplayPolicy.strict` is the default. It consumes each matching interaction once and reports exhaustion after all matching interactions have been used.

Other policies are available when reuse is intentional:

- `first` always returns the first matching interaction.
- `last` always returns the last matching interaction.
- `sequence` advances through the matching interactions and then keeps returning the last one.
- `cycle` advances through the matching interactions and then returns to the first one.

Set an engine default or override one replay session:

```dart
final engine = CassetteEngine(
  store: MemoryCassetteStore(),
  configuration: CassetteConfiguration(
    defaultReplayPolicy: ReplayPolicy.sequence,
  ),
);

final replay = await engine.startReplay(
  'polling/status',
  options: const ReplayOptions(policy: ReplayPolicy.cycle),
);
```

## Sanitisation

Every recorded interaction passes through sanitisation before persistence. Built-in rules redact common sensitive headers and common credential-shaped query and JSON member names.

Add project-specific rules when your API uses other sensitive fields:

```dart
final configuration = CassetteConfiguration(
  sanitisation: SanitisationConfiguration(
    additionalHeaders: {'x-project-secret'},
    additionalQueryParameters: {'session_code'},
    additionalJsonNames: {'account_number'},
    additionalJsonPointers: {'/customer/private_note'},
  ),
);
```

Sensitive JSON names match every object member with that name, at any depth. Use an exact JSON Pointer when only one path is sensitive. Header rules apply to requests and responses. Query rules apply only to request URIs. JSON name and pointer rules apply to JSON request and response bodies.

Sanitised request values are also excluded from the corresponding matcher component. This prevents replay from requiring the original secret. Body presence remains significant when a complete body value is excluded.

Custom request and response sanitisers can handle domain-specific data. They must return valid canonical values and report every changed match-relevant request location. The built-in pipeline remains active around custom sanitisers.

`SanitisationConfiguration.unsafeWithoutBuiltIns` disables the built-in rules. Its name is intentionally explicit because it can persist credentials and personal data. Prefer adding rules to the secure defaults.

> Automatic sanitisation reduces risk but cannot guarantee that a cassette is safe to commit. Review every generated cassette before sharing it.

## Body and cassette limits

Active adapters buffer complete request and response bodies. The defaults are 2 MiB for requests and 5 MiB for responses:

```dart
final configuration = CassetteConfiguration(
  bodyLimits: BodyLimits(
    requestBytes: 4 * 1024 * 1024,
    responseBytes: 10 * 1024 * 1024,
  ),
);
```

Larger bodies fail instead of being truncated. Stores also enforce one total encoded-cassette limit, which defaults to 64 MiB. The same store limit is used by the core before decoding.

## Activation policy

`CassetteActivationPolicy.enabled` allows normal session commands and is the default.

`disabledWithException` rejects recording and replay commands before store or transport work. `disabledWithPassThrough` returns inert sessions and leaves the engine inactive, so an installed adapter sends traffic normally and performs no cassette work.

```dart
final engine = CassetteEngine(
  store: store,
  activationPolicy: CassetteActivationPolicy.disabledWithPassThrough,
);
```

> `disabledWithPassThrough` permits real network access even when code calls `startReplay` or `replay`, because it does not create an active replay session.

## Diagnostics and failures

Operational failures use `CassetteException`. Its `diagnostic` contains a stable `DiagnosticCategory`, a safe summary, and the network-access status:

```dart
try {
  await engine.startReplay('account/details');
} on CassetteException catch (failure) {
  final category = failure.diagnostic.category;
  final message = failure.toString();
}
```

Mismatch diagnostics describe the request shape, matcher, replay policy, closest candidate, and value-free differences. They do not include sanitised values. `ScopedCassetteException` is used only when a scoped callback fails and session cleanup also fails; it keeps the original callback error and a separate safe cleanup diagnostic.

Store implementations throw `CassetteStoreException` with stable operation and failure enums. These exceptions use logical cassette names and do not expose file paths, bytes, revisions, or platform exceptions.

## Custom adapters

A transport adapter asks the engine for one `CassetteInterception` before buffering or translating a request.

```dart
final interception = engine.beginInterception();

if (!interception.isActive) {
  return sendOriginalRequest();
}

final outcome = await interception.proceed(
  canonicalRequest,
  () => sendOneRealCanonicalAttempt(),
  cancellation: cancellation,
);
```

An inactive permit means exact pass-through: do not buffer, finalise, or rebuild the transport request. An active permit exposes the configured body limits and may be used once. The real-attempt callback must make at most one transport attempt and return one canonical `CassetteOutcome`. Replay resolves without invoking it.

Adapters are responsible for converting transport values to `CassetteRequest`, reconstructing transport responses and failures, buffering bounded streams, and connecting cancellation. They must not implement matching, sanitisation, replay policy, persistence, or cassette lifecycle.

## Storage contract

`CassetteStore` works with bounded encoded bytes. A store does not parse JSON, validate a schema, sanitise values, or match requests. It supports existence checks, immutable reads, create-only writes, explicit replacement, and conditional replacement using an opaque `CassetteRevision`.

`MemoryCassetteStore` is isolate-local. `FileCassetteStore` uses same-directory temporary files and replacement rename. Atomic replacement depends on file-system support. Cross-process locking and guaranteed directory durability after sudden power loss are not provided.

## Limitations

- Engine and replay state are isolate-local.
- Active bodies are buffered; endless streams and server-sent events are unsupported.
- Replay does not reproduce chunk boundaries, timing, delays, or back-pressure.
- Multipart bodies are matched as raw bytes rather than by individual parts.
- Redirect chains and client-specific transport state are not stored.
- Automatic schema migration, record-on-miss mode, and per-request replay policies are not part of V1.
- Caller cancellation is never stored as a reusable interaction.

## Example

The package example shows a minimal custom adapter boundary recording and replaying one canonical response entirely in memory:

```sh
dart run example/http_cassette_example.dart
```

## Licence

This package is available under the BSD 3-Clause License. See [`LICENSE`](LICENSE).

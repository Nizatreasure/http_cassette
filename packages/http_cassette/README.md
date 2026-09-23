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

## Configuration guide

Most behaviour is configured once through `CassetteConfiguration` when the engine is created. The engine activation policy and the complete encoded-cassette limit have their own constructor parameters.

| Setting | Where to configure it | Default |
| --- | --- | --- |
| Recording close grace period | `CassetteConfiguration.recording.closeGracePeriod` | 30 seconds |
| Store existence-check, read, and write timeout | `CassetteConfiguration.storeOperations.timeout` | 30 seconds |
| Request body limit | `CassetteConfiguration.bodyLimits.requestBytes` | 2 MiB |
| Response body limit | `CassetteConfiguration.bodyLimits.responseBytes` | 5 MiB |
| Matching and exclusions | `CassetteConfiguration.matching` | Method, URI, and non-empty body |
| Sanitisation | `CassetteConfiguration.sanitisation` | Secure built-in rules |
| Replay policy | `CassetteConfiguration.defaultReplayPolicy` | `ReplayPolicy.strict` |
| Engine activation | `CassetteEngine.activationPolicy` constructor argument | `CassetteActivationPolicy.enabled` |
| Complete encoded cassette limit | Store `maximumBytes` constructor argument | 64 MiB |

The sections below explain each setting and include examples. Recording and replay session-specific choices remain in `RecordingOptions` and `ReplayOptions` rather than the engine-wide configuration.

## Record a cassette

Start recording before the application sends the requests that belong to the scenario. Closing immediately stops new requests from joining the recording, then waits up to 30 seconds for requests which already joined to finish.

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

Closing writes the complete sanitised cassette only when every admitted request produces a persistable interaction. If cassette processing or cancellation prevents that, or the grace period expires, close throws a `CassetteException`, discards the whole recording without writing, and releases the engine for another session. When an official adapter has already captured a complete live response before later cassette processing fails, it still returns that unchanged response to the application; closing then reports the failed recording and writes nothing. A mapped remote transport failure is itself a recordable outcome and does not cause this discard. A response arriving after a timeout can still return to the application, but it is not retained. Discarding releases the session without writing it. If close or discard fails, it reports the error and still releases the engine for another session. Recording is explicit; installing an adapter alone does not create cassettes.

Set one positive close grace period for every recording started by an engine:

```dart
final engine = CassetteEngine(
  store: store,
  configuration: CassetteConfiguration(
    recording: RecordingConfiguration(
      closeGracePeriod: Duration(seconds: 45),
    ),
  ),
);
```

The default is 30 seconds. The timeout applies once to the complete close wait; it does not restart for each request.

When recording begins to close, new requests pass through to the real server without being recorded. Requests which already entered the recording are allowed to finish during the grace period. If an adapter had already associated a request with the recording but had not submitted it before closing began, the request fails without contacting the server.

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

Replacement creates the cassette when the target is absent at session start and replaces it when the target is present. The engine remembers that initial state so the final store operation remains race-safe: a target which unexpectedly appears or disappears before close causes the close to fail instead of overwriting unrelated data.

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

Request headers do not participate in matching by default because credentials, dates, traces, and other volatile values commonly appear there. To compare a header, add its name to `MatchingConfiguration.includedHeaders`. Only the included header names participate in header matching. JSON bodies are compared structurally: object member order is ignored, array order is preserved, and scalar types and values must match. Other bodies use exact byte comparison.

Canonical requests require an absolute URI with a non-empty ASCII host. DNS names, `localhost`, IPv4, IPv6, and ASCII/Punycode internationalised domain names are supported. Controls, non-ASCII host spellings, unsafe delimiters, and percent escapes which remain after Dart's `Uri` normalisation are rejected without including the host value in the error.

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

Sensitive JSON names match every object member with that name, at any depth. For example, adding `code` as a sensitive JSON name redacts every member named `code`, regardless of which object contains it. Use an exact, case-sensitive RFC 6901 JSON Pointer such as `/credentials/code` when only one location is sensitive. Header rules apply to requests and responses. Query rules apply only to request URIs. JSON name and pointer rules apply to JSON request and response bodies.

The built-in sensitive names are:

| Location | Names |
| --- | --- |
| Headers | `api-key`, `authorization`, `cookie`, `proxy-authorization`, `set-cookie`, `x-api-key`, `x-auth-token`, `x-csrf-token`, `x-xsrf-token` |
| Query parameters and JSON members | `access_token`, `api_key`, `apikey`, `auth`, `authorization`, `client_secret`, `id_token`, `password`, `passwd`, `refresh_token`, `secret`, `token` |

Header, query parameter, and JSON member names are matched exactly and case-insensitively. Substrings do not match, so a built-in rule for `token` does not select `token_type`. Built-in sanitisation also replaces request URI user information when it is present.

When a sensitive JSON value is a map or list, sanitisation keeps its keys, positions, order, and nesting, then replaces every scalar value inside it. Empty maps and lists remain empty. This preserves the JSON shape needed for useful recordings and deterministic matching.

JSON scalar replacements preserve their JSON types:

| Original value | Replacement |
| --- | --- |
| Ordinary string | `"[REDACTED]"` |
| Recognised email address | `"redacted@example.invalid"` |
| Canonical UUID string | `"00000000-0000-4000-8000-000000000000"` |
| Integer | `0` |
| Non-integer number | `0.0` |
| Boolean | `false` |
| `null` | `null` |

Email and UUID recognition is applied only after a value has been selected as sensitive. The package does not redact a field merely because its value looks like an email address or UUID.

A single `Content-Encoding: identity` value means that the body is not transformed. HTTP Cassette therefore treats it like an unencoded body: valid JSON is inspected, sanitised, matched structurally, and stored as readable structured JSON. The redundant identity header is removed during persistence.

Gzip-coded JSON responses are stored without built-in body sanitisation by default. If the HTTP client supplies the original gzip bytes, HTTP Cassette keeps them as ordinary Base64. If the client has already decompressed valid JSON but retained the gzip header, HTTP Cassette recompresses the unchanged bytes for storage. In both cases, sensitive values remain present. On platforms supporting `dart:io`, opt into sanitisation and plain storage when those values must be removed:

```dart
final configuration = CassetteConfiguration(
  sanitisation: SanitisationConfiguration(
    gzipJsonResponses: GzipJsonResponseHandling.sanitiseAndStorePlain,
  ),
);
```

This option applies only to non-empty responses with one `Content-Type` identifying JSON and one case-insensitive `Content-Encoding: gzip` value. Dio, `http`, or their underlying transport may already have decompressed the body while retaining the original header. The core checks the captured bytes: a gzip signature is decoded, while bytes without that signature are treated as the already-decompressed JSON representation and validated normally. It enforces `BodyLimits.responseBytes` against captured and decoded bytes, sanitises the JSON, and persists readable plain JSON. The received gzip header is preserved so replay presents the same response metadata to the transport adapter. Decoding temporarily holds encoded and decoded data in memory, and plain JSON can make the cassette larger than compressed network content. Both sanitising modes require a platform with HTTP Cassette gzip processing support, currently a `dart:io` platform, even when the HTTP client has already decompressed the body. Invalid gzip, invalid JSON, unavailable platform support, or a body over the limit prevents that recording from being persisted.

Choose `GzipJsonResponseHandling.sanitiseAndStoreCompressed` to sanitise the same eligible responses while retaining the body state captured from the HTTP client. If the captured body was gzip bytes, the core decodes, sanitises and recompresses it, then stores it as ordinary `base64`; replay returns gzip bytes. If the client had already decompressed the body, the core sanitises and compresses it only for cassette storage as `gzipBase64`; replay decompresses it and returns plain bytes. Recompression usually produces a smaller cassette body than plain storage, but Base64 adds roughly one third to the compressed payload size. The received gzip header is preserved in either case.

Recompression temporarily retains decoded, sanitised, and recompressed representations, so it has greater CPU and peak-memory cost than plain storage. Plain storage avoids the recompression work and produces readable cassette JSON, but may use considerably more disk space than compressed network content.

Default `storeWithoutSanitisation` needs no gzip support when it receives gzip bytes and stores them unchanged. If the HTTP client has already decompressed those bytes, preserving that captured state requires storage-only recompression and therefore a supported platform.

`deflate`, `br`, `zstd`, multiple content codings, ambiguous headers, encoded requests, and encoded non-JSON responses are not decoded. They retain their original bytes and headers and receive no built-in body sanitisation.

Sanitised request values are also excluded from the corresponding matcher component. This prevents replay from requiring the original secret. Body presence remains significant when a complete body value is excluded.

Custom request and response sanitisers can handle domain-specific data. They run first in registration order, then the built-in rules sanitise their output. Custom sanitisers cannot bypass the built-in rules unless all built-ins are explicitly disabled with `SanitisationConfiguration.unsafeWithoutBuiltIns`.

A custom sanitiser must return valid canonical values. A request sanitiser must also report every changed location that affects matching so replay does not require the original value. Any sensitive value left in the returned request or response may be persisted, so custom sanitisers are responsible for completely removing the domain-specific data they handle.

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

Set `maximumBytes` on either built-in store to change the complete encoded-cassette limit:

```dart
final memoryStore = MemoryCassetteStore(
  maximumBytes: 16 * 1024 * 1024,
);

final fileStore = FileCassetteStore(
  Directory('test/cassettes'),
  maximumBytes: 16 * 1024 * 1024,
);
```

`maximumBytes` must be positive. It limits one complete encoded cassette during storage and decoding; it does not replace the separate request and response limits in `BodyLimits`.

## Store operation timeout

Each cassette-store existence check, read, or write has a 30-second timeout by default. A startup timeout fails with a safe `CassetteException`, releases the engine, and does not contact the network. A write timeout closes the recording, releases the engine, and reports `storeWriteResultUnconfirmed` because the core cannot know whether that write eventually changed storage.

Set one positive timeout for every session started by an engine:

```dart
final configuration = CassetteConfiguration(
  storeOperations: StoreOperationConfiguration(
    timeout: Duration(seconds: 10),
  ),
);
```

The timeout applies separately to each store operation. Dart futures cannot be cancelled, so a store may continue its own work after the engine stops waiting. A late startup result cannot activate the failed session. A late write may still modify storage, so callers must treat its result as unknown and allow a later session to validate the current cassette independently.

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

Mismatch diagnostics describe the request shape, matcher, replay policy, closest candidate, and value-free differences. They do not include sanitised values. Recording close uses `recordingRequestFailed` when an admitted request failed and `recordingCloseTimedOut` when the grace period expired. Both mean no cassette was written. `storeWriteResultUnconfirmed` means the store reported a general write failure and could not confirm whether that operation changed the cassette. Every close failure ends its session and releases the engine; a later session validates the store's current state independently. `ScopedCassetteException` is used only when a scoped callback fails and session cleanup also fails; it keeps the original callback error and a separate safe cleanup diagnostic.

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

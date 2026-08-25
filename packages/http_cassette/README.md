# http_cassette

`http_cassette` is the planned transport-neutral core of HTTP Cassette, a Dart
package family for recording and replaying HTTP interactions in tests.

This package is under active development. It currently provides foundational
canonical HTTP values and safe structured diagnostics. It does not yet record,
replay, sanitise or persist HTTP interactions, and the matcher is not yet
exposed as an operational engine.

## Installation

The package is not ready for use or publication. During development in this
workspace, it can be resolved with `dart pub get` from the repository root.

## Current API

`CassetteName` validates portable slash-separated logical names. Stores will own
the physical path and `.json` suffix:

```dart
final cassetteName = CassetteName('checkout/expired-discount');
```

`CassetteSnapshot` is the immutable encoded value returned by a store.
It defensively copies its bytes and carries an identity-only
`CassetteRevision`. The revision exposes no underlying value, has a redacted
string form and exists only for conditional replacement.

`CassetteStoreException` provides stable store failure and operation enums for
programmatic handling. It retains only the logical cassette name and never a
file path, encoded bytes, revision value or platform exception. The current
categories distinguish missing and existing targets, changed revisions,
unsupported operations and other operation failures.

`CassetteStore` is the public transport-neutral persistence contract. It
supports existence checks, immutable snapshot reads, create-only writes,
explicit replacement and revision-checked replacement. Implementations must
copy byte input and must not decode, match, sanitise or migrate cassette data.
Direct callers are responsible for supplying sanitised, validated and encoded
cassette bytes. Every store declares one positive `maximumBytes` value. The
store enforces it while accepting encoded data, and the core independently uses
the same value before decoding a snapshot.

`MemoryCassetteStore` provides isolate-local storage with no file-system or
network access. Each instance owns private state and accepts an optional
positive `maximumBytes` override:

```dart
final store = MemoryCassetteStore(maximumBytes: 64 * 1024 * 1024);
await store.create(cassetteName, encodedSafeCassetteBytes);
final snapshot = await store.read(cassetteName);
```

Creation never replaces an existing cassette. `replace` is explicit, while
`replaceIfUnchanged` rejects a stale snapshot. Directly supplied bytes must
already be sanitised, validated and encoded.

File-backed storage is available from
`package:http_cassette/file.dart` on platforms supporting `dart:io`:

```dart
final store = FileCassetteStore(
  Directory('test/cassettes'),
  maximumBytes: 64 * 1024 * 1024,
);
final snapshot = await store.read(cassetteName);
```

Reads are bounded and format-neutral: the store returns exact immutable bytes
without decoding UTF-8, parsing JSON or validating a schema. The core codec
owns those later steps. A missing root behaves as an empty store. Path
resolution rejects symbolic-link escapes without exposing absolute paths. File
creation is supported and never replaces an existing target. Explicit
replacement requires an existing regular file and uses a flushed,
same-directory temporary file followed by replacement rename. It is atomic
where the file system supports atomic replacement rename; no delete-and-rename
fallback is used. Cross-process locking and directory durability across sudden
power loss are not provided. File store revisions returned by reads privately
retain the exact bounded bytes
needed for content-based conditional replacement; they expose only an opaque
identity. `replaceIfUnchanged` accepts only a revision issued by that store for
that cassette and compares the complete current bytes twice, including
immediately before rename. A detected change leaves the current file intact.
This detects external changes observed before the final check, but another
process can still race after it because cross-process locking is outside V1.
The primary library does not import `dart:io`.

`ReplayPolicy` defines the agreed `strict`, `first`, `last`, `sequence` and
`cycle` choices. `ReplayOptions` holds an optional session override and the
future successful-close verification flag. A null policy means use the future
engine default, which will be `strict`. These values are configuration only:
matching-group selection, consumption and replay sessions are not implemented
yet.

`CassetteConfiguration` groups the matching, sanitisation, body-limit and
default replay-policy values that an engine shares across its sessions. Its
defaults retain secure sanitisation and strict replay:

```dart
final configuration = CassetteConfiguration(
  defaultReplayPolicy: ReplayPolicy.strict,
);
```

`CassetteMode.record` and `CassetteMode.replay` identify the explicit operation
of a future active session. They do not start a session, permit traffic or make
recording and replay available in the current package.

The internal session foundation now serialises close and discard transitions.
Successful completion is idempotent, while overlapping operations and attempts
after an uncertain completion failure produce safe structured lifecycle
failures. The public session handle and lifecycle-only engine use this state.

`CassetteSession` is now the public read-only handle for a future active
operation. It exposes its logical name, explicit mode and successful closed
status. Its `close()` and `discard()` methods serialise injected asynchronous
completion work and preserve failures. The lifecycle-only engine can now create
the handle, but the handle performs no cassette I/O or traffic processing by
itself.

`RecordingOptions` makes existing-cassette handling explicit. Recording will
fail by default when a target already exists; callers may instead select
`ExistingCassette.replace` or `ExistingCassette.append`. These values are
configuration only. Replacement and append are not connected to a recording
engine yet. Future append behaviour will require a valid cassette whose schema
version equals the implementation's current writable schema version.

The internal engine foundation now reserves at most one session synchronously.
Ownership remains reserved while completion is running and after a completion
failure leaves uncertain state. It is released only after close or discard
succeeds. Separate engine instances own independent state.

`CassetteEngine` retains a store and immutable shared configuration and reports
its active session. Recording starts remain lifecycle-only. Replay starts now
read and strictly validate the complete cassette before exposing a session.
Missing, unreadable, malformed or incompatible cassettes throw a safe
`CassetteException` and leave the engine inactive. While an asynchronous load
is pending, the engine rejects another start but exposes no session. The loaded
cassette is retained only for the active replay session and is released when
that session closes or is discarded. The engine still does not intercept,
match or replay requests, and scoped callback methods are not implemented.

The internal replay-loading foundation now maps a missing store target to a
`cassetteMissing` diagnostic and other expected replay read failures to
`cassetteUnreadable`. It retains only the logical cassette name and safe store
failure kind, always reports disabled network access, and performs no store read
itself. Recording and append store-read failures remain a separate diagnostic
category.

Value-free decoder failures can now be projected into internal replay-loading
diagnostics. Oversized input, invalid UTF-8 and JSON syntax failures remain
decode failures; schema-shape failures and unsupported older or newer versions
have distinct categories. The projection retains only safe structural
positions, safe integer version facts and the configured total cassette limit.
It does not retain cassette bytes or source lines and does not invoke decoding.

Store-read and decoder projections now share one internal sealed replay-loading
failure boundary. Its deterministic formatter displays the bounded logical
cassette name, fixed category, safe source-specific facts and disabled-network
status. Missing facts are omitted explicitly where necessary, and formatting
does not log or inspect raw exceptions, paths, source lines or cassette bytes.

The internal replay foundation can now build an immutable matching group from
a validated cassette. It applies the configured matcher and each interaction's
persisted exclusions, preserves recorded indices and identical interactions,
and excludes mismatches. Policy selection and consumption are still not
implemented, so this does not yet make requests replayable.

Internal strict replay state now selects the lowest recorded-index unconsumed
match and consumes each match once. It distinguishes an empty matching group
from a group exhausted by earlier selections. Replay diagnostics and engine
integration remain unimplemented, so exhaustion is not yet exposed through a
public replay operation.

Internal `first` and `last` replay state now reuse the lowest or highest
recorded-index match respectively. Empty groups remain no-match results and
these reusable policies never exhaust. Distinct-use tracking counts the reused
interaction once for future unused-interaction verification.

Internal `sequence` replay state now advances through matches in recorded-index
order and then reuses the final match indefinitely. It returns no-match for an
empty group and never exhausts.

Internal `cycle` replay state advances through matches in recorded-index order,
wraps from the final match to the first and continues indefinitely. It also
returns no-match for an empty group and never exhausts. Matching and selection
are still not connected to a public replay operation.

Replay selection state can now produce immutable point-in-time snapshots of
the distinct recorded indices it has used. An internal cassette-wide verifier
combines snapshots from independent matching groups and, when explicitly
enabled, returns either success or every unused index in recorded order.
Verification is disabled by default and is not yet connected to session close
or public diagnostics. A failed internal verification result now also retains
the safe total and used interaction counts and can assemble a structured
diagnostic with validated logical cassette identity, resolved replay policy,
fixed unused-interaction category and disabled-network status. Its internal
formatter renders the safe counts, policy and unused indices deterministically
without logging. It uses the same 128-character cassette-name and 16-index
display bounds as exhaustion diagnostics. Session-close integration remains
unimplemented.

Actual strict exhaustion can now be projected into immutable value-free facts:
the active policy, matching-group size, distinct used count, recorded indices
and disabled-network status. These facts retain no requests or outcomes. They
can be paired with internal immutable context containing a validated logical
cassette name and a value-free request summary. The summary retains only the
canonical method, its character length, body presence and byte length, and
request-arrival index. A method longer than 64 characters is omitted rather
than truncated. The summary does not retain URI, query, header or body values.
The context and verified exhaustion facts now assemble into an internal
structured exhaustion diagnostic with a fixed exhaustion category, safe
summary and disabled-network status. It cannot be mislabelled as a request
mismatch. Its internal deterministic plain-text formatter shows the safe
request facts, consumption state and policy without logging. Cassette names are
explicitly truncated after 128 characters and at most 16 recorded indices are
shown with an omitted count. Public replay integration is not implemented yet.

Internal no-match facts can now be created from the existing deterministic
candidate ranking. They retain the complete considered count and, when the
cassette is non-empty, the closest recorded index and the exact safe bounded
comparison already used for ranking. Matching is not recomputed and canonical
requests or interactions are not retained. Diagnostic assembly and formatting
remain unimplemented.

The active matcher can now be described internally without retaining configured
names, paths or custom matcher objects. Fixed method, URI and non-empty-body
matching remain explicit, while selected headers, ignored query parameters,
ignored JSON locations and custom components are represented only by counts.
This prevents confidential schema identifiers from crossing the diagnostic
boundary before a dedicated confidentiality policy exists.

The closest non-matching comparison can now be projected into internal
location-safe facts. Built-in component order and state, custom registration
order, bounded difference kinds and complete counts are preserved. All supplied
locations are marked as suppressed, and custom component names are replaced by
their registration indices. Exact-body byte lengths and first differing offset,
body comparison strategy and JSON classifications remain available without
retaining request values or body bytes.

The logical cassette and value-free request context, resolved replay policy,
safe matcher description, ranking counts and projected closest comparison now
assemble into an internal structured no-match diagnostic. Its category, safe
summary and disabled-network status are fixed. The diagnostic copies only the
location-suppressed projection, so the original comparison and its pre-policy
locations do not remain reachable. Human-readable formatting remains
internal. The deterministic formatter shows every built-in component, at most
eight custom components and at most eight retained difference kinds per
component. Omitted counts are explicit. Locations appear only as suppressed,
and body output is limited to comparison strategy, byte lengths, first
differing offset and JSON classifications. It performs no logging.

`CassetteDiagnostic` carries a stable category, concise safe summary and network
access status. `CassetteException` carries that structured diagnostic without
requiring consumers to parse exception text.

Diagnostics provide deterministic plain-text formatting without logging
automatically:

```dart
final text = diagnostic.format();
```

`CassetteHeaders` provides immutable, transport-neutral HTTP fields with
case-insensitive lookup and ordered repeated values:

```dart
final headers = CassetteHeaders(<String, Iterable<String>>{
  'Accept': <String>['application/json'],
});
```

`CassetteRequest` and `CassetteResponse` provide immutable canonical messages
with defensively protected byte bodies:

```dart
final request = CassetteRequest(
  method: 'GET',
  uri: Uri.parse('https://api.example.test/profile'),
  headers: headers,
);
```

`CassetteOutcome` represents either a received response or a portable transport
failure. Caller cancellation and cassette-system failures are not outcomes:

```dart
final outcome = CassetteResponseOutcome(response);
```

`BodyLimits` provides measured byte limits for future bounded buffering:

| Body | Default |
| --- | ---: |
| Request | 2 MiB |
| Response | 5 MiB |

Both values require positive byte counts and may be overridden explicitly.
Buffering and limit enforcement are not implemented yet.

`MatchingConfiguration` selects headers and exact query or JSON values to
ignore. Method, URI and non-empty-body matching remain fixed:

```dart
final matching = MatchingConfiguration(
  includedHeaders: <String>{'accept'},
  ignoredQueryParameters: <String>{'request_id'},
  ignoredJsonPointers: <String>{'/metadata/generated_at'},
);
```

The internal matching foundation now normalises HTTP methods, URI origins,
paths and queries conservatively. Query-name order is ignored, while repeated
values retain their order. Headers are ignored unless explicitly selected;
selected values preserve order and compare after surrounding HTTP whitespace is
removed. JSON bodies are classified from `application/json` and structured
`+json` content types, then parsed strictly as UTF-8 with duplicate object
members rejected. Parsed JSON can be compared structurally: object order is
ignored, array order is preserved and equivalent number spellings match without
losing precision. This remains an internal matching foundation; full request
comparison now composes these components without replay state. Opaque bodies
compare as exact bytes; differences retain only safe length, empty-state and
first-offset facts. Adapters must supply internationalised hosts in canonical
ASCII form. Matching exclusions validate header names and exact JSON Pointers.
Excluded query values retain their parameter names, multiplicity, order and
equals-sign state. A whole-body exclusion is available for custom sanitisers
that replace an opaque body or the complete body structure. It ignores the body
value only: an empty body still does not match a non-empty body. Use exact JSON
Pointers when only selected JSON locations changed.

The transport-neutral custom matcher contract supports additional safe matching
requirements. Registered components run after the built-in components in their
configuration order and contribute to matching eligibility and closest-match
ranking. Custom components cannot replace built-in matching in the current API.

`SanitisationConfiguration` enables fixed rules for common credential headers,
query parameters and JSON member names. Projects may add exact header names,
query names, JSON member names and JSON Pointers. This configuration is
available now, but the sanitisation pipeline is not implemented yet. These
defaults reduce risk; they cannot guarantee that a future cassette is safe to
commit, so generated cassettes will still require review.

Built-in rules can be disabled only with the conspicuously named
`SanitisationConfiguration.unsafeWithoutBuiltIns()` constructor. Recording with
that configuration may persist raw credentials and personal data. It is not an
ordinary setup option and is not used by the package example.

The internal sanitisation foundation now replaces complete values for
`authorization`, `cookie`, `proxy-authorization`, `set-cookie`, `x-api-key`,
`api-key`, `x-auth-token`, `x-csrf-token` and `x-xsrf-token`, plus configured
exact header names. Repeated values retain their count. It also replaces every
present value of common credential-shaped query parameters and configured exact
query names while preserving names, order, multiplicity, and missing versus
empty values. URI user information is replaced as one complete value. The
internal request-field result carries matching exclusions for every changed
location. The internal JSON foundation recursively sanitises exact sensitive
member names and exact RFC 6901 locations while retaining object and array
shape. Body composition and the recording pipeline are not implemented yet.

### Choosing JSON sanitisation rules

An additional JSON member name applies at every object depth and is matched
case-insensitively. For example, adding `customerReference` sanitises every
member with that name, including members inside arrays. Use this form only when
every occurrence is sensitive.

An RFC 6901 JSON Pointer applies to one exact, case-sensitive location. For
example, `/credentials/code` sanitises that value without changing
`/metadata/code`. Use a pointer when the same member name is sensitive in one
part of a document but safe elsewhere. Pointer tokens use RFC 6901 escaping:
`~1` represents `/` and `~0` represents `~`.

Built-in credential-shaped names such as `token`, `password` and
`authorization` deliberately apply everywhere as a secure default. A selected
object or array keeps its keys, length and nesting while all scalar descendants
are replaced. That remaining shape can itself be sensitive, so projects should
use a future custom body sanitiser when the structure must also be hidden.

Automatic sanitisation reduces risk but cannot recognise every secret or item
of personal information. Add project rules for domain-specific data and review
every generated cassette before committing it.

A body that declares a JSON media type must be valid UTF-8 JSON without
duplicate object member names before built-in sanitisation can inspect it. The
internal body sanitisation foundation fails safely rather than retaining
uninspectable claimed JSON. Non-JSON bodies are opaque to built-in sanitisation
and remain unchanged. A body with `Content-Encoding` is also opaque even when
its media type says JSON, because its canonical bytes still represent the
encoded payload. Projects must decode and sanitise such content explicitly,
returning headers consistent with the replacement bytes. The explicit unsafe
no-built-ins configuration also disables the ordinary claimed-JSON inspection
guarantee. Integration with the recording pipeline is not implemented yet. The
internal composition layer now applies these built-ins to complete canonical
requests and responses, and carries every changed request location into
matching exclusions.

### Custom sanitiser contracts

`RequestSanitiser` and `ResponseSanitiser` are transport-neutral extension
contracts. A request sanitiser returns a `SanitisedRequest` containing valid
canonical data and a validated `MatchingExclusions` value for every changed
location that affects matching. A response sanitiser returns a valid canonical
response. Implementations must be deterministic and must not log their raw
input. If a request sanitiser replaces the complete body, it may report a
whole-body exclusion; body presence remains significant.

Custom sanitisers may be registered through `SanitisationConfiguration` and are
retained in explicit order. Registration is immutable and defensively copied.
The unsafe no-built-ins constructor does not suppress custom sanitisers.
Custom request sanitisers now execute internally in that order, with each output
feeding the next. Each changed request is checked against the exclusions
reported by that sanitiser; incomplete exclusions or changes to fixed request
identity fail without retaining changed values in diagnostics. Response
sanitisers also execute internally in registration order, with each canonical
output feeding the next. Responses need no matching exclusions because they do
not select recorded interactions. The complete internal pipeline now runs each
custom chain first and the built-in rules last, then unions custom and built-in
request exclusions. The explicit unsafe no-built-ins policy still runs custom
sanitisers. Recording integration is not implemented yet.

The internal cassette domain now represents one immutable sanitised
interaction with its non-negative request-arrival index, canonical request,
persisted matching exclusions and exactly one canonical response or portable
transport failure. The immutable containing cassette fixes its writable schema
version at `1`, defensively owns its interaction list and requires indices to
start at zero and remain contiguous in ascending arrival order. Readable-version
compatibility and the schema codec are not implemented yet.

The persisted-body foundation represents zero-byte bodies explicitly, readable
text as validated UTF-8 content, and opaque bytes as canonical padded Base64.
Structured JSON is stored as a deeply immutable value with lexically ordered
object members and preserved array order, then reconstructed as deterministic
compact UTF-8 JSON. Each representation reconstructs immutable replay bytes.
The internal selector now applies the fixed precedence: empty, valid
media-type JSON, readable UTF-8 text, then Base64. Non-empty content-encoded
bytes always select Base64. Callers and adapters do not select representations.
Payload preparation updates an existing `content-length`, removes digest and
ETag validators, and removes `content-encoding` when no encoded bytes remain.
For requests, every changed header name must be added to that interaction's
matching exclusions. Weak ETags are also removed until an explicit validation
policy is introduced.

The encoder foundation canonicalises persisted request URIs independently of
their adapter-observed spelling. It normalises origin, default ports, paths,
percent escapes and query-name order, preserves repeated-query value order and
equals-sign state, and omits fragments.

The internal persistence foundation now projects a complete cassette into the
exact V1 field order. Projection prepares request and response bodies, corrects
payload-derived headers, adds changed request header names to matching
exclusions, and selects the response or transport-failure schema shape. The
result is a deeply immutable schema tree. The internal encoder writes that tree
as deterministic UTF-8 JSON with exact schema ordering, two-space indentation,
LF line endings and one final line feed. It preserves lossless JSON number
spelling and has a reviewed complete golden fixture. Reading persisted
cassettes now validates UTF-8, strict JSON, schema compatibility and every
interaction field before reconstructing a complete immutable cassette. The
decoder rejects duplicate or unknown fields, non-canonical field order,
malformed types, invalid body representations and non-contiguous interaction
indices. Decode failures report only a safe category and bounded structural
location; they do not quote recorded values. The codec remains internal while
storage and session integration are unfinished; replay is not available yet.

A reproducible encoder probe supports a 64 MiB default total cassette limit,
separate from the 2 MiB request and 5 MiB response body limits. The internal
decoder enforces the total limit before UTF-8 decoding or JSON parsing and
accepts an explicit positive override. Storage integration is not implemented
yet.

## Example

The example constructs body and matching configuration with canonical HTTP
values. It also formats a structured missing-cassette diagnostic.

```sh
dart run example/http_cassette_example.dart
```

## Licence

This package is licensed under the BSD 3-Clause License.

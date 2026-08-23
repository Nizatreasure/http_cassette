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
cassette bytes.

`MemoryCassetteStore` provides isolate-local storage with no file-system or
network access. Each instance owns private state:

```dart
final store = MemoryCassetteStore();
await store.create(cassetteName, encodedSafeCassetteBytes);
final snapshot = await store.read(cassetteName);
```

Creation never replaces an existing cassette. `replace` is explicit, while
`replaceIfUnchanged` rejects a stale snapshot. Directly supplied bytes must
already be sanitised, validated and encoded.

File-backed storage is not available yet. Its internal path-safety foundation
now maps validated logical names beneath an existing canonical root and rejects
symbolic-link escapes without exposing absolute paths. The primary library does
not import `dart:io`; the public platform library and file reads remain later
stages.

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
